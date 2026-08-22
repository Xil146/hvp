[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root)

$ErrorActionPreference = 'Stop'
$fullRoot = [IO.Path]::GetFullPath($Root)
if (-not (Test-Path -LiteralPath $fullRoot -PathType Container)) { throw "Tree root does not exist: $fullRoot" }
$rootItem = Get-Item -LiteralPath $fullRoot -Force
if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Tree root cannot be a reparse point.' }
$lines = [Collections.Generic.List[string]]::new()
foreach ($item in @(Get-ChildItem -LiteralPath $fullRoot -Recurse -Force | Sort-Object FullName)) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Tree contains a reparse point: $($item.FullName)" }
    $relative = [IO.Path]::GetRelativePath($fullRoot, $item.FullName).Replace('\','/')
    if ($item.PSIsContainer) { $lines.Add("D $relative") }
    else { $lines.Add("F $relative $((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()) $($item.Length)") }
}
$canonical = ($lines -join "`n") + "`n"
$sha = [Security.Cryptography.SHA256]::Create()
try { $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)) }
finally { $sha.Dispose() }
[pscustomobject]@{ root = $fullRoot; sha256 = (($digest | ForEach-Object { $_.ToString('x2') }) -join ''); entryCount = $lines.Count }
