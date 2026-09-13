# Architecture

Stable tags: `CORE`, `CTX`, `ACTION`, `CFG`, `IPC`, `UI`, `TERM`.

## CORE — resident host

AHQuiver is one resident AutoHotkey v2 process (`src/AHQuiver.ahk`) loading separately toggleable modules. Modules register actions, hotkeys, tray entries and optional timers/listeners through shared services rather than each building its own global plumbing.

Recommended layout:

```text
src/
  AHQuiver.ahk
  core/
    App.ahk
    Config.ahk
    Context.ahk
    WindowQuery.ahk
    ActionRegistry.ahk
    Process.ahk
    ClipboardGuard.ahk
    Capability.ahk
    Log.ahk
    Ipc.ahk
    Ui.ahk
  modules/
    F01_CloseMatchingWindows.ahk
    ...
    F13_PlasmaTermBpmDrift.ahk
config/
  ahquiver.example.ini
tests/
tools/
```

Exact filenames may evolve, but the separation of shared services from modules is normative.

## Module contract

Each module should expose a small lifecycle surface such as:

- stable ID and human-readable name;
- `Init(app)` / registration function;
- enable/disable state from configuration;
- declared actions and hotkeys;
- optional capability probe;
- optional teardown for listeners/timers/resources.

A disabled or unsupported module must not install active hooks, consume hotkeys or leave timers running.

## CTX — context model

Shared context should provide, at minimum:

- active HWND;
- owning PID and executable;
- window class/title;
- current process path when available;
- known terminal classification (`WindowsTerminal`, `conhost`, other/unknown);
- modifier state;
- optional project identity/profile;
- monotonic timestamp.

Context-sensitive modules must query this service rather than duplicating fragile executable/title heuristics.

## ACTION — registry

User-invokable behaviours should be named actions, not hard-wired hotkey bodies. Example IDs:

- `windows.close_matching`
- `terminal.paste_background`
- `terminal.safe_paste`
- `tracker.restart`

Actions accept structured parameters/config, return a result (`ok`, `cancelled`, `unsupported`, `failed`) and produce useful diagnostic text. Hotkeys, tray UI, hardware events and future IPC should all be able to invoke the same action.

## CFG — configuration

Use a human-editable configuration with a checked-in example/default. Prefer built-in AHK facilities and minimal dependencies. INI is the baseline format unless a later decision explicitly adopts another parser.

Required qualities:

- per-module enable/disable;
- hotkey binding indirection through action IDs;
- profiles/contexts without code edits;
- safe defaults;
- graceful handling of missing keys;
- no machine-specific paths committed as defaults.

Configuration reload should be possible without restarting Windows; whether this is live reload or a controlled host reload may be decided in the foundation issue.

## IPC — external events

IPC is optional until required by F09/F12/F13. External events must map to registered action IDs. Network-originated or device-originated arbitrary shell strings are forbidden by default. Prefer a small allowlisted message schema such as action ID + parameters.

Transport may be local HTTP, named pipe, UDP on loopback, serial bridge or another justified mechanism; record a durable choice in `DECISIONS.md`.

## UI — tray/control surface

The tray is the baseline always-available UI. A richer GUI may be added for F07/F02, but must consume the same action/config services. UI code must not contain alternate business logic for actions.

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
