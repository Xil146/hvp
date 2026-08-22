using System.Runtime.InteropServices;
using Hvp.Core.Playback;

namespace Hvp.Playback;

/// <summary>
/// A deliberately small libmpv owner. It only loads <c>libmpv-2.dll</c> next to
/// the application executable and never consults environment overrides.
/// </summary>
public sealed class LibmpvPlaybackEngine : IPlaybackController
{
    private const string LibraryFileName = "libmpv-2.dll";
    private const int MpvEventShutdown = 1;
    private const int MpvEventStartFile = 6;
    private const int MpvEventEndFile = 7;
    private const int MpvEventFileLoaded = 8;
    private const int MpvEventPause = 12;
    private const int MpvEventUnpause = 13;
    private readonly object gate = new();
    // Serializes every use of mpv_handle* with mpv_terminate_destroy.
    private readonly object nativeCallGate = new();
    private PlaybackSnapshot snapshot = PlaybackSnapshot.Idle;
    private nint module;
    private nint handle;
    private NativeApi? native;
    private Task? eventPump;
    private bool disposing;

    public event EventHandler<PlaybackSnapshot>? SnapshotChanged;

    public PlaybackSnapshot Snapshot
    {
        get { lock (gate) { return snapshot; } }
    }

    public Task InitializeAsync(nint videoHost, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (videoHost == nint.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(videoHost));
        }

        return Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            lock (gate)
            {
                ThrowIfDisposing();
                if (handle != nint.Zero)
                {
                    return;
                }

                try
                {
                    string libraryPath = Path.Combine(AppContext.BaseDirectory, LibraryFileName);
                    if (!File.Exists(libraryPath))
                    {
                        throw new FileNotFoundException($"HVP could not find its private libmpv library at '{libraryPath}'. Reinstall the complete application folder.", libraryPath);
                    }

                    using PrivateDllDirectory dllDirectory = PrivateDllDirectory.AddFor(libraryPath);
                    module = NativeLibrary.Load(libraryPath);
                    native = NativeApi.From(module);
                    uint apiVersion = native.ClientApiVersion();
                    if ((apiVersion >> 16) != 2 || (apiVersion & 0xffff) < 5)
                    {
                        throw new InvalidOperationException($"The private libmpv library reports incompatible client API {(apiVersion >> 16)}.{(apiVersion & 0xffff)}; 2.5 or later is required.");
                    }

                    handle = native.Create();
                    if (handle == nint.Zero)
                    {
                        throw new InvalidOperationException("libmpv could not create a playback handle.");
                    }

                    SetOption("wid", videoHost.ToString(System.Globalization.CultureInfo.InvariantCulture));
                    SetOption("vo", "gpu-next");
                    SetOption("gpu-api", "d3d11");
                    SetOption("hwdec", "auto-safe");
                    Check(native.Initialize(handle), "initialize libmpv");
                    eventPump = Task.Run(EventPump);
                }
                catch
                {
                    DestroyNative_NoLock();
                    throw;
                }
            }
        }, cancellationToken);
    }

    public Task OpenAsync(string path, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        string fullPath = Path.GetFullPath(path);
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException("The selected media file no longer exists.", fullPath);
        }

        UpdateSnapshot(new PlaybackSnapshot(PlaybackState.Opening));
        return ExecuteCommandAsync(cancellationToken, "loadfile", fullPath, "replace");
    }

    public Task SetPausedAsync(bool paused, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ExecuteCommandAsync(cancellationToken, "set", "pause", paused ? "yes" : "no");
    }

    public Task SeekAsync(TimeSpan position, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (position < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(position));
        }

        return ExecuteCommandAsync(cancellationToken, "seek", position.TotalSeconds.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture), "absolute");
    }

    public Task SeekRelativeAsync(TimeSpan offset, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ExecuteCommandAsync(cancellationToken, "seek", offset.TotalSeconds.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture), "relative");
    }

    public Task SeekToPercentAsync(double percent, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (double.IsNaN(percent) || double.IsInfinity(percent))
        {
            throw new ArgumentOutOfRangeException(nameof(percent));
        }

        return ExecuteCommandAsync(cancellationToken, "seek", Math.Clamp(percent, 0, 100).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture), "absolute-percent");
    }

    public Task SetVolumeAsync(double volume, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (double.IsNaN(volume) || double.IsInfinity(volume))
        {
            throw new ArgumentOutOfRangeException(nameof(volume));
        }

        return ExecuteCommandAsync(cancellationToken, "set", "volume", Math.Clamp(volume, 0, 100).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture));
    }

    public Task StopAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return StopCoreAsync(cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        Task? pump;
        NativeApi? api;
        nint handleToDestroy;
        lock (gate)
        {
            if (disposing)
            {
                return;
            }

            disposing = true;
            api = native;
            handleToDestroy = handle;
            pump = eventPump;
        }

        if (handleToDestroy != nint.Zero)
        {
            // mpv_wait_event can be in its bounded wait. Keep that wait off a
            // WPF close continuation while nativeCallGate serializes destroy.
            await Task.Run(() =>
            {
                // Do not hold gate here: the event pump takes nativeCallGate
                // first and then observes disposal under gate.
                lock (nativeCallGate)
                {
                    api!.TerminateDestroy(handleToDestroy);
                    lock (gate)
                    {
                        handle = nint.Zero;
                    }
                }
            }).ConfigureAwait(false);
        }

        if (pump is not null)
        {
            await pump.ConfigureAwait(false);
        }

        lock (gate)
        {
            if (module != nint.Zero)
            {
                NativeLibrary.Free(module);
                module = nint.Zero;
            }

            native = null;
            UpdateSnapshot_NoLock(PlaybackSnapshot.Idle);
        }
    }

    private void EventPump()
    {
        try
        {
            while (true)
            {
                MpvEvent nativeEvent;
                lock (nativeCallGate)
                {
                    NativeApi? api;
                    nint currentHandle;
                    lock (gate)
                    {
                        api = native;
                        currentHandle = handle;
                        if (disposing || api is null || currentHandle == nint.Zero)
                        {
                            return;
                        }
                    }

                    nint eventPointer = api.WaitEvent(currentHandle, 0.25);
                    if (eventPointer == nint.Zero)
                    {
                        continue;
                    }

                    nativeEvent = Marshal.PtrToStructure<MpvEvent>(eventPointer);
                }
                if (nativeEvent.EventId == MpvEventShutdown)
                {
                    return;
                }

                if (nativeEvent.Error < 0)
                {
                    UpdateSnapshot(new PlaybackSnapshot(PlaybackState.Error, $"libmpv failed while opening or playing media (error {nativeEvent.Error})."));
                    continue;
                }

                switch (nativeEvent.EventId)
                {
                    case MpvEventStartFile:
                        UpdateSnapshot(new PlaybackSnapshot(PlaybackState.Opening));
                        break;
                    case MpvEventFileLoaded:
                    case MpvEventUnpause:
                        UpdateSnapshot(new PlaybackSnapshot(PlaybackState.Playing));
                        break;
                    case MpvEventPause:
                        UpdateSnapshot(new PlaybackSnapshot(PlaybackState.Paused));
                        break;
                    case MpvEventEndFile:
                        MpvEndFileEvent endFile = nativeEvent.Data == nint.Zero
                            ? default
                            : Marshal.PtrToStructure<MpvEndFileEvent>(nativeEvent.Data);
                        UpdateSnapshot(endFile.Error < 0
                            ? new PlaybackSnapshot(PlaybackState.Error, $"libmpv could not finish the media file (error {endFile.Error}).")
                            : new PlaybackSnapshot(PlaybackState.Ended));
                        break;
                }
            }
        }
        catch (Exception exception) when (!IsDisposing())
        {
            UpdateSnapshot(new PlaybackSnapshot(PlaybackState.Error, $"The libmpv event loop stopped unexpectedly: {exception.Message}"));
        }
    }

    private void ExecuteCommand(params string[] arguments)
    {
        lock (nativeCallGate)
        {
            lock (gate)
            {
                ThrowIfDisposing();
                if (handle == nint.Zero || native is null)
                {
                    throw new InvalidOperationException("Playback has not been initialized with a video host.");
                }

                using Utf8ArgumentArray nativeArguments = new(arguments);
                Check(native.Command(handle, nativeArguments.Pointer), arguments[0]);
            }
        }
    }

    private Task ExecuteCommandAsync(CancellationToken cancellationToken, params string[] arguments) =>
        Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            ExecuteCommand(arguments);
        }, cancellationToken);

    private async Task StopCoreAsync(CancellationToken cancellationToken)
    {
        await ExecuteCommandAsync(cancellationToken, "stop").ConfigureAwait(false);
        UpdateSnapshot(PlaybackSnapshot.Idle);
    }

    private void SetOption(string name, string value)
    {
        Check(native!.SetOptionString(handle, name, value), $"set {name}");
    }

    private void Check(int result, string action)
    {
        if (result < 0)
        {
            throw new InvalidOperationException($"libmpv could not {action} (error {result}).");
        }
    }

    private void UpdateSnapshot(PlaybackSnapshot value)
    {
        EventHandler<PlaybackSnapshot>? changed;
        lock (gate)
        {
            changed = UpdateSnapshot_NoLock(value);
        }

        changed?.Invoke(this, value);
    }

    private EventHandler<PlaybackSnapshot>? UpdateSnapshot_NoLock(PlaybackSnapshot value)
    {
        snapshot = value;
        return SnapshotChanged;
    }

    private bool IsDisposing()
    {
        lock (gate) { return disposing; }
    }

    private void ThrowIfDisposing()
    {
        ObjectDisposedException.ThrowIf(disposing, this);
    }

    private void DestroyNative_NoLock()
    {
        if (handle != nint.Zero)
        {
            native?.TerminateDestroy(handle);
            handle = nint.Zero;
        }

        if (module != nint.Zero)
        {
            NativeLibrary.Free(module);
            module = nint.Zero;
        }

        native = null;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct MpvEvent
    {
        public readonly int EventId;
        public readonly int Error;
        public readonly ulong ReplyUserdata;
        public readonly nint Data;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct MpvEndFileEvent
    {
        public readonly int Reason;
        public readonly int Error;
        public readonly long PlaylistEntryId;
        public readonly long PlaylistInsertId;
        public readonly int PlaylistInsertNumEntries;
    }

    private sealed class Utf8ArgumentArray : IDisposable
    {
        private readonly nint[] strings;
        public Utf8ArgumentArray(IReadOnlyList<string> arguments)
        {
            strings = new nint[arguments.Count];
            Pointer = Marshal.AllocHGlobal(IntPtr.Size * (arguments.Count + 1));
            try
            {
                for (int index = 0; index < arguments.Count; index++)
                {
                    strings[index] = Marshal.StringToCoTaskMemUTF8(arguments[index]);
                    Marshal.WriteIntPtr(Pointer, index * IntPtr.Size, strings[index]);
                }

                Marshal.WriteIntPtr(Pointer, arguments.Count * IntPtr.Size, nint.Zero);
            }
            catch
            {
                Dispose();
                throw;
            }
        }

        public nint Pointer { get; private set; }

        public void Dispose()
        {
            foreach (nint value in strings)
            {
                if (value != nint.Zero) { Marshal.FreeCoTaskMem(value); }
            }

            if (Pointer != nint.Zero)
            {
                Marshal.FreeHGlobal(Pointer);
                Pointer = nint.Zero;
            }
        }
    }

    private sealed class NativeApi
    {
        private NativeApi(nint module)
        {
            ClientApiVersion = GetDelegate<ClientApiVersionDelegate>(module, "mpv_client_api_version");
            Create = GetDelegate<CreateDelegate>(module, "mpv_create");
            Initialize = GetDelegate<InitializeDelegate>(module, "mpv_initialize");
            TerminateDestroy = GetDelegate<TerminateDestroyDelegate>(module, "mpv_terminate_destroy");
            SetOptionString = GetDelegate<SetOptionStringDelegate>(module, "mpv_set_option_string");
            Command = GetDelegate<CommandDelegate>(module, "mpv_command");
            WaitEvent = GetDelegate<WaitEventDelegate>(module, "mpv_wait_event");
        }

        public ClientApiVersionDelegate ClientApiVersion { get; }
        public CreateDelegate Create { get; }
        public InitializeDelegate Initialize { get; }
        public TerminateDestroyDelegate TerminateDestroy { get; }
        public SetOptionStringDelegate SetOptionString { get; }
        public CommandDelegate Command { get; }
        public WaitEventDelegate WaitEvent { get; }

        public static NativeApi From(nint module) => new(module);

        private static T GetDelegate<T>(nint module, string export) where T : Delegate =>
            Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(module, export));

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate uint ClientApiVersionDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate nint CreateDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int InitializeDelegate(nint handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void TerminateDestroyDelegate(nint handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int SetOptionStringDelegate(nint handle, [MarshalAs(UnmanagedType.LPUTF8Str)] string name, [MarshalAs(UnmanagedType.LPUTF8Str)] string value);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int CommandDelegate(nint handle, nint arguments);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate nint WaitEventDelegate(nint handle, double timeout);
    }

    private sealed class PrivateDllDirectory : IDisposable
    {
        private const uint LoadLibrarySearchDefaultDirs = 0x00001000;
        private nint cookie;

        private PrivateDllDirectory(nint cookie) => this.cookie = cookie;

        public static PrivateDllDirectory AddFor(string libraryPath)
        {
            if (!SetDefaultDllDirectories(LoadLibrarySearchDefaultDirs))
            {
                throw new InvalidOperationException($"Could not restrict DLL search paths before loading libmpv (Win32 error {Marshal.GetLastWin32Error()}).");
            }

            string directory = Path.GetDirectoryName(libraryPath) ?? throw new InvalidOperationException("The private libmpv path has no parent directory.");
            nint cookie = AddDllDirectory(directory);
            if (cookie == nint.Zero)
            {
                throw new InvalidOperationException($"Could not add HVP's private DLL directory (Win32 error {Marshal.GetLastWin32Error()}).");
            }

            return new PrivateDllDirectory(cookie);
        }

        public void Dispose()
        {
            if (cookie != nint.Zero)
            {
                _ = RemoveDllDirectory(cookie);
                cookie = nint.Zero;
            }
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetDefaultDllDirectories(uint directoryFlags);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern nint AddDllDirectory(string newDirectory);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool RemoveDllDirectory(nint cookie);
    }
}
