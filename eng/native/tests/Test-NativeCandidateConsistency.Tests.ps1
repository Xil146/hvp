[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$nativeRoot = Split-Path -Parent $PSScriptRoot
$template = Join-Path $nativeRoot 'templates/native-candidate.template.json'
$script = Join-Path $nativeRoot 'scripts/Test-NativeCandidateConsistency.ps1'
$rejected = $false
try { & $script -CandidatePath $template } catch { $rejected = $true }
if (-not $rejected) { throw 'The candidate validator accepted its non-release template.' }
Write-Host 'Native candidate consistency validator rejects incomplete template evidence.'
