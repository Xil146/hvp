[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$TarPath,
    [switch]$AllowSafeLinks
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf) -or -not (Test-Path -LiteralPath $TarPath -PathType Leaf)) { throw 'Tar archive or pinned tar executable is missing.' }
function Normalize-ArchivePath([string]$Value, [string]$What) {
    $value = $Value.Replace('\','/').TrimEnd('/')
    while ($value.StartsWith('./')) { $value = $value.Substring(2) }
    if ([string]::IsNullOrWhiteSpace($value) -or $value.StartsWith('/') -or $value.Contains(':')) { throw "Unsafe archive $What path: $Value" }
    $segments = @($value.Split('/'))
    foreach ($segment in $segments) {
        if ($segment -in @('', '.', '..') -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) { throw "Unsafe archive $What path: $Value" }
        $base = $segment.Split('.')[0].ToUpperInvariant()
        if ($base -in @('CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9','LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9')) { throw "Windows-reserved archive $What path: $Value" }
    }
    return ($segments -join '/')
}
function Assert-LinkTarget([string]$Entry, [string]$Target) {
    if ($Target.StartsWith('/') -or $Target.Contains(':') -or $Target.Contains('\')) { throw "Unsafe archive link target: $Entry -> $Target" }
    $stack = [Collections.Generic.List[string]]::new()
    $parent = $Entry.Split('/'); for ($i = 0; $i -lt $parent.Count - 1; $i++) { $stack.Add($parent[$i]) }
    foreach ($part in $Target.Split('/')) {
        if ($part -in @('', '.')) { continue }
        if ($part -eq '..') { if ($stack.Count -eq 0) { throw "Archive link escapes extraction root: $Entry -> $Target" }; $stack.RemoveAt($stack.Count - 1) }
        else { $stack.Add($part) }
    }
    [void](Normalize-ArchivePath ($stack -join '/') 'link target')
}
$names = @(& $TarPath -tf $ArchivePath)
if ($LASTEXITCODE -ne 0 -or $names.Count -eq 0) { throw "Cannot list tar archive: $ArchivePath" }
$verbose = @(& $TarPath -tvf $ArchivePath)
if ($LASTEXITCODE -ne 0 -or $verbose.Count -ne $names.Count) { throw "Tar verbose inventory does not align with archive names: $ArchivePath" }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
for ($index = 0; $index -lt $names.Count; $index++) {
    $name = Normalize-ArchivePath ([string]$names[$index]) 'entry'
    if (-not $seen.Add($name)) { throw "Duplicate or case-colliding tar entry: $name" }
    $line = [string]$verbose[$index]
    if ([string]::IsNullOrWhiteSpace($line)) { throw "Tar entry has no type metadata: $name" }
    $type = $line[0]
    if ($type -in @('-','d')) { continue }
    if (-not $AllowSafeLinks -or $type -notin @('l','h')) { throw "Tar entry type is not allowed: $type $name" }
    $marker = if ($type -eq 'l') { ' -> ' } else { ' link to ' }
    $position = $line.LastIndexOf($marker, [StringComparison]::Ordinal)
    if ($position -lt 0) { throw "Cannot parse tar link target: $name" }
    Assert-LinkTarget $name $line.Substring($position + $marker.Length)
}
[pscustomobject]@{ archive = [IO.Path]::GetFullPath($ArchivePath); entryCount = $names.Count; safeLinksAllowed = [bool]$AllowSafeLinks; entries = @($seen | Sort-Object) }
