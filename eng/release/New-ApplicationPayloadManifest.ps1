[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PayloadRoot,

    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [string]$ContractPath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ContractPath)) {
    $ContractPath = Join-Path $PSScriptRoot 'managed-payload-contract.json'
}

& (Join-Path $PSScriptRoot 'Test-ManagedPayloadContract.ps1') -PayloadRoot $PayloadRoot -ContractPath $ContractPath

function Test-ReparsePoint {
    param([Parameter(Mandatory)]$Item)

    return ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
}

$root = [System.IO.Path]::GetFullPath($PayloadRoot)
if (-not [System.IO.Directory]::Exists($root)) {
    throw "Payload root does not exist: $root"
}
$rootItem = Get-Item -LiteralPath $root -Force
if (Test-ReparsePoint -Item $rootItem) {
    throw "Payload root must not be a reparse point: $($rootItem.FullName)"
}
$rootWithSeparator = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

$manifestFullPath = [System.IO.Path]::GetFullPath($ManifestPath)
if ($manifestFullPath -eq $root -or $manifestFullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The payload manifest must be written outside the payload root; a manifest cannot hash itself.'
}

$items = @(Get-ChildItem -LiteralPath $root -Recurse -Force)
foreach ($item in $items) {
    if (Test-ReparsePoint -Item $item) {
        throw "Payload must not contain a reparse point: $($item.FullName)"
    }
}

$paths = [System.Collections.Generic.List[string]]::new()
$fileByPath = [System.Collections.Generic.Dictionary[string, System.IO.FileInfo]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($file in @($items | Where-Object { -not $_.PSIsContainer })) {
            $fullPath = [System.IO.Path]::GetFullPath($file.FullName)
            if (-not $fullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Payload file resolves outside its root: $fullPath"
            }
            $relativePath = $fullPath.Substring($rootWithSeparator.Length).Replace('\', '/')
    if ($fileByPath.ContainsKey($relativePath)) {
        throw "Payload contains duplicate or case-colliding files: $relativePath"
    }
    $fileByPath.Add($relativePath, $file)
    $paths.Add($relativePath)
}
$paths.Sort([System.StringComparer]::Ordinal)
$files = @(
    foreach ($path in $paths) {
        [ordered]@{
            path = $path
            sha256 = (Get-FileHash -LiteralPath $fileByPath[$path].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
)

if ($files.Count -eq 0) {
    throw "Payload root contains no files: $root"
}

$manifest = [ordered]@{
    schemaVersion = 1
    payloadKind = 'managed-scaffold'
    files = $files
}

$manifestDirectory = Split-Path -Parent $manifestFullPath
if ($manifestDirectory) {
    New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
}

$manifestJson = $manifest | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($manifestFullPath, $manifestJson + [System.Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
