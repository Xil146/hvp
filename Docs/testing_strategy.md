# Testing strategy

Status: Proposed

## Principles

Automate deterministic policy and interop contracts; reserve real display, GPU, receiver, and subjective color validation for an explicit hardware matrix. A passing CI build is necessary but cannot certify HDR correctness.

## Automated layers

### Unit tests

- Dynamic-range classification with complete, missing, and conflicting metadata.
- Subtitle filename matching, `.sub`/`.idx` pairs, ordering, and directory containment.
- Audio/subtitle language/default/forced selection.
- Resume/completion thresholds and file identity.
- State transitions, error normalization, settings validation, and migrations.

### Playback contract tests

Use a fake native API behind the adapter to drive event order, property errors, callback races, command failures, fallback, and shutdown. Assert no WPF dependency and deterministic handle/callback ownership.

### Integration tests

Run a pinned real libmpv against tiny generated fixtures for load, property/track mapping, external subtitle addition, seek, end-file, invalid media, and repeated initialization/disposal. Fixtures must be generated from documented commands or be clearly redistributable.

### UI tests

Keep view-model behavior unit-testable. Add targeted Windows UI automation for open, play/pause, keyboard shortcuts, selectors, fullscreen recovery, and error recovery after the shell stabilizes.

## CI gates

- Locked restore; Release build with analyzers/warnings policy.
- Unit and non-GPU integration tests with test result artifacts.
- Formatting and repository policy checks.
- Dependency/license inventory, native checksum verification, and secret scan.
- Self-contained multi-file publish plus manifest validation of every staged path and digest.
- Native candidate consistency: one exact candidate cross-checks the source lock,
  dependency graph, compiled-source evidence, PE closure, notices/license texts,
  corresponding-source inputs, SPDX relationships, and staged native overlay.
- Candidate templates and incomplete provenance must fail closed; a passing
  contract test is not legal review, a clean-machine result, or GPU/HDR proof.
- The production native path binds extracted source and installed toolchain
  tree hashes, verifies dependency paths against private/system roots, inspects
  ordinary and delay-load imports, and binds runtime client API evidence to the
  selected output contract.
- No flaky retry counted as success without a tracking issue.

## Hardware matrix

At minimum before V1:

| Dimension | Coverage |
| --- | --- |
| OS | Current Windows 11; any Windows 10 edition/configuration explicitly claimed as supported under ADR 0001 |
| GPU | One supported Intel, AMD, and NVIDIA configuration |
| Display | SDR; HDR-capable with HDR off/on; mixed SDR/HDR multi-monitor |
| Source | SDR AVC 8-bit; SDR/10-bit edge; HDR10 HEVC; HLG; HDR10+; detectable Dolby Vision/base-layer fallback |
| Audio | Stereo PCM output; multichannel decode; compatible AC3/E-AC3/DTS/TrueHD passthrough paths |
| Subtitle | Embedded text/image where supported; each required external format; forced/language cases |
| Size/perf | Representative large 4K file, long duration, repeated seeks, fullscreen and monitor moves |

Record GPU/driver/display/connection, Windows HDR state, source facts, negotiated renderer facts, CPU/GPU utilization, dropped frames, seek latency, and observed result.

## Performance budgets

Set baselines during Phase 1, then ratchet rather than guess. Candidate targets are startup-to-window under 2 seconds on a reference system, responsive control input under load, no sustained UI-thread stalls, low CPU during hardware-decoded 4K playback, and no increasing handle/working-set trend across repeated opens.

## Release evidence

The release issue links CI, clean-machine smoke result, hardware matrix, known limitations, dependency/SBOM review, and artifact hashes. Any waived case names an owner and follow-up issue.
