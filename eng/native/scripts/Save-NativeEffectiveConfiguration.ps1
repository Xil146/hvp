[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$Component,
    [Parameter(Mandatory)][string[]]$RequestedFlags,
    [Parameter(Mandatory)][string[]]$Evidence,
    [Parameter(Mandatory)][string]$CompilerPath,
    [Parameter(Mandatory)][string]$LinkerPath,
    [string]$PolicyPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/native-policy.json'
}
& (Join-Path $PSScriptRoot 'Test-NativeConfiguration.ps1') -Component $Component -Flags $RequestedFlags -PolicyPath $PolicyPath

$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
$requiredKinds = @($policy.effectiveEvidence.$Component)
if ($requiredKinds.Count -eq 0) { throw "No effective-evidence contract exists for component: $Component" }

$records = @()
$seenKinds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$combinedText = [Text.StringBuilder]::new()
foreach ($item in $Evidence) {
    $separator = $item.IndexOf('=')
    if ($separator -le 0) { throw "Evidence must use kind=path syntax: $item" }
    $kind = $item.Substring(0, $separator)
    $path = [IO.Path]::GetFullPath($item.Substring($separator + 1))
    if (-not $seenKinds.Add($kind)) { throw "Duplicate effective-evidence kind: $kind" }
    if ($requiredKinds -notcontains $kind) { throw "Unexpected effective-evidence kind for ${Component}: $kind" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Effective-evidence file is missing: $path" }
    $file = Get-Item -LiteralPath $path -Force
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Effective-evidence file cannot be a reparse point: $path" }
    $content = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) { throw "Effective-evidence file is empty: $path" }
    [void]$combinedText.AppendLine($content)
    $records += [ordered]@{
        kind = $kind
        fileName = $file.Name
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        length = $file.Length
    }
}
foreach ($kind in $requiredKinds) {
    if (-not $seenKinds.Contains($kind)) { throw "Required effective-evidence file is missing: $kind" }
}

foreach ($assertion in @($policy.effectiveAssertions.$Component) + @($policy.effectiveAssertions.all)) {
    if ($combinedText.ToString().IndexOf([string]$assertion, [StringComparison]::Ordinal) -lt 0) {
        throw "Effective configuration does not prove required assertion: $assertion"
    }
}
foreach ($forbidden in @('ambient-path','current-directory','meson-wrap','pacman-sync','glad','vulkan-headers')) {
    if ($combinedText.ToString().IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Effective configuration contains a forbidden dependency/input marker: $forbidden"
    }
}

$tools = @()
foreach ($tool in @(@{ role='compiler'; path=$CompilerPath }, @{ role='linker'; path=$LinkerPath })) {
    $fullPath = [IO.Path]::GetFullPath([string]$tool.path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Native tool is missing: $fullPath" }
    $file = Get-Item -LiteralPath $fullPath -Force
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Native tool cannot be a reparse point: $fullPath" }
    $version = (& $fullPath --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($version)) { throw "Could not capture native tool version: $fullPath" }
    $tools += [ordered]@{
        role = $tool.role
        fileName = $file.Name
        sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        version = $version
    }
}

$record = [ordered]@{
    schemaVersion = 2
    kind = 'hvp-native-effective-configuration'
    component = $Component
    requestedFlags = @($RequestedFlags)
    evidence = $records
    tools = $tools
    environment = [ordered]@{
        sourceDateEpoch = $env:SOURCE_DATE_EPOCH
        locale = $env:LC_ALL
        timezone = $env:TZ
        pythonHashSeed = $env:PYTHONHASHSEED
        msys2PathType = $env:MSYS2_PATH_TYPE
    }
}
$parent = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($OutputPath, (($record | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
