[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchiveDirectory,
    [Parameter(Mandatory)][string]$SourceDirectory,
    [Parameter(Mandatory)][string]$TarPath,
    [string]$ManifestPath,
    [string]$ToolchainLockPath,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
function Test-AbsolutePath([string]$Path) { return -not [string]::IsNullOrWhiteSpace($Path) -and [IO.Path]::GetFullPath($Path) -ceq $Path }
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/native-inputs.json' }
if ([string]::IsNullOrWhiteSpace($ToolchainLockPath)) { $ToolchainLockPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/toolchain.lock.json' }
if (-not (Test-AbsolutePath $SourceDirectory)) { throw 'Source extraction directory must be absolute.' }
if (Test-Path -LiteralPath $SourceDirectory) { throw 'Source extraction directory must not already exist.' }
if (-not (Test-Path -LiteralPath $TarPath -PathType Leaf)) { throw 'Pinned tar extractor is missing.' }
$manifest = [IO.Path]::GetFullPath($ManifestPath); $toolchainLock = Get-Content -LiteralPath $ToolchainLockPath -Raw | ConvertFrom-Json
& (Join-Path $PSScriptRoot 'Test-NativeSourceArchiveSet.ps1') -ArchiveDirectory $ArchiveDirectory -ManifestPath $manifest | Out-Null
$tar = [IO.Path]::GetFullPath($TarPath); $inputs = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
if ($null -eq $toolchainLock.bootstrap -or (Get-FileHash -LiteralPath $tar -Algorithm SHA256).Hash.ToLowerInvariant() -cne $toolchainLock.bootstrap.tarSha256) { throw 'Source extractor is not the hash-bound toolchain bootstrap tar.' }
New-Item -ItemType Directory -Path $SourceDirectory | Out-Null
try {
    foreach ($source in @($inputs.sources | Sort-Object id)) {
        $archive = Join-Path $ArchiveDirectory "$($source.id)-$($source.archive.sha256)-$($source.archive.name)"
        & (Join-Path $PSScriptRoot 'Test-NativeTarArchive.ps1') -ArchivePath $archive -TarPath $tar | Out-Null
        $temporary = Join-Path $SourceDirectory ('.incomplete-' + $source.id)
        New-Item -ItemType Directory -Path $temporary | Out-Null
        & $tar -xf $archive -C $temporary
        if ($LASTEXITCODE -ne 0) { throw "Source extraction failed: $($source.id)" }
        $top = @(Get-ChildItem -LiteralPath $temporary -Force)
        if ($top.Count -ne 1 -or -not $top[0].PSIsContainer -or ($top[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Source archive does not contain one safe root directory: $($source.id)" }
        foreach ($item in @(Get-ChildItem -LiteralPath $top[0].FullName -Recurse -Force)) { if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Extracted source contains a link or reparse point: $($source.id)" } }
        Move-Item -LiteralPath $top[0].FullName -Destination (Join-Path $SourceDirectory $source.id)
        Remove-Item -LiteralPath $temporary -Force
    }
} catch { if (Test-Path -LiteralPath $SourceDirectory) { Remove-Item -LiteralPath $SourceDirectory -Recurse -Force }; throw }
$tree = & (Join-Path $PSScriptRoot 'Get-NativeTreeHash.ps1') -Root $SourceDirectory
$record = [ordered]@{ schemaVersion = 1; kind = 'hvp-native-source-tree-evidence'; sourceDirectory = [IO.Path]::GetFullPath($SourceDirectory); sourceCount = @($inputs.sources).Count; sourceLockSha256 = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant(); treeSha256 = $tree.sha256; treeEntryCount = $tree.entryCount; extraction = 'locked archives after type, path, collision, and link validation' }
if (-not [string]::IsNullOrWhiteSpace($EvidencePath)) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($EvidencePath), (($record | ConvertTo-Json -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false)) }
[pscustomobject]$record
