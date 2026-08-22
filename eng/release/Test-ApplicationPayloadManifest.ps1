[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PayloadRoot,

    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [string]$ExcludedTopLevelDirectory
)

$ErrorActionPreference = 'Stop'

function Test-ReparsePoint {
    param([Parameter(Mandatory)]$Item)

    return ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
}

function Get-NormalizedPayloadPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path) -or $Path.Contains('\') -or $Path.StartsWith('/') -or $Path.EndsWith('/')) {
        throw "Manifest path is not a normalized relative path: $Path"
    }

    $segments = $Path.Split('/')
    if ($segments.Count -eq 0 -or ($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -ne 0) {
        throw "Manifest path escapes or is not normalized: $Path"
    }

    return $Path
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
if (-not [System.IO.File]::Exists($ManifestPath)) {
    throw "Payload manifest does not exist: $ManifestPath"
}

try {
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
}
catch {
    throw "Payload manifest is not valid JSON: $($_.Exception.Message)"
}

if ($manifest.schemaVersion -ne 1 -or $manifest.payloadKind -ne 'managed-scaffold' -or $null -eq $manifest.files) {
    throw 'Payload manifest does not match the managed-scaffold schema.'
}

$expected = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in @($manifest.files)) {
    if ($null -eq $entry.path -or $null -eq $entry.sha256) {
        throw 'Payload manifest contains an entry without path or sha256.'
    }

    $path = Get-NormalizedPayloadPath -Path ([string]$entry.path)
    $sha256 = ([string]$entry.sha256).ToLowerInvariant()
    if ($sha256 -notmatch '^[0-9a-f]{64}$') {
        throw "Payload manifest has an invalid SHA-256 for $path"
    }
    if ($expected.ContainsKey($path)) {
        throw "Payload manifest contains a duplicate or case-colliding path: $path"
    }
    $expected.Add($path, $sha256)
}

if ($expected.Count -eq 0) {
    throw 'Payload manifest contains no files.'
}

$actual = [System.Collections.Generic.Dictionary[string, System.IO.FileInfo]]::new([System.StringComparer]::OrdinalIgnoreCase)
$items = @(Get-ChildItem -LiteralPath $root -Recurse -Force)
foreach ($item in $items) {
    if (Test-ReparsePoint -Item $item) {
        throw "Payload must not contain a reparse point: $($item.FullName)"
    }
}
foreach ($file in @($items | Where-Object { -not $_.PSIsContainer })) {
    $fullPath = [System.IO.Path]::GetFullPath($file.FullName)
    if (-not $fullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Payload file resolves outside its root: $fullPath"
    }
    $relativePath = $fullPath.Substring($rootWithSeparator.Length).Replace('\', '/')
    if (-not [string]::IsNullOrWhiteSpace($ExcludedTopLevelDirectory) -and
        $relativePath.StartsWith($ExcludedTopLevelDirectory.TrimEnd('/') + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }
    $path = Get-NormalizedPayloadPath -Path $relativePath
    if ($actual.ContainsKey($path)) {
        throw "Payload contains duplicate or case-colliding files: $path"
    }
    $actual.Add($path, $file)
}

foreach ($path in $expected.Keys) {
    if (-not $actual.ContainsKey($path)) {
        throw "Payload is missing manifest file: $path"
    }
}
foreach ($path in $actual.Keys) {
    if (-not $expected.ContainsKey($path)) {
        throw "Payload contains an unexpected file: $path"
    }
}

foreach ($path in $expected.Keys) {
    $actualHash = (Get-FileHash -LiteralPath $actual[$path].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne $expected[$path]) {
        throw "Payload SHA-256 does not match manifest for $path"
    }
}

Write-Host "Validated $($expected.Count) managed application-payload files."
