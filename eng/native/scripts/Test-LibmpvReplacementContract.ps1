[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PrivateLibmpvPath,
    [string]$OverridePath = [Environment]::GetEnvironmentVariable('HVP_LIBMPV_PATH'),
    [string]$ExpectedFileName = 'libmpv-2.dll'
)

$ErrorActionPreference = 'Stop'
function Resolve-AbsoluteExistingFile([string]$Candidate, [string]$Description) {
    # IsPathFullyQualified is unavailable in the Windows PowerShell/.NET Framework
    # host still used by Windows CI. A rooted drive path or UNC path is required;
    # a drive-relative path such as C:foo is explicitly rejected.
    if ([string]::IsNullOrWhiteSpace($Candidate) -or $Candidate -notmatch '^(?:[A-Za-z]:[\\/]|\\\\)') { throw "$Description must be an absolute path." }
    $resolved = [IO.Path]::GetFullPath($Candidate)
    if (-not [IO.File]::Exists($resolved)) { throw "$Description does not exist: $resolved" }
    if ([IO.Path]::GetFileName($resolved) -ine $ExpectedFileName) { throw "$Description must name $ExpectedFileName." }
    return $resolved
}
$private = Resolve-AbsoluteExistingFile $PrivateLibmpvPath 'Private libmpv path'
$selected = if ([string]::IsNullOrWhiteSpace($OverridePath)) { $private } else { Resolve-AbsoluteExistingFile $OverridePath 'HVP_LIBMPV_PATH override' }
[pscustomobject]@{ selectedPath = $selected; source = if ([string]::IsNullOrWhiteSpace($OverridePath)) { 'private' } else { 'override' }; allowCurrentDirectory = $false; allowAmbientPath = $false; invalidOverrideFails = $true }
