# Development workflow

Status: Active process

## Board flow

```text
Todo -> Design Check -> Design -> Ready -> In Progress -> Review -> Test -> Done
                         |                    ^                   |
                         `---- not needed ----'                   `-> In Progress on failure
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

Implement in larger coherent phases. During a phase, run focused tests and make
small corrections without requesting a separate review for every action. At the
end of the phase, self-review the complete diff, link the issue/design/evidence,
and perform a short risk-focused independent review when the change touches
native lifetime/threading, DLL loading, dependencies, packaging, HDR, or
security, or licensing. Review follows `AGENTS.md` priorities. A failure returns
the item to In Progress with evidence.

### Test

Run only the remaining evidence named by the issue/design and required by the
risk level. Failures return to In Progress with evidence.

### Done

Merged to `main`; acceptance criteria and required evidence pass; designs/notices are current; follow-ups are tracked; issue/project status is closed.

## Board-driven agent protocol

A maintainer starts work by asking an integrator chat to take a named GitHub
Project item. The integrator reads the issue and its current Status, chooses
the lowest-cost role that can safely pass that stage, and keeps ownership of
requirements, integration, status transitions, and the final report. It does
not poll the board continuously.

Once a maintainer has authorized board automation, the integrator may move the
current item's Status as soon as the documented gate passes. It must not move
an item past an unresolved product decision, missing required evidence, or a
failed gate. Status changes are accompanied by a concise issue comment or
linked PR/evidence when that record materially helps the next stage.

### Stage routing and minimum evidence

| Stage | Default lowest-cost role | Escalate when | Minimum gate/evidence |
| --- | --- | --- | --- |
| Todo | `hvp_scout` | outcome or acceptance criteria are ambiguous | task, scope, and observable acceptance criteria are present |
| Design Check | `hvp_scout` | architecture, native, HDR, dependency, security, licensing, or hardware judgement is involved | record whether existing design is sufficient, no design impact exists, or Design is required |
| Design | main/high-capability integrator; `hvp_scout` may research facts | a durable design decision is needed | updated component design and ADR where required; maintainer approval |
| Ready | `hvp_scout` | affected boundary or validation is uncertain | affected files/components, validation level, and blockers are known |
| In Progress | `hvp_worker` (Terra-medium) for a bounded, accepted design | native lifetime/threading, HDR, dependency/license, or cross-component ownership is involved | smallest coherent diff plus the focused evidence selected below |
| Review | implementation-owner self-review | native lifetime/threading, DLL loading, dependencies, packaging, HDR, security, or licensing changed | independent `hvp_reviewer` review for those risks; otherwise self-review is sufficient |
| Test | `hvp_worker` or integrator | hardware/manual or release evidence is required | only outstanding targeted checks; record the result |
| Done | integrator | any acceptance criterion or required evidence is missing | merged change, passing stated evidence, and tracked follow-ups |

Use the least evidence that can demonstrate the changed behavior:

| Change risk | Required evidence |
| --- | --- |
| Editorial Markdown-only change | link/structure check and focused diff self-review; no test run or independent review |
| Process/configuration change with no runtime effect | targeted parser/linter or configuration check when available, plus self-review |
| Isolated managed behavior | focused unit/contract test at the changed boundary |
| UI, persistence, packaging, or real playback integration | focused integration/UI/payload check plus the applicable automated tests |
| HDR, GPU decoding, passthrough, display, or clean-machine claim | targeted automated checks and the matching manual hardware/clean-machine matrix evidence |

Do not run a full solution suite merely because a task entered Test. Run it
before a PR only when it is relevant to the changed area or required by branch
protection/release policy. Never waive required native, security, licensing,
or hardware evidence solely to reduce cost.

## Agent routing

The stage policy above is the default for board-driven work. The following
role-to-work mapping applies within a stage and for work that is not yet on the
board.

The main agent remains the integrator and keeps requirements/decisions in the primary context.

| Work | Suggested role | Verification |
| --- | --- | --- |
| File/code inventory, focused docs lookup, log/test-output summary | `hvp_scout` on the fast/low-cost model | Main agent checks cited files/facts. |
| Small mechanical edit with exact pattern and disjoint files | `hvp_scout` or `hvp_worker` | Main agent reviews diff and runs checks. |
| Bounded production implementation after accepted design | `hvp_worker` on balanced model | Focused tests during the phase; short independent review at the phase boundary when risk warrants it. |
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
