[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [string]$ContractPath,
    [switch]$RequireApprovedCandidate
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ContractPath)) { $ContractPath = Join-Path $PSScriptRoot 'native-payload-contract.json' }
if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container) -or -not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) { throw 'Native payload root or contract is missing.' }
$contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json
if ($contract.schemaVersion -ne 1 -or $contract.payloadKind -cne 'native-candidate-overlay' -or [string]::IsNullOrWhiteSpace([string]$contract.nativeDirectory)) { throw 'Unsupported native payload contract.' }
$root = [IO.Path]::GetFullPath($PayloadRoot); $nativeRoot = [IO.Path]::GetFullPath((Join-Path $root $contract.nativeDirectory))
if (-not $nativeRoot.StartsWith($root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $nativeRoot -PathType Container)) { throw 'Native payload directory is missing or escapes the payload root.' }
$candidate = Join-Path $root ([string]$contract.candidateManifest)
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { if ($RequireApprovedCandidate) { throw 'Approved native candidate manifest is required.' }; Write-Host 'No approved native candidate overlay is present; native release gate remains closed.'; return }
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'native/scripts/Test-NativeCandidateConsistency.ps1') -CandidatePath $candidate -PayloadRoot $nativeRoot -RequirePayload
