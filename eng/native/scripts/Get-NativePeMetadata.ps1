[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)

$ErrorActionPreference = 'Stop'
$fullPath = [IO.Path]::GetFullPath($Path)
if (-not [IO.File]::Exists($fullPath)) { throw "PE file does not exist: $fullPath" }
$bytes = [IO.File]::ReadAllBytes($fullPath)
if ($bytes.Length -lt 0x100 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0x5a4d) { throw "Not a PE file: $fullPath" }
$peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
if ($peOffset -lt 0 -or $peOffset + 24 -gt $bytes.Length -or
    $bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45 -or
    $bytes[$peOffset + 2] -ne 0 -or $bytes[$peOffset + 3] -ne 0) {
    throw "Malformed PE signature: $fullPath"
}
$machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
$sectionCount = [BitConverter]::ToUInt16($bytes, $peOffset + 6)
$optionalSize = [BitConverter]::ToUInt16($bytes, $peOffset + 20)
$optionalOffset = $peOffset + 24
if ($optionalOffset + $optionalSize -gt $bytes.Length -or [BitConverter]::ToUInt16($bytes, $optionalOffset) -ne 0x20b) { throw "PE is not PE32+ (AMD64 required): $fullPath" }
if ($optionalSize -lt 0x80) { throw "Malformed PE optional header: $fullPath" }
$coffCharacteristics = [BitConverter]::ToUInt16($bytes, $peOffset + 22)
$dllCharacteristics = [BitConverter]::ToUInt16($bytes, $optionalOffset + 70)
$sections = @()
$sectionOffset = $optionalOffset + $optionalSize
for ($i = 0; $i -lt $sectionCount; $i++) {
    $offset = $sectionOffset + (40 * $i)
    if ($offset + 40 -gt $bytes.Length) { throw "Malformed PE section table: $fullPath" }
    $sections += [pscustomobject]@{ VirtualAddress = [BitConverter]::ToUInt32($bytes, $offset + 12); VirtualSize = [BitConverter]::ToUInt32($bytes, $offset + 8); RawSize = [BitConverter]::ToUInt32($bytes, $offset + 16); RawOffset = [BitConverter]::ToUInt32($bytes, $offset + 20) }
}
function Convert-RvaToOffset([uint32]$Rva) {
    foreach ($section in $sections) {
        $length = [Math]::Max([uint64]$section.VirtualSize, [uint64]$section.RawSize)
        if ($Rva -ge $section.VirtualAddress -and [uint64]$Rva -lt ([uint64]$section.VirtualAddress + $length)) {
            $result = [uint64]$section.RawOffset + ([uint64]$Rva - [uint64]$section.VirtualAddress)
            if ($result -ge $bytes.Length) { throw "PE RVA points outside the file: $fullPath" }
            return [int]$result
        }
    }
    throw "PE RVA has no backing section: $fullPath"
}
function Read-AsciiZ([int]$Offset) {
    if ($Offset -lt 0 -or $Offset -ge $bytes.Length) { throw "PE string is outside the file: $fullPath" }
    $end = $Offset
    while ($end -lt $bytes.Length -and $bytes[$end] -ne 0) { $end++ }
    if ($end -eq $bytes.Length) { throw "Unterminated PE string: $fullPath" }
    return [Text.Encoding]::ASCII.GetString($bytes, $Offset, $end - $Offset)
}
function Get-Directory([int]$Index) {
    $offset = $optionalOffset + 112 + (8 * $Index)
    if ($offset + 8 -gt $optionalOffset + $optionalSize) { return $null }
    $rva = [BitConverter]::ToUInt32($bytes, $offset)
    $size = [BitConverter]::ToUInt32($bytes, $offset + 4)
    if ($rva -eq 0 -or $size -eq 0) { return $null }
    return [pscustomobject]@{ Rva = $rva; Size = $size }
}
$imports = [Collections.Generic.List[string]]::new()
$importDirectory = Get-Directory 1
if ($null -ne $importDirectory) {
    $offset = Convert-RvaToOffset $importDirectory.Rva
    while ($true) {
        if ($offset + 20 -gt $bytes.Length) { throw "Malformed PE import table: $fullPath" }
        $nameRva = [BitConverter]::ToUInt32($bytes, $offset + 12)
        if ($nameRva -eq 0) { break }
        $imports.Add((Read-AsciiZ (Convert-RvaToOffset $nameRva)))
        $offset += 20
    }
}
$delayImports = [Collections.Generic.List[string]]::new()
$delayDirectory = Get-Directory 13
if ($null -ne $delayDirectory) {
    $offset = Convert-RvaToOffset $delayDirectory.Rva
    while ($true) {
        if ($offset + 32 -gt $bytes.Length) { throw "Malformed PE delay-import table: $fullPath" }
        $attributes = [BitConverter]::ToUInt32($bytes, $offset)
        $nameValue = [BitConverter]::ToUInt32($bytes, $offset + 4)
        $allZero = $true
        for ($field = 0; $field -lt 8; $field++) {
            if ([BitConverter]::ToUInt32($bytes, $offset + (4 * $field)) -ne 0) { $allZero = $false; break }
        }
        if ($allZero) { break }
        if (($attributes -band 1) -eq 0 -or $nameValue -eq 0) { throw "Malformed PE delay-import descriptor: $fullPath" }
        $delayImports.Add((Read-AsciiZ (Convert-RvaToOffset $nameValue)))
        $offset += 32
    }
}
$exports = [Collections.Generic.List[string]]::new()
$exportDirectory = Get-Directory 0
if ($null -ne $exportDirectory) {
    $offset = Convert-RvaToOffset $exportDirectory.Rva
    if ($offset + 40 -gt $bytes.Length) { throw "Malformed PE export table: $fullPath" }
    $nameCount = [BitConverter]::ToUInt32($bytes, $offset + 24)
    $namesRva = [BitConverter]::ToUInt32($bytes, $offset + 32)
    if ($nameCount -gt 0) {
        $namesOffset = Convert-RvaToOffset $namesRva
        for ($i = 0; $i -lt $nameCount; $i++) {
            if ($namesOffset + (4 * $i) + 4 -gt $bytes.Length) { throw "Malformed PE export names: $fullPath" }
            $exports.Add((Read-AsciiZ (Convert-RvaToOffset ([BitConverter]::ToUInt32($bytes, $namesOffset + (4 * $i))))))
        }
    }
}
[pscustomobject]@{
    path = $fullPath
    sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    peMachine = switch ($machine) { 0x8664 { 'AMD64' } 0x14c { 'I386' } 0xaa64 { 'ARM64' } default { ('0x{0:x4}' -f $machine) } }
    imports = @($imports | Sort-Object -Unique)
    delayImports = @($delayImports | Sort-Object -Unique)
    exports = @($exports | Sort-Object -Unique)
    coffCharacteristics = ('0x{0:x4}' -f $coffCharacteristics)
    isDll = ($coffCharacteristics -band 0x2000) -ne 0
    dllCharacteristics = ('0x{0:x4}' -f $dllCharacteristics)
    dynamicBase = ($dllCharacteristics -band 0x0040) -ne 0
    nxCompatible = ($dllCharacteristics -band 0x0100) -ne 0
}
