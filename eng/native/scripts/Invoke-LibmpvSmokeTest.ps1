[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LibmpvPath,
    [Parameter(Mandatory)][string]$FixturePath,
    [ValidateRange(1,1000)][int]$Iterations = 5,
    [ValidateRange(1,120)][int]$LoadTimeoutSeconds = 15,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'The libmpv smoke test is Windows-only.' }
$selection = & (Join-Path $PSScriptRoot 'Test-LibmpvReplacementContract.ps1') -PrivateLibmpvPath $LibmpvPath
$library = [string]$selection.selectedPath
$fixture = [IO.Path]::GetFullPath($FixturePath)
if (-not [IO.File]::Exists($fixture)) { throw "Tiny local fixture does not exist: $fixture" }
if (-not ('Hvp.NativeSmoke.Loader' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Hvp.NativeSmoke {
 public static class Loader {
  [DllImport("kernel32", SetLastError=true)] public static extern bool SetDefaultDllDirectories(uint flags);
  [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
  [DllImport("kernel32", SetLastError=true)] public static extern bool FreeLibrary(IntPtr module);
  [DllImport("kernel32", CharSet=CharSet.Ansi, SetLastError=true)] public static extern IntPtr GetProcAddress(IntPtr module, string name);
 }
 [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate IntPtr Create();
  // Windows uses LLP64: C unsigned long is 32 bits.
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate uint ClientApiVersion();
 [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int Initialize(IntPtr h);
 [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void Destroy(IntPtr h);
 [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet=CharSet.Ansi)] public delegate int SetOption(IntPtr h, string n, string v);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int Command(IntPtr h, IntPtr args);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate IntPtr WaitEvent(IntPtr h, double timeout);
}
'@
}
$LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR = 0x100; $LOAD_LIBRARY_SEARCH_SYSTEM32 = 0x800
if (-not [Hvp.NativeSmoke.Loader]::SetDefaultDllDirectories($LOAD_LIBRARY_SEARCH_SYSTEM32)) { throw "SetDefaultDllDirectories failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
function Get-Delegate([IntPtr]$Module, [string]$Name, [type]$Type) { $address = [Hvp.NativeSmoke.Loader]::GetProcAddress($Module, $Name); if ($address -eq [IntPtr]::Zero) { throw "libmpv required export is missing: $Name" }; return [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($address, $Type) }
$module = [Hvp.NativeSmoke.Loader]::LoadLibraryEx($library, [IntPtr]::Zero, ($LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR -bor $LOAD_LIBRARY_SEARCH_SYSTEM32))
if ($module -eq [IntPtr]::Zero) { throw "Restricted libmpv load failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
try {
    $apiVersion = Get-Delegate $module 'mpv_client_api_version' ([Hvp.NativeSmoke.ClientApiVersion]); $create = Get-Delegate $module 'mpv_create' ([Hvp.NativeSmoke.Create]); $initialize = Get-Delegate $module 'mpv_initialize' ([Hvp.NativeSmoke.Initialize]); $destroy = Get-Delegate $module 'mpv_terminate_destroy' ([Hvp.NativeSmoke.Destroy]); $setOption = Get-Delegate $module 'mpv_set_option_string' ([Hvp.NativeSmoke.SetOption]); $command = Get-Delegate $module 'mpv_command' ([Hvp.NativeSmoke.Command]); $waitEvent = Get-Delegate $module 'mpv_wait_event' ([Hvp.NativeSmoke.WaitEvent])
    $rawApiVersion = $apiVersion.Invoke(); $apiMajor = [uint32]($rawApiVersion -shr 16); $apiMinor = [uint32]($rawApiVersion -band 0xffff)
    if ($apiMajor -ne 2 -or $apiMinor -lt 5) { throw "Loaded libmpv client API $apiMajor.$apiMinor is incompatible; API 2.5 or newer is required." }
    for ($i = 0; $i -lt $Iterations; $i++) {
        $handle = $create.Invoke(); if ($handle -eq [IntPtr]::Zero) { throw 'mpv_create returned a null handle.' }
        try {
            foreach ($option in @(@('ao','null'), @('vo','null'))) { if ($setOption.Invoke($handle, $option[0], $option[1]) -lt 0) { throw "mpv_set_option_string rejected $($option[0])=null." } }
            if ($initialize.Invoke($handle) -lt 0) { throw 'mpv_initialize failed.' }
            $strings = @('loadfile', $fixture, 'replace'); $pointers = [Collections.Generic.List[IntPtr]]::new(); $args = [IntPtr]::Zero
            try { foreach ($value in $strings) { $pointers.Add([Runtime.InteropServices.Marshal]::StringToCoTaskMemUTF8($value)) }; $args = [Runtime.InteropServices.Marshal]::AllocHGlobal([IntPtr]::Size * ($pointers.Count + 1)); for ($j=0; $j -lt $pointers.Count; $j++) { [Runtime.InteropServices.Marshal]::WriteIntPtr($args, $j * [IntPtr]::Size, $pointers[$j]) }; [Runtime.InteropServices.Marshal]::WriteIntPtr($args, $pointers.Count * [IntPtr]::Size, [IntPtr]::Zero); if ($command.Invoke($handle, $args) -lt 0) { throw 'mpv loadfile command failed for the local fixture.' } } finally { if ($args -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($args) }; foreach ($pointer in $pointers) { [Runtime.InteropServices.Marshal]::FreeCoTaskMem($pointer) } }
            $loaded = $false; $deadline = [DateTime]::UtcNow.AddSeconds($LoadTimeoutSeconds)
            while ([DateTime]::UtcNow -lt $deadline) {
                $eventPointer = $waitEvent.Invoke($handle, 0.25)
                if ($eventPointer -eq [IntPtr]::Zero) { throw 'mpv_wait_event returned a null event pointer.' }
                $eventId = [Runtime.InteropServices.Marshal]::ReadInt32($eventPointer, 0)
                $eventError = [Runtime.InteropServices.Marshal]::ReadInt32($eventPointer, 4)
                if ($eventId -eq 8) { $loaded = $true; break }
                if ($eventId -eq 7 -or $eventError -lt 0) { throw "libmpv ended the fixture before file-loaded (event=$eventId error=$eventError)." }
            }
            if (-not $loaded) { throw 'Timed out waiting for MPV_EVENT_FILE_LOADED.' }
        } finally { $destroy.Invoke($handle) }
    }
} finally { if (-not [Hvp.NativeSmoke.Loader]::FreeLibrary($module)) { throw "FreeLibrary failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" } }
$exclusive = $null
try { $exclusive = [IO.File]::Open($fixture, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None) }
catch { throw "Fixture remained locked after libmpv teardown: $($_.Exception.Message)" }
finally { if ($null -ne $exclusive) { $exclusive.Dispose() } }
$record = [ordered]@{ schemaVersion = 1; kind = 'hvp-libmpv-smoke-evidence'; iterations = $Iterations; fixtureLoaded = $true; fixtureUnlocked = $true; libraryFileName = [IO.Path]::GetFileName($library); librarySource = $selection.source; apiVersion = "$apiMajor.$apiMinor"; searchPolicy = 'LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32'; generatedUtc = [DateTime]::UtcNow.ToString('o') }
if (-not [string]::IsNullOrWhiteSpace($EvidencePath)) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($EvidencePath), (($record | ConvertTo-Json -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false)) }
[pscustomobject]$record
