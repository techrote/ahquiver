# Development

## Prerequisites

- Windows 10 or 11.
- AutoHotkey v2. The CI baseline is pinned to AutoHotkey **v2.0.28**.
- Git for normal contribution workflows.

No administrator rights are required for the Phase 0 host.

## First run

1. Copy `config\ahquiver.example.ini` to `config\ahquiver.ini` if you want local overrides.
2. Keep feature modules disabled until their implementation issues are complete.
3. Launch:

```powershell
AutoHotkey64.exe .\src\AHQuiver.ahk
```

The resident host exposes a minimal tray with status, configuration reload and exit actions.

## Command-line options

```text
--config <path>   Use a specific INI file.
--headless        Do not initialize tray/UI. Intended for automation/tests.
--probe-startup   Start core services, then cleanly stop and exit 0. Intended for CI smoke testing.
```

Unknown arguments are rejected rather than silently ignored.

## Configuration behavior

`config\ahquiver.ini` is a local override and is ignored by Git. If it does not exist, the host uses `config\ahquiver.example.ini`.

The baseline configuration is intentionally conservative: every F01-F13 module is disabled. `Reload configuration` re-reads the INI source and re-evaluates registered module lifecycle state without restarting Windows.

## Tests

Run the deterministic AHK test harness directly:

```powershell
AutoHotkey64.exe /ErrorStdOut .\tests\TestRunner.ahk
```

Run the startup smoke separately:

```powershell
AutoHotkey64.exe /ErrorStdOut .\src\AHQuiver.ahk --probe-startup --headless --config .\config\ahquiver.example.ini
```

The tests avoid real destructive desktop actions. OS-facing services are kept narrow so feature issues can inject fakes where appropriate. The clipboard restore failure-path test uses an in-memory fake backend rather than the user's clipboard.

## Core contracts

Phase 0 establishes:

- `AQResult` structured status values: `ok`, `cancelled`, `unsupported`, `invalid`, `rejected`, `failed`.
- `AQConfig` dependency-free INI access.
- `AQActionRegistry` named action registration and dispatch.
- `AQCapabilityRegistry` explicit `supported` / `unsupported` / `degraded` / `unknown` reporting.
- `AQContextService` active-window/process/terminal/modifier snapshots.
- `AQWindowQuery` reusable window enumeration and HWND/PID/executable/class revalidation.
- `AQClipboardGuard` save/restore semantics behind an injectable backend.
- `AQProcess` local configured process launching.
- `AQModuleHost` disabled-by-default module lifecycle management.
- `AQTrayUi` minimal host control surface.

Feature code should consume these services rather than creating parallel global plumbing.

## CI

`.github/workflows/windows-ci.yml` downloads the official portable AutoHotkey v2.0.28 package on `windows-latest`, runs the test harness, then runs the headless startup probe. A failing AHK parse/startup/test exits non-zero and blocks the PR check.
