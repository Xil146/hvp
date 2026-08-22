[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$SourceId,
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/native-inputs.json' }
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw "Archive does not exist: $ArchivePath" }
$inputs = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$matches = @($inputs.sources | Where-Object { $_.id -ceq $SourceId })
if ($inputs.schemaVersion -ne 2 -or $inputs.kind -ne 'hvp-native-source-lock' -or $matches.Count -ne 1) { throw "Source id is undeclared or duplicated: $SourceId" }
$expected = [string]$matches[0].archive.sha256
if ($expected -notmatch '^[0-9a-f]{64}$') { throw "Source hash is not locked: $SourceId" }
$actual = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -cne $expected) { throw "Archive checksum does not match lock: $SourceId" }
Write-Host "Verified archive checksum for $SourceId."
