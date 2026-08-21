# Contributing to HVP

Thanks for helping build HVP. The project is pre-alpha; design documents may land before code.

## Before starting

1. Read `brief.md`, `implementation_plan.md`, `AGENTS.md`, and the relevant document in `Docs/`.
2. Open or claim an issue with acceptance criteria.
3. Run the Design Check in `Docs/development_workflow.md`.
4. For changes that affect architecture, behavior, dependencies, packaging, native interop, or user experience, update the relevant design or add an ADR before implementation.

## Pull requests

- Keep one coherent outcome per PR and link its issue.
- Include tests for behavior changes and list the commands actually run.
- Attach manual evidence for GPU, HDR, passthrough, DPI, or clean-machine claims.
- Update public docs and third-party notices when behavior or dependencies change.
- Do not include copyrighted movie samples, secrets, machine-specific paths, or unverified native binaries.
- Expect review for correctness, native lifetime/threading, untrusted input, single-file compatibility, and licensing.

See `Docs/development_workflow.md` for board stages and definitions of ready/done.

## Development setup

The build instructions will become active when Phase 0 creates `Hvp.slnx`. Until then, documentation and workflow contributions can be made with any text editor.

## License of contributions

By submitting a contribution, you agree that it may be distributed under the repository's MIT License. Do not submit code or assets you do not have the right to license.
