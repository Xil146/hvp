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
    private const int MpvEventVideoReconfig = 17;
    private const int MpvEventPropertyChange = 22;
    private const int MpvFormatString = 1;
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
                    ObserveTrackProperties();
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
        return SetPausedCoreAsync(paused, cancellationToken);
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

    public async Task SetSubtitleAsync(int? trackId, CancellationToken cancellationToken = default)
    {
        string selection = trackId?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "no";
        await ExecuteCommandAsync(cancellationToken, "set", "sid", selection).ConfigureAwait(false);
        IReadOnlyList<SubtitleTrack> tracks = ReadSubtitleTracks();
        int? selectedTrackId = ReadSelectedSubtitleTrackId();
        TransformSnapshot(current => current with
        {
            SubtitleTracks = tracks,
            SelectedSubtitleTrackId = selectedTrackId,
        });
    }

    public async Task SetAudioAsync(int trackId, CancellationToken cancellationToken = default)
    {
        if (trackId < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(trackId));
        }

        await ExecuteCommandAsync(cancellationToken, "set", "aid", trackId.ToString(System.Globalization.CultureInfo.InvariantCulture)).ConfigureAwait(false);
        IReadOnlyList<AudioTrack> tracks = ReadAudioTracks();
        int? selectedTrackId = ReadSelectedAudioTrackId();
        TransformSnapshot(current => current with
        {
            AudioTracks = tracks,
            SelectedAudioTrackId = selectedTrackId,
        });
    }

    public async Task SetVideoAsync(int trackId, CancellationToken cancellationToken = default)
    {
        if (trackId < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(trackId));
        }

        await ExecuteCommandAsync(cancellationToken, "set", "vid", trackId.ToString(System.Globalization.CultureInfo.InvariantCulture)).ConfigureAwait(false);
        IReadOnlyList<VideoTrack> tracks = ReadVideoTracks();
        int? selectedTrackId = ReadSelectedVideoTrackId();
        TransformSnapshot(current => current with
        {
            VideoTracks = tracks,
            SelectedVideoTrackId = selectedTrackId,
        });
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
                        UpdateSnapshot(new PlaybackSnapshot(
                            PlaybackState.Playing,
                            Stream: ReadStreamDescriptor(),
                            SubtitleTracks: ReadSubtitleTracks(),
                            SelectedSubtitleTrackId: ReadSelectedSubtitleTrackId(),
                            AudioTracks: ReadAudioTracks(),
                            SelectedAudioTrackId: ReadSelectedAudioTrackId(),
                            VideoTracks: ReadVideoTracks(),
                            SelectedVideoTrackId: ReadSelectedVideoTrackId()));
                        break;
                    case MpvEventVideoReconfig:
                        StreamDescriptor descriptor = ReadStreamDescriptor();
                        TransformSnapshot(current => current with { Stream = descriptor });
                        break;
                    case MpvEventPropertyChange:
                        RefreshTrackSnapshot();
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

    private async Task SetPausedCoreAsync(bool paused, CancellationToken cancellationToken)
    {
        await ExecuteCommandAsync(cancellationToken, "set", "pause", paused ? "yes" : "no").ConfigureAwait(false);
        TransformSnapshot(current => current with { State = paused ? PlaybackState.Paused : PlaybackState.Playing });
    }

    private StreamDescriptor ReadStreamDescriptor()
    {
        return StreamDescriptorFactory.Create(
            GetPropertyString("width"),
            GetPropertyString("height"),
            GetPropertyString("video-format"),
            GetPropertyString("video-params/pixelformat"),
            GetPropertyString("video-params/gamma"),
            GetPropertyString("video-params/primaries"));
    }

    private IReadOnlyList<SubtitleTrack> ReadSubtitleTracks()
    {
        int count = TryParseInt(GetPropertyString("track-list/count")) ?? 0;
        List<SubtitleTrack> tracks = [];
        for (int index = 0; index < count; index++)
        {
            string prefix = $"track-list/{index}";
            if (!string.Equals(GetPropertyString($"{prefix}/type"), "sub", StringComparison.Ordinal))
            {
                continue;
            }

            int? id = TryParseInt(GetPropertyString($"{prefix}/id"));
            if (id is null)
            {
                continue;
            }

            string? title = GetPropertyString($"{prefix}/title");
            string? language = GetPropertyString($"{prefix}/lang");
            string label = !string.IsNullOrWhiteSpace(title)
                ? title
                : !string.IsNullOrWhiteSpace(language) ? language : $"Subtitle {id.Value}";
            bool external = string.Equals(GetPropertyString($"{prefix}/external"), "yes", StringComparison.OrdinalIgnoreCase);
            tracks.Add(new SubtitleTrack(id.Value, label, external));
        }

        return tracks;
    }

    private int? ReadSelectedSubtitleTrackId()
    {
        string? selected = GetPropertyString("sid");
        return int.TryParse(selected, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out int id) ? id : null;
    }

    private IReadOnlyList<AudioTrack> ReadAudioTracks()
    {
        int count = TryParseInt(GetPropertyString("track-list/count")) ?? 0;
        List<AudioTrack> tracks = [];
        for (int index = 0; index < count; index++)
        {
            string prefix = $"track-list/{index}";
            if (!string.Equals(GetPropertyString($"{prefix}/type"), "audio", StringComparison.Ordinal))
            {
                continue;
            }

            int? id = TryParseInt(GetPropertyString($"{prefix}/id"));
            if (id is null)
            {
                continue;
            }

            string? title = GetPropertyString($"{prefix}/title");
            string? language = GetPropertyString($"{prefix}/lang");
            string label = !string.IsNullOrWhiteSpace(title)
                ? title
                : !string.IsNullOrWhiteSpace(language) ? language : $"Audio {id.Value}";
            bool external = string.Equals(GetPropertyString($"{prefix}/external"), "yes", StringComparison.OrdinalIgnoreCase);
            tracks.Add(new AudioTrack(id.Value, label, external));
        }

        return tracks;
    }

    private int? ReadSelectedAudioTrackId()
    {
        string? selected = GetPropertyString("aid");
        return int.TryParse(selected, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out int id) ? id : null;
    }

    private IReadOnlyList<VideoTrack> ReadVideoTracks()
    {
        int count = TryParseInt(GetPropertyString("track-list/count")) ?? 0;
        List<VideoTrack> tracks = [];
        for (int index = 0; index < count; index++)
        {
            string prefix = $"track-list/{index}";
            if (!string.Equals(GetPropertyString($"{prefix}/type"), "video", StringComparison.Ordinal))
            {
                continue;
            }

            int? id = TryParseInt(GetPropertyString($"{prefix}/id"));
            if (id is null)
            {
                continue;
            }

            string? title = GetPropertyString($"{prefix}/title");
            string? language = GetPropertyString($"{prefix}/lang");
            string label = !string.IsNullOrWhiteSpace(title)
                ? title
                : !string.IsNullOrWhiteSpace(language) ? language : $"Video {id.Value}";
            bool external = string.Equals(GetPropertyString($"{prefix}/external"), "yes", StringComparison.OrdinalIgnoreCase);
            tracks.Add(new VideoTrack(id.Value, label, external));
        }

        return tracks;
    }

    private int? ReadSelectedVideoTrackId()
    {
        string? selected = GetPropertyString("vid");
        return int.TryParse(selected, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out int id) ? id : null;
    }

    private void ObserveTrackProperties()
    {
        Check(native!.ObserveProperty(handle, 1, "track-list/count", MpvFormatString), "observe track-list/count");
        Check(native.ObserveProperty(handle, 2, "sid", MpvFormatString), "observe sid");
        Check(native.ObserveProperty(handle, 3, "aid", MpvFormatString), "observe aid");
        Check(native.ObserveProperty(handle, 4, "vid", MpvFormatString), "observe vid");
    }

    private void RefreshTrackSnapshot()
    {
        IReadOnlyList<SubtitleTrack> subtitleTracks = ReadSubtitleTracks();
        int? selectedSubtitleTrackId = ReadSelectedSubtitleTrackId();
        IReadOnlyList<AudioTrack> audioTracks = ReadAudioTracks();
        int? selectedAudioTrackId = ReadSelectedAudioTrackId();
        IReadOnlyList<VideoTrack> videoTracks = ReadVideoTracks();
        int? selectedVideoTrackId = ReadSelectedVideoTrackId();
        TransformSnapshot(current => current with
        {
            SubtitleTracks = subtitleTracks,
            SelectedSubtitleTrackId = selectedSubtitleTrackId,
            AudioTracks = audioTracks,
            SelectedAudioTrackId = selectedAudioTrackId,
            VideoTracks = videoTracks,
            SelectedVideoTrackId = selectedVideoTrackId,
        });
    }

    private static int? TryParseInt(string? value) =>
        int.TryParse(value, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out int result) ? result : null;

    private string? GetPropertyString(string name)
    {
        lock (nativeCallGate)
        {
            lock (gate)
            {
                if (disposing || handle == nint.Zero || native is null)
                {
                    return null;
                }

                nint value = native.GetPropertyString(handle, name);
                if (value == nint.Zero)
                {
                    return null;
                }

                try { return Marshal.PtrToStringUTF8(value); }
                finally { native.Free(value); }
            }
        }
    }

    private void TransformSnapshot(Func<PlaybackSnapshot, PlaybackSnapshot> transform)
    {
        EventHandler<PlaybackSnapshot>? changed;
        PlaybackSnapshot value;
        lock (gate)
        {
            value = transform(snapshot);
            changed = UpdateSnapshot_NoLock(value);
        }

        changed?.Invoke(this, value);
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
            ObserveProperty = GetDelegate<ObservePropertyDelegate>(module, "mpv_observe_property");
            WaitEvent = GetDelegate<WaitEventDelegate>(module, "mpv_wait_event");
            GetPropertyString = GetDelegate<GetPropertyStringDelegate>(module, "mpv_get_property_string");
            Free = GetDelegate<FreeDelegate>(module, "mpv_free");
        }

        public ClientApiVersionDelegate ClientApiVersion { get; }
        public CreateDelegate Create { get; }
        public InitializeDelegate Initialize { get; }
        public TerminateDestroyDelegate TerminateDestroy { get; }
        public SetOptionStringDelegate SetOptionString { get; }
        public CommandDelegate Command { get; }
        public ObservePropertyDelegate ObserveProperty { get; }
        public WaitEventDelegate WaitEvent { get; }
        public GetPropertyStringDelegate GetPropertyString { get; }
        public FreeDelegate Free { get; }

        public static NativeApi From(nint module) => new(module);

        private static T GetDelegate<T>(nint module, string export) where T : Delegate =>
            Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(module, export));

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate uint ClientApiVersionDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate nint CreateDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int InitializeDelegate(nint handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void TerminateDestroyDelegate(nint handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int SetOptionStringDelegate(nint handle, [MarshalAs(UnmanagedType.LPUTF8Str)] string name, [MarshalAs(UnmanagedType.LPUTF8Str)] string value);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int CommandDelegate(nint handle, nint arguments);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int ObservePropertyDelegate(nint handle, ulong replyUserdata, [MarshalAs(UnmanagedType.LPUTF8Str)] string name, int format);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate nint WaitEventDelegate(nint handle, double timeout);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate nint GetPropertyStringDelegate(nint handle, [MarshalAs(UnmanagedType.LPUTF8Str)] string name);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void FreeDelegate(nint data);
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
