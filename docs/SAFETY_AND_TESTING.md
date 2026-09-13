# Safety and testing

AHQuiver manipulates windows, input, clipboard state and external processes. Safety is a functional requirement, not optional polish.

## Safety classes

### S0 — read-only/observational
Examples: context inspection, quota display, capability probes. These may run automatically if lightweight.

### S1 — reversible interaction
Examples: changing a window title, selecting a profile, temporary clipboard use. Preserve prior state when reasonable and provide deterministic failure reporting.

### S2 — state-changing/destructive
Examples: closing windows, interrupting/restarting a process, executing pasted commands, editing source. These require narrow targeting, explicit configuration, safe defaults and evidence for failure paths.

### S3 — externally triggered action
Examples: hardware/network events invoking actions. Treat inbound payloads as untrusted until validated. Only allow registered/allowlisted actions and validated parameters.

## Window targeting rules

- Target by HWND plus corroborating process/class metadata; never mutate a window solely from a stale title match.
- Revalidate target immediately before an S2 action.
- Prefer normal close/termination protocols before force.
- Maintain exclusion hooks for shell/critical/sensitive windows.
- Multi-window actions must enumerate and optionally report their candidate set.

## Focus/input rules

- Never claim background input if foreground focus was actually moved.
- Record capability outcome as supported/unsupported/degraded.
- A fallback that briefly activates a target must be separately configurable and named.
- Context-sensitive hotkeys must provide an emergency bypass/disable mechanism.
- Avoid intercepting input in unrelated applications.

## Clipboard rules

When clipboard content is only temporary transport:

1. save the complete clipboard state where AHK permits;
2. perform the operation;
3. restore it even after handled failure;
4. avoid logging clipboard contents by default.

Clipboard-sensitive tests must use synthetic non-secret fixtures.

## External execution rules

- Commands/program paths come from local configuration or trusted presets.
- Device/network payloads cannot directly supply arbitrary shell command text by default.
- Quote/escape arguments safely.
- Surface exit code/launch failure.
- Never commit user-specific absolute paths as defaults.

## Automated test strategy

The foundation issue should establish a repeatable `tests/` harness callable from CI on a Windows runner. Prefer pure-function and service tests where possible:

- config parsing/defaults/errors;
- action registration and result states;
- context/grouping predicates;
- hotkey/profile conflict resolution;
- clipboard text classification;
- device message validation/rate limiting;
- timer/math state for F13;
- simulated process/external adapters.

UI/Win32 behaviour that cannot be asserted headlessly should have a deterministic smoke harness plus documented manual evidence.

## Per-module minimum test matrix

Every feature PR must include:

- happy path;
- disabled-module path;
- invalid/missing configuration;
- unsupported capability where applicable;
- wrong/stale target rejection for state-changing actions;
- one regression test for the highest-risk failure mode in that feature.

## Manual evidence template

For behaviour requiring real Windows UI:

```text
Environment: Windows version; AHK version; terminal/app version
Scenario:
Expected:
Observed:
Safety check:
Result: PASS/FAIL
```

Screenshots are optional; concise reproducible text evidence is sufficient unless the issue requires visuals.

## CI policy

A PR may merge only after all configured automated checks for its head commit pass. Do not disable, delete or weaken checks to obtain a green result. Flaky checks should be fixed or explicitly isolated with rationale, not repeatedly rerun until lucky.
