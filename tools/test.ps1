<#
.SYNOPSIS
Lints a core's RTL and runs its testbenches in Verilator.

.DESCRIPTION
Reads only cores/<core>/rtl, cores/<core>/sim and modules/, never pocket/, so
game logic stays testable without the openFPGA framework.

1. Lints the RTL and modules/ with verilator --lint-only -Wall.
2. Lints each testbench without -Wall, which misreports clocking blocks.
3. Builds each testbench with --binary --x-assign unique and runs it with
   +verilator+rand+reset+0 (zeros), +1 (ones), and +2 (random) with seeds 1
   to 5.

A testbench is a file in sim/ named tb_<name>.sv whose top module has the same
name. Every other file in sim/ is compiled into each testbench, for models and
checkers. Builds and logs go to out/<core>/sim/<testbench>.

Verilator runs in the MSYS2 UCRT64 environment at C:\msys64. Exits with 1 if
any lint, build or run fails.

.PARAMETER Core
Folder name under cores/.

.PARAMETER Test
Run only the testbench with this name, such as tb_cpu. Lint still covers all
of the RTL.

.EXAMPLE
./tools/test.ps1 -Core rallyx

.EXAMPLE
./tools/test.ps1 -Core rallyx -Test tb_cpu
#>
param(
    [Parameter(Mandatory)]
    [string]$Core,
    [string]$Test
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Path $PSScriptRoot -Parent
$coreDir = Join-Path -Path $root -ChildPath "cores/$Core"
$msys = "C:\msys64"
$resetModes = @(
    "+verilator+rand+reset+0",
    "+verilator+rand+reset+1",
    "+verilator+rand+reset+2 +verilator+seed+1",
    "+verilator+rand+reset+2 +verilator+seed+2",
    "+verilator+rand+reset+2 +verilator+seed+3",
    "+verilator+rand+reset+2 +verilator+seed+4",
    "+verilator+rand+reset+2 +verilator+seed+5"
)

if (-not (Test-Path -Path $coreDir -PathType Container)) {
    throw "No core at $coreDir"
}

# Runs a command in an MSYS2 UCRT64 login shell, where Verilator finds its own
# Perl, make and g++. Returns the exit code and appends all output to $Log.
function Invoke-Ucrt64 {
    param(
        [string[]]$Arguments,
        [string]$Log
    )

    $quoted = $Arguments | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }
    & "$msys\usr\bin\env.exe" MSYSTEM=UCRT64 CHERE_INVOKING=1 /usr/bin/bash -lc ($quoted -join " ") *>> $Log

    return $LASTEXITCODE
}

function Get-SourceFiles {
    param([string]$Path)

    if (-not (Test-Path -Path $Path -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -Path $Path -Filter "*.sv" -File -Recurse | ForEach-Object { $_.FullName.Replace("\", "/") })
}

$rtl = @(Get-SourceFiles -Path (Join-Path -Path $coreDir -ChildPath "rtl")) +
    @(Get-SourceFiles -Path (Join-Path -Path $root -ChildPath "modules"))
$sim = Get-SourceFiles -Path (Join-Path -Path $coreDir -ChildPath "sim")
$testbenches = @($sim | Where-Object { (Split-Path -Path $_ -Leaf) -like "tb_*.sv" })
$support = @($sim | Where-Object { $_ -notin $testbenches })

if ($Test) {
    $testbenches = @($testbenches | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) -eq $Test })

    if ($testbenches.Count -eq 0) {
        throw "No testbench $Test.sv in $coreDir/sim"
    }
}

$outDir = Join-Path -Path $root -ChildPath "out/$Core/sim"
New-Item -Path $outDir -ItemType Directory -Force | Out-Null

$failures = [System.Collections.Generic.List[string]]::new()
$runCount = 0

# Prints the error lines of a failed step and records it.
function Add-Failure {
    param(
        [string]$Step,
        [string]$Log
    )

    $failures.Add($Step)
    $errors = @(
        Select-String -Path $Log -Pattern "%Error|%Warning|ERROR|Error:|error:" |
            Select-Object -First 5 |
            ForEach-Object { $_.Line }
    )

    if ($errors.Count -eq 0) {
        $errors = @(Get-Content -Path $Log -Tail 5)
    }

    Write-Host "FAIL $Step"
    $errors | ForEach-Object { Write-Host "    $_" }
    Write-Host "    Full log: $Log"
}

# Lint the RTL as one design. Every module that nothing instantiates becomes a
# top, so MULTITOP is expected.
if ($rtl.Count -gt 0) {
    $log = Join-Path -Path $outDir -ChildPath "lint-rtl.log"
    Remove-Item -Path $log -ErrorAction SilentlyContinue
    $code = Invoke-Ucrt64 -Log $log -Arguments (@("verilator", "--lint-only", "-Wall", "-Wno-MULTITOP") + $rtl)

    if ($code -ne 0) {
        Add-Failure -Step "lint rtl" -Log $log
    }
}

foreach ($testbench in $testbenches) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($testbench)
    $buildDir = Join-Path -Path $outDir -ChildPath $name
    $files = @($testbench) + $support + $rtl

    if (Test-Path -Path $buildDir) {
        Remove-Item -Path $buildDir -Recurse -Force
    }

    New-Item -Path $buildDir -ItemType Directory -Force | Out-Null

    $log = Join-Path -Path $buildDir -ChildPath "lint.log"
    $code = Invoke-Ucrt64 -Log $log -Arguments (@("verilator", "--lint-only", "--timing", "--top-module", $name) + $files)

    if ($code -ne 0) {
        Add-Failure -Step "lint $name" -Log $log
        continue
    }

    $log = Join-Path -Path $buildDir -ChildPath "build.log"
    $buildArguments = @(
        "verilator",
        "--binary",
        "-j", "0",
        "--x-assign", "unique",
        "--Mdir", $buildDir.Replace("\", "/"),
        "--top-module", $name
    )
    $code = Invoke-Ucrt64 -Log $log -Arguments ($buildArguments + $files)

    if ($code -ne 0) {
        Add-Failure -Step "build $name" -Log $log
        continue
    }

    $binary = Join-Path -Path $buildDir -ChildPath "V$name.exe"

    for ($i = 0; $i -lt $resetModes.Count; $i++) {
        $mode = $resetModes[$i]
        $log = Join-Path -Path $buildDir -ChildPath "run$i.log"
        $code = Invoke-Ucrt64 -Log $log -Arguments (@($binary.Replace("\", "/")) + $mode.Split(" "))
        $runCount++

        if ($code -ne 0) {
            Add-Failure -Step "run $name $mode" -Log $log
        }
    }
}

$status = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }
Write-Host "SUMMARY $status core=$Core testbenches=$($testbenches.Count) runs=$runCount failures=$($failures.Count)"

if ($failures.Count -gt 0) {
    exit 1
}
