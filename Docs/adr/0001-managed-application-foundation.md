# ADR 0001: Managed application foundation

- Status: Accepted
- Date: 2026-08-21
- Owners: @Xil146
- Related issue/PR: [#5](https://github.com/Xil146/hvp/issues/5)
- Supersedes: None

## Context

HVP needs a small Windows application shell that can host libmpv without
allowing UI, platform, persistence, or native-engine concerns to collapse into
one assembly. The V1 distribution must run offline without a preinstalled .NET
runtime and must preserve an auditable, replaceable native dependency boundary.

The target framework's Windows platform version is an API-availability floor;
it is not, by itself, an operating-system support promise. .NET 10 support on
Windows follows Microsoft's current .NET and Windows lifecycle policy. Ordinary
Windows 10 Home and Pro 22H2 reached end of support before this decision, so HVP
must not describe that combination as a fully supported baseline merely because
the application can target Windows APIs introduced in build 19041.

## Decision

1. Use C# on .NET 10 LTS, with the SDK pinned by `global.json`.
   `Hvp.Core`, `Hvp.Playback`, and `Hvp.Persistence` target platform-neutral
   `net10.0`. `Hvp.App` and `Hvp.Platform.Windows` target
   `net10.0-windows10.0.19041.0`; x64 is the deployment architecture. Windows 11
   is the supported desktop baseline. Windows 10 is supported only on
   editions/configurations that remain supported by Microsoft and .NET; other
   Windows 10 22H2 use is best-effort.
2. Use WPF for the application shell. Host libmpv's child window through a
   dedicated `HwndHost` owned by `Hvp.Platform.Windows`. Because of WPF airspace
   behavior, interactive WPF controls remain outside the native video region.
3. Use five production projects with dependencies pointing toward `Hvp.Core`:
   `Hvp.App`, `Hvp.Core`, `Hvp.Playback`, `Hvp.Platform.Windows`, and
   `Hvp.Persistence`. `Hvp.Core` has no WPF, Windows API, persistence-format, or
   libmpv dependency. UI code performs no native calls. Native mpv declarations,
   ownership, event translation, and shutdown belong to `Hvp.Playback`.
4. Publish V1 for `win-x64` as a self-contained, untrimmed, single-file
   application with native-library self-extraction enabled. The default release
   remains one downloaded executable, while documentation states that native
   files are extracted at runtime. A portable ZIP may be offered separately.
5. This ADR does not approve a libmpv binary, source revision, ABI, or build.
   Those require a separate native-foundation ADR, issue, licensing/provenance
   review, and replaceability evidence before integration.

## Alternatives considered

- **.NET 8:** currently mature, but would shorten the planned support horizon and
  diverge from the approved project direction without resolving a product risk.
- **WinUI 3:** offers a newer UI stack but adds deployment and native-window
  integration complexity without improving the minimal local-player outcome.
- **Draw video into the WPF visual tree:** would avoid child-window airspace but
  requires a more complex render API and lifetime path than the initial
  `wid`-based libmpv integration.
- **One application project:** reduces initial files but obscures dependency
  direction and makes native lifetime, policy, and persistence harder to test.
- **Framework-dependent or multi-file distribution:** simplifies native loading
  or publish size, but violates the primary one-download/no-runtime V1 outcome.
- **Trimmed publish:** may reduce size, but is deferred until WPF and native
  interop behavior have dedicated compatibility evidence.

## Consequences

- The repository carries more projects than a single-shell prototype, but each
  high-risk boundary can be tested independently.
- `HwndHost` constrains layout and requires explicit HWND lifetime, resize, DPI,
  focus, and shutdown validation in Phase 1.
- The executable may extract native libraries under the .NET extraction cache;
  unwritable/cleaned temporary storage must produce an actionable failure.
- x64 is the only V1 architecture. ARM64 and MSIX remain out of scope.
- The Windows API target can permit best-effort execution on unsupported Windows
  releases; release documentation and testing must not overstate support.
- Native licensing, provenance, ABI compatibility, and hardware correctness
  remain gates rather than implications of a successful managed publish.

## Validation

- Locked restore, Release build, unit tests, and self-contained `win-x64`
  single-file publish pass on a clean Windows CI runner.
- Assembly references enforce the documented dependency direction and
  `Hvp.Core` remains free of WPF and libmpv references.
- The Phase 1 spike verifies resize, focus, repeated creation/disposal, bounded
  shutdown, hardware decode observation, and software fallback on the exact
  approved native bundle.
- Release testing verifies the exact artifact on supported clean Windows 11 and
  any claimed supported Windows 10 configuration without a system .NET runtime.

## Follow-up

- Complete the separately reviewed native libmpv foundation before integrating
  libmpv or starting the Phase 1 playback spike.
- Record Windows support test evidence and lifecycle wording in release notes.
