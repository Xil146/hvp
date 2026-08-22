# HVP implementation plan

Status: Proposed

Last updated: 2026-08-22

Source of truth: [`brief.md`](brief.md)

## 1. Outcome

HVP will be a lightweight, Windows-only local video player whose primary path is:

> Open a large movie file, detect its media and display characteristics, select safe defaults, and play it correctly with minimal interaction.

V1 targets Windows 11 on x64 hardware. Windows 10 is supported only on editions/configurations that remain supported by Microsoft and .NET 10; ordinary Windows 10 22H2 use is best-effort. The `net10.0-windows10.0.19041.0` target expresses the Windows API floor rather than a lifecycle support guarantee. The first release artifact is one offline self-contained Windows x64 folder containing the .NET runtime, HVP, libmpv, codecs, supporting DLLs, notices, and licenses. It requires no separately installed runtime, codec pack, account, or network connection. An installer is deferred until playback is proven.

## 2. Scope

### V1 includes

- Local `.mkv` playback plus common containers supported by the bundled libmpv/FFmpeg build.
- H.264/AVC and H.265/HEVC, including 8-bit and 10-bit content.
- D3D11 hardware decoding through supported NVIDIA, AMD, and Intel drivers, with software fallback.
- SDR, HDR10, HLG, HDR10+, and detectable Dolby Vision classification.
- Native HDR output when the Windows/display chain supports it and high-quality tone mapping otherwise.
- Embedded and matching external subtitles.
- Embedded audio tracks and fast track switching.
- Optional audio passthrough for compatible devices and formats.
- Playback position history and language-aware track defaults.
- Minimal controls, keyboard operation, and a compact stream-status indicator.

### Explicitly out of scope for V1

- Media library, playlists, metadata scraping, thumbnails, streaming, casting, accounts, cloud sync, media servers, plug-ins, and mobile/non-Windows platforms.
- Blu-ray menus, DRM, optical-disc playback, frame interpolation, video editing, and capture.
- Automatic Windows HDR toggling. HVP adapts to the current display mode and explains when Windows HDR must be enabled.
- Guaranteed Dolby Vision passthrough. V1 reports detectable profiles and uses libmpv's supported rendering path.
- Microsoft Store/MSIX distribution and ARM64. These can be evaluated after x64 V1 is stable.

## 3. Architecture decisions

| Area | Decision | Reason |
| --- | --- | --- |
| Runtime | .NET 10 LTS, C# | Supported through November 2028 and suitable for a self-contained desktop release. |
| UI | WPF | Mature Windows desktop stack with straightforward Win32 child-window hosting and fewer unpackaged deployment constraints than WinUI 3. |
| Video host | `HwndHost` child HWND | Matches libmpv's Windows `wid` integration. Controls must not overlap the video because of WPF airspace rules. |
| Playback | A pinned, LGPL-only libmpv build using `vo=gpu-next` | Delegates demuxing, decoding, subtitles, rendering, color management, and tone mapping to a proven engine. |
| GPU path | D3D11 with `hwdec=auto-safe` and software fallback | Broad Windows GPU support without vendor-specific application code. |
| Interop | Small internal P/Invoke layer | Keeps native ownership, versioning, error handling, and licensing visible; avoids an additional wrapper dependency. |
| App pattern | MVVM at the shell, service interfaces at boundaries | Keeps WPF state testable without building a framework-heavy application. |
| Persistence | Versioned JSON in `%LOCALAPPDATA%\HVP` | Local, inspectable, migration-friendly, and network-free. |
| Distribution | One offline self-contained, multi-file, untrimmed `win-x64` folder | Gets a real portable payload and clean-machine proof before installer work. |
| License | MIT for HVP; separately documented third-party licenses | The app remains permissively licensed while respecting LGPL and other dependency obligations. |

The managed application decisions are accepted by [`ADR 0001`](Docs/adr/0001-managed-application-foundation.md). Its packaging item is superseded by [`ADR 0003`](Docs/adr/0003-offline-installer-and-installed-payload.md). The native policy is accepted by [`ADR 0002`](Docs/adr/0002-native-libmpv-foundation.md), while approval of an actual bundle remains a separate evidence-gated work item.

## 4. Proposed repository structure

```text
HVP/
|-- .codex/
|   |-- agents/                    # Project-scoped subagent roles
|   `-- config.toml
|-- .github/
|   |-- ISSUE_TEMPLATE/
|   |-- workflows/                 # CI and tagged release builds
|   |-- CODEOWNERS
|   |-- PULL_REQUEST_TEMPLATE.md
|   `-- dependabot.yml
|-- Docs/
|   |-- adr/                       # Architecture decision records
|   |-- master_design.md           # Design index and status
|   |-- architecture.md
|   |-- ui_and_input.md
|   |-- playback_engine.md
|   |-- hdr_color_pipeline.md
|   |-- media_tracks.md
|   |-- persistence.md
|   |-- packaging_and_distribution.md
|   |-- testing_strategy.md
|   |-- development_workflow.md
|   `-- github_setup.md
|-- eng/
|   |-- native/                    # Pinned third-party libmpv bundle metadata
|   `-- release/                   # Payload manifest and smoke tests
|-- src/
|   |-- Hvp.App/                   # WPF shell, views, view models, composition
|   |-- Hvp.Core/                  # Domain models and platform-neutral policies
|   |-- Hvp.Playback/              # Playback abstraction and libmpv adapter
|   |-- Hvp.Platform.Windows/      # HWND, display, power, file-dialog services
|   `-- Hvp.Persistence/           # Settings and playback history
|-- tests/
|   |-- Hvp.Core.Tests/
|   |-- Hvp.Playback.Tests/
|   |-- Hvp.Persistence.Tests/
|   |-- Hvp.IntegrationTests/
|   `-- media-fixtures/            # Tiny generated fixtures; no copyrighted media
|-- AGENTS.md
|-- brief.md
|-- Directory.Build.props
|-- Directory.Packages.props
|-- global.json
|-- Hvp.slnx
|-- LICENSE
|-- THIRD_PARTY_NOTICES.md
`-- README.md
```

Only the governance and design files are created in this planning pass. Code folders should be created in Phase 0 so the initial structure reflects the actual solution generated by the installed .NET SDK.

## 5. Component boundaries

- `Hvp.App`: owns window lifetime, commands, view models, keyboard input, dialogs, accessibility, and user-visible errors.
- `Hvp.Core`: owns immutable media/status models, language and resume policies, and interfaces. It must not reference WPF or libmpv.
- `Hvp.Playback`: owns libmpv initialization, commands, observed properties, event translation, track loading, and deterministic disposal.
- `Hvp.Platform.Windows`: owns `HwndHost`, HWND helpers, display/HDR capability queries, screensaver/power integration, and OS version behavior.
- `Hvp.Persistence`: owns versioned settings/history files, migrations, atomic writes, and corruption recovery.

UI code never calls P/Invoke directly. Native callbacks never mutate WPF-bound state directly. Every libmpv resource has one explicit owner and deterministic cleanup.

## 6. Delivery phases

### Phase 0 - repository and dependency foundation

Deliverables:

- Create `Hvp.slnx`, projects, shared build properties, pinned packages, nullable reference types, analyzers, and deterministic builds.
- Target platform-neutral libraries to `net10.0`, Windows-facing projects to
  `net10.0-windows10.0.19041.0`, and the application publish to x64 only.
- Select one maintained redistributable Windows x64 libmpv bundle; pin its exact version, archive/DLL SHA-256 values, licenses/notices, and matching publisher source/build-material reference.
- Copy the exact selected DLL closure into HVP's private application directory. Do not build libmpv or provide `HVP_LIBMPV_PATH` in V1.
- Make CI restore, build, unit-test, and publish on a clean Windows runner.
- Stage the complete self-contained application and approved DLL closure as one
  canonical installed-directory tree with a machine-readable file/hash manifest.
- Optionally produce a portable ZIP from that exact staged tree; installer
  technology is not on the Phase 0 critical path.

Gate: a clean clone builds without undocumented machine-local files; the selected bundle has version, hashes, licenses, and source/build-material reference; and the complete staged folder launches offline on one clean Windows 11 machine without a system .NET runtime or codec packs.

### Phase 1 - risk-reduction playback spike

Deliverables:

- WPF window containing a resize-safe `HwndHost` video surface.
- Minimal libmpv P/Invoke layer with safe handles, event loop, logging, and shutdown.
- `loadfile` passed as an argument array rather than a command string.
- D3D11 `gpu-next` output, `hwdec=auto-safe`, software fallback, and error reporting.
- Open, play/pause, seek, volume, stop, resize, fullscreen, and clean exit.
- Immediately test one normal user-owned MP4; do not wait for installer work or exhaustive automation.

Gate: normal MP4 playback works; no UI deadlocks, native callback exceptions, leaked mpv handle, or file lock after stop/dispose; repeated startup/shutdown is stable.

### Phase 2 - playback core and minimal shell

Deliverables:

- `IPlaybackEngine` contract and normalized event/state models.
- State machine: `Idle -> Opening -> Ready/Playing/Paused -> Ended/Error -> Idle`.
- Minimal control bar, seek state, volume/mute, fullscreen, open-file dialog, drag/drop, and keyboard shortcuts.
- Loading, unsupported-file, and decoder-failure states that preserve the current window.
- Power/screensaver inhibition only during active video playback.

Gate: core control paths have unit/integration coverage and remain responsive during open, seek, track switch, and shutdown.

### Phase 3 - HDR and color pipeline

Deliverables:

- Normalize libmpv stream properties into `Sdr`, `Hdr10`, `Hlg`, `Hdr10Plus`, `DolbyVision`, or `UnknownHdr`.
- Query the effective Windows output/display state without changing system settings.
- Default `target-colorspace-hint=auto`; log negotiated input/output color spaces.
- Validate native HDR, HDR-to-SDR tone mapping, SDR-on-HDR preservation, and SDR-on-SDR behavior.
- Status indicator showing dynamic range, resolution, codec, and bit depth.
- Diagnostics export that contains versions/options/display facts but no media path unless the user opts in.

Gate: the hardware test matrix records expected output for all four HDR/SDR source/output combinations. Unknown or unsupported paths degrade visibly and safely rather than silently mislabeling output.

### Phase 4 - subtitles, audio, and persistence

Deliverables:

- Unified embedded/external track models and selectors.
- Deterministic external subtitle matching for `.srt`, `.ass`, `.ssa`, `.vtt`, and `.sub`/`.idx` pairs.
- Language preference and forced/default-track policy with user override.
- Audio track switching and opt-in passthrough profile with an automatic fallback path.
- Versioned settings and playback history with atomic writes.
- Resume only after a minimum watched threshold; consider content completed near the end.

Gate: track selection policy is unit tested, external matching never scans outside the media directory, and malformed/corrupt settings recover without blocking playback.

### Phase 5 - practical V1 package

Deliverables:

- Self-contained Windows x64 folder containing the expected managed and pinned native DLLs.
- Bundle version/hashes, third-party notices, license texts, matching source/build-material reference, and changelog.
- Offline clean-Windows-11 launch and playback of two or three normal local files.
- Focused checks: DLL/API load, loaded event, stop/dispose unlock, missing-DLL error, repeated startup/shutdown, and packaged payload closure.

Gate: issue #6's simplified acceptance criteria pass and its bundle version/hashes and clean-machine result are recorded. Installer, SBOM, candidate promotion, reproducible builds, replacement DLLs, HDR/passthrough, exotic codecs, and extensive performance work remain follow-up scope.

## 7. Build and release target

The release project should eventually contain equivalent settings:

```xml
<SelfContained>true</SelfContained>
<RuntimeIdentifier>win-x64</RuntimeIdentifier>
<PublishTrimmed>false</PublishTrimmed>
<DebugType>embedded</DebugType>
```

Expected release command after Phase 0:

```powershell
dotnet publish .\src\Hvp.App\Hvp.App.csproj -c Release -r win-x64 --self-contained true
```

The publish workflow copies the selected native closure into the self-contained folder and validates the expected relative paths and SHA-256 values. The folder must launch offline without a system .NET runtime or codec packs.

## 8. Quality strategy

- Unit tests cover status classification, subtitle matching, default-track selection, resume policy, persistence migration, and state transitions.
- Contract tests run the playback adapter against a fake native API so edge cases are deterministic.
- Integration tests use a real pinned libmpv bundle for native load, a file-loaded event, file unlock after stop/dispose, missing-DLL error, and repeated startup/shutdown.
- CI verifies build, focused tests, notices/licenses, and the staged payload's expected DLLs and hashes.
- Manual V1 testing uses H.264/AAC MP4, a multi-audio/subtitle MKV, a large seekable file, an unsupported/damaged file, and a filename containing spaces and non-ASCII characters.

HDR, passthrough, exotic codecs, and extensive performance validation are deferred; they must not be claimed from these checks.

## 9. Security and privacy

- Treat media files, subtitles, metadata, and native decoder output as untrusted input.
- Pin and regularly update libmpv/FFmpeg; monitor security advisories.
- No network code, telemetry, update checker, or path upload in V1.
- Store history locally with least detail; never log full paths by default.
- Avoid shell invocation and command-string construction for media paths.
- Validate integer conversions, callback lifetimes, cancellation, and native event payloads at the interop boundary.

## 10. Open decisions before implementation

Recommended defaults are shown in parentheses:

1. Public product name and executable name (`HVP`).
2. Minimum OS (resolved by ADR 0001: Windows 11 supported baseline; Windows 10 only where Microsoft and .NET 10 support remain, otherwise best-effort).
3. V1 architecture (`x64 only`).
4. Passthrough default (`off`, with an explicit compatible-device setting).
5. Resume thresholds (`resume after 60 seconds`; mark complete at 95%).
6. Preferred audio/subtitle languages (system language first, then original/default metadata; expose settings).
7. Whether early releases remain unsigned (yes for development; pursue Authenticode when distribution grows).
8. Whether to add file associations in V1 (defer unless a lightweight per-user registration design is approved).

None blocks the playback spike; they must be closed before the related phase is merged.

## 11. V1 definition of done

- A user launches one offline self-contained Windows x64 folder and plays supported local files without sourcing dependencies.
- The pinned libmpv bundle loads from HVP's private directory, with recorded version, hashes, license texts/notices, and source/build-material reference.
- Open, play/pause, seek, volume, stop, and shutdown work for real local files; stop/dispose leaves no lock.
- The focused automated native/payload checks pass and one clean Windows 11 machine plays two or three files offline.
