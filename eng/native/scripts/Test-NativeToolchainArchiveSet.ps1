[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchiveDirectory,
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/toolchain.lock.json' }

function Assert-Regular([string]$Path, [string]$What) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Locked toolchain artifact is missing: $What" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 0) { throw "Locked toolchain artifact is not a non-empty regular file: $What" }
    return $item
}
function Assert-Hash([string]$Path, [string]$Expected, [string]$What) {
    if ($Expected -cnotmatch '^[0-9a-f]{64}$') { throw "Toolchain artifact hash is not locked: $What" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $Expected) { throw "Locked toolchain artifact checksum mismatch: $What" }
}

$lockPath = [IO.Path]::GetFullPath($ManifestPath)
if ([IO.Path]::GetFileName($lockPath) -cne 'toolchain.lock.json') { throw 'Toolchain archive verification requires toolchain.lock.json.' }
$manifestRoot = Split-Path -Parent $lockPath
& (Join-Path $PSScriptRoot 'Test-NativeLock.ps1') -ManifestRoot $manifestRoot -BuildInputsOnly | Out-Null
$root = [IO.Path]::GetFullPath($ArchiveDirectory)
$rootItem = Get-Item -LiteralPath $root -Force
if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Toolchain archive directory must be a real directory.' }
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$records = @([pscustomobject]@{ id = 'msys2-base'; archive = $lock.baseArchive.archive; signature = $lock.baseArchive.signature }) + @($lock.packages | ForEach-Object { [pscustomobject]@{ id = $_.id; archive = $_.archive; signature = $_.signature } })
$expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($record in $records) {
    foreach ($artifact in @(@{ value = $record.archive; kind = 'archive' }, @{ value = $record.signature; kind = 'signature' })) {
        $name = [string]$artifact.value.name
        if (-not $expected.Add($name)) { throw "Duplicate or case-colliding locked toolchain artifact: $name" }
        $path = Join-Path $root $name
        Assert-Regular $path "$($record.id) $($artifact.kind)" | Out-Null
        Assert-Hash $path ([string]$artifact.value.sha256) "$($record.id) $($artifact.kind)"
    }
}
$files = @(Get-ChildItem -LiteralPath $root -File -Force)
foreach ($file in $files) {
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Toolchain archive set contains a reparse point: $($file.Name)" }
    if (-not $expected.Contains($file.Name)) { throw "Unexpected toolchain artifact: $($file.Name)" }
}
if ($files.Count -ne $expected.Count) { throw 'Toolchain archive set does not match the locked closure.' }

[pscustomobject]@{ archiveCount = $records.Count; artifactCount = $expected.Count; lockSha256 = (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant() }
