# Testing strategy

Status: Proposed

## Lean V1 automated checks

Use the pinned real libmpv bundle to verify:

- the native DLL loads and reports a compatible client API;
- one local file opens and produces a loaded event;
- stop/dispose unlocks the video file;
- a missing DLL returns a useful error;
- repeated startup/shutdown does not crash;
- the self-contained published folder contains the expected native DLLs.

Keep unit tests for deterministic state and path policies. UI behavior stays
unit-testable where possible; native callbacks and handles require focused
interop/lifetime tests.

## Practical manual set

Test a normal user-owned H.264/AAC MP4, an MKV with multiple audio/subtitle
tracks, a large seekable file, an unsupported or damaged file, and a filename
with spaces and non-ASCII characters. Record the observed behavior and whether
the file unlocks after stop/shutdown.

After publishing the folder, launch it offline on one clean Windows 11 machine
and play two or three of those files.

## Deferred evidence

HDR, passthrough, exotic codecs, replacement DLLs, broad GPU/display matrices,
and extensive performance testing are not lean-V1 gates. They cannot be claimed
from the focused checks and must get their own acceptance criteria when resumed.
