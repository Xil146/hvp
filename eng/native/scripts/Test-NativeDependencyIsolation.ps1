[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][string]$Msys2Root,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
$evidence=[IO.Path]::GetFullPath($EvidenceRoot);$allowed=@([IO.Path]::GetFullPath($Prefix),[IO.Path]::GetFullPath($SourceRoot),[IO.Path]::GetFullPath($BuildRoot),[Environment]::GetFolderPath('Windows'),${env:ProgramFiles(x86)}+'\Windows Kits')|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}
$msys=[IO.Path]::GetFullPath($Msys2Root);$paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($file in @(Get-ChildItem -LiteralPath $evidence -File -Force|Where-Object{$_.Name-like'*dependencies*'-or$_.Name-like'*CMakeCache*'-or$_.Name-eq'ffmpeg-config.mak'})){
    $text=Get-Content -LiteralPath $file.FullName -Raw
    if($text-match '(?i)(wrapdb|\.wrap(?:["'';\s]|$)|forcefallback)'){throw "Dependency evidence contains a Meson wrap/fallback marker: $($file.Name)"}
    foreach($match in [regex]::Matches($text,'(?i)(?:[A-Z]:[\\/][^"'';\r\n ]+|/(?:[^"'';\r\n ]+/)*[^"'';\r\n ]+\.(?:dll|lib|a))')){[void]$paths.Add($match.Value.TrimEnd(',)',']'))}
}
foreach($value in $paths){$windows=$value;if($value.StartsWith('/')){continue};$full=[IO.Path]::GetFullPath($windows);if($full.StartsWith($msys,[StringComparison]::OrdinalIgnoreCase)){throw "Target dependency resolves from the MSYS2 toolchain rather than the private prefix: $value"};if(@($allowed|Where-Object{$full.StartsWith($_,[StringComparison]::OrdinalIgnoreCase)}).Count-eq 0){throw "Target dependency path is outside approved source/build/prefix/system roots: $value"}}
$record=[ordered]@{schemaVersion=1;kind='hvp-native-dependency-isolation';isolated=$true;ambientPathAllowed=$false;currentDirectoryAllowed=$false;mesonWrapAllowed=$false;inspectedPaths=@($paths|Sort-Object);approvedRoots=@($allowed)}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(($record|ConvertTo-Json -Depth 6)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));[pscustomobject]$record
