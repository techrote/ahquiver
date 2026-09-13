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

## Retrieval hints

Search by stable feature ID `F01` through `F13`, architecture tags `CORE`, `CTX`, `ACTION`, `CFG`, `IPC`, `UI`, `TERM`, or concrete service names such as `AQActionRegistry`, `AQContextService`, `AQWindowQuery`, `AQClipboardGuard`, and `AQModuleHost`.
