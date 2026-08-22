[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DownloadDirectory,
    [Parameter(Mandatory)][switch]$QuarantineOnly,
    [string]$ManifestPath,
    [string]$EvidencePath,
    [scriptblock]$DownloadScript
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/native-inputs.json'
}
if (-not $QuarantineOnly) { throw 'Source acquisition is quarantine-only until signature, pin, and license evidence is complete.' }

$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
if ([IO.Path]::GetFileName($manifestFullPath) -cne 'native-inputs.json') {
    throw 'Source acquisition requires a complete reviewed manifest root containing native-inputs.json.'
}
$manifestRoot = Split-Path -Parent $manifestFullPath
& (Join-Path $PSScriptRoot 'Test-NativeLock.ps1') -ManifestRoot $manifestRoot -AllowIncomplete | Out-Null

$inputs = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
if ($inputs.schemaVersion -ne 2 -or $inputs.kind -ne 'hvp-native-source-lock') { throw 'Unsupported source lock schema.' }
$downloadRoot = [IO.Path]::GetFullPath($DownloadDirectory)
$quarantineRoot = Join-Path $downloadRoot 'quarantine'

foreach ($source in @($inputs.sources | Sort-Object id)) {
    if ([string]$source.archive.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw "Source archive hash is not locked: $($source.id)" }
    $expectedPath = Join-Path $quarantineRoot "$($source.id)-$($source.archive.sha256)-$($source.archive.name)"
    if (Test-Path -LiteralPath $expectedPath -PathType Leaf) { continue }
    & (Join-Path $PSScriptRoot 'Get-NativeSourceArchive.ps1') `
        -SourceId ([string]$source.id) `
        -DownloadDirectory $downloadRoot `
        -ManifestPath $manifestFullPath `
        -AllowQuarantineForHashDiscovery `
        -DownloadScript $DownloadScript | Out-Null
}

& (Join-Path $PSScriptRoot 'Test-NativeSourceArchiveSet.ps1') `
    -ArchiveDirectory $quarantineRoot `
    -ManifestPath $manifestFullPath `
    -EvidencePath $EvidencePath
