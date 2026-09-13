# Architecture

Stable tags: `CORE`, `CTX`, `ACTION`, `CFG`, `IPC`, `UI`, `TERM`.

## CORE — resident host

AHQuiver is one resident AutoHotkey v2 process (`src/AHQuiver.ahk`) loading separately toggleable modules. Modules register actions, hotkeys, tray entries and optional timers/listeners through shared services rather than each building its own global plumbing.

Current Phase 0 layout:

```text
src/
  AHQuiver.ahk
  core/
    App.ahk
    Result.ahk
    Config.ahk
    Context.ahk
    WindowQuery.ahk
    ActionRegistry.ahk
    Process.ahk
    ClipboardGuard.ahk
    Capability.ahk
    ModuleHost.ahk
    Log.ahk
    Ui.ahk
  modules/
    F01_CloseMatchingWindows.ahk
    ...
    F13_PlasmaTermBpmDrift.ahk
config/
  ahquiver.example.ini
tests/
```

`src/modules/` is populated by feature issues. IPC is intentionally deferred until a feature needs it. Exact filenames may evolve, but the separation of shared services from modules is normative.

## Module contract

Each module should expose a small lifecycle surface such as:

- stable ID and human-readable name;
- `Init(app)` / registration function;
- enable/disable state from configuration;
- declared actions and hotkeys;
- optional capability probe;
- optional teardown for listeners/timers/resources.

`AQModuleHost` reads module enablement from `[modules]`. A disabled or unsupported module must not install active hooks, consume hotkeys or leave timers running. Module initialization failure is isolated: the module is marked failed and the resident host continues.

## CTX — context model

`AQContextService` provides, at minimum:

- active HWND;
- owning PID and executable;
- window class/title;
- current process path when available;
- known terminal classification (`WindowsTerminal`, `conhost`, other/unknown);
- modifier state;
- optional project identity/profile;
- monotonic timestamp.

`AQWindowQuery` provides reusable window descriptions/enumeration and target revalidation by HWND plus corroborating PID/executable/class metadata. Context-sensitive modules must query these services rather than duplicating fragile executable/title heuristics.

## ACTION — registry

User-invokable behaviours are named actions, not hard-wired hotkey bodies. Example IDs:

- `windows.close_matching`
- `terminal.paste_background`
- `terminal.safe_paste`
- `tracker.restart`

`AQActionRegistry` accepts structured parameters/config and returns `AQResult`. The stable Phase 0 result states are:

- `ok` — completed successfully;
- `cancelled` — user/policy cancelled without failure;
- `unsupported` — required capability is unavailable;
- `invalid` — invalid configuration/input/action ID;
- `rejected` — stale, ambiguous or unsafe target rejected;
- `failed` — execution attempted but failed.

Hotkeys, tray UI, hardware events and future IPC should all invoke the same registered action instead of duplicating feature logic.

## CFG — configuration

Use a human-editable configuration with a checked-in example/default. Prefer built-in AHK facilities and minimal dependencies. INI is the baseline format unless a later decision explicitly adopts another parser.

Required qualities:

- per-module enable/disable;
- hotkey binding indirection through action IDs;
- profiles/contexts without code edits;
- safe defaults;
- graceful handling of missing keys;
- no machine-specific paths committed as defaults.

The local override is `config/ahquiver.ini` and is ignored by Git. If absent, the host reads `config/ahquiver.example.ini`. Phase 0 reload is a controlled in-process reload: re-read the INI source, teardown currently enabled registered modules, then re-evaluate configured module enablement. It does not restart Windows or spawn a replacement host.

## Clipboard

Temporary clipboard transport goes through `AQClipboardGuard`. The guard saves via an injectable backend and restores in `finally`, allowing failure-path tests without touching a real clipboard. Feature code should not create separate save/restore schemes unless required by a documented capability constraint.

## Process execution

Configured local process launches go through `AQProcess`. Feature-specific process discovery/termination may extend this service, but should preserve explicit result states and argument quoting rather than embedding opaque shell strings in UI/hotkey callbacks.

## Capability model

`AQCapabilityRegistry` records `supported`, `unsupported`, `degraded`, or `unknown` plus diagnostic detail. Feature code must not collapse degraded/unsupported behaviour into optimistic success.

## IPC — external events

IPC is optional until required by F09/F12/F13. External events must map to registered action IDs. Network-originated or device-originated arbitrary shell strings are forbidden by default. Prefer a small allowlisted message schema such as action ID + parameters.

Transport may be local HTTP, named pipe, UDP on loopback, serial bridge or another justified mechanism; record a durable choice in `DECISIONS.md`.

## UI — tray/control surface

The Phase 0 tray is deliberately minimal: status, configuration reload, exit. A richer GUI may be added for F07/F02, but must consume the same action/config services. UI code must not contain alternate business logic for actions.

## TERM — terminal adapters

Terminal-sensitive behaviour uses adapter/capability layers. Windows Terminal, classic console/conhost and generic GUI terminals have materially different input/selection semantics. Do not encode one successful technique as universal behaviour. See `TERMINAL_INTEROP.md`.

## Dependencies

Default stance: no vendored third-party AHK library unless the feature demonstrably needs one (for example UI Automation). If added:

- pin/version it;
- document origin/license;
- isolate it behind a small adapter;
- add a smoke test or capability probe;
- avoid making unrelated modules depend on it.

Small PowerShell/Python helpers are permitted only where they outperform an AHK implementation in correctness/maintainability. AHK remains the orchestration/user-interaction layer for the initial programme.
