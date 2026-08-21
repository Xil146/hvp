# HVP master design catalog

Status: Proposed

Last updated: 2026-08-21

Product brief: [`../brief.md`](../brief.md)

Delivery plan: [`../implementation_plan.md`](../implementation_plan.md)

## Purpose

This file is the index for HVP's design. Component documents describe the current intended behavior and boundaries; architecture decision records explain important choices and their alternatives.

Design statuses are:

- `Proposed`: ready for review but not yet proven in code.
- `Accepted`: approved for implementation.
- `Implemented`: present in the main branch and covered by its stated evidence.
- `Superseded`: retained for history and linked to its replacement.

## Product principles

1. Open a local video and make the correct common choices automatically.
2. Favor playback correctness, stable native lifetime, and diagnostic clarity over feature count.
3. Keep the default interface minimal and fully keyboard-operable.
4. Remain offline and local-first in V1.
5. Use libmpv capabilities before duplicating a media engine in application code.
6. Never claim HDR, passthrough, or hardware decode without observable evidence.
7. Keep HVP MIT licensed and make all native dependency obligations auditable.

## Design index

| Design | Scope | Status | Implementation owner |
| --- | --- | --- | --- |
| [`architecture.md`](architecture.md) | System boundaries, dependency direction, runtime flow, failure model | Accepted by [ADR 0001](adr/0001-managed-application-foundation.md) | Cross-cutting |
| [`ui_and_input.md`](ui_and_input.md) | Window, controls, keyboard, fullscreen, accessibility | Proposed | `Hvp.App` |
| [`playback_engine.md`](playback_engine.md) | libmpv lifecycle, interop, eventing, commands, diagnostics | Proposed | `Hvp.Playback` |
| [`hdr_color_pipeline.md`](hdr_color_pipeline.md) | HDR classification, output decisions, tone mapping, validation | Proposed | Playback + Windows platform |
| [`media_tracks.md`](media_tracks.md) | Audio/subtitle discovery, matching, selection, passthrough | Proposed | Core + Playback |
| [`persistence.md`](persistence.md) | Settings, playback history, privacy, migration, recovery | Proposed | `Hvp.Persistence` |
| [`packaging_and_distribution.md`](packaging_and_distribution.md) | Single EXE, native bundle, licensing, release artifacts | Managed artifact accepted by [ADR 0001](adr/0001-managed-application-foundation.md); native bundle pending | Build/release |
| [`testing_strategy.md`](testing_strategy.md) | Automated, integration, hardware, performance, release evidence | Proposed | Cross-cutting |
| [`development_workflow.md`](development_workflow.md) | Kanban stages, design check, agents, review and done | Active process | Contributors |
| [`github_setup.md`](github_setup.md) | Authentication, remote sync, board and protection setup | Active runbook | Maintainer |

## Cross-component contracts

- The UI consumes immutable snapshots/events from `IPlaybackEngine`; it does not expose native mpv types.
- Playback state changes arrive on an engine-owned event loop and are marshaled once through a UI dispatcher boundary.
- `Hvp.Core` owns policies and normalized models; platform and engine adapters provide facts.
- Persistence receives stable core models, not WPF view models or raw native structures.
- Packaging selects the exact native ABI that playback targets and records its provenance.
- Testing owns generated fixtures and the release hardware matrix shared by all components.

## Decision records

- [`ADR 0001`](adr/0001-managed-application-foundation.md) accepts the managed
  .NET/WPF/project-boundary/packaging foundation.
- [`ADR 0002`](adr/0002-native-libmpv-foundation.md) accepts the native build,
  licensing, ABI, replacement, provenance, and evidence policy; the actual bundle
  remains pending issue #6.

Use [`adr/0000-template.md`](adr/0000-template.md) when a choice:

- changes component boundaries or dependency direction;
- adds a production or native dependency;
- changes the supported OS/architecture or packaging model;
- changes HDR, audio, subtitle, persistence, privacy, or security behavior;
- accepts a durable tradeoff that future contributors would otherwise revisit.

ADRs are append-only after acceptance. Supersede an old decision with a new ADR rather than rewriting history.

## Design review checklist

- Does the change map to a requirement or explicitly accepted scope addition?
- Is the smallest owning component clear?
- Are UI/native threading and lifetime rules explicit?
- Are fallback, failure, and diagnostics paths designed?
- Are untrusted input and privacy implications covered?
- Are single-file and native-license constraints preserved?
- Can the behavior be tested automatically, and what hardware/manual proof remains?
- Are acceptance criteria observable to a user or reviewer?
