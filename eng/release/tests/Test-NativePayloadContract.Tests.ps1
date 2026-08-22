[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$releaseRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hvp-native-payload-' + [guid]::NewGuid())
try {
  $payload = Join-Path $testRoot 'payload'; New-Item -ItemType Directory -Path (Join-Path $payload 'native') -Force | Out-Null
  & (Join-Path $releaseRoot 'Test-NativePayloadContract.ps1') -PayloadRoot $payload
  $failed = $false; try { & (Join-Path $releaseRoot 'Test-NativePayloadContract.ps1') -PayloadRoot $payload -RequireApprovedCandidate } catch { $failed = $true }
  if (-not $failed) { throw 'Native payload contract accepted a missing required candidate.' }
  Write-Host 'Native payload contract remains closed until approved candidate evidence exists.'
} finally { if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force } }
