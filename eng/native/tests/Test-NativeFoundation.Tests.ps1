[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$nativeRoot = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $nativeRoot 'scripts'
$manifestRoot = Join-Path $nativeRoot 'manifests'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hvp-native-foundation-' + [guid]::NewGuid().ToString('N'))

function Assert-Rejected([scriptblock]$Action, [string]$ExpectedMessage) {
    try { & $Action }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($ExpectedMessage) -and $_.Exception.Message -notlike "*$ExpectedMessage*") {
            throw "Validation failed for the wrong reason. Expected '$ExpectedMessage', got '$($_.Exception.Message)'."
        }
        return
    }
    throw 'A fail-closed native validation case was accepted.'
}
function Copy-FixtureManifests([string]$Name) {
    $destination = Join-Path $testRoot $Name
    Copy-Item -LiteralPath $manifestRoot -Destination $destination -Recurse
    return $destination
}
function Save-Json([object]$Value, [string]$Path) {
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 30) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}
function Invoke-Lock([string]$Root, [switch]$AllowIncomplete) {
    & (Join-Path $scripts 'Test-NativeLock.ps1') -ManifestRoot $Root -AllowIncomplete:$AllowIncomplete
}
function New-TestZip([string]$Path, [string[]]$Entries) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($entryName in $Entries) {
                $entry = $archive.CreateEntry($entryName)
                $writer = [IO.StreamWriter]::new($entry.Open())
                try { $writer.Write('fixture') } finally { $writer.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}
function New-LockedToolchainPackage([string]$Id, [AllowEmptyCollection()][string[]]$DependsOn) {
    return [pscustomobject]@{
        id = $Id
        packageName = "mingw-w64-clang-x86_64-$Id"
        version = '1.0.0-1'
        architecture = 'x86_64'
        archive = [pscustomobject]@{
            name = "$Id-1.0.0-1-any.pkg.tar.zst"
            url = "https://repo.msys2.org/mingw/clang64/$Id-1.0.0-1-any.pkg.tar.zst"
            allowedRedirectHosts = @('repo.msys2.org')
            sha256 = ('a' * 64)
        }
        signature = [pscustomobject]@{
            name = "$Id-1.0.0-1-any.pkg.tar.zst.sig"
            url = "https://repo.msys2.org/mingw/clang64/$Id-1.0.0-1-any.pkg.tar.zst.sig"
            allowedRedirectHosts = @('repo.msys2.org')
            sha256 = ('b' * 64)
            keyFingerprint = ('C' * 40)
            status = 'verified'
            evidence = 'Fixture detached-signature verification evidence.'
        }
        dependsOn = [string[]]@($DependsOn)
    }
}
function Complete-ProductionFixture([string]$Root) {
    $inputsPath = Join-Path $Root 'native-inputs.json'
    $inputs = Get-Content -LiteralPath $inputsPath -Raw | ConvertFrom-Json
    foreach ($source in @($inputs.sources)) {
        $source.archive.sha256 = ('a' * 64)
        $source.pinToCommit = 'verified'
        $source.signature.status = 'not-available-reviewed'
        $source.signature.fingerprint = $null
        $source.signature.evidence = 'Synthetic production-boundary fixture evidence.'
        $source.licenseConcluded = 'TEST-ONLY'
    }
    Save-Json $inputs $inputsPath

    $toolchainPath = Join-Path $Root 'toolchain.lock.json'
    $toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json
    $toolchain.baseArchive = [pscustomobject]@{
        id = 'msys2-base'; version = '2026-08-01'; architecture = 'x86_64'
        archive = [pscustomobject]@{ name = 'msys2-base-x86_64-20260801.tar.xz'; url = 'https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-20260801.tar.xz'; allowedRedirectHosts = @('repo.msys2.org'); sha256 = ('a' * 64) }
        signature = [pscustomobject]@{ name = 'msys2-base-x86_64-20260801.tar.xz.sig'; url = 'https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-20260801.tar.xz.sig'; allowedRedirectHosts = @('repo.msys2.org'); sha256 = ('b' * 64); keyFingerprint = ('C' * 40); status = 'verified'; evidence = 'Synthetic detached-signature fixture evidence.' }
    }
    $packages = @()
    foreach ($id in @($toolchain.requiredPackageIds)) {
        $dependencies = if ($id -eq 'clang') { @('bash') } else { @() }
        $packages += New-LockedToolchainPackage -Id $id -DependsOn $dependencies
    }
    $toolchain.packages = $packages
    $toolchain.packageDatabase = [pscustomobject]@{ path = 'var/lib/pacman/local'; sha256 = ('d' * 64); packageIds = @($toolchain.requiredPackageIds); evidence = 'Synthetic package database snapshot.' }
    $toolchain.bootstrap = [pscustomobject]@{ tarSha256 = ('1' * 64); gpgSha256 = ('2' * 64); keyringTreeSha256 = ('3' * 64) }
    $toolchain.closureStatus = 'verified'
    Save-Json $toolchain $toolchainPath

    $outputsPath = Join-Path $Root 'output-contract.json'
    $outputs = Get-Content -LiteralPath $outputsPath -Raw | ConvertFrom-Json
    foreach ($output in @($outputs.outputs)) {
        $output.path = "$($output.role).dll"
        $output.sha256 = ('e' * 64)
        $output.peMachine = 'AMD64'
        $output.imports = @('KERNEL32.dll')
        $output | Add-Member -NotePropertyName delayImports -NotePropertyValue @() -Force
        $output.exports = @("$($output.role)_fixture_export")
        $output | Add-Member -NotePropertyName dllCharacteristics -NotePropertyValue '0x0140' -Force
        $output.apiVersion = $null
        $output.licenseConclusion = 'TEST-ONLY'
    }
    $libmpv = @($outputs.outputs | Where-Object role -eq 'libmpv')[0]
    $libmpv.apiVersion = '2.5'
    $libmpv.exports = @('mpv_client_api_version','mpv_create','mpv_initialize','mpv_terminate_destroy','mpv_set_option_string','mpv_command','mpv_wait_event')
    $outputs.closureEvidence.recursiveImportsComplete = $true
    $outputs.closureEvidence.unexpectedDlls = [Collections.ArrayList]::new()
    $outputs.closureEvidence.systemDllAllowlistVersion = 'windows-system-dlls-v1'
    Save-Json $outputs $outputsPath
}
function New-ProductionFixture([string]$Name) {
    $root = Copy-FixtureManifests $Name
    Complete-ProductionFixture $root
    return $root
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null

    $baseline = Copy-FixtureManifests 'baseline'
    Invoke-Lock $baseline -AllowIncomplete
    Assert-Rejected { Invoke-Lock $baseline } 'Production source provenance is incomplete'
    Assert-Rejected {
        & (Join-Path $scripts 'Invoke-NativeToolchainAcquisition.ps1') -DownloadDirectory (Join-Path $testRoot 'incomplete-toolchain') -ManifestPath (Join-Path $baseline 'toolchain.lock.json') -DownloadScript { throw 'must not download' }
    } 'Production source provenance is incomplete'
    Assert-Rejected {
        & (Join-Path $scripts 'Install-NativeToolchain.ps1') -ArchiveDirectory (Join-Path $testRoot 'no-toolchain-archives') -InstallDirectory (Join-Path $testRoot 'toolchain-install') -TarPath (Get-Command tar.exe -ErrorAction Stop).Source -ManifestPath (Join-Path $baseline 'toolchain.lock.json')
    } 'Production source provenance is incomplete'
    & (Join-Path $scripts 'Test-NativeSourceAcquisitionEvidence.ps1')
    $badAcquisitionEvidencePath = Join-Path $testRoot 'bad-source-acquisition-evidence.json'
    $badAcquisitionEvidence = Get-Content -LiteralPath (Join-Path $nativeRoot 'evidence/source-acquisition.json') -Raw | ConvertFrom-Json
    $badAcquisitionEvidence.sourceLockSha256 = ('0' * 64)
    Save-Json $badAcquisitionEvidence $badAcquisitionEvidencePath
    Assert-Rejected {
        & (Join-Path $scripts 'Test-NativeSourceAcquisitionEvidence.ps1') -EvidencePath $badAcquisitionEvidencePath -ManifestPath (Join-Path $manifestRoot 'native-inputs.json')
    } 'does not bind the current source lock'

    # Canonical Windows PowerShell 5.1 invocation must resolve default paths.
    $cliOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'Test-NativeLock.ps1') -AllowIncomplete 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Canonical Test-NativeLock invocation failed: $($cliOutput -join [Environment]::NewLine)" }

    $missingSource = Copy-FixtureManifests 'missing-source'
    $inputs = Get-Content -LiteralPath (Join-Path $missingSource 'native-inputs.json') -Raw | ConvertFrom-Json
    $inputs.sources = @($inputs.sources | Select-Object -Skip 1)
    Save-Json $inputs (Join-Path $missingSource 'native-inputs.json')
    Assert-Rejected { Invoke-Lock $missingSource -AllowIncomplete } 'set differs'

    $floating = Copy-FixtureManifests 'floating'
    $inputs = Get-Content -LiteralPath (Join-Path $floating 'native-inputs.json') -Raw | ConvertFrom-Json
    $inputs.sources[0].archive.url = 'https://github.com/mpv-player/mpv/archive/main.tar.gz'
    Save-Json $inputs (Join-Path $floating 'native-inputs.json')
    Assert-Rejected { Invoke-Lock $floating -AllowIncomplete } 'floating URI'

    $unsafeArchiveName = Copy-FixtureManifests 'unsafe-archive-name'
    $inputs = Get-Content -LiteralPath (Join-Path $unsafeArchiveName 'native-inputs.json') -Raw | ConvertFrom-Json
    $inputs.sources[0].archive.name = '../outside.tar.gz'
    Save-Json $inputs (Join-Path $unsafeArchiveName 'native-inputs.json')
    Assert-Rejected { Invoke-Lock $unsafeArchiveName -AllowIncomplete } 'Unsafe Windows archive leaf name'
    Assert-Rejected {
        & (Join-Path $scripts 'Get-NativeSourceArchive.ps1') -SourceId mpv -DownloadDirectory (Join-Path $testRoot 'unsafe-download') -ManifestPath (Join-Path $unsafeArchiveName 'native-inputs.json') -AllowQuarantineForHashDiscovery -DownloadScript { throw 'must not download' }
    } 'Unsafe Windows archive leaf name'

    $reservedArchiveName = Copy-FixtureManifests 'reserved-archive-name'
    $inputs = Get-Content -LiteralPath (Join-Path $reservedArchiveName 'native-inputs.json') -Raw | ConvertFrom-Json
    $inputs.sources[0].archive.name = 'AUX.txt'
    Save-Json $inputs (Join-Path $reservedArchiveName 'native-inputs.json')
    Assert-Rejected { Invoke-Lock $reservedArchiveName -AllowIncomplete } 'Unsafe Windows archive leaf name'

    $wrongCommit = Copy-FixtureManifests 'wrong-commit'
    $inputs = Get-Content -LiteralPath (Join-Path $wrongCommit 'native-inputs.json') -Raw | ConvertFrom-Json
    $inputs.sources[0].archive.url = 'https://github.com/mpv-player/mpv/archive/0000000000000000000000000000000000000000.tar.gz'
    Save-Json $inputs (Join-Path $wrongCommit 'native-inputs.json')
    Assert-Rejected { Invoke-Lock $wrongCommit -AllowIncomplete } 'not bound to the reviewed commit'

    $badSignature = Copy-FixtureManifests 'bad-signature'
    $inputs = Get-Content -LiteralPath (Join-Path $badSignature 'native-inputs.json') -Raw | ConvertFrom-Json
    $inputs.sources[0].signature.status = 'trusted-because-build-passed'
    Save-Json $inputs (Join-Path $badSignature 'native-inputs.json')
    Assert-Rejected { Invoke-Lock $badSignature -AllowIncomplete } 'Unknown signature state'

    $duplicateSource = Copy-FixtureManifests 'duplicate-source'
    $inputs = Get-Content -LiteralPath (Join-Path $duplicateSource 'native-inputs.json') -Raw | ConvertFrom-Json
    $copy = $inputs.sources[0] | Select-Object *
    $copy.id = 'MPV'
    $inputs.sources += $copy
    Save-Json $inputs (Join-Path $duplicateSource 'native-inputs.json')
    Assert-Rejected { Invoke-Lock $duplicateSource -AllowIncomplete } 'Duplicate, case-colliding'

    $cycle = Copy-FixtureManifests 'cycle'
    $graph = Get-Content -LiteralPath (Join-Path $cycle 'dependency-graph.json') -Raw | ConvertFrom-Json
    ($graph.nodes | Where-Object id -eq 'zlib').dependsOn = @('ffmpeg')
    Save-Json $graph (Join-Path $cycle 'dependency-graph.json')
    Assert-Rejected { Invoke-Lock $cycle -AllowIncomplete } 'set differs'

    $missingOutput = Copy-FixtureManifests 'missing-output'
    $outputs = Get-Content -LiteralPath (Join-Path $missingOutput 'output-contract.json') -Raw | ConvertFrom-Json
    $outputs.outputs = @($outputs.outputs | Select-Object -Skip 1)
    Save-Json $outputs (Join-Path $missingOutput 'output-contract.json')
    Assert-Rejected { Invoke-Lock $missingOutput -AllowIncomplete } 'output role set differs'

    $badOutputPath = Copy-FixtureManifests 'bad-output-path'
    $outputs = Get-Content -LiteralPath (Join-Path $badOutputPath 'output-contract.json') -Raw | ConvertFrom-Json
    $outputs.outputs[0].path = 'CON.dll'
    Save-Json $outputs (Join-Path $badOutputPath 'output-contract.json')
    Assert-Rejected { Invoke-Lock $badOutputPath -AllowIncomplete } 'Windows-unsafe'

    $caseOutput = Copy-FixtureManifests 'case-output'
    $outputs = Get-Content -LiteralPath (Join-Path $caseOutput 'output-contract.json') -Raw | ConvertFrom-Json
    $outputs.outputs[1].path = 'LIBMPV-2.DLL'
    Save-Json $outputs (Join-Path $caseOutput 'output-contract.json')
    Assert-Rejected { Invoke-Lock $caseOutput -AllowIncomplete } 'case-colliding output path'

    $wrongOutputOwner = Copy-FixtureManifests 'wrong-output-owner'
    $outputs = Get-Content -LiteralPath (Join-Path $wrongOutputOwner 'output-contract.json') -Raw | ConvertFrom-Json
    $outputs.outputs[0].sourceNode = 'ffmpeg'
    Save-Json $outputs (Join-Path $wrongOutputOwner 'output-contract.json')
    Assert-Rejected { Invoke-Lock $wrongOutputOwner -AllowIncomplete } 'owned by the wrong source node'

    $productionComplete = New-ProductionFixture 'production-complete'
    Invoke-Lock $productionComplete

    $wrongPeMachine = New-ProductionFixture 'wrong-pe-machine'
    $outputsPath = Join-Path $wrongPeMachine 'output-contract.json'
    $outputs = Get-Content -LiteralPath $outputsPath -Raw | ConvertFrom-Json
    $outputs.outputs[0].peMachine = 'I386'
    Save-Json $outputs $outputsPath
    Assert-Rejected { Invoke-Lock $wrongPeMachine } 'Production output evidence is incomplete'

    $emptyImports = New-ProductionFixture 'empty-imports'
    $outputsPath = Join-Path $emptyImports 'output-contract.json'
    $outputs = Get-Content -LiteralPath $outputsPath -Raw | ConvertFrom-Json
    $outputs.outputs[0].imports = [Collections.ArrayList]::new()
    Save-Json $outputs $outputsPath
    Assert-Rejected { Invoke-Lock $emptyImports } 'Production output evidence is incomplete'

    $emptyExports = New-ProductionFixture 'empty-exports'
    $outputsPath = Join-Path $emptyExports 'output-contract.json'
    $outputs = Get-Content -LiteralPath $outputsPath -Raw | ConvertFrom-Json
    $outputs.outputs[1].exports = [Collections.ArrayList]::new()
    Save-Json $outputs $outputsPath
    Assert-Rejected { Invoke-Lock $emptyExports } 'Production output evidence is incomplete'

    foreach ($badApiVersion in @('1.99','2.4')) {
        $apiFixture = New-ProductionFixture ("bad-api-" + $badApiVersion.Replace('.', '-'))
        $outputsPath = Join-Path $apiFixture 'output-contract.json'
        $outputs = Get-Content -LiteralPath $outputsPath -Raw | ConvertFrom-Json
        $outputs.outputs[0].apiVersion = $badApiVersion
        Save-Json $outputs $outputsPath
        Assert-Rejected { Invoke-Lock $apiFixture } 'client API evidence must be major 2 and minor 5 or newer'
    }

    $missingMpvExport = New-ProductionFixture 'missing-mpv-export'
    $outputsPath = Join-Path $missingMpvExport 'output-contract.json'
    $outputs = Get-Content -LiteralPath $outputsPath -Raw | ConvertFrom-Json
    $outputs.outputs[0].exports = @('mpv_client_api_version','mpv_create','mpv_initialize')
    Save-Json $outputs $outputsPath
    Assert-Rejected { Invoke-Lock $missingMpvExport } 'missing required export evidence'

    $missingOutputHash = New-ProductionFixture 'missing-output-hash'
    $outputsPath = Join-Path $missingOutputHash 'output-contract.json'
    $outputs = Get-Content -LiteralPath $outputsPath -Raw | ConvertFrom-Json
    $outputs.outputs[0].sha256 = $null
    Save-Json $outputs $outputsPath
    Assert-Rejected { Invoke-Lock $missingOutputHash } 'Production output evidence is incomplete'

    $missingOutputLicense = New-ProductionFixture 'missing-output-license'
    $outputsPath = Join-Path $missingOutputLicense 'output-contract.json'
    $outputs = Get-Content -LiteralPath $outputsPath -Raw | ConvertFrom-Json
    $outputs.outputs[0].licenseConclusion = $null
    Save-Json $outputs $outputsPath
    Assert-Rejected { Invoke-Lock $missingOutputLicense } 'Production output evidence is incomplete'

    $unexpectedDll = New-ProductionFixture 'unexpected-dll'
    $outputsPath = Join-Path $unexpectedDll 'output-contract.json'
    $outputs = Get-Content -LiteralPath $outputsPath -Raw | ConvertFrom-Json
    $outputs.closureEvidence.unexpectedDlls = @('unreviewed-runtime.dll')
    Save-Json $outputs $outputsPath
    Assert-Rejected { Invoke-Lock $unexpectedDll } 'Recursive PE closure evidence is incomplete'

    $mutatedPolicy = Copy-FixtureManifests 'mutated-policy'
    $policy = Get-Content -LiteralPath (Join-Path $mutatedPolicy 'native-policy.json') -Raw | ConvertFrom-Json
    $policy.forbiddenOptionKeys = @($policy.forbiddenOptionKeys | Where-Object { $_ -ne '--enable-gpl' })
    Save-Json $policy (Join-Path $mutatedPolicy 'native-policy.json')
    Assert-Rejected { Invoke-Lock $mutatedPolicy -AllowIncomplete } 'policy bytes differ'

    $mutatedSchema = Copy-FixtureManifests 'mutated-schema'
    $schemaPath = Join-Path $mutatedSchema 'schemas/toolchain-lock.schema.json'
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    $schema.type = 'array'
    Save-Json $schema $schemaPath
    Assert-Rejected { Invoke-Lock $mutatedSchema -AllowIncomplete } 'schema catalog entry is incomplete'

    $badToolchainSignature = Copy-FixtureManifests 'bad-toolchain-signature'
    $toolchainPath = Join-Path $badToolchainSignature 'toolchain.lock.json'
    $toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json
    $toolchain.baseArchive = [pscustomobject]@{
        id = 'msys2-base'; version = '2026-08-01'; architecture = 'x86_64'
        archive = [pscustomobject]@{ name = 'msys2-base-x86_64-20260801.tar.xz'; url = 'https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-20260801.tar.xz'; allowedRedirectHosts = @('repo.msys2.org'); sha256 = ('a' * 64) }
        signature = [pscustomobject]@{ name = 'msys2-base-x86_64-20260801.tar.xz.sig'; url = 'https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-20260801.tar.xz.sig'; allowedRedirectHosts = @('repo.msys2.org'); sha256 = ('b' * 64); keyFingerprint = ('C' * 40); status = 'pending'; evidence = 'fixture' }
    }
    Save-Json $toolchain $toolchainPath
    Assert-Rejected { Invoke-Lock $badToolchainSignature -AllowIncomplete } 'Detached-signature provenance is incomplete'

    $toolchainCycle = Copy-FixtureManifests 'toolchain-cycle'
    $toolchainPath = Join-Path $toolchainCycle 'toolchain.lock.json'
    $toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json
    $packages = @()
    foreach ($id in @($toolchain.requiredPackageIds)) {
        $dependencies = if ($id -eq 'bash') { @('clang') } elseif ($id -eq 'clang') { @('bash') } else { @() }
        $packages += New-LockedToolchainPackage -Id $id -DependsOn $dependencies
    }
    $toolchain.packages = $packages
    $toolchain.packageDatabase = [pscustomobject]@{ path = 'var/lib/pacman/local'; sha256 = ('d' * 64); packageIds = @($toolchain.requiredPackageIds); evidence = 'Fixture package database snapshot.' }
    Save-Json $toolchain $toolchainPath
    Assert-Rejected { Invoke-Lock $toolchainCycle -AllowIncomplete } 'package dependency cycle detected'

    $policy = Get-Content -LiteralPath (Join-Path $baseline 'native-policy.json') -Raw | ConvertFrom-Json
    foreach ($component in @($policy.required.PSObject.Properties.Name)) {
        & (Join-Path $scripts 'Test-NativeConfiguration.ps1') -Component $component -Flags @($policy.required.$component) -PolicyPath (Join-Path $baseline 'native-policy.json')
    }
    $ffmpegFlags = @($policy.required.ffmpeg) + '--enable-gpl=yes'
    Assert-Rejected {
        & (Join-Path $scripts 'Test-NativeConfiguration.ps1') -Component ffmpeg -Flags $ffmpegFlags -PolicyPath (Join-Path $baseline 'native-policy.json')
    } 'Forbidden native option'
    $libplaceboFlags = @($policy.required.libplacebo) + '-Djavascript=enabled'
    Assert-Rejected {
        & (Join-Path $scripts 'Test-NativeConfiguration.ps1') -Component libplacebo -Flags $libplaceboFlags -PolicyPath (Join-Path $baseline 'native-policy.json')
    } 'Unreviewed native option'
    $caseChangedMpvFlags = @($policy.required.mpv | ForEach-Object { if ($_ -ceq '-Dbuild-date=false') { '-Dbuild-date=False' } else { $_ } })
    Assert-Rejected {
        & (Join-Path $scripts 'Test-NativeConfiguration.ps1') -Component mpv -Flags $caseChangedMpvFlags -PolicyPath (Join-Path $baseline 'native-policy.json')
    } 'Required native option is missing'
    $mpvFlags = @($policy.required.mpv | Where-Object { $_ -ne '-Dcplayer=false' }) + '-Dcplayer=true'
    Assert-Rejected {
        & (Join-Path $scripts 'Test-NativeConfiguration.ps1') -Component mpv -Flags $mpvFlags -PolicyPath (Join-Path $baseline 'native-policy.json')
    } 'Required native option is missing'

    $effectiveRoot = Join-Path $testRoot 'effective-configuration'
    New-Item -ItemType Directory -Path $effectiveRoot | Out-Null
    $evidence = @()
    foreach ($kind in @($policy.effectiveEvidence.libass)) {
        $evidencePath = Join-Path $effectiveRoot "$kind.txt"
        [IO.File]::WriteAllText($evidencePath, 'CONFIG_ICONV=0 isolated-target-search no-ambient-target-dependencies no-unapproved-enabled-features')
        $evidence += "$kind=$evidencePath"
    }
    $gitPath = (Get-Command git.exe -ErrorAction Stop).Source
    & (Join-Path $scripts 'Save-NativeEffectiveConfiguration.ps1') -OutputPath (Join-Path $effectiveRoot 'accepted.json') -Component libass -RequestedFlags @($policy.required.libass) -Evidence $evidence -CompilerPath $gitPath -LinkerPath $gitPath -PolicyPath (Join-Path $baseline 'native-policy.json')
    foreach ($kind in @($policy.effectiveEvidence.libass)) {
        [IO.File]::WriteAllText((Join-Path $effectiveRoot "$kind.txt"), 'isolated-target-search no-ambient-target-dependencies')
    }
    Assert-Rejected {
        & (Join-Path $scripts 'Save-NativeEffectiveConfiguration.ps1') -OutputPath (Join-Path $effectiveRoot 'rejected.json') -Component libass -RequestedFlags @($policy.required.libass) -Evidence $evidence -CompilerPath $gitPath -LinkerPath $gitPath -PolicyPath (Join-Path $baseline 'native-policy.json')
    } 'CONFIG_ICONV=0'

    $archive = Join-Path $testRoot 'archive.bin'
    [IO.File]::WriteAllText($archive, 'approved archive')
    $hashFixture = Copy-FixtureManifests 'archive-hash'
    $inputs = Get-Content -LiteralPath (Join-Path $hashFixture 'native-inputs.json') -Raw | ConvertFrom-Json
    $inputs.sources[0].archive.sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    Save-Json $inputs (Join-Path $hashFixture 'native-inputs.json')
    & (Join-Path $scripts 'Test-NativeArchiveChecksum.ps1') -ArchivePath $archive -SourceId mpv -ManifestPath (Join-Path $hashFixture 'native-inputs.json')
    [IO.File]::WriteAllText($archive, 'changed archive')
    Assert-Rejected {
        & (Join-Path $scripts 'Test-NativeArchiveChecksum.ps1') -ArchivePath $archive -SourceId mpv -ManifestPath (Join-Path $hashFixture 'native-inputs.json')
    } 'checksum does not match'

    $archiveSetRoot = Join-Path $testRoot 'archive-set'
    New-Item -ItemType Directory -Path $archiveSetRoot | Out-Null
    $archiveSetManifests = Copy-FixtureManifests 'archive-set-manifests'
    $archiveSetManifest = Join-Path $archiveSetManifests 'native-inputs.json'
    $inputs = Get-Content -LiteralPath $archiveSetManifest -Raw | ConvertFrom-Json
    $fixtureArchives = @{}
    foreach ($source in @($inputs.sources)) {
        $content = "locked archive set fixture:$($source.id)"
        $fixtureArchive = Join-Path $testRoot "$($source.id)-fixture.bin"
        [IO.File]::WriteAllText($fixtureArchive, $content)
        $fixtureHash = (Get-FileHash -LiteralPath $fixtureArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        $source.archive.sha256 = $fixtureHash
        $lockedArchiveName = "$($source.id)-$fixtureHash-$($source.archive.name)"
        $lockedArchivePath = Join-Path $archiveSetRoot $lockedArchiveName
        Copy-Item -LiteralPath $fixtureArchive -Destination $lockedArchivePath
        $fixtureArchives[[string]$source.id] = [pscustomobject]@{ content = $content; path = $lockedArchivePath; hash = $fixtureHash }
    }
    Save-Json $inputs $archiveSetManifest
    $archiveSetEvidence = Join-Path $testRoot 'source-acquisition-evidence.json'
    $record = & (Join-Path $scripts 'Test-NativeSourceArchiveSet.ps1') -ArchiveDirectory $archiveSetRoot -ManifestPath $archiveSetManifest -EvidencePath $archiveSetEvidence
    if ($record.archiveCount -ne 13 -or @($record.archives | Where-Object id -eq 'mpv')[0].sha256 -cne $fixtureArchives.mpv.hash -or -not (Test-Path -LiteralPath $archiveSetEvidence)) {
        throw 'Source archive set evidence was not generated correctly.'
    }
    [IO.File]::WriteAllText((Join-Path $archiveSetRoot 'unexpected.tar.gz'), 'unexpected')
    Assert-Rejected {
        & (Join-Path $scripts 'Test-NativeSourceArchiveSet.ps1') -ArchiveDirectory $archiveSetRoot -ManifestPath $archiveSetManifest
    } 'Unexpected source archive file'
    Remove-Item -LiteralPath (Join-Path $archiveSetRoot 'unexpected.tar.gz')
    Remove-Item -LiteralPath $fixtureArchives.mpv.path
    Assert-Rejected {
        & (Join-Path $scripts 'Test-NativeSourceArchiveSet.ps1') -ArchiveDirectory $archiveSetRoot -ManifestPath $archiveSetManifest
    } 'Locked source archive is missing'
    [IO.File]::WriteAllText($fixtureArchives.mpv.path, $fixtureArchives.mpv.content)
    [IO.File]::WriteAllText($fixtureArchives.mpv.path, 'tampered')
    Assert-Rejected {
        & (Join-Path $scripts 'Test-NativeSourceArchiveSet.ps1') -ArchiveDirectory $archiveSetRoot -ManifestPath $archiveSetManifest
    } 'checksum mismatch'
    [IO.File]::WriteAllText($fixtureArchives.mpv.path, $fixtureArchives.mpv.content)

    $truncatedManifests = Copy-FixtureManifests 'truncated-acquisition-manifests'
    $truncatedInputsPath = Join-Path $truncatedManifests 'native-inputs.json'
    $truncatedInputs = Get-Content -LiteralPath $truncatedInputsPath -Raw | ConvertFrom-Json
    $truncatedInputs.sources = @($truncatedInputs.sources[0])
    $truncatedInputs.approvedSourceIds = @('mpv')
    Save-Json $truncatedInputs $truncatedInputsPath
    Assert-Rejected {
        & (Join-Path $scripts 'Invoke-NativeSourceAcquisition.ps1') -DownloadDirectory (Join-Path $testRoot 'truncated-acquisition') -QuarantineOnly -ManifestPath $truncatedInputsPath -DownloadScript { throw 'must not download' }
    } 'set differs from the reviewed contract'
    Assert-Rejected {
        & (Join-Path $scripts 'Get-NativeSourceArchive.ps1') -SourceId mpv -DownloadDirectory (Join-Path $testRoot 'truncated-direct-acquisition') -ManifestPath $truncatedInputsPath -AllowQuarantineForHashDiscovery -DownloadScript { throw 'must not download' }
    } 'set differs from the reviewed contract'

    $orchestratedRoot = Join-Path $testRoot 'orchestrated-acquisition'
    $orchestratedQuarantine = Join-Path $orchestratedRoot 'quarantine'
    New-Item -ItemType Directory -Path $orchestratedQuarantine -Force | Out-Null
    foreach ($fixture in $fixtureArchives.GetEnumerator()) {
        if ($fixture.Key -ne 'mpv') { Copy-Item -LiteralPath $fixture.Value.path -Destination $orchestratedQuarantine }
    }
    $orchestratedEvidence = Join-Path $testRoot 'orchestrated-evidence.json'
    $orchestratedDownload = {
        param($uri, $destination)
        [IO.File]::WriteAllText($destination, 'locked archive set fixture:mpv')
        return 'https://codeload.github.com/mpv-player/mpv/tar.gz/fixture'
    }
    $orchestratedRecord = & (Join-Path $scripts 'Invoke-NativeSourceAcquisition.ps1') -DownloadDirectory $orchestratedRoot -QuarantineOnly -ManifestPath $archiveSetManifest -EvidencePath $orchestratedEvidence -DownloadScript $orchestratedDownload
    if ($orchestratedRecord.archiveCount -ne 13 -or -not (Test-Path -LiteralPath $orchestratedEvidence)) {
        throw 'Orchestrated source acquisition did not produce complete evidence.'
    }
    & (Join-Path $scripts 'Test-NativeSourceAcquisitionEvidence.ps1') -EvidencePath $orchestratedEvidence -ManifestPath $archiveSetManifest
    & (Join-Path $scripts 'Invoke-NativeSourceAcquisition.ps1') -DownloadDirectory $orchestratedRoot -QuarantineOnly -ManifestPath $archiveSetManifest -DownloadScript { throw 'Locked archive should have been reused.' } | Out-Null

    $downloads = Join-Path $testRoot 'downloads'
    $mockDownload = {
        param($uri, $destination)
        [IO.File]::WriteAllText($destination, 'quarantine bytes')
        return 'https://codeload.github.com/mpv-player/mpv/tar.gz/fixture'
    }
    $result = & (Join-Path $scripts 'Get-NativeSourceArchive.ps1') -SourceId mpv -DownloadDirectory $downloads -ManifestPath (Join-Path $baseline 'native-inputs.json') -AllowQuarantineForHashDiscovery -DownloadScript $mockDownload
    if ($result.buildReady -ne $false -or -not (Test-Path -LiteralPath $result.path)) { throw 'Hash-discovery acquisition produced an invalid quarantine result.' }
    Assert-Rejected {
        & (Join-Path $scripts 'Get-NativeSourceArchive.ps1') -SourceId mpv -DownloadDirectory $downloads -ManifestPath (Join-Path $baseline 'native-inputs.json') -AllowQuarantineForHashDiscovery -DownloadScript $mockDownload
    } 'already exists'
    $badRedirect = {
        param($uri, $destination)
        [IO.File]::WriteAllText($destination, 'redirect bytes')
        return 'https://example.invalid/archive.tar.gz'
    }
    Assert-Rejected {
        & (Join-Path $scripts 'Get-NativeSourceArchive.ps1') -SourceId ffmpeg -DownloadDirectory $downloads -ManifestPath (Join-Path $baseline 'native-inputs.json') -AllowQuarantineForHashDiscovery -DownloadScript $badRedirect
    } 'unapproved host'
    if (@(Get-ChildItem -LiteralPath $downloads -Filter '.incomplete-*' -Force).Count -ne 0) { throw 'Partial acquisition directory was not cleaned.' }

    $traversalZip = Join-Path $testRoot 'traversal.zip'
    New-TestZip $traversalZip @('../escape.txt')
    Assert-Rejected { & (Join-Path $scripts 'Test-NativeZipArchive.ps1') -ArchivePath $traversalZip } 'Unsafe ZIP entry path'
    $collisionZip = Join-Path $testRoot 'collision.zip'
    New-TestZip $collisionZip @('safe/File.txt','safe/file.txt')
    Assert-Rejected { & (Join-Path $scripts 'Test-NativeZipArchive.ps1') -ArchivePath $collisionZip } 'case-colliding ZIP entry'
    $reservedZip = Join-Path $testRoot 'reserved.zip'
    New-TestZip $reservedZip @('AUX.txt')
    Assert-Rejected { & (Join-Path $scripts 'Test-NativeZipArchive.ps1') -ArchivePath $reservedZip } 'Windows-unsafe ZIP entry path'
}
finally {
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host 'Native foundation focused tests passed.'
