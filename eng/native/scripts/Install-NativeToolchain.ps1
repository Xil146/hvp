[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchiveDirectory,
    [Parameter(Mandatory)][string]$InstallDirectory,
    [string]$ManifestPath,
    [Parameter(Mandatory)][string]$TarPath,
    [string]$GpgPath,
    [string]$KeyringDirectory,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
function Test-AbsolutePath([string]$Path) { return -not [string]::IsNullOrWhiteSpace($Path) -and [IO.Path]::GetFullPath($Path) -ceq $Path }
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/toolchain.lock.json' }
if (-not (Test-AbsolutePath $InstallDirectory) -or (Test-Path -LiteralPath $InstallDirectory)) { throw 'Toolchain install directory must be an absolute new path.' }
& (Join-Path $PSScriptRoot 'Test-NativeToolchainArchiveSet.ps1') -ArchiveDirectory $ArchiveDirectory -ManifestPath $ManifestPath | Out-Null
if ([string]::IsNullOrWhiteSpace($GpgPath) -or [string]::IsNullOrWhiteSpace($KeyringDirectory) -or [string]::IsNullOrWhiteSpace($EvidencePath)) { throw 'Pinned GPG, keyring, and install evidence paths are required.' }
$tar = [IO.Path]::GetFullPath($TarPath); $gpg = [IO.Path]::GetFullPath($GpgPath); $keyring = [IO.Path]::GetFullPath($KeyringDirectory)
foreach ($path in @($tar,$gpg)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Pinned bootstrap executable is missing: $path" } }
if (-not (Test-Path -LiteralPath $keyring -PathType Container)) { throw 'Pinned signature keyring directory is missing.' }
$lockPath = [IO.Path]::GetFullPath($ManifestPath); $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
if ($null -eq $lock.bootstrap) { throw 'Toolchain bootstrap identities are not locked.' }
if ((Get-FileHash -LiteralPath $tar -Algorithm SHA256).Hash.ToLowerInvariant() -cne $lock.bootstrap.tarSha256 -or (Get-FileHash -LiteralPath $gpg -Algorithm SHA256).Hash.ToLowerInvariant() -cne $lock.bootstrap.gpgSha256) { throw 'Toolchain bootstrap executable hash differs from the lock.' }
$keyringTree = & (Join-Path $PSScriptRoot 'Get-NativeTreeHash.ps1') -Root $keyring
if ($keyringTree.sha256 -cne $lock.bootstrap.keyringTreeSha256) { throw 'Toolchain signature keyring differs from the lock.' }
function Assert-DetachedSignature([object]$Record, [string]$ArtifactPath) {
    $signaturePath = Join-Path $ArchiveDirectory ([string]$Record.signature.name)
    $status = @(& $gpg --homedir $keyring --status-fd 1 --verify $signaturePath $ArtifactPath 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Detached signature verification failed: $($Record.id)" }
    $valid = @($status | Where-Object { $_ -match '^\[GNUPG:\] VALIDSIG ' })
    if ($valid.Count -ne 1 -or ($valid[0] -split '\s+')[2] -cne [string]$Record.signature.keyFingerprint) { throw "Detached signature fingerprint differs from the lock: $($Record.id)" }
}
$basePath = Join-Path $ArchiveDirectory $lock.baseArchive.archive.name
& (Join-Path $PSScriptRoot 'Test-NativeTarArchive.ps1') -ArchivePath $basePath -TarPath $tar -AllowSafeLinks | Out-Null
foreach ($package in @($lock.packages)) { & (Join-Path $PSScriptRoot 'Test-NativeTarArchive.ps1') -ArchivePath (Join-Path $ArchiveDirectory $package.archive.name) -TarPath $tar -AllowSafeLinks | Out-Null }
Assert-DetachedSignature ([pscustomobject]@{ id='msys2-base'; signature=$lock.baseArchive.signature }) $basePath
foreach ($package in @($lock.packages)) { Assert-DetachedSignature $package (Join-Path $ArchiveDirectory $package.archive.name) }

$parent = Split-Path -Parent $InstallDirectory; if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Toolchain install parent directory must already exist.' }
$temporary = Join-Path $parent ('.incomplete-toolchain-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    & $tar -xf $basePath -C $temporary; if ($LASTEXITCODE -ne 0) { throw 'MSYS2 base extraction failed.' }
    $top = @(Get-ChildItem -LiteralPath $temporary -Force)
    if ($top.Count -ne 1 -or -not $top[0].PSIsContainer -or ($top[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'MSYS2 base archive must contain one real root directory.' }
    Move-Item -LiteralPath $top[0].FullName -Destination $InstallDirectory
    Remove-Item -LiteralPath $temporary -Force
    $pacman = Join-Path $InstallDirectory 'usr/bin/pacman.exe'
    if (-not (Test-Path -LiteralPath $pacman -PathType Leaf)) { throw 'MSYS2 base archive does not contain pacman.exe at the locked root.' }
    $paths = @($lock.packages | ForEach-Object { Join-Path $ArchiveDirectory $_.archive.name })
    & $pacman --noconfirm --needed -U @paths; if ($LASTEXITCODE -ne 0) { throw 'Offline local MSYS2 package installation failed.' }
    $installed = @(& $pacman -Q); if ($LASTEXITCODE -ne 0) { throw 'Cannot inventory installed MSYS2 packages.' }
    foreach ($package in @($lock.packages)) { if ($installed -cnotcontains "$($package.packageName) $($package.version)") { throw "Installed package identity differs from lock: $($package.id)" } }
    $database = Join-Path $InstallDirectory 'var/lib/pacman/local'; $databaseTree = & (Join-Path $PSScriptRoot 'Get-NativeTreeHash.ps1') -Root $database
    if ($databaseTree.sha256 -cne $lock.packageDatabase.sha256) { throw 'Installed package database tree differs from the preserved lock.' }
    $tree = & (Join-Path $PSScriptRoot 'Get-NativeTreeHash.ps1') -Root $InstallDirectory
    $record = [ordered]@{ schemaVersion=1; kind='hvp-native-toolchain-install-evidence'; installDirectory=[IO.Path]::GetFullPath($InstallDirectory); toolchainLockSha256=(Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant(); treeSha256=$tree.sha256; treeEntryCount=$tree.entryCount; packageDatabaseSha256=$databaseTree.sha256; packageInventory=@($installed | Sort-Object); repositorySync=$false; packageInstallMode='pacman -U locked local archives only' }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($EvidencePath), (($record | ConvertTo-Json -Depth 6) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    [pscustomobject]$record
} catch {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    if (Test-Path -LiteralPath $InstallDirectory) { Remove-Item -LiteralPath $InstallDirectory -Recurse -Force }
    throw
}
