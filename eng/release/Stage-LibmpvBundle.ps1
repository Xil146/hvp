[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$PublishDirectory,
    [string]$ManifestPath,
    [string]$PayloadDirectory
)

$ErrorActionPreference = 'Stop'

function Get-Sha256 {
    param([Parameter(Mandatory)] [string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'native/libmpv-bundle.json' }
if ([string]::IsNullOrWhiteSpace($PayloadDirectory)) { $PayloadDirectory = Join-Path (Get-Location) 'artifacts/libmpv/payload' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.architecture -cne 'x86_64' -or @($manifest.files).Count -ne 1) {
    throw 'Pinned libmpv bundle manifest is incomplete or not Windows x64.'
}

$file = @($manifest.files)[0]
if ($file.sourcePath -cne 'libmpv-2.dll' -or $file.destinationPath -cne 'libmpv-2.dll' -or $file.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw 'Pinned libmpv bundle manifest does not define the expected libmpv-2.dll payload.'
}

if (-not (Test-Path -LiteralPath $PublishDirectory -PathType Container)) { throw 'Publish directory does not exist.' }
$source = Join-Path $PayloadDirectory $file.destinationPath
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Pinned native payload is missing $source. Run eng/native/Get-LibmpvBundle.ps1 first." }

$actual = Get-Sha256 -Path $source
if ($actual -cne $file.sha256.ToLowerInvariant()) { throw "Pinned native payload hash mismatch for $($file.destinationPath)." }

Copy-Item -LiteralPath $source -Destination (Join-Path $PublishDirectory $file.destinationPath) -Force
