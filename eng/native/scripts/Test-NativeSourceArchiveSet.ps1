[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchiveDirectory,
    [string]$ManifestPath,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/native-inputs.json'
}

function Assert-NotReparsePoint([IO.FileSystemInfo]$Item, [string]$What) {
    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not allowed in the native source archive set: $What"
    }
}

$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
$archiveRoot = [IO.Path]::GetFullPath($ArchiveDirectory)
if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) { throw "Source lock is missing: $manifestFullPath" }
if ([IO.Path]::GetFileName($manifestFullPath) -cne 'native-inputs.json') {
    throw 'Source archive verification requires a complete reviewed manifest root containing native-inputs.json.'
}
$manifestRoot = Split-Path -Parent $manifestFullPath
& (Join-Path $PSScriptRoot 'Test-NativeLock.ps1') -ManifestRoot $manifestRoot -AllowIncomplete | Out-Null
if (-not (Test-Path -LiteralPath $archiveRoot -PathType Container)) { throw "Source archive directory is missing: $archiveRoot" }
Assert-NotReparsePoint (Get-Item -LiteralPath $archiveRoot -Force) $archiveRoot

$inputs = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
if ($inputs.schemaVersion -ne 2 -or $inputs.kind -ne 'hvp-native-source-lock') { throw 'Unsupported source lock schema.' }

$expectedNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$evidence = @()
foreach ($source in @($inputs.sources | Sort-Object id)) {
    if ([string]$source.archive.sha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw "Source archive hash is not locked: $($source.id)"
    }
    $expectedName = "$($source.id)-$($source.archive.sha256)-$($source.archive.name)"
    if (-not $expectedNames.Add($expectedName)) { throw "Duplicate or case-colliding source archive name: $expectedName" }
    $archivePath = Join-Path $archiveRoot $expectedName
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw "Locked source archive is missing: $($source.id)" }
    $item = Get-Item -LiteralPath $archivePath -Force
    Assert-NotReparsePoint $item $archivePath
    if ($item.Length -le 0) { throw "Locked source archive is empty: $($source.id)" }
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne [string]$source.archive.sha256) { throw "Locked source archive checksum mismatch: $($source.id)" }
    $evidence += [ordered]@{
        id = [string]$source.id
        version = [string]$source.version
        commit = [string]$source.commit
        archiveName = [string]$source.archive.name
        sourceUrl = [string]$source.archive.url
        sha256 = $actualHash
        length = [long]$item.Length
    }
}

$actualFiles = @(Get-ChildItem -LiteralPath $archiveRoot -File -Force)
foreach ($file in $actualFiles) {
    Assert-NotReparsePoint $file $file.FullName
    if (-not $expectedNames.Contains($file.Name)) { throw "Unexpected source archive file: $($file.Name)" }
}
if ($actualFiles.Count -ne $expectedNames.Count) { throw 'Source archive set does not match the locked source count.' }

$record = [ordered]@{
    '$schema' = '../manifests/schemas/source-acquisition-evidence.schema.json'
    schemaVersion = 1
    kind = 'hvp-native-source-acquisition-evidence'
    sourceLockSha256 = (Get-FileHash -LiteralPath $manifestFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    archiveCount = $evidence.Count
    archives = $evidence
}
if (-not [string]::IsNullOrWhiteSpace($EvidencePath)) {
    $evidenceFullPath = [IO.Path]::GetFullPath($EvidencePath)
    $evidenceParent = Split-Path -Parent $evidenceFullPath
    if (-not (Test-Path -LiteralPath $evidenceParent -PathType Container)) {
        New-Item -ItemType Directory -Path $evidenceParent -Force | Out-Null
    }
    $temporaryPath = "$evidenceFullPath.incomplete-$([guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($temporaryPath, (($record | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $evidenceFullPath) { throw "Source acquisition evidence already exists: $evidenceFullPath" }
        [IO.File]::Move($temporaryPath, $evidenceFullPath)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

$record
