[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidatePath,
    [string]$ManifestRoot,
    [string]$PayloadRoot,
    [switch]$RequirePayload,
    [string]$TarPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManifestRoot)) { $ManifestRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests' }
function Read-Json([string]$Path, [string]$What) { try { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { throw "Invalid JSON for ${What}: $($_.Exception.Message)" } }
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Assert-Hash([string]$Value, [string]$What) { if ($Value -cnotmatch '^[0-9a-f]{64}$') { throw "Invalid SHA-256 for $What" } }
function Assert-Relative([string]$Value, [string]$What) {
    if ([string]::IsNullOrWhiteSpace($Value) -or [IO.Path]::IsPathRooted($Value) -or $Value.Contains('\') -or $Value -match '(^|/)(\.|\.\.)(/|$)') { throw "Unsafe relative path for ${What}: $Value" }
}
$candidateFile = [IO.Path]::GetFullPath($CandidatePath)
$candidateRoot = Split-Path -Parent $candidateFile
function Resolve-CandidatePath([string]$Relative, [string]$What, [switch]$Directory) {
    Assert-Relative $Relative $What
    $full = [IO.Path]::GetFullPath((Join-Path $candidateRoot $Relative))
    if (-not $full.StartsWith($candidateRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Candidate path escapes its root: $Relative" }
    if ($Directory) { if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "Candidate directory is missing: $Relative" } }
    elseif (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Candidate artifact is missing: $Relative" }
    $item = Get-Item -LiteralPath $full -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Candidate artifact is a reparse point: $Relative" }
    return $full
}
function Resolve-Artifact([object]$Artifact, [string]$What) {
    $path = Resolve-CandidatePath ([string]$Artifact.path) $What
    Assert-Hash ([string]$Artifact.sha256) $What
    if ((Hash $path) -cne [string]$Artifact.sha256) { throw "Candidate artifact hash differs: $($Artifact.path)" }
    return $path
}
function Assert-ExactSet([string[]]$Expected, [string[]]$Actual, [string]$What) {
    $expectedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $actualSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($Expected)) { if (-not $expectedSet.Add([string]$value)) { throw "Reviewed $What contains a duplicate: $value" } }
    foreach ($value in @($Actual)) { if (-not $actualSet.Add([string]$value)) { throw "Candidate $What contains a duplicate or case collision: $value" } }
    if ($expectedSet.Count -ne $actualSet.Count) { throw "Candidate $What is not the exact reviewed set." }
    foreach ($value in $expectedSet) { if (-not $actualSet.Contains($value)) { throw "Candidate $What is missing: $value" } }
}
function Assert-JsonEvidence([string]$Path, [string]$What) {
    $value = Read-Json $Path $What
    if ($null -eq $value -or @($value.PSObject.Properties).Count -eq 0) { throw "$What evidence is empty." }
    return $value
}

if (-not (Test-Path -LiteralPath $candidateFile -PathType Leaf)) { throw "Candidate manifest is missing: $candidateFile" }
$candidate = Read-Json $candidateFile 'candidate manifest'
if ($candidate.schemaVersion -ne 1 -or $candidate.kind -cne 'hvp-native-candidate' -or $candidate.'$schema' -cne 'schemas/native-candidate.schema.json' -or [string]::IsNullOrWhiteSpace([string]$candidate.candidateId) -or $candidate.candidateId -match 'REPLACE') { throw 'Candidate manifest is a template or has an unsupported schema.' }

$manifestRoot = [IO.Path]::GetFullPath($ManifestRoot)
& (Join-Path $PSScriptRoot 'Test-NativeLock.ps1') -ManifestRoot $manifestRoot | Out-Null
$sourceLock = Join-Path $manifestRoot 'native-inputs.json'; $graphPath = Join-Path $manifestRoot 'dependency-graph.json'; $contractPath = Join-Path $manifestRoot 'output-contract.json'; $policyPath = Join-Path $manifestRoot 'native-policy.json'
foreach ($binding in @(@{ value=$candidate.sourceLockSha256; path=$sourceLock; name='source lock' }, @{ value=$candidate.dependencyGraphSha256; path=$graphPath; name='dependency graph' }, @{ value=$candidate.outputContractSha256; path=$contractPath; name='output contract' })) {
    Assert-Hash ([string]$binding.value) $binding.name
    if ([string]$binding.value -cne (Hash $binding.path)) { throw "Candidate does not bind the current reviewed $($binding.name) bytes." }
}
$inputs = Read-Json $sourceLock 'source lock'; $graph = Read-Json $graphPath 'dependency graph'; $contract = Read-Json $contractPath 'output contract'; $policy = Read-Json $policyPath 'native policy'

Assert-ExactSet @($inputs.sources | ForEach-Object id) @($candidate.sources | ForEach-Object id) 'source/license inventory'
foreach ($source in @($candidate.sources)) {
    $locked = @($inputs.sources | Where-Object id -CEQ $source.id)
    if ($locked.Count -ne 1 -or [string]$source.declaredLicense -cne [string]$locked[0].licenseDeclared -or [string]$source.concludedLicense -cne [string]$locked[0].licenseConcluded -or [string]::IsNullOrWhiteSpace([string]$source.concludedLicense) -or [string]$source.concludedLicense -eq 'NOASSERTION') { throw "Candidate license conclusion differs from the reviewed source lock: $($source.id)" }
    [void](Resolve-CandidatePath ([string]$source.conclusionEvidence) "license conclusion $($source.id)")
}

$requestedEvidence=Assert-JsonEvidence (Resolve-CandidatePath ([string]$candidate.build.requestedConfigurationPath) 'requested configuration') 'requested configuration'
$effectiveEvidence=Assert-JsonEvidence (Resolve-CandidatePath ([string]$candidate.build.effectiveConfigurationPath) 'effective configuration') 'effective configuration'
$compiledEvidence=Assert-JsonEvidence (Resolve-CandidatePath ([string]$candidate.build.compiledSourcesPath) 'compiled sources') 'compiled sources'
$dependencyEvidence=Assert-JsonEvidence (Resolve-CandidatePath ([string]$candidate.build.dependencyPathsPath) 'dependency paths') 'dependency paths'
$toolEvidence=Assert-JsonEvidence (Resolve-CandidatePath ([string]$candidate.build.toolIdentitiesPath) 'tool identities') 'tool identities'
$isolationEvidence=Assert-JsonEvidence (Resolve-CandidatePath ([string]$candidate.build.dependencyIsolationPath) 'dependency isolation') 'dependency isolation'
if($requestedEvidence.kind-cne'hvp-native-requested-configuration'-or$requestedEvidence.policySha256-cne(Hash $policyPath)-or$effectiveEvidence.kind-cne'hvp-native-effective-configuration'-or$compiledEvidence.kind-cne'hvp-native-compiled-source-evidence'-or$dependencyEvidence.kind-cne'hvp-native-dependency-path-evidence'-or$toolEvidence.kind-cne'hvp-native-tool-identities'-or$isolationEvidence.kind-cne'hvp-native-dependency-isolation'-or$isolationEvidence.isolated-ne$true){throw 'Build evidence kinds, policy binding, or dependency-isolation result are invalid.'}
if($effectiveEvidence.gpuNextCompiled-ne$true-or$effectiveEvidence.d3d11ContextCompiled-ne$true-or$effectiveEvidence.d3d11vaCompiled-ne$true){throw 'Effective configuration does not prove gpu-next, D3D11 context, and D3D11VA compilation.'}
Assert-ExactSet @($policy.required.PSObject.Properties.Name) @($requestedEvidence.components.PSObject.Properties.Name) 'requested component configuration'
Assert-ExactSet @($policy.required.PSObject.Properties.Name) @($effectiveEvidence.components|ForEach-Object component) 'effective component configuration'
if(@($compiledEvidence.files).Count-lt 10-or@($dependencyEvidence.files).Count-lt 10-or@($toolEvidence.tools).Count-lt 7){throw 'Compiled-source, dependency-path, or tool identity evidence is incomplete.'}
foreach($set in @(@{base=[string]$candidate.build.compiledSourcesPath;items=@($compiledEvidence.files);name='compiled source'},@{base=[string]$candidate.build.dependencyPathsPath;items=@($dependencyEvidence.files);name='dependency path'},@{base=[string]$candidate.build.effectiveConfigurationPath;items=@($effectiveEvidence.components);name='effective configuration'})){$baseDirectory=Split-Path -Parent $set.base;foreach($item in @($set.items)){$relative=if([string]::IsNullOrWhiteSpace($baseDirectory)){[string]$item.path}else{$baseDirectory.TrimEnd('/')+'/'+[string]$item.path};$artifact=[pscustomobject]@{path=$relative;sha256=[string]$item.sha256};[void](Resolve-Artifact $artifact "$($set.name) evidence")}}
$builds = @($candidate.build.reproducibility.cleanBuilds)
$reproArtifact=[pscustomobject]@{path=[string]$candidate.build.reproducibilityEvidencePath;sha256=[string]$candidate.build.reproducibilityEvidenceSha256};$reproEvidence=Assert-JsonEvidence (Resolve-Artifact $reproArtifact 'reproducibility evidence') 'reproducibility evidence'
if($reproEvidence.kind-cne'hvp-native-reproducibility-evidence'-or$reproEvidence.status-cne$candidate.build.reproducibility.status-or(($reproEvidence.cleanBuilds|ConvertTo-Json -Depth 12 -Compress)-cne($builds|ConvertTo-Json -Depth 12 -Compress))){throw 'Candidate reproducibility record differs from the build-produced evidence artifact.'}
if ($builds.Count -lt 2) { throw 'Reproducibility evidence requires at least two clean builds.' }
Assert-ExactSet @($contract.requiredRoles) @($builds[0].outputHashes.PSObject.Properties.Name) 'first reproducibility output set'
for ($index = 0; $index -lt $builds.Count; $index++) {
    Assert-ExactSet @($contract.requiredRoles) @($builds[$index].outputHashes.PSObject.Properties.Name) "reproducibility output set $index"
    foreach ($role in @($contract.requiredRoles)) { Assert-Hash ([string]$builds[$index].outputHashes.$role) "reproducibility $role" }
    foreach($role in @($contract.requiredRoles)){$expectedOutput=@($contract.outputs|Where-Object role -CEQ $role)[0];if([string]$builds[$index].outputHashes.$role-cne[string]$expectedOutput.sha256){throw "Clean-build hash does not match selected candidate output: $role"}}
}
if ($candidate.build.reproducibility.status -ceq 'identical') {
    foreach ($build in $builds | Select-Object -Skip 1) { foreach($role in @($contract.requiredRoles)){if([string]$build.outputHashes.$role-cne[string]$builds[0].outputHashes.$role){throw 'Clean build hashes differ despite identical reproducibility status.'}} }
} elseif ($candidate.build.reproducibility.status -ceq 'difference-explained') {
    [void](Resolve-CandidatePath ([string]$candidate.build.reproducibility.differenceEvidencePath) 'reproducibility difference evidence')
} else { throw 'Unsupported reproducibility status.' }

$bundleRoot = Resolve-CandidatePath ([string]$candidate.bundleDirectory) 'native bundle' -Directory
Assert-ExactSet @($contract.requiredRoles) @($candidate.binaries | ForEach-Object role) 'binary role inventory'
foreach ($binary in @($candidate.binaries)) {
    $expected = @($contract.outputs | Where-Object role -CEQ $binary.role)
    if ($expected.Count -ne 1) { throw "Binary role has no unique output contract entry: $($binary.role)" }
    $expectedPath = ([string]$candidate.bundleDirectory).TrimEnd('/') + '/' + [string]$expected[0].path
    if ([string]$binary.path -cne $expectedPath -or [string]$binary.sha256 -cne [string]$expected[0].sha256 -or [string]$binary.peMachine -cne [string]$expected[0].peMachine -or [string]$binary.sourceId -cne [string]$expected[0].sourceNode -or [string]$binary.licenseConclusion -cne [string]$expected[0].licenseConclusion -or [string]$binary.dllCharacteristics -cne [string]$expected[0].dllCharacteristics) { throw "Candidate binary identity differs from output contract: $($binary.role)" }
    foreach ($property in @('imports','delayImports','exports')) { if ((@($binary.$property | Sort-Object -Unique) -join "`n") -cne (@($expected[0].$property | Sort-Object -Unique) -join "`n")) { throw "Candidate binary $property differs from output contract: $($binary.role)" } }
}
$generatedPe = Join-Path ([IO.Path]::GetTempPath()) ('hvp-candidate-pe-' + [guid]::NewGuid().ToString('N') + '.json')
try { & (Join-Path $PSScriptRoot 'Test-NativeOutputBundle.ps1') -BundleRoot $bundleRoot -OutputContractPath $contractPath -EvidencePath $generatedPe | Out-Null
    $recordedPePath = Resolve-Artifact $candidate.peEvidence 'PE evidence'
    $recordedPe = Read-Json $recordedPePath 'recorded PE evidence'; $freshPe = Read-Json $generatedPe 'fresh PE evidence'
    $recordedPe.generatedUtc = $null; $freshPe.generatedUtc = $null
    if (($recordedPe | ConvertTo-Json -Depth 12 -Compress) -cne ($freshPe | ConvertTo-Json -Depth 12 -Compress)) { throw 'Recorded PE evidence differs from fresh binary inspection.' }
} finally { if (Test-Path -LiteralPath $generatedPe) { Remove-Item -LiteralPath $generatedPe -Force } }

$smoke = Assert-JsonEvidence (Resolve-Artifact $candidate.smokeEvidence 'smoke matrix evidence') 'smoke matrix'
foreach ($scenario in @('bundled','missingCompanion','tamperedCompanion','validOverride','missingOverride','wrongArchitecture','missingExport','incompatibleApi')) {
    $entry = $smoke.scenarios.$scenario
    if ($null -eq $entry -or $entry.passed -ne $true) { throw "Smoke/replacement matrix is incomplete: $scenario" }
}
if ($smoke.searchPolicy -cne 'LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32' -or $smoke.fixtureUnlocked -ne $true -or $smoke.fixtureLoaded -ne $true -or [string]$smoke.scenarios.bundled.apiVersion -cne [string](@($contract.outputs|Where-Object role -eq 'libmpv')[0].apiVersion)) { throw 'Smoke evidence does not prove restricted loading, runtime API identity, and fixture lifecycle.' }

[void](Resolve-Artifact $candidate.notices 'third-party notices')
$licenseRoot = Resolve-CandidatePath ([string]$candidate.notices.licenseDirectory) 'license directory' -Directory
$recordedLicensePaths = @($candidate.notices.licenseFiles | ForEach-Object path)
$actualLicensePaths = @(Get-ChildItem -LiteralPath $licenseRoot -File -Recurse -Force | ForEach-Object { [IO.Path]::GetRelativePath($candidateRoot, $_.FullName).Replace('\','/') })
Assert-ExactSet $actualLicensePaths $recordedLicensePaths 'license text files'
foreach ($license in @($candidate.notices.licenseFiles)) { [void](Resolve-Artifact $license "license text $($license.path)") }

$sourceArchive=Resolve-Artifact ([pscustomobject]@{path=$candidate.correspondingSource.path;sha256=$candidate.correspondingSource.sha256}) 'corresponding-source archive'
$sourceInputs = Assert-JsonEvidence (Resolve-Artifact ([pscustomobject]@{path=$candidate.correspondingSource.archiveInputsPath;sha256=$candidate.correspondingSource.archiveInputsSha256}) 'corresponding-source inputs') 'corresponding-source inputs'
[void](Resolve-Artifact ([pscustomobject]@{path=$candidate.correspondingSource.buildInstructionsPath;sha256=$candidate.correspondingSource.buildInstructionsSha256}) 'corresponding-source build instructions')
Assert-ExactSet @($inputs.sources | ForEach-Object id) @($sourceInputs.sources | ForEach-Object id) 'corresponding-source input inventory'
foreach ($source in @($sourceInputs.sources)) { $locked = @($inputs.sources | Where-Object id -CEQ $source.id)[0]; if ([string]$source.sha256 -cne [string]$locked.archive.sha256 -or [string]$source.commit -cne [string]$locked.commit -or [string]$source.path -cne "sources/$($locked.archive.name)") { throw "Corresponding-source input differs from source lock: $($source.id)" } }
$expectedPatches=@($inputs.sources|ForEach-Object{$id=$_.id;@($_.patches)|ForEach-Object{"$id|$($_.path)|$($_.sha256)"}});$recordedPatches=@($sourceInputs.patches|ForEach-Object{"$($_.sourceId)|$($_.path)|$($_.sha256)"});Assert-ExactSet $expectedPatches $recordedPatches 'corresponding-source patch inventory'
foreach($requiredScript in @('eng/native/config/build-native.sh','eng/native/scripts/Invoke-NativeBuild.ps1','eng/native/scripts/Invoke-NativeReproducibilityBuild.ps1')){if(@($sourceInputs.buildScripts.path)-cnotcontains$requiredScript){throw "Corresponding source omits required build script: $requiredScript"}}
if([string]::IsNullOrWhiteSpace($TarPath)){$TarPath=(Get-Command tar.exe -ErrorAction Stop).Source};$toolchainLock=Read-Json(Join-Path $manifestRoot 'toolchain.lock.json')'toolchain lock';if((Get-FileHash -LiteralPath $TarPath -Algorithm SHA256).Hash.ToLowerInvariant()-cne$toolchainLock.bootstrap.tarSha256){throw 'Corresponding-source extractor is not bound to the reviewed bootstrap tar.'}
&(Join-Path $PSScriptRoot 'Test-NativeTarArchive.ps1')-ArchivePath $sourceArchive -TarPath $TarPath|Out-Null
$sourceTemp=Join-Path([IO.Path]::GetTempPath())('hvp-corresponding-source-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $sourceTemp|Out-Null
try{&$TarPath -xf $sourceArchive -C $sourceTemp;if($LASTEXITCODE-ne 0){throw 'Corresponding-source archive extraction failed.'};$actualEntries=@(Get-ChildItem -LiteralPath $sourceTemp -File -Recurse -Force|ForEach-Object{[pscustomobject]@{path=[IO.Path]::GetRelativePath($sourceTemp,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}});Assert-ExactSet @($actualEntries.path) @($sourceInputs.archiveEntries.path) 'corresponding-source archive file inventory';foreach($entry in $actualEntries){$recorded=@($sourceInputs.archiveEntries|Where-Object path -CEQ $entry.path);if($recorded.Count-ne 1-or[string]$recorded[0].sha256-cne$entry.sha256){throw "Corresponding-source archive file hash differs: $($entry.path)"}}}finally{if(Test-Path -LiteralPath $sourceTemp){Remove-Item -LiteralPath $sourceTemp -Recurse -Force}}

$sbom = Assert-JsonEvidence (Resolve-Artifact $candidate.sbom 'SPDX SBOM') 'SPDX SBOM'
if ($sbom.spdxVersion -cne 'SPDX-2.3' -or @($sbom.relationships).Count -eq 0) { throw 'SPDX candidate has no supported version or relationships.' }
Assert-ExactSet @($inputs.sources | ForEach-Object id) @($sbom.packages | ForEach-Object name) 'SPDX source package inventory'
foreach ($package in @($sbom.packages)) { $locked=@($inputs.sources|Where-Object id -CEQ $package.name);$checksum=@($package.checksums|Where-Object algorithm -CEQ 'SHA256');if($locked.Count-ne 1-or$package.licenseDeclared-cne$locked[0].licenseDeclared-or$package.licenseConcluded-cne$locked[0].licenseConcluded-or$package.downloadLocation-cne$locked[0].archive.url-or$checksum.Count-ne 1-or$checksum[0].checksumValue-cne$locked[0].archive.sha256-or[string]::IsNullOrWhiteSpace([string]$package.SPDXID)){throw "SPDX package evidence differs from source lock: $($package.name)"} }
$spdxByName=@{};foreach($package in @($sbom.packages)){$spdxByName[$package.name]=[string]$package.SPDXID};$expectedEdges=@();foreach($node in @($graph.nodes)){foreach($dependency in @($node.dependsOn)){$expectedEdges+="$($spdxByName[$node.id])|DEPENDS_ON|$($spdxByName[$dependency])"}};$actualEdges=@($sbom.relationships|Where-Object relationshipType -CEQ 'DEPENDS_ON'|ForEach-Object{"$($_.spdxElementId)|DEPENDS_ON|$($_.relatedSpdxElement)"});Assert-ExactSet $expectedEdges $actualEdges 'SPDX dependency relationship'
Assert-ExactSet @($candidate.binaries.path) @($sbom.files.fileName) 'SPDX contributed binary inventory';foreach($binary in @($candidate.binaries)){$file=@($sbom.files|Where-Object fileName -CEQ $binary.path);if($file.Count-ne 1-or@($file[0].checksums|Where-Object{ $_.algorithm-ceq'SHA256'-and$_.checksumValue-ceq$binary.sha256}).Count-ne 1){throw "SPDX binary checksum differs: $($binary.role)"};$relationship=@($sbom.relationships|Where-Object{$_.spdxElementId-ceq$file[0].SPDXID-and$_.relationshipType-ceq'GENERATED_FROM'-and$_.relatedSpdxElement-ceq$spdxByName[$binary.sourceId]});if($relationship.Count-ne 1){throw "SPDX binary/source relationship is missing: $($binary.role)"}}

$security = Assert-JsonEvidence (Resolve-Artifact $candidate.securityReview 'security advisory review') 'security advisory review'
$review = Assert-JsonEvidence (Resolve-Artifact $candidate.independentReview 'independent licensing/provenance review') 'independent licensing/provenance review'
if ($security.status -cne 'complete' -or $review.status -cne 'approved' -or @($review.scope) -notcontains 'licensing' -or @($review.scope) -notcontains 'provenance') { throw 'Required security and independent licensing/provenance review evidence is incomplete.' }

$recordedPayload = @($candidate.payloadFiles | ForEach-Object path)
$actualPayload = @(Get-ChildItem -LiteralPath $candidateRoot -File -Recurse -Force | Where-Object { $_.FullName -cne $candidateFile } | ForEach-Object { [IO.Path]::GetRelativePath($candidateRoot, $_.FullName).Replace('\','/') })
Assert-ExactSet $actualPayload $recordedPayload 'native payload file inventory'
foreach ($file in @($candidate.payloadFiles)) { [void](Resolve-Artifact $file "native payload file $($file.path)") }

if ($RequirePayload -or -not [string]::IsNullOrWhiteSpace($PayloadRoot)) {
    $payload = [IO.Path]::GetFullPath($PayloadRoot)
    if ($payload -cne $candidateRoot) { throw 'Candidate manifest must be at the root of the native payload overlay.' }
}
Write-Host "Native candidate $($candidate.candidateId) is internally consistent; external legal and clean-machine gates remain required."
