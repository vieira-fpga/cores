<#
.SYNOPSIS
Starts a new core in cores/<Name> from vieira-fpga/core-template.

.DESCRIPTION
Clones core-template at -Ref into cores/<Name> and deletes the clone's .git
folder, so the core's files belong to this repository. It also deletes the
clone's .rules.verible_lint and .verible_lint_waivers, because the copies at
the repository root apply to every core. Then sets shortname, author, url,
version and date_release in the core's core.json, and stages the folder with
git add. It doesn't commit.

The new core is a full copy. Later changes to core-template don't reach it, so
bring each one over by hand. The script prints the template commit it copied,
so put that in the commit message.

.PARAMETER Name
Folder name under cores/, in lowercase, such as rallyx.

.PARAMETER ShortName
The core's shortname in core.json, such as Rally-X. Pocket names the core's
folder Cores/<Author>.<ShortName>.

.PARAMETER Author
The author in core.json.

.PARAMETER Ref
Branch or tag of core-template to copy.

.EXAMPLE
./tools/new-core.ps1 -Name rallyx -ShortName Rally-X
#>
param(
    [Parameter(Mandatory)]
    [ValidatePattern("^[a-z0-9][a-z0-9-]*$")]
    [string]$Name,

    # Pocket allows 31 characters. A dot would split Cores/<Author>.<ShortName>.
    [Parameter(Mandatory)]
    [ValidatePattern("^[A-Za-z0-9_-]{1,31}$")]
    [string]$ShortName,

    [ValidatePattern("^[A-Za-z0-9_-]{1,31}$")]
    [string]$Author = "MorganVieira",

    [string]$Ref = "main"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$templateUrl = "https://github.com/vieira-fpga/core-template.git"
$root = Split-Path -Path $PSScriptRoot -Parent
$core = Join-Path -Path $root -ChildPath "cores/$Name"

if (Test-Path -Path $core) {
    throw "$core already exists"
}

# Copy the template and drop its history.
git.exe clone --quiet --depth 1 --branch $Ref $templateUrl $core
$commit = git.exe -C $core rev-parse HEAD
Remove-Item -Path (Join-Path -Path $core -ChildPath ".git") -Recurse -Force

# The repository root has the same Verible configs, and they cover every core.
$lintConfigs = @(
    Join-Path -Path $core -ChildPath ".rules.verible_lint"
    Join-Path -Path $core -ChildPath ".verible_lint_waivers"
)
Remove-Item -Path $lintConfigs -Force

# Edit core.json line by line, so its layout stays as the template has it.
$coreJsonPath = Join-Path -Path $core -ChildPath "core.json"
$coreJson = Get-Content -Path $coreJsonPath -Raw

$metadata = [ordered]@{
    shortname    = $ShortName
    author       = $Author
    url          = "https://github.com/vieira-fpga/cores/tree/main/cores/$Name"
    version      = "0.1.0"
    date_release = Get-Date -Format "yyyy-MM-dd"
}

foreach ($key in $metadata.Keys) {
    $pattern = "(`"$key`":\s*)`"[^`"]*`""

    if ([regex]::Matches($coreJson, $pattern).Count -ne 1) {
        throw "core.json: expected one `"$key`" field"
    }

    $coreJson = [regex]::Replace($coreJson, $pattern, "`${1}`"$($metadata[$key])`"")
}

Set-Content -Path $coreJsonPath -Value $coreJson -NoNewline

git.exe -C $root add -- "cores/$Name"

Write-Host "Copied core-template $commit into cores/$Name as $Author.$ShortName"
