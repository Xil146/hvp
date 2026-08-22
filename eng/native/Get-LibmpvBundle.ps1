[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$CacheDirectory,
    [string]$DestinationDirectory
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path $PSScriptRoot 'libmpv-bundle.json' }
if ([string]::IsNullOrWhiteSpace($CacheDirectory)) { $CacheDirectory = Join-Path (Get-Location) 'artifacts/libmpv/cache' }
if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) { $DestinationDirectory = Join-Path (Get-Location) 'artifacts/libmpv/payload' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.architecture -cne 'x86_64' -or [string]::IsNullOrWhiteSpace($manifest.downloadUrl)) {
    throw 'The libmpv bundle manifest is incomplete or not Windows x64.'
}

New-Item -ItemType Directory -Force -Path $CacheDirectory, $DestinationDirectory | Out-Null
$archive = Join-Path $CacheDirectory $manifest.asset
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    Invoke-WebRequest -Uri $manifest.downloadUrl -OutFile $archive
}

$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($archiveHash -cne $manifest.archiveSha256) { throw "libmpv archive SHA-256 mismatch: $archiveHash" }

$extractRoot = Join-Path $CacheDirectory 'extracted'
if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Force -Recurse }
New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
tar.exe -xf $archive -C $extractRoot
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the pinned libmpv archive.' }

foreach ($file in @($manifest.files)) {
    $source = Join-Path $extractRoot $file.sourcePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Pinned bundle is missing $($file.sourcePath)." }
    $actual = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $file.sha256.ToLowerInvariant()) { throw "libmpv DLL SHA-256 mismatch for $($file.sourcePath): $actual" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $DestinationDirectory $file.destinationPath) -Force
}

Write-Host "Pinned libmpv $($manifest.release) staged at $DestinationDirectory."
