# AHQuiver RAG pack

This directory is the canonical context pack for implementation work.

## Authority order

1. Current GitHub issue and maintainer comments.
2. `docs/DECISIONS.md`.
3. `docs/ARCHITECTURE.md`.
4. `docs/SAFETY_AND_TESTING.md`.
5. `docs/FEATURE_CATALOG.md`.
6. `docs/ROADMAP.md`.
7. `docs/AGENT_CONTEXT.md`.
8. Root `README.md`.

If implementation evidence requires a cross-cutting change, update the appropriate canonical document in the same PR.

## Documents

- `AGENT_CONTEXT.md` — execution and completion conventions.
- `ARCHITECTURE.md` — host/module contracts, configuration, IPC and dependency policy.
- `FEATURE_CATALOG.md` — scope for the 13 initial modules.
- `ROADMAP.md` — dependency graph and implementation order.
- `SAFETY_AND_TESTING.md` — safety, tests and evidence requirements.
- `TERMINAL_INTEROP.md` — Windows Terminal/conhost capability model.
- `DEVELOPMENT.md` — concrete run, test, CI and Phase 0 service contracts.
- `PR_MERGE_PROTOCOL.md` — branch, PR, checks, merge and reconciliation procedure.
- `DECISIONS.md` — durable architectural decisions.
- `features/F01_CLOSE_MATCHING_WINDOWS.md` — implemented F01 action, configuration, safety model and verification.
- `features/F02_TERMINAL_IDENTITY.md` — F02 project/role presets, identity registry, singleton semantics and terminal title behavior.
- `features/F03_TERMINAL_KEY_GUARD.md` — F03 policies, context rules, bypass/disable controls and verification.
- `features/F04_FOCUS_PRESERVING_PASTE.md` — F04 target capture, capability truth, verified background adapter and degraded fallback.
- `features/F05_MULTILINE_PASTE.md` — F05 conservative classification and explicit whole/line/confirm/cancel delivery modes.
- `features/F06_TRACKER_RESTART.md` — F06 owned-PID tracker registry, graceful/force restart sequence, adoption and worker protection.
- `features/F07_CONTROL_SURFACE.md` — F07 registry-driven tray/panel, generic action dispatch, state views and payload-free failure history.

## Retrieval hints

Search by stable feature ID `F01` through `F13`, architecture tags `CORE`, `CTX`, `ACTION`, `CFG`, `IPC`, `UI`, `TERM`, or concrete service names such as `AQActionRegistry`, `AQContextService`, `AQWindowQuery`, `AQClipboardGuard`, `AQIdentityRegistry`, `F06TrackerRegistry`, `AQControlSurfaceModel`, `AQTrayUi`, and `AQModuleHost`.
