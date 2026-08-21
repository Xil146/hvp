# Development workflow

Status: Active process

## Board flow

```text
Todo -> Design Check -> Design -> Ready -> In Progress -> Review -> Test -> Done
                         |                    ^             |
                         `---- not needed ----'             `-> In Progress on failure
```

Use one GitHub Project with a single-select `Status` field matching these columns. Keep repository labels for type/risk, not as a second status system.

## Stage policies

### Todo

An issue has a problem/outcome, context, and initial acceptance criteria. It is not yet promised for a release.

### Design Check

Answer:

- Does this alter user behavior, architecture, component contracts, native interop, dependencies, persistence/schema, privacy/security, packaging, or HDR/audio/subtitle policy?
- Does it introduce a choice that future contributors will revisit?
- Does it require hardware/manual verification?

If no, link the relevant existing design and move to Ready. If yes, move to Design.

### Design

Update the relevant component document and add an ADR for durable tradeoffs. Define scope/out-of-scope, failure/fallback behavior, acceptance criteria, and automated versus manual evidence. Obtain maintainer design approval before implementation.

### Ready

Definition of Ready:

- acceptance criteria are observable;
- dependencies and affected files/components are known;
- design/ADR is accepted or explicitly not needed;
- validation plan and hardware needs are named;
- no unresolved blocker requires a product decision.

### In Progress

Use a focused branch named `feature/<issue>-slug`, `fix/<issue>-slug`, or `docs/<issue>-slug`. One person/agent owns integration. Keep WIP low: one implementation item per contributor plus review work.

### Review

The PR is self-reviewed, linked, documented, and has automated evidence. Review follows `AGENTS.md` code review priorities. Significant changes should have independent verification by someone/agent that did not implement them.

### Test

Run remaining integration, UI, clean-machine, GPU/HDR, receiver, or performance checks on the exact candidate artifact. Failures return to In Progress with evidence.

### Done

Merged to `main`; acceptance criteria and required evidence pass; designs/notices are current; follow-ups are tracked; issue/project status is closed.

## Agent routing

The main agent remains the integrator and keeps requirements/decisions in the primary context.

| Work | Suggested role | Verification |
| --- | --- | --- |
| File/code inventory, focused docs lookup, log/test-output summary | `hvp_scout` on the fast/low-cost model | Main agent checks cited files/facts. |
| Small mechanical edit with exact pattern and disjoint files | `hvp_scout` or `hvp_worker` | Main agent reviews diff and runs checks. |
| Bounded production implementation after accepted design | `hvp_worker` on balanced model | Independent `hvp_reviewer` plus tests. |
| Architecture, native lifetime/threading, HDR policy, dependency/license decision | Main agent/high-capability model | Maintainer review and targeted evidence. |
| Final PR risk review | `hvp_reviewer` on high-capability model, read-only | Main agent resolves findings and reruns gates. |

Parallelize read-heavy independent work. For writes, use disjoint paths or worktrees and name the integration owner. A subagent returns a short evidence-backed summary; raw exploration stays in its thread.

## GitHub configuration

- Issue forms capture design need, acceptance criteria, and validation.
- PR template enforces issue/design/test/evidence links.
- CODEOWNERS requests maintainer review.
- Branch protection on `main`: PR required, required CI check, resolved conversations, no force push/deletion.
- Releases use annotated `vMAJOR.MINOR.PATCH` tags after the Test stage.

See `github_setup.md` for the maintainer setup steps that cannot be stored declaratively in the repository.
