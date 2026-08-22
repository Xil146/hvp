[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$ManagedManifestPath,
    [switch]$RequireApprovedNativeCandidate
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Test-ApplicationPayloadManifest.ps1') -PayloadRoot $PayloadRoot -ManifestPath $ManagedManifestPath -ExcludedTopLevelDirectory 'native'
& (Join-Path $PSScriptRoot 'Test-NativePayloadContract.ps1') -PayloadRoot $PayloadRoot -RequireApprovedCandidate:$RequireApprovedNativeCandidate
Write-Host 'Managed payload and native overlay contracts both passed.'
