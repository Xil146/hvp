[CmdletBinding()]
param([Parameter(Mandatory)][string]$ArchivePath)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ([IO.Path]::GetExtension($ArchivePath) -cne '.zip') { throw 'The validation fixture must be a ZIP archive.' }
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw 'ZIP archive does not exist.' }
if (((Get-Item -LiteralPath $ArchivePath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'ZIP archive cannot be a reparse point.'
}

$reserved = '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$'
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
try {
    foreach ($entry in $archive.Entries) {
        $name = $entry.FullName.Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($name) -or [IO.Path]::IsPathRooted($name) -or
            $name.StartsWith('/') -or $name.Contains(':') -or
            @($name.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -ne 0) {
            throw "Unsafe ZIP entry path: $($entry.FullName)"
        }
        foreach ($segment in $name.Split('/')) {
            if ($segment -match $reserved -or $segment -match '[\. ]$') {
                throw "Windows-unsafe ZIP entry path: $($entry.FullName)"
            }
        }
        $normalized = $name.TrimEnd('/')
        if (-not $seen.Add($normalized)) { throw "Duplicate or case-colliding ZIP entry: $($entry.FullName)" }
        $unixMode = ($entry.ExternalAttributes -shr 16) -band 0xF000
        if ($unixMode -ne 0 -and $unixMode -notin @(0x8000, 0x4000)) {
            throw "Special or symbolic ZIP entry is not allowed: $($entry.FullName)"
        }
    }
}
finally { $archive.Dispose() }

Write-Host 'ZIP fixture paths are safe. No extraction was performed.'
