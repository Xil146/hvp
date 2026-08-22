[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleRoot,
    [string]$OutputContractPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/output-contract.json'),
    [string]$EvidencePath,
    [string[]]$SystemDllAllowlist = @('api-ms-win-core*.dll','bcrypt.dll','combase.dll','d3d11.dll','dxgi.dll','gdi32.dll','kernel32.dll','kernelbase.dll','mfplat.dll','ole32.dll','oleaut32.dll','secur32.dll','shell32.dll','shcore.dll','user32.dll','ucrtbase.dll','vcruntime140.dll','version.dll','winmm.dll','ws2_32.dll')
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($BundleRoot)
if (-not [IO.Directory]::Exists($root)) { throw "Native bundle root does not exist: $root" }
if (-not [IO.File]::Exists($OutputContractPath)) { throw "Native output contract does not exist: $OutputContractPath" }
$contract = Get-Content -LiteralPath $OutputContractPath -Raw | ConvertFrom-Json
if ($contract.kind -cne 'hvp-native-output-contract' -or $contract.architecture -cne 'x64') { throw 'Native output contract is not an x64 HVP contract.' }
if (@($contract.outputs | Where-Object { $null -eq $_.path -or $null -eq $_.sha256 }).Count -ne 0) { throw 'Native output contract is incomplete; binary verification fails closed.' }
$expected = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($output in @($contract.outputs)) {
    $relative = [string]$output.path
    if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains('..') -or $relative.Contains('\')) { throw "Unsafe output contract path: $relative" }
    if (-not $expected.TryAdd($relative, $output)) { throw "Duplicate or case-colliding native output path: $relative" }
}
$allItems = @(Get-ChildItem -LiteralPath $root -Recurse -Force)
foreach($item in $allItems){if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "Native bundle contains a reparse point: $($item.FullName)"}}
$actualFiles = @($allItems | Where-Object { -not $_.PSIsContainer })
foreach ($file in $actualFiles) {
    $relative = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\','/')
    if (-not $expected.ContainsKey($relative)) { throw "Native bundle contains an unreviewed file: $relative" }
}
$metadata = @(); $resolvedNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $expected.GetEnumerator()) {
    $file = Join-Path $root $entry.Key
    if (-not [IO.File]::Exists($file)) { throw "Native bundle is missing contract DLL: $($entry.Key)" }
    $details = & (Join-Path $PSScriptRoot 'Get-NativePeMetadata.ps1') -Path $file
    if ($details.peMachine -cne 'AMD64' -or $details.sha256 -cne [string]$entry.Value.sha256) { throw "Native DLL identity/hash does not match the output contract: $($entry.Key)" }
    foreach ($property in @('imports','delayImports','exports')) {
        $actual = @($details.$property | Sort-Object -Unique); $recorded = @($entry.Value.$property | Sort-Object -Unique)
        if (($actual -join "`n") -cne ($recorded -join "`n")) { throw "Native DLL $property evidence does not match the binary: $($entry.Key)" }
    }
    if ($entry.Value.peMachine -cne $details.peMachine -or
        [string]$entry.Value.dllCharacteristics -cne [string]$details.dllCharacteristics -or
        -not $details.isDll -or -not $details.dynamicBase -or -not $details.nxCompatible) {
        throw "Recorded PE identity/security characteristics differ from binary: $($entry.Key)"
    }
    [void]$resolvedNames.Add([IO.Path]::GetFileName($entry.Key))
    $metadata += $details
}
foreach ($dll in $metadata) {
    foreach ($import in @($dll.imports) + @($dll.delayImports)) {
        if ($resolvedNames.Contains($import)) { continue }
        if (@($SystemDllAllowlist | Where-Object { $import -like $_ }).Count -eq 0) { throw "Unresolved or unapproved recursive DLL import '$import' in $([IO.Path]::GetFileName($dll.path))" }
    }
}
$libmpv = @($contract.outputs | Where-Object role -eq 'libmpv')
if ($libmpv.Count -ne 1) { throw 'The output contract must contain exactly one libmpv role.' }
foreach ($export in @('mpv_client_api_version','mpv_create','mpv_initialize','mpv_terminate_destroy','mpv_set_option_string','mpv_command','mpv_wait_event')) { if (@($libmpv[0].exports) -cnotcontains $export) { throw "libmpv required export is absent: $export" } }
$api = @([string]$libmpv[0].apiVersion -split '\.')
if ($api.Count -ne 2 -or [int]$api[0] -ne 2 -or [int]$api[1] -lt 5) { throw 'libmpv client API must be major 2, minor 5 or newer.' }
$evidence = [ordered]@{ schemaVersion = 1; kind = 'hvp-native-pe-evidence'; generatedUtc = [DateTime]::UtcNow.ToString('o'); architecture = 'AMD64'; recursiveImportsComplete = $true; unexpectedDlls = @(); systemDllAllowlist = @($SystemDllAllowlist | Sort-Object); outputs = @($metadata | Sort-Object path) }
if ($EvidencePath) { $parent = Split-Path -Parent $EvidencePath; if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }; [IO.File]::WriteAllText([IO.Path]::GetFullPath($EvidencePath), ($evidence | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false)) }
$evidence
