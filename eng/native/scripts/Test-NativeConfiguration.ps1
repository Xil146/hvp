[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Component,
    [Parameter(Mandatory)][string[]]$Flags,
    [string]$PolicyPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/native-policy.json'
}

function Get-OptionKey([string]$Flag) {
    if ($Flag -match '^(?<key>--[^=]+)(=.*)?$') { return $Matches.key.ToLowerInvariant() }
    if ($Flag -match '^(?<key>-D[^=]+)(=.*)?$') { return $Matches.key.ToLowerInvariant() }
    return $Flag.ToLowerInvariant()
}

$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
if ($policy.schemaVersion -ne 2 -or $policy.kind -ne 'hvp-native-policy') {
    throw 'Unsupported native policy schema.'
}

$required = @($policy.required.$Component)
if ($required.Count -eq 0) { throw "No approved policy exists for component: $Component" }

$seenFlags = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$seenExactFlags = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$seenKeys = @{}
foreach ($flag in $Flags) {
    if ([string]::IsNullOrWhiteSpace($flag) -or -not $seenFlags.Add($flag)) {
        throw "Duplicate, case-alias, or empty flag: $flag"
    }
    [void]$seenExactFlags.Add($flag)

    $key = Get-OptionKey $flag
    if ($seenKeys.ContainsKey($key)) { throw "Native option is assigned more than once: $key" }
    $seenKeys[$key] = $flag

    foreach ($forbidden in @($policy.forbiddenOptionKeys)) {
        $forbiddenKey = Get-OptionKey ([string]$forbidden)
        $hasAssignment = [string]$forbidden -match '='
        if (($hasAssignment -and $flag -ieq [string]$forbidden) -or
            (-not $hasAssignment -and $key -eq $forbiddenKey)) {
            throw "Forbidden native option: $flag"
        }
    }
}

foreach ($requiredFlag in $required) {
    if (-not $seenExactFlags.Contains([string]$requiredFlag)) {
        throw "Required native option is missing: $requiredFlag"
    }
}
if ($seenExactFlags.Count -ne $required.Count) {
    $extra = @($Flags | Where-Object { $required -cnotcontains $_ })
    throw "Unreviewed native option is not allowed: $($extra -join ', ')"
}

Write-Host "Approved $Component requested configuration validated."
