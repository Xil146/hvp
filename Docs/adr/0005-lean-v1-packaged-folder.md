# ADR 0005: Lean V1 packaged folder

- Status: Accepted
- Date: 2026-08-22
- Owners: @Xil146
- Related issue/PR: [#6](https://github.com/Xil146/hvp/issues/6)
- Supersedes: V1 distribution and validation portions of [ADR 0003](0003-offline-installer-and-installed-payload.md)

## Decision

V1 produces a self-contained `win-x64` folder, not an installer. It contains
the .NET runtime, HVP, the pinned libmpv DLL closure, notices, and licenses.
The folder is validated offline on one clean Windows 11 machine and must play
two or three local files. A simple relative-path/hash payload manifest confirms
the expected DLLs.

Installer technology, upgrade/uninstall testing, portable ZIP variants,
container signing, and a full release-promotion pipeline are deferred until
after playback is working reliably.

## Consequences

The folder is sufficient evidence for issue #6 but is not a broadly distributed
installer release. Future installer work must wrap this validated payload
without adding online acquisition or changing the private DLL loading policy.
