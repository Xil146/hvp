[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PayloadRoot,

    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [Parameter(Mandatory)]
    [string]$ChecksumsPath
)

$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($PayloadRoot)
if (-not [System.IO.Directory]::Exists($root)) {
    throw "Payload root does not exist: $root"
}
$rootWithSeparator = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$checksumsFullPath = [System.IO.Path]::GetFullPath($ChecksumsPath)
if ($checksumsFullPath -eq $root -or $checksumsFullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The payload checksums must be written outside the payload root; a checksum file cannot hash itself.'
}

& (Join-Path $PSScriptRoot 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $PayloadRoot -ManifestPath $ManifestPath

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$hashByPath = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
foreach ($entry in @($manifest.files)) {
    $hashByPath.Add([string]$entry.path, ([string]$entry.sha256).ToLowerInvariant())
}
$paths = [System.Collections.Generic.List[string]]::new()
foreach ($path in $hashByPath.Keys) {
    $paths.Add($path)
}
$paths.Sort([System.StringComparer]::Ordinal)
$lines = @(
    foreach ($path in $paths) {
        '{0} *{1}' -f $hashByPath[$path], $path
    }
)

$checksumsDirectory = Split-Path -Parent $checksumsFullPath
if ($checksumsDirectory) {
    New-Item -ItemType Directory -Path $checksumsDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllLines($checksumsFullPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
