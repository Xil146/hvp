# ADR 0003: Offline installer and multi-file installed payload

- Status: Accepted
- Date: 2026-08-22
- Owners: @Xil146
- Related issue/PR: [#5](https://github.com/Xil146/hvp/issues/5), [#7](https://github.com/Xil146/hvp/pull/7)
- Supersedes: Packaging decision 4 of [ADR 0001](0001-managed-application-foundation.md) only

## Context

ADR 0001 selected a self-contained single-file application whose native
libraries would be extracted at runtime. That provides one downloaded file, but
it makes the native DLL closure less visible, adds temporary extraction behavior
to startup, and does not match the desired Windows installation experience.

HVP still needs one simple offline acquisition path. Users must not install or
source .NET, libmpv, FFmpeg, codecs, or supporting libraries themselves. At the
same time, the native payload must remain auditable, securely loadable, and
replaceable under ADR 0002.

## Decision

1. The primary V1 distribution is one offline Windows x64 installer. It installs
   one HVP application and every required managed and native runtime file. The
   installer performs no network acquisition.
2. The application is published self-contained, untrimmed, and multi-file for
   `win-x64`. The canonical payload is a staged installed-directory tree that
   includes the .NET runtime, HVP assemblies, libmpv, FFmpeg, codecs, supporting
   DLLs, notices, and other required runtime files. Users do not source any of
   these dependencies.
3. HVP does not use .NET single-file publishing or native-library
   self-extraction. Native files load from approved private application
   locations under the restricted search and replacement policy in ADR 0002;
   the current directory and ambient `PATH` remain excluded.
4. A machine-readable application-payload manifest records every file in the
   canonical staged tree, its destination-relative path, and SHA-256 digest. CI
   validates that tree against the manifest instead of asserting that publish
   output contains exactly one executable.
5. The installer copies the exact validated application payload without
   modifying it. Installer-owned bookkeeping outside that payload, such as an
   uninstaller and installation state, is separately inventoried and tested; it
   is not part of the portable application payload. An optional portable ZIP may
   be emitted from the same application payload for diagnostics and replacement
   testing; it is not a different build or dependency set.
6. Installer technology is deliberately deferred until after the Phase 1
   playback spike. Phase 0 proves the complete staged directory and optional
   ZIP first; V1 still requires install, offline launch, upgrade, uninstall, and
   reinstall evidence from the final installer.

All non-packaging decisions in ADR 0001 remain accepted and unchanged.
ADR 0002's historical reference to a "clean-machine extraction matrix" is now
implemented as a clean-machine staged/private-load matrix. It validates delivery
and restricted loading of the native payload; it does not permit runtime native
extraction.

## Alternatives considered

- **Single-file publish with native self-extraction:** minimizes the visible
  file count but hides the installed DLL closure behind startup extraction and
  adds temporary-directory failure and cleanup behavior.
- **Portable ZIP as the primary distribution:** exposes the payload and avoids
  extraction at launch, but leaves installation, upgrade, shortcuts, and
  uninstall behavior to the user.
- **Framework-dependent application:** reduces the HVP payload but requires the
  user or installer to acquire a compatible .NET runtime, which conflicts with
  offline, no-user-sourced dependencies.
- **Bootstrapper or web installer:** can reduce the initial download but adds a
  network dependency and makes the installed inputs less reproducible.
- **Select installer technology now:** would settle mechanics early, but would
  make installer debugging part of the critical path before playback and the
  native payload are proven.

## Consequences

- The installed directory contains multiple files even though the user installs
  and launches one product.
- Release integrity is defined over the complete manifest and staged directory,
  not only the application executable.
- Native DLL discovery is predictable and inspectable, and does not depend on a
  per-user temporary extraction cache.
- Application binaries are signed, when configured, before the final payload
  manifest is generated. The installer and optional ZIP preserve the resulting
  relative paths and file contents. Installer-owned files are inventoried
  separately. The installer/ZIP containers are signed when applicable and
  hashed only after their final form is produced.
- Installer selection, per-user versus per-machine scope, shortcuts, file
  associations, and upgrade mechanics remain follow-up design work. None may
  introduce online dependency acquisition.

## Validation

- Locked restore, Release build, tests, and self-contained multi-file `win-x64`
  publish pass on a clean Windows runner.
- CI validates every application-payload file and SHA-256 digest against the
  payload manifest and rejects missing, unexpected, or path-escaping entries.
- The approved native PE/import closure is complete and resolves only from the
  staged private locations or an explicit valid `HVP_LIBMPV_PATH` override.
- The staged directory and optional portable ZIP launch offline on a supported
  clean Windows 11 x64 machine without a system .NET runtime or codec packs.
- The final installer reproduces the validated application payload, separately
  inventories installer-owned files, and passes offline install, launch,
  upgrade, uninstall, and reinstall tests on clean Windows.
- Notices, corresponding source references, SBOM, payload manifest, and release
  hashes all describe the exact shipped files.

## Follow-up

- Correct PR #7 so the project and CI stop enforcing single-file publication and
  native self-extraction, and make CI validate the documented staged payload.
- Update release automation to hash the complete payload rather than only the
  executable.
- Select and record installer technology after the Phase 1 playback spike.
