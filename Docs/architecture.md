# Architecture design

Status: Accepted by [`ADR 0001`](adr/0001-managed-application-foundation.md)

## Context

HVP is a thin Windows application around libmpv, not a new decoder/rendering stack. Its value is safe orchestration: Windows hosting, automatic policies, a minimal UI, local persistence, diagnostics, packaging, and verification.

## Runtime shape

```text
WPF views and input
        |
        v
View models / application coordinator
        |
        +---------------------> settings and history
        |
        v
IPlaybackEngine + core policies <----- Windows display/power facts
        |
        v
libmpv adapter and event pump
        |
        +---- libmpv / FFmpeg / libplacebo
        |
        `---- child HWND in the WPF HwndHost
```

Dependency direction points toward `Hvp.Core`. `Hvp.Core` does not reference WPF, Windows APIs, persistence formats, or native mpv types.

## Projects

### `Hvp.App`

- Application/window lifetime and composition root.
- Views, view models, commands, dialogs, drag/drop, keyboard routing, and accessibility.
- Maps normalized engine state to presentation state.
- Contains no P/Invoke and no JSON/file persistence implementation.

### `Hvp.Core`

- `MediaDescriptor`, `VideoDescriptor`, `TrackDescriptor`, `PlaybackSnapshot`, `DisplayDescriptor`, and error models.
- Dynamic-range classification, language ranking, external-subtitle matching, resume/completion thresholds, and state transition policies.
- Interfaces for playback, persistence, display facts, clocks, and diagnostics.

### `Hvp.Playback`

- Minimal libmpv native declarations and safe ownership wrappers.
- Engine initialization/options, commands, observed properties, event normalization, logging, and shutdown.
- Converts native track/video properties into core models.
- Does not decide UI presentation or write application settings.

### `Hvp.Platform.Windows`

- WPF `HwndHost` implementation and HWND lifecycle.
- Display/HDR facts, DPI/monitor changes, power/screensaver inhibition, and Windows-specific file dialogs.
- No playback policy beyond reporting platform capabilities.

### `Hvp.Persistence`

- Versioned settings and history repositories.
- Atomic replace, corruption quarantine, migrations, and bounded cleanup.
- No WPF or libmpv references.

## Application lifetime

1. Create the composition root and load settings/history without touching libmpv.
2. Create the main window and video host HWND.
3. Resolve the approved libmpv binary, verify ABI/version, set pre-initialize options including `wid`, then initialize.
4. Start one cancellable event pump.
5. On open, validate a local path, issue argument-array `loadfile`, and transition to `Opening`.
6. Normalize observed properties/events and publish immutable snapshots.
7. Persist progress periodically and on pause/end/close using non-blocking writes.
8. On shutdown, stop commands, cancel the event pump, unregister callbacks, terminate mpv, release HWND/native handles, and finish pending atomic persistence.

Shutdown is idempotent and bounded. The application must not wait forever for a native callback or background write.

## Concurrency model

- WPF dispatcher: views and bound state only.
- Playback event pump: waits for and translates mpv events; it never touches WPF objects.
- Command serialization: one engine-owned queue/gate maintains command order during load/shutdown.
- Persistence: asynchronous snapshots with a single writer; last-write coalescing is allowed.
- Native callbacks do minimal work, catch all managed exceptions, and signal the event pump.

## Error model

Errors are normalized into `UserActionable`, `UnsupportedMedia`, `Environment`, `NativeEngine`, and `Internal` categories. Each carries a stable code, safe user message, optional technical detail, and recoverability flag. File paths and raw metadata are redacted from logs by default.

A failed open returns to a usable idle/error shell. A failed hardware decode retries the supported software path. Native initialization failure prevents playback but leaves diagnostics accessible.

## Dependency policy

- Pin the .NET SDK and NuGet graph; use lock files and central package management.
- Prefer platform/BCL code for small utilities over adding a dependency.
- Native binaries are never committed without provenance, checksum, ABI, license, build flags, and update ownership.
- All dependencies must support offline runtime operation and self-contained publish.
