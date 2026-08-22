[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$native = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $native 'scripts'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hvp-native-verification-' + [guid]::NewGuid())
function Assert-Rejected([scriptblock]$Action, [string]$Expectation) {
    try { & $Action } catch { if ($_.Exception.Message -like "*$Expectation*") { return }; throw "Expected rejection containing '$Expectation', got: $($_.Exception.Message)" }
    throw "Expected rejection containing '$Expectation'."
}
try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $private = Join-Path $testRoot 'libmpv-2.dll'; [IO.File]::WriteAllText($private, 'fixture')
    $selected = & (Join-Path $scripts 'Test-LibmpvReplacementContract.ps1') -PrivateLibmpvPath $private
    if ($selected.source -ne 'private' -or $selected.allowCurrentDirectory -or $selected.allowAmbientPath) { throw 'Private replacement resolution does not record restricted loading.' }
    $replacementDirectory = Join-Path $testRoot 'replacement'; New-Item -ItemType Directory -Path $replacementDirectory | Out-Null
    $replacement = Join-Path $replacementDirectory 'libmpv-2.dll'; [IO.File]::WriteAllText($replacement, 'replacement')
    $selected = & (Join-Path $scripts 'Test-LibmpvReplacementContract.ps1') -PrivateLibmpvPath $private -OverridePath $replacement
    if ($selected.source -ne 'override' -or $selected.selectedPath -cne [IO.Path]::GetFullPath($replacement)) { throw 'Absolute replacement override was not selected.' }
    Assert-Rejected { & (Join-Path $scripts 'Test-LibmpvReplacementContract.ps1') -PrivateLibmpvPath $private -OverridePath 'libmpv-2.dll' } 'must be an absolute path'
    Assert-Rejected { & (Join-Path $scripts 'Test-LibmpvReplacementContract.ps1') -PrivateLibmpvPath $private -OverridePath (Join-Path $testRoot 'missing.dll') } 'does not exist'
    $other = Join-Path $testRoot 'other.dll'; [IO.File]::WriteAllText($other, 'other')
    Assert-Rejected { & (Join-Path $scripts 'Test-LibmpvReplacementContract.ps1') -PrivateLibmpvPath $private -OverridePath $other } 'must name libmpv-2.dll'

    $header = Join-Path $testRoot 'client.h'
    [IO.File]::WriteAllText($header, @'
#define MPV_CLIENT_API_VERSION MPV_MAKE_VERSION(2, 5)
int mpv_client_api_version(void); void *mpv_create(void); int mpv_initialize(void *h);
void mpv_terminate_destroy(void *h); int mpv_set_option_string(void *h, const char *n, const char *v); int mpv_command(void *h, const char **args);
'@)
    $output = Join-Path $testRoot 'LibmpvNative.Generated.cs'; $hash = (Get-FileHash -LiteralPath $header -Algorithm SHA256).Hash.ToLowerInvariant()
    $declaration = & (Join-Path $scripts 'New-LibmpvInteropDeclarations.ps1') -ClientHeaderPath $header -OutputPath $output -ExpectedHeaderSha256 $hash
    if ($declaration.apiVersion -ne '2.5' -or -not (Select-String -LiteralPath $output -SimpleMatch 'IntPtr mpv_create' -Quiet) -or -not (Select-String -LiteralPath $output -SimpleMatch 'uint mpv_client_api_version' -Quiet) -or -not (Select-String -LiteralPath $output -SimpleMatch 'UnmanagedType.LPUTF8Str' -Quiet) -or -not (Select-String -LiteralPath $output -SimpleMatch 'CallingConvention.Cdecl' -Quiet)) { throw 'Generated interop declarations do not preserve the required Windows ABI surface.' }
    Assert-Rejected { & (Join-Path $scripts 'New-LibmpvInteropDeclarations.ps1') -ClientHeaderPath $header -OutputPath $output -ExpectedHeaderSha256 ('0' * 64) } 'does not match its pinned SHA-256'
    [IO.File]::WriteAllText($header, '#define MPV_CLIENT_API_VERSION MPV_MAKE_VERSION(2, 4)')
    $hash = (Get-FileHash -LiteralPath $header -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Rejected { & (Join-Path $scripts 'New-LibmpvInteropDeclarations.ps1') -ClientHeaderPath $header -OutputPath $output -ExpectedHeaderSha256 $hash } 'not compatible'

    $smoke = Get-Content -LiteralPath (Join-Path $scripts 'Invoke-LibmpvSmokeTest.ps1') -Raw
    foreach ($required in @('SetDefaultDllDirectories', 'LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR', 'LOAD_LIBRARY_SEARCH_SYSTEM32', "@('ao','null')", "@('vo','null')", 'mpv_wait_event', 'MPV_EVENT_FILE_LOADED', 'FileShare', 'mpv_terminate_destroy')) { if ($smoke -notlike "*$required*") { throw "Smoke harness does not implement required contract evidence: $required" } }
    if ($smoke -like '*LOAD_LIBRARY_SEARCH_DEFAULT_DIRS*' -or $smoke -like '*delegate ulong ClientApiVersion*') { throw 'Smoke harness permits fallback search or uses the wrong Windows unsigned-long ABI width.' }

    $systemDll = Join-Path $env:SystemRoot 'System32/kernel32.dll'
    $pe = & (Join-Path $scripts 'Get-NativePeMetadata.ps1') -Path $systemDll
    if ($pe.peMachine -ne 'AMD64' -or @($pe.exports).Count -eq 0 -or -not $pe.dynamicBase -or -not $pe.nxCompatible -or $pe.dllCharacteristics -notmatch '^0x[0-9a-f]{4}$') { throw 'Real AMD64 PE metadata parsing did not produce complete identity/security evidence.' }
}
finally { if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force } }
Write-Host 'Native verification focused tests passed.'
