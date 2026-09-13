# Agent context

## Programme objective

Implement AHQuiver as a practical Windows automation toolkit whose initial scope is the 13 features in `FEATURE_CATALOG.md`. The repository, documentation, tests and issue history are the evolving source of truth.

## Per-issue execution contract

For an implementation issue:

1. Read the issue body and every referenced canonical document before coding.
2. Inspect the current repository; do not assume the issue prompt reflects every later merged change.
3. Create a focused branch from the current default branch.
4. Implement the complete issue scope, including configuration, documentation, tests and migration/reconciliation needed by the change.
5. Prefer small reusable core primitives over feature-local duplication when at least two modules need the same behaviour.
6. Run all repository checks plus issue-specific checks. Capture evidence for behaviour that cannot be fully automated.
7. Open a PR linked to the issue with a concise implementation summary, test evidence, known limits and any canonical-doc changes.
8. Resolve failures and review findings rather than bypassing checks.
9. After required automated checks pass, merge the PR using a repository-supported merge method. The maintainer explicitly authorizes issue executors to merge their own implementation PRs after checks pass.
10. Verify the merge landed on the default branch, reconcile documentation/status if needed, and close the issue only when its acceptance criteria are actually met.

If repository policy or GitHub permissions prevent merging, leave the PR ready and document the exact blocker; do not weaken protections.

## Engineering constraints

- AutoHotkey v2 syntax only.
- Target Windows 10/11 x64 unless a feature explicitly narrows support.
- Avoid requiring administrator privileges for ordinary operation.
- Avoid global hooks or input interception broader than necessary.
- Preserve clipboard contents when a workflow only needs temporary clipboard use.
- Never assume a background-window input technique works just because it works in one terminal build; use capability detection where required.
- External command execution must be explicit and configurable; network-originated commands require allowlisting.
- Keep experimental modules isolated behind configuration and capability checks.

## Repository hygiene

- Production code under `src/`.
- Shared reusable code under `src/core/`.
- Modules under `src/modules/` and identified by `F01`..`F13`.
- Default configuration/examples under `config/`.
- Tests under `tests/`; test helpers and fixtures must not leak into production startup.
- Supporting PowerShell/Python code, when justified, under `tools/` with a documented reason.
- Architecture changes require an entry in `DECISIONS.md` when they create or change a durable convention.

## Definition of done

An issue is not done when code merely exists. It is done when the implemented behaviour is reachable through AHQuiver, failure paths are safe, tests/checks pass, user-facing configuration is documented, limitations are explicit, and the merged default branch reflects the result.
