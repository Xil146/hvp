[CmdletBinding()]
param(
    [string]$EvidencePath,
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
$nativeRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($EvidencePath)) { $EvidencePath = Join-Path $nativeRoot 'evidence/source-acquisition.json' }
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path $nativeRoot 'manifests/native-inputs.json' }

$evidenceFullPath = [IO.Path]::GetFullPath($EvidencePath)
$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $evidenceFullPath -PathType Leaf)) { throw "Source acquisition evidence is missing: $evidenceFullPath" }
if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) { throw "Source lock is missing: $manifestFullPath" }
if ([IO.Path]::GetFileName($manifestFullPath) -cne 'native-inputs.json') {
    throw 'Source acquisition evidence requires a complete reviewed manifest root containing native-inputs.json.'
}
& (Join-Path $PSScriptRoot 'Test-NativeLock.ps1') -ManifestRoot (Split-Path -Parent $manifestFullPath) -AllowIncomplete | Out-Null

$evidence = Get-Content -LiteralPath $evidenceFullPath -Raw | ConvertFrom-Json
$inputs = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
if ($evidence.schemaVersion -ne 1 -or $evidence.kind -ne 'hvp-native-source-acquisition-evidence' -or
    $evidence.'$schema' -cne '../manifests/schemas/source-acquisition-evidence.schema.json') {
    throw 'Unsupported source acquisition evidence schema.'
}
$manifestHash = (Get-FileHash -LiteralPath $manifestFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($evidence.sourceLockSha256 -cne $manifestHash) { throw 'Source acquisition evidence does not bind the current source lock.' }

$records = @{}
foreach ($archive in @($evidence.archives)) {
    $key = ([string]$archive.id).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($key) -or $records.ContainsKey($key)) { throw "Duplicate or empty source acquisition evidence id: $($archive.id)" }
    $records[$key] = $archive
}
if ($evidence.archiveCount -ne @($inputs.sources).Count -or $records.Count -ne @($inputs.sources).Count) {
    throw 'Source acquisition evidence count differs from the source lock.'
}
foreach ($source in @($inputs.sources)) {
    $key = ([string]$source.id).ToLowerInvariant()
    if (-not $records.ContainsKey($key)) { throw "Source acquisition evidence is missing: $($source.id)" }
    $archive = $records[$key]
    if ([string]$archive.id -cne [string]$source.id -or
        [string]$archive.version -cne [string]$source.version -or
        [string]$archive.commit -cne [string]$source.commit -or
        [string]$archive.archiveName -cne [string]$source.archive.name -or
        [string]$archive.sourceUrl -cne [string]$source.archive.url -or
        [string]$archive.sha256 -cne [string]$source.archive.sha256 -or
        [long]$archive.length -le 0) {
        throw "Source acquisition evidence differs from the lock: $($source.id)"
    }
}

Write-Host 'Source acquisition evidence matches the locked 13-archive set.'
