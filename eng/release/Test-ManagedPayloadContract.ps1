[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PayloadRoot,

    [string]$ContractPath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ContractPath)) {
    $ContractPath = Join-Path $PSScriptRoot 'managed-payload-contract.json'
}

function Test-ReparsePoint {
    param([Parameter(Mandatory)]$Item)

    return ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
}

function Get-NormalizedPayloadPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path) -or $Path.Contains('\') -or $Path.StartsWith('/') -or $Path.EndsWith('/')) {
        throw "Payload path is not a normalized relative path: $Path"
    }
    $segments = $Path.Split('/')
    if ($segments.Count -eq 0 -or ($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -ne 0) {
        throw "Payload path escapes or is not normalized: $Path"
    }
    return $Path
}

function Get-PayloadFiles {
    param([Parameter(Mandatory)][string]$Root)

    $rootItem = Get-Item -LiteralPath $Root -Force
    if (Test-ReparsePoint -Item $rootItem) {
        throw "Payload root must not be a reparse point: $($rootItem.FullName)"
    }

    $rootWithSeparator = $rootItem.FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $items = @(Get-ChildItem -LiteralPath $rootItem.FullName -Force -Recurse)
    foreach ($item in $items) {
        if (Test-ReparsePoint -Item $item) {
            throw "Payload must not contain a reparse point: $($item.FullName)"
        }
    }

    $actual = [System.Collections.Generic.Dictionary[string, System.IO.FileInfo]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @($items | Where-Object { -not $_.PSIsContainer })) {
        $fullPath = [System.IO.Path]::GetFullPath($file.FullName)
        if (-not $fullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Payload file resolves outside its root: $fullPath"
        }
        $path = Get-NormalizedPayloadPath -Path $fullPath.Substring($rootWithSeparator.Length).Replace('\', '/')
        if ($actual.ContainsKey($path)) {
            throw "Payload contains duplicate or case-colliding files: $path"
        }
        $actual.Add($path, $file)
    }
    return $actual
}

if (-not [System.IO.Directory]::Exists($PayloadRoot)) {
    throw "Payload root does not exist: $PayloadRoot"
}
if (-not [System.IO.File]::Exists($ContractPath)) {
    throw "Managed payload contract does not exist: $ContractPath"
}

try {
    $contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json
}
catch {
    throw "Managed payload contract is not valid JSON: $($_.Exception.Message)"
}
if ($contract.schemaVersion -ne 1 -or $contract.payloadKind -ne 'managed-scaffold' -or $null -eq $contract.firstPartyManagedFiles -or $null -eq $contract.allowedFiles) {
    throw 'Managed payload contract does not match the managed-scaffold schema.'
}

$allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in @($contract.allowedFiles)) {
    $path = Get-NormalizedPayloadPath -Path ([string]$entry)
    if (-not $allowed.Add($path)) {
        throw "Managed payload contract contains a duplicate or case-colliding file: $path"
    }
}

$firstParty = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in @($contract.firstPartyManagedFiles)) {
    $path = Get-NormalizedPayloadPath -Path ([string]$entry)
    if (-not $firstParty.Add($path)) {
        throw "Managed payload contract contains a duplicate or case-colliding first-party file: $path"
    }
    if (-not $allowed.Contains($path)) {
        throw "Managed payload contract does not allow required first-party file: $path"
    }
}

$actual = Get-PayloadFiles -Root $PayloadRoot
foreach ($path in $firstParty) {
    if (-not $actual.ContainsKey($path)) {
        throw "Payload is missing required first-party file: $path"
    }
}
foreach ($path in $allowed) {
    if (-not $actual.ContainsKey($path)) {
        throw "Payload is missing contract file: $path"
    }
}
foreach ($path in $actual.Keys) {
    if (-not $allowed.Contains($path)) {
        throw "Payload contains a file not allowed by the managed payload contract: $path"
    }
}

Write-Host "Validated managed payload contract with $($actual.Count) files."
