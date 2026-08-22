# ADR 0006: LGPL libmpv bundle selection

- Status: Accepted
- Date: 2026-08-22
- Owners: @Xil146
- Related issue/PR: [#6](https://github.com/Xil146/hvp/issues/6)
- Supersedes: Bundle-selection implementation of ADR 0004

## Context

The initially pinned `shinchiro/mpv-winbuild-cmake` development bundle enables
GPL/GPLv3 FFmpeg options and GPL codec libraries. That contradicts HVP's
LGPL-only native-bundle decision and prevents HVP from retaining its intended
MIT first-party licensing posture.

## Decision

Use the exact Windows x64 `mpv-dev-lgpl` release recorded in
`eng/native/libmpv-bundle.json` from `zhongfly/mpv-winbuild`. Pin the archive
and `libmpv-2.dll` SHA-256 values. Keep LGPL v2.1 and v3 texts in `licenses/`,
copy them and `THIRD_PARTY_NOTICES.md` to the published folder, and retain the
publisher release, build-run, and LGPL-build-patch references.

Do not use the x86_64-v3 asset; HVP supports ordinary Windows x64 CPUs without
that newer baseline. The release is a build-author assertion, not an
independent legal certification.

## Consequences

The private-DLL loading and staging model remains unchanged. The publisher
keeps build releases for a limited time, so HVP must retain the verified archive
or released native payload with its hashes and records before relying on it for
a shipped artifact.

## Validation

Verify archive and DLL hashes, API loading, staged notices/license texts, and
the issue #6 real-file and clean-machine smoke evidence. Re-evaluate the
license inventory if the selected bundle or its build configuration changes.
