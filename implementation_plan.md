# HVP implementation plan

Status: Proposed

Last updated: 2026-08-21

Source of truth: [`brief.md`](brief.md)

## 1. Outcome

HVP will be a lightweight, Windows-only local video player whose primary path is:

> Open a large movie file, detect its media and display characteristics, select safe defaults, and play it correctly with minimal interaction.

V1 targets Windows 10 22H2 and Windows 11 on x64 hardware. The primary release artifact will be one self-contained `HVP-win-x64.exe`. It will not require a .NET installation, an installer, an account, or a network connection. Because .NET single-file applications must extract native libraries, the executable will unpack libmpv and native runtime files into the user's temporary directory on first launch.

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
| Distribution | Self-contained, single-file, untrimmed `win-x64` publish | One executable for users; trimming is avoided until WPF and reflection behavior are proven safe. |
| License | MIT for HVP; separately documented third-party licenses | The app remains permissively licensed while respecting LGPL and other dependency obligations. |

These are accepted defaults for planning. Any reversal should be recorded as an architecture decision record in `Docs/adr/`.

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
|   |-- native/                    # Reproducible libmpv build/verification
|   `-- release/                   # Packaging, checksums, SBOM, smoke tests
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
- Target `net10.0-windows10.0.19041.0`, x64 only.
- Establish reproducible acquisition/build of a pinned LGPL-only libmpv plus dependency manifest, checksums, license texts, source offer, and SBOM inputs.
- Add an external `HVP_LIBMPV_PATH` override so an LGPL-compatible replacement library can be tested without rebuilding HVP.
- Make CI restore, build, unit-test, and publish on a clean Windows runner.

Gate: a clean clone builds without undocumented machine-local files, and every binary dependency has a version, source, checksum, and license classification.

### Phase 1 - risk-reduction playback spike

Deliverables:

- WPF window containing a resize-safe `HwndHost` video surface.
- Minimal libmpv P/Invoke layer with safe handles, event loop, logging, and shutdown.
- `loadfile` passed as an argument array rather than a command string.
- D3D11 `gpu-next` output, `hwdec=auto-safe`, software fallback, and error reporting.
- Open, play/pause, seek, resize, fullscreen, and clean exit.
- Manual evidence for at least one large 4K HEVC 10-bit file on one GPU.

Gate: no UI deadlocks, no native callback exceptions, no leaked mpv handle, stable repeated open/close, and measurable hardware decoding when available.

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

### Phase 5 - hardening and V1 release

Deliverables:

- Self-contained single-file x64 publish with native extraction enabled.
- Optional transparent portable ZIP for troubleshooting and dependency replacement.
- Release checksums, SBOM, third-party notices, source/build references, and changelog.
- Clean-machine smoke test, Windows Defender scan, startup/seek/CPU/GPU measurements, and multi-GPU HDR test report.
- Accessibility pass, high-DPI/multi-monitor pass, crash-safe shutdown, and file-association design review.

Gate: every V1 acceptance criterion passes, release artifacts are reproducible, and licensing review is complete. Code signing is optional for early releases but required before presenting the binary as broadly trusted; unsigned builds will likely trigger SmartScreen reputation warnings.

## 7. Build and release target

The release project should eventually contain equivalent settings:

```xml
<PublishSingleFile>true</PublishSingleFile>
<SelfContained>true</SelfContained>
<RuntimeIdentifier>win-x64</RuntimeIdentifier>
<IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
<PublishTrimmed>false</PublishTrimmed>
<DebugType>embedded</DebugType>
```

Expected release command after Phase 0:

```powershell
dotnet publish .\src\Hvp.App\Hvp.App.csproj -c Release -r win-x64 --self-contained true
```

The release workflow must assert that the user-facing output directory contains exactly the documented artifact set and that `HVP-win-x64.exe` launches without a system .NET runtime.

## 8. Quality strategy

- Unit tests cover status classification, subtitle matching, default-track selection, resume policy, persistence migration, and state transitions.
- Contract tests run the playback adapter against a fake native API so edge cases are deterministic.
- Integration tests use tiny generated SDR/HDR/audio/subtitle fixtures and a real pinned libmpv build.
- CI verifies build, tests, formatting/analyzers, dependency lock state, license inventory, publish output, and artifact hashes.
- Hardware/manual tests cover Windows 10/11, Intel/AMD/NVIDIA, SDR/HDR displays, multi-monitor movement, passthrough receivers, and representative large files.
- Performance baselines record startup time, seek latency, dropped frames, CPU, GPU decode/video utilization, and working set.

GPU/HDR correctness cannot be proven by GitHub-hosted CI alone. A release candidate is not done until the manual hardware matrix is attached to the release issue.

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
2. Minimum OS (`Windows 10 22H2`; Windows 11 recommended for HDR).
3. V1 architecture (`x64 only`).
4. Passthrough default (`off`, with an explicit compatible-device setting).
5. Resume thresholds (`resume after 60 seconds`; mark complete at 95%).
6. Preferred audio/subtitle languages (system language first, then original/default metadata; expose settings).
7. Whether early releases remain unsigned (yes for development; pursue Authenticode when distribution grows).
8. Whether to add file associations in V1 (defer unless a lightweight per-user registration design is approved).

None blocks the playback spike; they must be closed before the related phase is merged.

## 11. V1 definition of done

- A new user downloads one x64 executable and opens a supported local file without installing dependencies.
- A large 4K HEVC 10-bit MKV uses hardware decoding on supported Intel, AMD, and NVIDIA systems with safe fallback.
- All four SDR/HDR source/output combinations have recorded, visually correct results on the release matrix.
- Embedded and matching external subtitles plus all embedded audio tracks are selectable.
- Resume and language defaults work, remain local, and recover from corrupt settings.
- The app is keyboard-operable, handles errors without hanging, and exits without orphan processes or locked files.
- CI is green, release evidence is attached, dependency licenses are satisfied, and the source remains MIT licensed.
