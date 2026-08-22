# HVP agent instructions

## Mission and source of truth

Build the smallest reliable Windows player that satisfies `brief.md`. Read `implementation_plan.md` and `Docs/master_design.md` before architecture or feature work. If code and a design document disagree, stop and either update the design in the same change or record the exception as an ADR.

V1 is local-file playback only. Do not add libraries, streaming, accounts, telemetry, update checks, media servers, playlists, or network dependencies without explicit approval.

## Repository map

- `src/Hvp.App`: WPF shell, views, view models, and composition root.
- `src/Hvp.Core`: platform-neutral models and policies; no WPF or libmpv references.
- `src/Hvp.Playback`: playback abstraction, libmpv interop, and event translation.
- `src/Hvp.Platform.Windows`: HWND, display/HDR, power, and Windows integration.
- `src/Hvp.Persistence`: versioned local settings and history.
- `tests`: unit, contract, and integration tests.
- `Docs`: reviewed design, workflow, test, packaging, and ADR documents.
- `eng`: native dependency and release automation.

The planned tree may precede the code. Do not invent build commands when the solution has not been scaffolded.

## Required workflow

1. Classify the request as question, bug, feature, refactor, dependency, or release work.
2. Link or create an issue with acceptance criteria. Run the Design Check in `Docs/development_workflow.md`.
3. For a design-relevant change, update the component document or add an ADR before implementation.
4. Make the smallest coherent change. Preserve unrelated user work.
5. Add or update tests at the same boundary as the behavior.
6. Work in coherent implementation phases. Run focused checks while building, then perform one short, risk-focused review at the end of each phase rather than stopping for a formal review after every action.
7. Review the phase diff against the issue, design, security, native-resource, and licensing constraints.
8. Report what changed, verification evidence, residual risks, and follow-up work.

Never mark work done because code compiles. Done means acceptance criteria are met and the appropriate automated and hardware/manual evidence exists.

## Build and verification

After Phase 0 creates the solution, use these canonical commands from the repository root:

```powershell
dotnet restore .\Hvp.slnx --locked-mode
dotnet build .\Hvp.slnx -c Release --no-restore
dotnet test .\Hvp.slnx -c Release --no-build
dotnet publish .\src\Hvp.App\Hvp.App.csproj -c Release -r win-x64 --self-contained true
```

Until those files exist, validate Markdown/YAML/TOML structure and clearly state that the code build is not yet available.

For a focused change, run focused tests first. Before a PR is ready, run the full relevant suite. Never claim HDR, passthrough, GPU, or clean-machine behavior from unit tests or CI alone; attach the matching manual matrix evidence.

## Engineering constraints

- Target .NET 10 LTS, WPF, Windows x64, nullable reference types, deterministic builds, and warnings-as-errors for first-party code.
- UI code must not call native functions directly. Keep libmpv behind `IPlaybackEngine` and a narrow interop layer.
- Never block the WPF dispatcher while waiting for libmpv. Marshal normalized state to the UI thread.
- Own and dispose every native handle, callback registration, cancellation source, and event loop deterministically. Shutdown must be idempotent.
- Use argument-array APIs for filenames and commands. Never build shell or libmpv command strings from media paths.
- Keep controls outside the `HwndHost` video region; WPF airspace prevents reliable overlay composition.
- Preserve automatic software fallback when hardware decoding is unavailable.
- Do not silently force HDR or change Windows display settings. Detect, adapt, report, and expose diagnostics.
- Treat media and subtitle files as untrusted. Do not scan beyond the opened file's directory.
- Persistence is local, versioned, atomic, and path-private in logs.
- Pin production dependencies centrally. Adding or changing one requires license, security, native-ABI, installed-payload, and update-policy review.
- HVP code is MIT. Ship only an approved native bundle and keep `THIRD_PARTY_NOTICES.md`, source references, checksums, and SBOM data current.

## Subagent policy

Use subagents to protect the main context and reduce wall-clock time only when work is bounded and genuinely separable. A subagent consumes additional tokens, so do not delegate tiny tasks, serial decisions, or work that requires the full evolving conversation.

The main agent owns requirements, architecture decisions, task decomposition, integration, final diff review, and the user-facing result.

Preferred project roles are configured in `.codex/agents/`:

- `hvp_scout`: low-cost, read-only exploration, inventory, documentation lookup, or log summarization.
- `hvp_worker`: balanced implementation for one isolated file set after the design and acceptance criteria are settled.
- `hvp_reviewer`: high-capability, read-only verification for correctness, regression, threading, interop, tests, and licensing risks.

Delegation rules:

- Give each agent one outcome, exact scope, relevant files, constraints, required evidence, and a concise return format.
- Prefer parallel read-heavy work. Do not give multiple agents overlapping write ownership.
- For parallel implementation, use separate worktrees or disjoint file sets and identify the integration owner first.
- Ask subagents to return findings and file references, not raw logs.
- A lower-cost agent may perform mechanical edits, inventories, fixture creation, or narrow tests. Complete substantial, coherent phases before requesting a short independent review; the main agent then reviews the diff and reruns the relevant checks.
- Do not use a reviewer to rubber-stamp its own implementation. Verification must be independent for risky work.
- Stop delegating when coordination or context transfer costs more than doing the work in the main thread.

Recommended task contract:

```text
Goal: one measurable outcome.
Scope: files/components the agent may read or edit.
Constraints: design, safety, compatibility, and do-not rules.
Evidence: commands/tests/references required.
Return: concise result, changed files, findings, and unresolved risks.
```

## Code review rules

Review findings in this order:

1. User-visible playback, color, audio, subtitle, resume, or shutdown regressions.
2. Deadlocks, callback races, use-after-free, leaks, invalid marshaling, and non-idempotent disposal.
3. Unsafe path/command handling or untrusted media/subtitle processing.
4. Loss of hardware-decoding fallback or incorrect HDR/display claims.
5. Missing tests or hardware evidence for changed behavior.
6. Dependency, binary provenance, license, source-offer, or notice problems.
7. Accessibility, DPI, keyboard, and WPF airspace regressions.

Ignore style-only issues covered by formatting or analyzers unless they hide a correctness problem.

## Approval boundaries

Read, diagnose, plan, edit in-scope local files, and run non-destructive validation without asking. Require user confirmation for destructive actions, external writes such as pushes/releases/project changes, new production dependencies, code-signing purchases, or material scope expansion.
