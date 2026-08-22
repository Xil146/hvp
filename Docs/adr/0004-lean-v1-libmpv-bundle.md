# ADR 0004: Lean V1 libmpv bundle

- Status: Accepted
- Date: 2026-08-22
- Owners: @Xil146
- Related issue/PR: [#6](https://github.com/Xil146/hvp/issues/6)
- Supersedes: [ADR 0002](0002-native-libmpv-foundation.md)

## Context

The custom native toolchain, double-build reproducibility work, candidate
promotion system, SBOM, extensive provenance review, and replacement-DLL matrix
delay the first real playback result without improving the first V1 user path.

V1 needs one maintained redistributable Windows x64 libmpv bundle, a clear
record of what was shipped, and practical proof that the application can load
and use it safely. HVP will not build libmpv itself in V1.

## Decision

1. Select one maintained Windows x64 libmpv bundle that the publisher permits
   redistribution. Pin its publisher, release/version, download URL, archive
   SHA-256, and SHA-256 for every shipped native DLL in a small checked-in
   manifest.
2. Keep the bundle's applicable license texts and notices in `licenses/`, and
   record the publisher's matching source or build-material reference in
   `THIRD_PARTY_NOTICES.md`. This is a basic release record, not an SBOM or an
   independent provenance program.
3. Ship the selected DLL closure in HVP's private application directory. Load
   libmpv only from that directory using a restricted Windows DLL search policy;
   never use the current directory or ambient `PATH`.
4. Do not provide `HVP_LIBMPV_PATH` in V1. Add an override only if a concrete
   development or support need arises and design it then.
5. The V1 native checks are: x64 DLL/API compatibility and successful native
   load; a real file produces a loaded event; stop/dispose releases the file;
   missing DLL returns a useful error; repeated startup/shutdown does not crash;
   and the packaged payload contains the expected DLLs.
6. Before closing issue #6, publish a self-contained Windows x64 folder and
   launch it offline on one clean Windows 11 machine, playing two or three
   ordinary local files.

## Consequences

- V1 deliberately does not build libmpv, run reproducible double builds,
  generate an SBOM, promote candidates, audit an exhaustive source graph, or
  test replacement DLLs.
- The selected publisher and exact binary hashes become the upgrade boundary.
  Updating the bundle requires updating the manifest, notices/reference, and
  focused native checks.
- Native handles, callbacks, event-loop shutdown, and file-path safety remain
  non-negotiable implementation constraints.

## Validation

- Test a H.264/AAC MP4, a multi-track MKV, a large seekable file, an unsupported
  or damaged file, and a path containing spaces and non-ASCII characters.
- Run the focused automated native checks listed in Decision 5 and the one
  clean-machine packaged-folder test. HDR, passthrough, exotic codecs,
  replacement DLLs, and extensive performance work are deferred.
