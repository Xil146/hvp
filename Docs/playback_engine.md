# Playback engine design

Status: Proposed

## Responsibility

`Hvp.Playback` exposes a stable managed playback contract and contains all libmpv-specific behavior. The rest of HVP must not depend on native structs, numeric property formats, option spelling, or ABI details.

## Integration strategy

- Host libmpv's Win32 output in a child HWND supplied through `wid`.
- Set initialization-only options before `mpv_initialize`.
- Prefer `vo=gpu-next`, D3D11 output/context, `hwdec=auto-safe`, and automatic colorspace signaling.
- Use structured command arrays for `loadfile` and other commands; never parse or escape user paths into a command string.
- Observe only properties required to build the normalized playback snapshot, stream descriptor, and audio/subtitle-track lists.
- Treat unsupported/unknown properties as capability differences, not fatal errors.

The first spike must validate exact option compatibility against the pinned mpv version; planned defaults are not frozen until that evidence exists.

## Managed contract

The interface should cover:

- initialize against a video-host handle;
- open/stop and current item identity;
- play/pause, absolute/relative seek, volume/mute, fullscreen intent;
- enumerate/select video, audio, and subtitle tracks;
- snapshot/event stream for state, time, duration, cache, video/audio descriptors, tracks, and errors;
- diagnostic version/options/log export;
- asynchronous, idempotent disposal.

Keep commands semantic. UI code asks to select an audio or subtitle track rather than setting raw mpv properties. Track IDs, title/language values, and stream facts are copied into immutable core models before UI dispatch.

## Native ownership

- Wrap the main `mpv_handle*` in one safe owner; no duplicated free paths.
- Keep callback delegates rooted for exactly the native registration lifetime.
- Copy native strings/arrays before the next native call can invalidate them.
- Check every return code and translate it with `mpv_error_string` for technical diagnostics.
- Bound shutdown and prevent commands after disposal begins.
- Centralize ABI-sensitive declarations and test structure sizes/representative conversions on x64.

## Events and state

One long-lived event pump waits with cancellation-friendly intervals, converts mpv events, and emits immutable managed snapshots. A wakeup callback may signal the pump but performs no WPF work and never throws across the native boundary.

Important events include file loaded, start/end file, property change, video reconfiguration, seek/playback restart, log message, and shutdown. `file-loaded` captures the normalized stream descriptor and track lists. Observe only the track count and active video/audio/subtitle IDs so runtime track-list changes and explicit selection commands refresh the normalized selector state. Duplicate/high-frequency time updates may be coalesced before reaching the UI.

## Open and fallback flow

1. Reject a missing, non-file, or inaccessible path with a safe error.
2. Issue `loadfile` as a structured command.
3. On `file-loaded`, capture duration, formats, video params, display facts, and track list.
4. Apply deterministic track policy and any remembered position.
5. Confirm selected decoder/hardware context from observed properties/logs.
6. If hardware decoding fails, retry with the supported software path and surface a non-blocking diagnostic.
7. If playback fails, stop the item, retain the shell, and release per-file state.

## Diagnostics

Diagnostics should include HVP/libmpv/FFmpeg/libplacebo versions, selected VO/GPU API, decoder and hardware context, source/output colorspace facts, tracks, relevant options, dropped frames, and sanitized errors. Full paths are omitted unless the user explicitly chooses to include them.

## Acceptance criteria

- Repeatedly open/close different files without leaks, deadlocks, stale state, or file locks after stop.
- Seek and track changes remain responsive during large 4K playback.
- Hardware decode is observable and software fallback is functional.
- Native failure never escapes as an unhandled exception or leaves the application unable to open another file.
