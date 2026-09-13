# Implementation guide

Use this checklist for feature work alongside the issue-specific prompt.

## Module skeleton

Each F01-F13 module should define:

- stable feature ID and display name;
- configuration section/keys with defaults;
- enable/disable behaviour;
- registered action IDs;
- hotkeys only through the shared binding/configuration layer when available;
- capability probe where support varies by environment;
- diagnostics/status suitable for the tray/control UI;
- teardown for timers/listeners/resources.

## Action result contract

Actions should return enough structured state for callers/UI/tests to distinguish:

- success;
- user cancellation;
- unsupported capability;
- invalid configuration/input;
- stale or rejected target;
- execution failure.

Avoid boolean-only results for state-changing operations.

## Configuration contract

New keys require:

- safe default;
- entry in the checked-in example configuration;
- validation/error behaviour;
- short user documentation;
- migration note if an existing key changes meaning.

## Diagnostics

Log metadata needed to debug targeting/capability problems, but avoid sensitive payloads. Clipboard contents, typed/pasted command text and arbitrary device payload bodies should not be logged by default.

## Tests

Prefer testable pure logic around OS-facing edges. Wrap volatile Win32/UI/external behaviours behind small adapters so tests can inject fakes. Every feature includes the minimum matrix in `SAFETY_AND_TESTING.md` plus issue-specific acceptance tests.

## Documentation reconciliation

If implementation changes a cross-cutting contract, update `ARCHITECTURE.md` and add/change a decision in `DECISIONS.md`. If feature scope changes based on evidence, update `FEATURE_CATALOG.md` rather than leaving stale promises.
