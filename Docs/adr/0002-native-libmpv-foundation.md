# ADR 0002: Reproducible LGPL-compatible native libmpv foundation

- Status: Accepted
- Date: 2026-08-21
- Owners: @Xil146
- Related issue/PR: [#6](https://github.com/Xil146/hvp/issues/6)
- Supersedes: None

## Context

HVP is MIT licensed but depends on a native media stack whose effective license,
security posture, ABI, and runtime behavior depend on the exact compiled sources,
linked libraries, flags, and toolchain. An arbitrary community Windows build is
not sufficient provenance.

mpv can produce an LGPLv2.1-or-later build when GPL-only files are excluded, but
upstream explicitly states that `-Dgpl=false` is a build-system convenience and
does not by itself create an LGPL license grant. Linked libraries also affect the
result; in particular, an FFmpeg build with GPL components changes the licensing
analysis.

The current upstream stable baseline is mpv `v0.41.0`, release commit
`41f6a645068483470267271e1d09966ca3b9f413`, with client API 2.5. Its release
requires FFmpeg 6.1 or newer and libplacebo 6.338.2 or newer. Exact transitive
source and tool pins belong in the reviewed native manifest produced by issue
[#6](https://github.com/Xil146/hvp/issues/6).

## Decision

1. Build a Windows x64 shared libmpv bundle from immutable, checksum-verified
   sources. Evaluate mpv `v0.41.0` at the commit above as the initial baseline;
   any version change requires the same security, ABI, license, and provenance
   review.
2. Build libmpv with `-Dlibmpv=true` and `-Dgpl=false`, do not ship the mpv CLI,
   and audit the actual compiled mpv source set. Build FFmpeg without
   `--enable-gpl` and without `--enable-nonfree`; exclude GPL/nonfree transitive
   libraries. Disable network features for V1 unless separately approved.
3. Pin and record mpv, FFmpeg, libplacebo, libass, every other dependency,
   patches, build tools, SDK/sysroot, requested and effective flags, source and
   output SHA-256 values, declared/concluded licenses, and link relationships in
   a machine-readable manifest.
4. Treat the headers from the exact pinned mpv source as the ABI authority.
   Verify x64 PE architecture, imports, exports, and `mpv_client_api_version`;
   require API major 2 and at least the minor used by HVP. Interop declarations
   must preserve Windows C ABI widths.
5. Dynamically load libmpv. `HVP_LIBMPV_PATH`, when set, must be an absolute path
   loaded with a restricted DLL search policy. Invalid overrides fail explicitly
   and never fall back silently. The current directory and ambient `PATH` are not
   native-library search sources.
6. Ship complete notices and applicable license texts, corresponding source and
   patches/build instructions for the exact binaries, SHA-256 checksums, and
   SPDX SBOM inputs. Release/download surfaces identify FFmpeg and its source;
   terms do not prohibit LGPL reverse engineering for debugging modifications.
7. No binary is approved merely by this ADR. The bundle becomes approved only
   when issue #6's reproducibility, license, ABI, replacement, clean-machine, and
   independent-review evidence all pass. Legal review remains required before
   the first public binary; this ADR is engineering policy, not legal advice.

## Alternatives considered

- **Community Windows bundle:** fastest to consume, but its source graph, flags,
  checksums, update ownership, and effective license are not under HVP's control.
- **GPL libmpv:** technically viable for a compatible open-source distribution,
  but conflicts with the selected MIT-plus-LGPL distribution policy and broadens
  obligations beyond the approved plan.
- **Static native linking:** can simplify file count but complicates LGPL
  relinking/replacement and transitive-license analysis.
- **Search `PATH` or the working directory:** convenient for development but
  creates DLL-preloading ambiguity and makes replacement evidence unreliable.
- **Silently fall back after an invalid override:** keeps playback available but
  can falsely report that a replacement was tested.

## Consequences

- The native build is a separate high-risk work item and may take longer than the
  managed scaffold.
- Some codecs can still be decoded by LGPL FFmpeg implementations without GPL
  encoder libraries such as x264/x265; feature names alone do not determine the
  license result.
- Exact source/build artifacts and notices must be retained and published with
  every native-bearing release.
- User-selected replacement libraries are identified as external/unverified and
  need ABI compatibility, not equality with HVP's production checksum.
- CI can establish provenance, policy, ABI, loading, and deterministic lifetime;
  it cannot establish GPU/HDR correctness or performance.

## Validation

- Verify all input/output hashes, effective flags, compiled sources, linked
  dependencies, licenses, PE architecture/imports/exports, and client API.
- Run repeated create/initialize/destroy and tiny-fixture load/unlock probes with
  null audio/video output.
- Verify valid and invalid `HVP_LIBMPV_PATH` cases with restricted DLL loading.
- Cross-check binary manifests, notices, corresponding source, SBOM, and release
  hashes for one exact version.
- Independently review licensing/provenance before integration, then run the
  clean-machine extraction matrix. Reserve D3D11/HDR evidence for Phase 1/later.

## Follow-up

- Implement and independently review issue #6 before beginning the Phase 1
  WPF/libmpv playback spike.

## Upstream references

- [mpv v0.41.0 release](https://github.com/mpv-player/mpv/releases/tag/v0.41.0)
- [mpv licensing details](https://github.com/mpv-player/mpv/blob/v0.41.0/Copyright)
- [mpv Windows/libmpv build guidance](https://github.com/mpv-player/mpv/blob/v0.41.0/DOCS/compile-windows.md)
- [mpv client API header](https://github.com/mpv-player/mpv/blob/v0.41.0/include/mpv/client.h)
- [FFmpeg LGPL compliance checklist](https://ffmpeg.org/legal.html)
