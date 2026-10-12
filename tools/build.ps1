<#
.SYNOPSIS
Builds a core against the shared Pocket shell and packages it for the SD card.

.DESCRIPTION
Copies the Quartus project in pocket/src/fpga to out/<core>/fpga and points its
core/core.qip at the core's own core.qip, so the core's sources compile in
place. Runs a full Quartus compile, reverses the bits of each byte of the .rbf
into bitstream.rbf_r, stages the SD card folders in out/<core>/sd, and zips
them as out/<core>/<Author>.<Core>_<Version>_<YYYY-MM-DD>.zip. The author,
core name, version and date come from the core's core.json.

A core keeps its Pocket files in cores/<core>/pocket, laid out like the
starter in pocket/:

    core.qip          Quartus sources, constraints and IP of the core
    stp1.stp          SignalTap setup for -SignalTap builds, optional
    *.json, info.txt  copied to Cores/<Author>.<Core>/
    dist/icon.bin     copied to Cores/<Author>.<Core>/
    dist/platforms/   copied to Platforms/
    dist/assets/      copied to Assets/

Each run deletes and rebuilds out/<core>/fpga, out/<core>/sd and the zip.

.PARAMETER Core
Folder name under cores/. Omit it to build the gray-screen starter in pocket/
into out/pocket.

.PARAMETER SignalTap
Compile the SignalTap logic analyzer in stp1.stp, next to the core's core.qip,
into the bitstream. Use it for debug builds over JTAG, not for releases.

.EXAMPLE
./tools/build.ps1 -Core rallyx

.EXAMPLE
./tools/build.ps1 -SignalTap
#>
param(
    [string]$Core,
    [switch]$SignalTap
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Path $PSScriptRoot -Parent
$shellProject = Join-Path -Path $root -ChildPath "pocket/src/fpga"

if ($Core) {
    $name = $Core
    $metaDir = Join-Path -Path $root -ChildPath "cores/$Core/pocket"
    $coreQip = Join-Path -Path $metaDir -ChildPath "core.qip"
} else {
    $name = "pocket"
    $metaDir = Join-Path -Path $root -ChildPath "pocket"
    $coreQip = Join-Path -Path $shellProject -ChildPath "core/core.qip"
}

foreach ($required in @($coreQip, (Join-Path -Path $metaDir -ChildPath "core.json"))) {
    if (-not (Test-Path -Path $required -PathType Leaf)) {
        throw "Missing $required"
    }
}

# Read the release name from core.json and check it against the Pocket's limits.
$coreJson = Get-Content -Path (Join-Path -Path $metaDir -ChildPath "core.json") -Raw |
    ConvertFrom-Json -DateKind String
$metadata = $coreJson.core.metadata
$coreId = "$($metadata.author).$($metadata.shortname)"

if ($metadata.author.Length -gt 31 -or $metadata.shortname.Length -gt 31) {
    throw "core.json: author and shortname must be 31 characters or fewer"
}

if ($metadata.date_release -notmatch "^\d{4}-\d{2}-\d{2}$") {
    throw "core.json: date_release must be YYYY-MM-DD, got '$($metadata.date_release)'"
}

if ($coreJson.core.cores.Count -ne 1 -or $coreJson.core.cores[0].filename -ne "bitstream.rbf_r") {
    throw "core.json: expected one entry in cores, with filename bitstream.rbf_r"
}

$quartusSh = Get-Command -Name "quartus_sh.exe" -ErrorAction SilentlyContinue

if ($quartusSh) {
    $quartusSh = $quartusSh.Source
} else {
    $quartusSh = "C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe"
}

if (-not (Test-Path -Path $quartusSh -PathType Leaf)) {
    throw "quartus_sh.exe isn't on PATH or at $quartusSh"
}

# Assemble the project from the shell, without the starter's core files or
# build output, and point core/core.qip at the core's own core.qip.
$outDir = Join-Path -Path $root -ChildPath "out/$name"
$project = Join-Path -Path $outDir -ChildPath "fpga"
$sd = Join-Path -Path $outDir -ChildPath "sd"
$zips = Get-ChildItem -Path $outDir -Filter "*.zip" -ErrorAction SilentlyContinue

foreach ($path in @($project, $sd) + @($zips | ForEach-Object { $_.FullName })) {
    if (Test-Path -Path $path) {
        Remove-Item -Path $path -Recurse -Force
    }
}

New-Item -Path (Join-Path -Path $project -ChildPath "core") -ItemType Directory -Force | Out-Null

Get-ChildItem -Path $shellProject -Force |
    Where-Object { $_.Name -notin @("core", "db", "incremental_db", "output_files") } |
    Copy-Item -Destination $project -Recurse

$qipPath = (Resolve-Path -Path $coreQip).Path.Replace("\", "/")
$stub = Join-Path -Path $project -ChildPath "core/core.qip"
Set-Content -Path $stub -Value "set_global_assignment -name QIP_FILE `"$qipPath`""

# Quartus rejects SignalTap assignments in a .qip, so add them to the copied .qsf.
if ($SignalTap) {
    $stp = Join-Path -Path (Split-Path -Path $coreQip -Parent) -ChildPath "stp1.stp"

    if (-not (Test-Path -Path $stp -PathType Leaf)) {
        throw "Missing $stp"
    }

    $stpPath = (Resolve-Path -Path $stp).Path.Replace("\", "/")
    Add-Content -Path (Join-Path -Path $project -ChildPath "ap_core.qsf") -Value @(
        "",
        "set_global_assignment -name ENABLE_SIGNALTAP ON",
        "set_global_assignment -name USE_SIGNALTAP_FILE `"$stpPath`"",
        "set_global_assignment -name SIGNALTAP_FILE `"$stpPath`""
    )
}

# Compile. Quartus writes thousands of lines, so keep them in a log and print
# only the errors.
$log = Join-Path -Path $outDir -ChildPath "quartus.log"
Write-Host "Compiling $coreId in $project"

Push-Location -Path $project
try {
    & $quartusSh --flow compile ap_core *> $log
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($exitCode -ne 0) {
    Select-String -Path $log -Pattern "^Error" | ForEach-Object { Write-Host $_.Line }
    throw "Quartus compile failed with exit code $exitCode. Full log: $log"
}

$summary = Join-Path -Path $project -ChildPath "output_files/ap_core.sta.summary"
$failingSlack = Select-String -Path $summary -Pattern "^Slack : -"

if ($failingSlack) {
    Write-Warning "Timing fails at $($failingSlack.Count) corner checks. Read $summary before releasing."
}

# Pocket loads the .rbf with the bits of each byte reversed.
$reverseTable = foreach ($value in 0..255) {
    $reversed = 0
    for ($bit = 0; $bit -lt 8; $bit++) {
        $reversed = ($reversed -shl 1) -bor (($value -shr $bit) -band 1)
    }
    [byte]$reversed
}

$bytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $project -ChildPath "output_files/ap_core.rbf"))
for ($i = 0; $i -lt $bytes.Length; $i++) {
    $bytes[$i] = $reverseTable[$bytes[$i]]
}

# Stage the folders that Pocket expects on the SD card.
$coreFolder = Join-Path -Path $sd -ChildPath "Cores/$coreId"
New-Item -Path $coreFolder -ItemType Directory -Force | Out-Null

[System.IO.File]::WriteAllBytes((Join-Path -Path $coreFolder -ChildPath "bitstream.rbf_r"), $bytes)

Get-ChildItem -Path $metaDir -File |
    Where-Object { $_.Extension -eq ".json" -or $_.Name -eq "info.txt" } |
    Copy-Item -Destination $coreFolder

$dist = Join-Path -Path $metaDir -ChildPath "dist"
$icon = Join-Path -Path $dist -ChildPath "icon.bin"

if (Test-Path -Path $icon -PathType Leaf) {
    Copy-Item -Path $icon -Destination $coreFolder
}

foreach ($pair in @(@("platforms", "Platforms"), @("assets", "Assets"))) {
    $source = Join-Path -Path $dist -ChildPath $pair[0]
    $files = Get-ChildItem -Path $source -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @(".keep", ".gitkeep") }

    foreach ($file in $files) {
        $relative = [System.IO.Path]::GetRelativePath($source, $file.FullName)
        $target = Join-Path -Path $sd -ChildPath (Join-Path -Path $pair[1] -ChildPath $relative)
        New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item -Path $file.FullName -Destination $target
    }
}

$zip = Join-Path -Path $outDir -ChildPath "$($coreId)_$($metadata.version)_$($metadata.date_release).zip"
[System.IO.Compression.ZipFile]::CreateFromDirectory($sd, $zip)

Write-Host "Bitstream: $(Join-Path -Path $coreFolder -ChildPath "bitstream.rbf_r")"
Write-Host "JTAG:      $(Join-Path -Path $project -ChildPath "output_files/ap_core.sof")"
Write-Host "Release:   $zip"
