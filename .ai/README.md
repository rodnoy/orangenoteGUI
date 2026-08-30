# Project State Layer (.ai/)

This directory serves as the durable project-state and coordination layer between developers and AI agents working on the OrangeNote codebase.

## Mandatory Agent Read Order

Before inspecting code or performing any analysis, design, or code-modifying implementation tasks, agents must strictly follow the mandatory read order:

1. `.ai/README.md` (this file): Directory layout, state contracts, and execution rules.
2. `.ai/context.md`: Ground-truth technical architecture, file topology, and verified facts.
3. `.ai/decisions.md`: Durable architectural decisions (D001–D028). Decisions override speculation.
4. `.ai/plan.md`: Approved phased execution plan and atomic task specifications.
5. `.ai/handoff.md`: Current execution cursor, active phase/chunk/task, and next immediate action.
6. `.ai/build-errors.md`: Current unresolved build, test, or verification errors.
7. `.ai/build-log.md`: History of successful verification runs and check results.

Prior to executing any code-modifying task, reading `context.md`, `decisions.md`, `plan.md`, and `handoff.md` is mandatory, and `.ai/step.md` serves as the simple current task marker.

## State Artifacts Summary

| File | Role & Contract |
|------|-----------------|
| `README.md` | Entry point, state-layer guidelines, and mandatory read sequence. |
| `context.md` | Ground-truth technical reconnaissance and system topology. |
| `decisions.md` | Durable decisions log (D001–D028). Decisions override speculation. |
| `plan.md` | Approved execution plan (Tasks 1.1–3.19, Phases 1–6, Chunks A–R). |
| `handoff.md` | Session handoff state, execution status, and next single task. |
| `step.md` | Simple current task marker. |
| `build-errors.md` | Current unresolved build, lint, or test failures. |
| `build-log.md` | Log of successful verifications and command results. |

## Execution Guardrails

- **Scope boundary**: Only execute the single assigned task specified in `handoff.md`. Never execute future tasks or combine chunks without explicit user authorization and state update.
- **Decision precedence**: Architectural decisions recorded in `decisions.md` strictly supersede ad-hoc assumptions and framework defaults.
- **Native macOS architecture**: OrangeNote is a native macOS SwiftUI application with Rust via C FFI (not Tauri, not Electron).
- **Zero-drift state**: Update `handoff.md`, `step.md`, `build-errors.md`, and `build-log.md` upon completing each unit of work.
