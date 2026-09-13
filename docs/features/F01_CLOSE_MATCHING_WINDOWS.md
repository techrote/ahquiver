# F01 — Close matching windows

F01 provides the `windows.close_matching` S2 action. It enumerates visible top-level windows, groups them against the active/selected target, applies exclusions/protections, revalidates every HWND immediately before mutation, and requests a normal `WM_CLOSE` through AutoHotkey `WinClose`.

It does **not** terminate owning processes and does not fall back to `WinKill`.

## Default behaviour

The module is disabled by default. When enabled:

- grouping is by owning executable, case-insensitive;
- exact window-class matching is optional;
- exact title matching is optional;
- AHQuiver's own PID is protected;
- shell desktop/taskbar classes are protected;
- confirmation is requested when two or more closable windows match;
- no global hotkey is claimed unless one is explicitly configured;
- a close request waits up to 750 ms for each target to disappear before reporting failure.

Protected shell classes currently include `Shell_TrayWnd`, `Shell_SecondaryTrayWnd`, `Progman`, and `WorkerW`. Explorer folder windows (`CabinetWClass`) are not blanket-excluded, because closing all Explorer windows is a primary use case.

## Configuration

```ini
[modules]
F01=1

[F01]
; Example only. Choose a chord appropriate to your machine.
hotkey=^!+w
match_class=0
match_title=0
protect_self=1
protect_shell=1
exclude_exes=
exclude_classes=
preview=0
confirm=1
confirm_min=2
close_timeout_ms=750
```

`exclude_exes` and `exclude_classes` accept comma-separated case-insensitive names. Setting `match_class=1` or `match_title=1` makes the grouping predicate stricter than executable-only grouping.

## Action parameters

Callers may override these per invocation without changing persistent configuration:

- `preview`: enumerate/report but do not close;
- `confirm`: enable/disable confirmation for this invocation;
- `confirm_min`: minimum closable count that triggers confirmation;
- `close_timeout_ms`: per-window wait before a requested close is reported as failed.

The action result data contains:

- `candidate`: same-group windows found before protection/exclusion;
- `closed`: windows confirmed closed after a normal close request;
- `skipped`: protected or explicitly excluded windows;
- `failed`: close requests that errored or timed out;
- `stale`: HWND/process/class identity changed between enumeration and mutation;
- `windows`: non-sensitive preview metadata (`hwnd`, `pid`, executable, class) for closable matches.

Window titles are deliberately omitted from result diagnostics by default.

## Safety model

F01 is an S2 state-changing action. Important properties:

1. Candidate discovery uses the shared `AQWindowQuery` service.
2. Each selected HWND is revalidated against captured PID/executable/class metadata immediately before closing.
3. Protected/excluded windows never receive a close request.
4. Preview mode performs no mutation.
5. Cancelling confirmation performs no mutation.
6. Normal window-close semantics are the only production close path.
7. The module installs no action or hotkey while disabled, and teardown unregisters/disables both.

## Verification

`tests/F01Tests.ahk` uses a deterministic fake window adapter to test grouping, refinements, protections, stale handles, failures, cancellation, exclusions, and module lifecycle.

`tests/F01WindowSmoke.ahk` creates three real benign AHK GUI windows on the Windows CI runner. Two share the target title and one is a control. F01 must close only the matching pair via the real `AQWindowQuery`/`WinClose` path and leave the control GUI alive.

For a local Explorer smoke, enable F01 with a deliberate hotkey, open several Explorer windows plus an unrelated application, invoke preview first if desired, then execute. The Explorer windows should receive normal close requests while the unrelated application, taskbar, desktop, and AHQuiver remain untouched.
