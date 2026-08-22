# Packaging and distribution design

Status: Accepted by [`ADR 0003`](adr/0003-offline-installer-and-installed-payload.md); native bundle pending its evidence gate

## User-facing artifact

The primary V1 download is one offline Windows x64 installer. It installs one HVP application and a private multi-file directory containing the self-contained .NET runtime, HVP assemblies, libmpv, FFmpeg, codecs, supporting DLLs, notices, and other required runtime files.

The installer does not download prerequisites. A user does not source .NET, codec packs, libmpv, FFmpeg, or supporting libraries. HVP does not use .NET single-file publication or runtime native extraction.

Phase 0 first produces a canonical staged directory. An optional `HVP-win-x64-portable.zip` may package that exact tree for contributors, diagnostics, and replacement testing. Installer technology is selected after the Phase 1 playback spike and wraps the same proven payload rather than rebuilding it.

## Publish configuration

- `TargetFramework`: `net10.0-windows10.0.19041.0`. This is the Windows API
  availability floor, not an operating-system lifecycle promise.
- Supported desktop baseline: Windows 11. Windows 10 is supported only where
  the Windows edition/configuration and .NET 10 remain supported by Microsoft;
  other Windows 10 22H2 use is best-effort and must not be advertised as fully
  supported.
- `RuntimeIdentifier`: `win-x64`.
- Self-contained multi-file publish enabled; single-file publishing disabled.
- Native self-extraction disabled; native DLLs are explicit members of the staged payload.
- Trimming disabled for V1; revisit only with a dedicated WPF/native compatibility matrix.
- PDBs embedded or published as a separate symbols artifact, never loose beside the user EXE by accident.
- Deterministic/continuous-integration build settings and Source Link enabled.

### Managed scaffold payload contract

`eng/release/managed-payload-contract.json` is the reviewed, version-controlled
inventory for the current managed-only publish. CI validates the publish against
that independent contract before generating the per-file SHA-256 payload
manifest. Missing, unexpected, case-colliding, path-escaping, or reparse-point
entries fail the gate; the generated manifest then protects the exact candidate
through later staging and download steps.

The contract is intentionally exact and tied to the SDK/runtime pin. An approved
SDK/runtime change must update it explicitly. Issue #6 will extend the staged
payload with its separately approved native manifest and DLL closure rather than
silently allowing new native files through the managed contract.

### Native candidate overlay contract

`eng/release/native-payload-contract.json` reserves a separately validated
`native/` overlay for an approved native candidate. It is deliberately not an
allow-list exception to the managed contract: a candidate must bind the exact
source lock, dependency graph, output contract, PE records, notices, license
texts, corresponding-source inputs, and SPDX 2.3 document. The release gate
fails if any native DLL is missing from that overlay or differs from the
candidate hash. Until those records and independent legal review exist, there
is no approved native payload and this is not a release-ready claim.

`Test-ReleasePayloadContract.ps1` is the final composition gate: it validates
the independent managed manifest and the native overlay contract together.
Release automation must invoke it with `-RequireApprovedNativeCandidate`; the
ordinary managed scaffold CI intentionally does not pretend a native candidate
exists.

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

The app exposes About/Licenses and a command-line license display, and the installed payload includes the applicable notice and license files.

## Release artifacts

- one offline Windows x64 installer and its SHA-256 digest;
- the canonical multi-file application payload and its relative-path/SHA-256 manifest;
- `HVP-<version>-sbom.spdx.json`.
- optional symbols archive and portable ZIP produced from the canonical payload.
- GitHub release notes with supported OS/architecture, known HDR limitations, native versions, license/source links, hardware matrix, and unsigned/signed status.

## Release pipeline

The release workflow validates the managed publish before native staging. It
then downloads `HVP-native-approved-candidate` from an explicitly reviewed
workflow run ID (or a protected run-ID variable for tag builds), validates the
composed managed/native contracts, and only then creates the final full-tree
manifest and checksums. The managed-only manifest remains separate evidence and
is never used to hash a native-bearing tree.

1. Build from a clean tagged commit with pinned SDK and locked dependencies.
2. Build/obtain the approved native bundle and verify checksums/provenance.
3. Restore, build, test, publish, stage, scan dependencies/artifacts, and generate the SBOM/notices.
4. Sign application binaries when configured, then generate and validate the final application-payload manifest.
5. Before Phase 1, smoke-test the exact staged payload offline on a clean Windows machine without .NET or codec packs installed.
6. Run and attach the hardware/HDR matrix.
7. After the playback spike is proven, build the installer from the exact staged application payload, separately inventory installer-owned files, and test offline install, launch, upgrade, uninstall, and reinstall.
8. Sign the installer/ZIP containers when applicable, hash their final forms, and publish through a protected GitHub environment.

## Updates and signing

V1 has no self-updater or network check. Users download releases from GitHub. Early artifacts may be unsigned and will be clearly labeled; Windows SmartScreen reputation warnings are expected. Authenticode signing is a maintainer decision that requires certificate procurement and protected CI secrets.

## Acceptance criteria

- The primary download is one offline installer and the installed application launches on a supported clean x64 machine without network access, a system .NET runtime, or codec packs.
- The installed directory contains the complete documented DLL closure; no runtime native extraction is required.
- Native DLL replacement works through the documented override.
- Every binary is traceable to source, flags, checksum, and license evidence.
- The installer and optional portable ZIP reproduce the canonical application payload without modifying its files; installer-owned bookkeeping is separately inventoried.
- Release assets, payload manifest, checksums, SBOM, notices, and test evidence agree on one version.
- Offline install, launch, upgrade, uninstall, and reinstall pass on clean Windows.
