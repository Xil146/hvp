[CmdletBinding()]
param([string]$ManifestRoot, [switch]$AllowIncomplete)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManifestRoot)) {
    $ManifestRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests'
}

$requiredSources = @('mpv','ffmpeg','libplacebo','libass','spirv-cross','glslang','fast-float','freetype','fribidi','harfbuzz','zlib','jinja','markupsafe')
$requiredEdges = @{
    'mpv' = @('ffmpeg','libplacebo','libass')
    'ffmpeg' = @('zlib')
    'libplacebo' = @('spirv-cross','glslang','fast-float','jinja','markupsafe')
    'libass' = @('freetype','fribidi','harfbuzz')
    'spirv-cross' = @()
    'glslang' = @()
    'fast-float' = @()
    'freetype' = @('zlib')
    'fribidi' = @()
    'harfbuzz' = @()
    'zlib' = @()
    'jinja' = @('markupsafe')
    'markupsafe' = @()
}
$requiredRoles = @('libmpv','avcodec','avfilter','avformat','avutil','swresample','swscale','libplacebo','libass','freetype','fribidi','harfbuzz','zlib','spirv-cross','glslang','spirv')
$requiredRoleOwners = @{
    'libmpv'='mpv'; 'avcodec'='ffmpeg'; 'avfilter'='ffmpeg'; 'avformat'='ffmpeg';
    'avutil'='ffmpeg'; 'swresample'='ffmpeg'; 'swscale'='ffmpeg';
    'libplacebo'='libplacebo'; 'libass'='libass'; 'freetype'='freetype';
    'fribidi'='fribidi'; 'harfbuzz'='harfbuzz'; 'zlib'='zlib';
    'spirv-cross'='spirv-cross'; 'glslang'='glslang'; 'spirv'='glslang'
}
$requiredToolRoots = @('bash','clang','cmake','coreutils','git','gzip','lld','llvm','make','meson','nasm','ninja','patch','pkgconf','python','tar','xz')
$reviewedPolicySha256 = 'e17211d53dde23291e57bb1d9e75cbedf3629cadbc0f10452e9d82fcbcd14f71'
$reservedName = '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$'

function Read-Json([string]$Name) {
    $path = Join-Path $ManifestRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing native manifest: $Name" }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    catch { throw "Invalid native manifest JSON: $Name. $($_.Exception.Message)" }
}
function Test-Hash([object]$Value) { return $Value -is [string] -and $Value -cmatch '^[0-9a-f]{64}$' }
function New-Set([AllowEmptyCollection()][object[]]$Values, [string]$What) {
    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # Windows PowerShell 5.1 materializes an empty JSON array as $null.
    if ($null -eq $Values) { return ,$set }
    foreach ($value in @($Values)) {
        if ([string]::IsNullOrWhiteSpace([string]$value) -or -not $set.Add([string]$value)) {
            throw "Duplicate, case-colliding, or empty ${What}: $value"
        }
    }
    return ,$set
}
function Assert-ExactSet([object[]]$Actual, [object[]]$Expected, [string]$What) {
    $actualSet = New-Set $Actual $What
    $expectedSet = New-Set $Expected "expected $What"
    if ($actualSet.Count -ne $expectedSet.Count) { throw "$What set differs from the reviewed contract." }
    foreach ($item in $expectedSet) {
        if (-not $actualSet.Contains($item)) { throw "Missing reviewed ${What}: $item" }
    }
}
function Assert-RelativeWindowsPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
        $Path.Contains('\') -or $Path.Contains(':') -or $Path -match '(^|/)(\.|\.\.)(/|$)') {
        throw "Unsafe relative Windows path: $Path"
    }
    foreach ($segment in $Path.Split('/')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -match $reservedName -or $segment -match '[\. ]$') {
            throw "Windows-unsafe path segment: $Path"
        }
    }
}
function Assert-SafeLeafName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name) -or [IO.Path]::IsPathRooted($Name) -or
        [IO.Path]::GetFileName($Name) -cne $Name -or $Name -match '[:\\/]' -or
        $Name -match $reservedName -or $Name -match '[\. ]$') {
        throw "Unsafe Windows archive leaf name: $Name"
    }
}
function Assert-ImmutableUri([object]$Record, [string]$What) {
    $uri = $null
    if (-not [Uri]::TryCreate([string]$Record.url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or $uri.Query.Length -ne 0 -or
        [string]$Record.url -match '(^|/)(main|master|latest)(/|\.|$)' -or
        @($Record.allowedRedirectHosts) -notcontains $uri.Host) {
        throw "Unapproved or floating URI for ${What}: $($Record.url)"
    }
}
function Assert-ArchiveRecord([object]$Record, [string]$What) {
    if ($null -eq $Record) { throw "Missing archive record for $What" }
    Assert-SafeLeafName ([string]$Record.name)
    Assert-ImmutableUri $Record $What
    [void](New-Set @($Record.allowedRedirectHosts) "redirect host for $What")
    if (-not (Test-Hash $Record.sha256)) { throw "Archive checksum is incomplete for $What" }
}
function Assert-SignatureRecord([object]$Record, [string]$What) {
    if ($null -eq $Record) { throw "Missing detached-signature record for $What" }
    Assert-SafeLeafName ([string]$Record.name)
    Assert-ImmutableUri $Record "detached signature for $What"
    [void](New-Set @($Record.allowedRedirectHosts) "signature redirect host for $What")
    if (-not (Test-Hash $Record.sha256) -or
        [string]$Record.keyFingerprint -notmatch '^[0-9A-Fa-f]{40,64}$' -or
        $Record.status -cne 'verified' -or
        [string]::IsNullOrWhiteSpace([string]$Record.evidence)) {
        throw "Detached-signature provenance is incomplete for $What"
    }
}

$inputs = Read-Json 'native-inputs.json'
$toolchain = Read-Json 'toolchain.lock.json'
$graph = Read-Json 'dependency-graph.json'
$outputs = Read-Json 'output-contract.json'
$policy = Read-Json 'native-policy.json'
$manifestInstances = @{
    'native-inputs.json' = $inputs
    'toolchain.lock.json' = $toolchain
    'dependency-graph.json' = $graph
    'output-contract.json' = $outputs
    'native-policy.json' = $policy
}
$schemaNames = @{
    'native-inputs.json' = 'native-inputs.schema.json'
    'toolchain.lock.json' = 'toolchain-lock.schema.json'
    'dependency-graph.json' = 'dependency-graph.schema.json'
    'output-contract.json' = 'output-contract.schema.json'
    'native-policy.json' = 'native-policy.schema.json'
}
foreach ($manifestName in $schemaNames.Keys) {
    $schemaName = $schemaNames[$manifestName]
    $schemaPath = Join-Path (Join-Path $ManifestRoot 'schemas') $schemaName
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Missing native JSON schema: $schemaName" }
    try { $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json }
    catch { throw "Invalid native JSON schema: $schemaName. $($_.Exception.Message)" }
    if ($schema.'$schema' -cne 'https://json-schema.org/draft/2020-12/schema' -or
        [string]::IsNullOrWhiteSpace([string]$schema.'$id') -or $schema.type -cne 'object' -or
        @($schema.required).Count -eq 0) {
        throw "Native JSON schema catalog entry is incomplete: $schemaName"
    }
    $declaredSchema = [string]$manifestInstances[$manifestName].'$schema'
    if (-not [string]::IsNullOrWhiteSpace($declaredSchema) -and
        $declaredSchema -cne "schemas/$schemaName") {
        throw "Native manifest declares the wrong schema: $manifestName"
    }
}
$policyPath = Join-Path $ManifestRoot 'native-policy.json'
if ((Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $reviewedPolicySha256) {
    throw 'Native policy bytes differ from the independently reviewed contract.'
}
foreach ($manifest in @($inputs,$toolchain,$graph,$outputs,$policy)) {
    if ($manifest.schemaVersion -ne 2) { throw 'Unsupported native manifest schema version.' }
}
if ($inputs.kind -ne 'hvp-native-source-lock' -or $toolchain.kind -ne 'hvp-native-toolchain-lock' -or
    $graph.kind -ne 'hvp-native-dependency-graph' -or $outputs.kind -ne 'hvp-native-output-contract' -or
    $policy.kind -ne 'hvp-native-policy') { throw 'Native manifest kind mismatch.' }

Assert-ExactSet @($inputs.approvedSourceIds) $requiredSources 'approved source id'
Assert-ExactSet @($inputs.sources | ForEach-Object id) $requiredSources 'source id'
$sourceIds = New-Set @($inputs.sources | ForEach-Object id) 'source id'
foreach ($source in @($inputs.sources)) {
    if ([string]$source.commit -notmatch '^[0-9a-f]{40}$' -or
        [string]::IsNullOrWhiteSpace($source.version) -or
        [string]::IsNullOrWhiteSpace($source.licenseDeclared) -or
        [string]::IsNullOrWhiteSpace($source.owner)) {
        throw "Incomplete source identity: $($source.id)"
    }
    Assert-SafeLeafName ([string]$source.archive.name)
    Assert-ImmutableUri $source.archive "source $($source.id)"
    if ($source.archive.url -match '/archive/' -and $source.archive.url -notmatch [regex]::Escape([string]$source.commit)) {
        throw "Commit archive URL is not bound to the reviewed commit: $($source.id)"
    }
    if ($source.signature.status -notin @('pending','verified','revoked','revoked-reviewed','not-available-reviewed')) {
        throw "Unknown signature state: $($source.id)"
    }
    foreach ($patch in @($source.patches)) {
        Assert-RelativeWindowsPath ([string]$patch.path)
        if (-not (Test-Hash $patch.sha256)) { throw "Patch lacks a locked hash: $($source.id)" }
    }
    if (-not $AllowIncomplete) {
        if (-not (Test-Hash $source.archive.sha256) -or $source.pinToCommit -ne 'verified' -or
            $source.signature.status -notin @('verified','revoked-reviewed','not-available-reviewed') -or
            [string]::IsNullOrWhiteSpace($source.signature.evidence) -or
            [string]::IsNullOrWhiteSpace($source.licenseConcluded)) {
            throw "Production source provenance is incomplete: $($source.id)"
        }
        if ($source.signature.status -in @('verified','revoked-reviewed') -and
            [string]::IsNullOrWhiteSpace($source.signature.fingerprint)) {
            throw "Verified/reviewed signature lacks a key fingerprint: $($source.id)"
        }
    }
}

Assert-ExactSet @($graph.approvedNodeIds) $requiredSources 'approved dependency node'
Assert-ExactSet @($graph.nodes | ForEach-Object id) $requiredSources 'dependency node'
$nodeIds = New-Set @($graph.nodes | ForEach-Object id) 'dependency node'
$edges = @{}
foreach ($node in @($graph.nodes)) {
    if (-not $sourceIds.Contains([string]$node.source)) { throw "Dependency node has an undeclared source: $($node.id)" }
    $expectedLink = if ($node.id -in @('fast-float')) { 'header-only' } elseif ($node.id -in @('jinja','markupsafe')) { 'build-only' } else { 'shared' }
    if ($node.linkType -cne $expectedLink) { throw "Unexpected link type for $($node.id): $($node.linkType)" }
    Assert-ExactSet @($node.dependsOn) @($requiredEdges[$node.id]) "dependency edge for $($node.id)"
    $edges[$node.id] = @($node.dependsOn)
}
$visiting = @{}; $complete = @{}
function Visit-Node([string]$Id) {
    if ($visiting[$Id]) { throw "Dependency graph cycle detected at: $Id" }
    if ($complete[$Id]) { return }
    $visiting[$Id] = $true
    foreach ($dependency in $edges[$Id]) { Visit-Node $dependency }
    $visiting.Remove($Id)
    $complete[$Id] = $true
}
foreach ($id in $nodeIds) { Visit-Node $id }

Assert-ExactSet @($outputs.requiredRoles) $requiredRoles 'required output role'
Assert-ExactSet @($outputs.outputs | ForEach-Object role) $requiredRoles 'output role'
$outputPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($output in @($outputs.outputs)) {
    if (-not $nodeIds.Contains([string]$output.sourceNode)) { throw "Output has an undeclared source node: $($output.role)" }
    if ([string]$output.sourceNode -cne [string]$requiredRoleOwners[[string]$output.role]) {
        throw "Output role is owned by the wrong source node: $($output.role)"
    }
    if ($null -ne $output.path) {
        Assert-RelativeWindowsPath ([string]$output.path)
        if (-not $outputPaths.Add([string]$output.path)) { throw "Duplicate or case-colliding output path: $($output.path)" }
    }
    if (-not $AllowIncomplete) {
        Assert-RelativeWindowsPath ([string]$output.path)
        if (-not (Test-Hash $output.sha256) -or $output.peMachine -ne 'AMD64' -or
            @($output.imports).Count -eq 0 -or @($output.exports).Count -eq 0 -or
            [string]::IsNullOrWhiteSpace($output.licenseConclusion)) {
            throw "Production output evidence is incomplete: $($output.role)"
        }
        if ($output.role -eq 'libmpv') {
            $apiParts = @([string]$output.apiVersion -split '\.')
            if ($apiParts.Count -ne 2 -or [int]$apiParts[0] -ne 2 -or [int]$apiParts[1] -lt 5) {
                throw 'libmpv client API evidence must be major 2 and minor 5 or newer.'
            }
            foreach ($requiredExport in @('mpv_client_api_version','mpv_create','mpv_initialize','mpv_terminate_destroy')) {
                if (@($output.exports) -cnotcontains $requiredExport) { throw "libmpv is missing required export evidence: $requiredExport" }
            }
        }
    }
}
if (-not $AllowIncomplete -and
    ($outputs.architecture -ne 'x64' -or $outputs.closureEvidence.recursiveImportsComplete -ne $true -or
     @($outputs.closureEvidence.unexpectedDlls).Count -ne 0 -or
     [string]::IsNullOrWhiteSpace($outputs.closureEvidence.systemDllAllowlistVersion))) {
    throw 'Recursive PE closure evidence is incomplete.'
}

Assert-ExactSet @($toolchain.requiredPackageIds) $requiredToolRoots 'required toolchain root'
if ($toolchain.platform -ne 'windows-x64' -or $toolchain.route -ne 'MSYS2 CLANG64' -or $toolchain.architecture -ne 'x86_64') {
    throw 'Toolchain platform/route/architecture differs from the reviewed contract.'
}
$hasBaseArchive = $null -ne $toolchain.baseArchive
$hasPackages = @($toolchain.packages).Count -gt 0
$hasPackageDatabase = $null -ne $toolchain.packageDatabase
if (-not $AllowIncomplete -and (-not $hasBaseArchive -or -not $hasPackages -or -not $hasPackageDatabase)) {
    throw 'Toolchain lock is incomplete.'
}
if ($hasBaseArchive) {
    if ($toolchain.baseArchive.id -cne 'msys2-base' -or
        $toolchain.baseArchive.architecture -cne 'x86_64' -or
        [string]::IsNullOrWhiteSpace([string]$toolchain.baseArchive.version)) {
        throw 'MSYS2 base archive identity is incomplete.'
    }
    Assert-ArchiveRecord $toolchain.baseArchive.archive 'MSYS2 base archive'
    Assert-SignatureRecord $toolchain.baseArchive.signature 'MSYS2 base archive'
}
if ($hasPackages) {
    $packageIds = New-Set @($toolchain.packages | ForEach-Object id) 'toolchain package'
    foreach ($root in $requiredToolRoots) { if (-not $packageIds.Contains($root)) { throw "Missing toolchain root package: $root" } }
    $packageEdges = @{}
    foreach ($package in @($toolchain.packages)) {
        if ($package.architecture -notin @('x86_64','any') -or
            [string]::IsNullOrWhiteSpace([string]$package.packageName) -or
            [string]::IsNullOrWhiteSpace([string]$package.version)) {
            throw "Toolchain package identity is incomplete: $($package.id)"
        }
        Assert-ArchiveRecord $package.archive "toolchain package $($package.id)"
        Assert-SignatureRecord $package.signature "toolchain package $($package.id)"
        $packageDependencies = @($package.dependsOn | Where-Object { $null -ne $_ })
        [void](New-Set -Values $packageDependencies -What "toolchain dependency for $($package.id)")
        foreach ($dependency in $packageDependencies) {
            if (-not $packageIds.Contains([string]$dependency)) { throw "Undeclared toolchain package dependency: $($package.id) -> $dependency" }
        }
        $packageEdges[[string]$package.id] = $packageDependencies
    }
    $packageVisiting = @{}; $packageComplete = @{}
    function Visit-Package([string]$Id) {
        if ($packageVisiting[$Id]) { throw "Toolchain package dependency cycle detected at: $Id" }
        if ($packageComplete[$Id]) { return }
        $packageVisiting[$Id] = $true
        foreach ($dependency in $packageEdges[$Id]) { Visit-Package $dependency }
        $packageVisiting.Remove($Id)
        $packageComplete[$Id] = $true
    }
    foreach ($packageId in $packageIds) { Visit-Package $packageId }
}
if ($hasPackageDatabase) {
    if ($toolchain.packageDatabase.path -cne 'var/lib/pacman/local' -or
        -not (Test-Hash $toolchain.packageDatabase.sha256) -or
        [string]::IsNullOrWhiteSpace([string]$toolchain.packageDatabase.evidence)) {
        throw 'Preserved package database evidence is incomplete.'
    }
    if (-not $hasPackages) { throw 'Package database evidence exists without a locked package closure.' }
    Assert-ExactSet @($toolchain.packageDatabase.packageIds) @($toolchain.packages | ForEach-Object id) 'package database package id'
}

$criticalForbidden = @('--enable-gpl','--enable-nonfree','--enable-network','--enable-libcurl','--wrap-mode=forcefallback','-Dgpl=true','-Dprefer_static=true')
foreach ($forbidden in $criticalForbidden) {
    if (@($policy.forbiddenOptionKeys) -notcontains $forbidden) { throw "Critical forbidden option is absent from policy: $forbidden" }
}
foreach ($component in @($policy.required.PSObject.Properties.Name)) {
    & (Join-Path $PSScriptRoot 'Test-NativeConfiguration.ps1') -Component $component -Flags @($policy.required.$component) -PolicyPath (Join-Path $ManifestRoot 'native-policy.json') | Out-Null
}
foreach ($inputName in @('current-directory','ambient-path','meson-wrap','pacman-sync','unlocked-msys2-package','glad','vulkan-headers')) {
    if (@($policy.forbiddenInputs) -notcontains $inputName) { throw "Critical forbidden input is absent from policy: $inputName" }
}

Write-Host 'Native manifests conform to the reviewed schema-v2 foundation.'
