# Packaging and distribution design

Status: Accepted for the managed artifact by [`ADR 0001`](adr/0001-managed-application-foundation.md); native bundle pending separate approval

## User-facing artifact

The primary V1 download is `HVP-win-x64.exe`: a self-contained .NET single-file publish that runs without a preinstalled .NET runtime. Managed assemblies and native dependencies are bundled into it.

Native libraries are extracted by the .NET host under `%TEMP%\.net` before loading; this is one downloaded/run file, not a zero-extraction binary. The README/release notes must state this, and startup must handle an unwritable or cleaned temp directory with an actionable error.

An optional `HVP-win-x64-portable.zip` may place the executable and native DLLs side-by-side for contributors, diagnostics, and replacement testing. It is not the default user path.

## Publish configuration

- `TargetFramework`: `net10.0-windows10.0.19041.0`. This is the Windows API
  availability floor, not an operating-system lifecycle promise.
- Supported desktop baseline: Windows 11. Windows 10 is supported only where
  the Windows edition/configuration and .NET 10 remain supported by Microsoft;
  other Windows 10 22H2 use is best-effort and must not be advertised as fully
  supported.
- `RuntimeIdentifier`: `win-x64`.
- Self-contained and single-file enabled.
- `IncludeNativeLibrariesForSelfExtract=true`.
- Trimming disabled for V1; revisit only with a dedicated WPF/native compatibility matrix.
- PDBs embedded or published as a separate symbols artifact, never loose beside the user EXE by accident.
- Deterministic/continuous-integration build settings and Source Link enabled.

## Native dependency policy

The MIT license applies to HVP first-party source, not bundled dependencies. Do not take an arbitrary community mpv Windows build and ship it.

The native policy is accepted by [`ADR 0002`](adr/0002-native-libmpv-foundation.md),
but no binary is approved until its separate evidence gate passes. The approved
native bundle must:

- build mpv in its documented LGPL mode and exclude GPL-only mpv source; the
  `-Dgpl=false` switch is necessary but not proof without auditing the compiled
  source set and linked dependency graph;
- use an FFmpeg/dependency configuration whose licenses are compatible with the selected distribution model;
- preserve dynamic libmpv loading and provide `HVP_LIBMPV_PATH` as a documented
  compatible-library override; require an absolute path and restricted DLL
  search, and fail without silent fallback when a configured override is invalid;
- record source commit/tag, patches, full configure/build flags, toolchain/container version, dependency versions, licenses, and SHA-256 checksums;
- make the corresponding source/build scripts available for the released binary;
- include required copyright/license notices and an SBOM;
- receive legal review before the first public binary release. This document is engineering guidance, not legal advice.

The app exposes About/Licenses and a command-line license display so notices remain accessible even when the release is a single file.

## Release artifacts

- `HVP-win-x64.exe`.
- `HVP-win-x64.exe.sha256`.
- `HVP-<version>-sbom.spdx.json`.
- optional symbols archive and portable ZIP.
- GitHub release notes with supported OS/architecture, known HDR limitations, native versions, license/source links, hardware matrix, and unsigned/signed status.

## Release pipeline

1. Build from a clean tagged commit with pinned SDK and locked dependencies.
2. Build/obtain the approved native bundle and verify checksums/provenance.
3. Restore, build, test, publish, and run structural single-file checks.
4. Scan dependencies/artifacts and generate the SBOM/notices.
5. Smoke-test the exact EXE on a clean Windows machine without .NET installed.
6. Run and attach the hardware/HDR matrix.
7. Sign when configured, hash after signing, and publish through a protected GitHub environment.

## Updates and signing

V1 has no self-updater or network check. Users download releases from GitHub. Early artifacts may be unsigned and will be clearly labeled; Windows SmartScreen reputation warnings are expected. Authenticode signing is a maintainer decision that requires certificate procurement and protected CI secrets.

## Acceptance criteria

- The primary download is one EXE and launches offline on a supported clean x64 machine.
- Extraction behavior, cache location, cleanup expectations, and troubleshooting are documented.
- Native DLL replacement works through the documented override.
- Every binary is traceable to source, flags, checksum, and license evidence.
- Release assets, checksums, SBOM, notices, and test evidence agree on one version.
