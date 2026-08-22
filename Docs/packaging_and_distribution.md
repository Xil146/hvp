# Packaging and distribution design

Status: Lean V1 policy accepted by [ADR 0004](adr/0004-lean-v1-libmpv-bundle.md) and [ADR 0005](adr/0005-lean-v1-packaged-folder.md)

## V1 artifact

V1 produces one offline, self-contained, multi-file `win-x64` folder. It holds
the .NET runtime, HVP assemblies, the selected libmpv DLL closure, notices, and
licenses. It has no installer, runtime native extraction, network acquisition,
or `HVP_LIBMPV_PATH` override.

Native libraries load only from HVP's private application directory with a
restricted Windows search policy. The current directory and ambient `PATH` are
not native-library sources.

## Native bundle record

HVP does not build libmpv in V1. Before copying a bundle into the folder, record:

- publisher, exact version/release, and download URL;
- archive SHA-256 and SHA-256 for every shipped native DLL;
- applicable license texts and notices in `licenses/`;
- a matching publisher source or build-material reference.

The record and `THIRD_PARTY_NOTICES.md` are intentionally a practical release
inventory, not an SBOM, custom toolchain, double-build, candidate-promotion
system, or extensive provenance program.

## Publish and checks

Publish self-contained, untrimmed, multi-file `win-x64` output. Copy the exact
pinned native closure, notices, and licenses into that folder. A relative-path
and SHA-256 manifest verifies the expected DLLs.

The required automated checks are:

- native DLL loads and reports a compatible API;
- a local file produces a loaded event;
- stop/dispose unlocks the file;
- a missing DLL produces a useful error;
- repeated startup/shutdown does not crash;
- the published folder contains the expected DLLs.

## Acceptance criteria

The exact self-contained folder launches offline on one clean Windows 11 x64
machine without a system .NET runtime or codec packs, and plays two or three
ordinary local files. Issue #6 records the selected bundle's version/hashes and
the clean-machine result.

Installer, portable ZIP, signing, upgrade/uninstall, SBOM, replacement DLLs,
and release-candidate promotion are follow-up work.
