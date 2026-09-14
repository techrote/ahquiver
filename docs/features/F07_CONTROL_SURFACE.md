# F07 — Unified project/control tray and compact GUI

## Purpose

F07 provides one resident control surface over AHQuiver's existing registries. It is intentionally a **thin UI layer**: feature behavior remains owned by F01-F06 and future modules, and F07 dispatches the same action IDs through `AQActionRegistry.Invoke()` that hotkeys/IPC callers use.

## Dynamic registry model

When F07 is enabled, `AQTrayUi` creates an `AQControlSurfaceModel` backed by:

- `AQActionRegistry.List()` for available actions;
- `AQModuleHost.List()` for registered module state;
- `AQCapabilityRegistry.List()` for supported/unsupported/degraded/unknown capability state.

Every refresh reads these registries again. A later module/action therefore appears automatically without adding F07-specific feature code. When a module unregisters its actions, they disappear on refresh instead of becoming dead buttons.

## Tray

F07 replaces the minimal tray with:

- **Open AHQuiver control panel**;
- optional dynamic **Actions** submenu (`F07.action_menu=1`);
- configuration reload;
- emergency disable of all feature modules for the current session;
- exit.

Each dynamic action item shows its action ID and safety class. Tray actions dispatch through the registry. If an action returns `invalid` (commonly because it requires parameters), the compact panel opens with that action selected so parameters can be supplied generically.

S2 actions receive a generic F07 confirmation before dispatch. This does not replace or bypass feature-level target checks/confirmations.

## Compact panel

The panel has four tabs:

1. **Actions** — action ID, safety class and description, plus a generic parameter editor.
2. **Modules** — enabled/disabled/failed/registered state.
3. **Capabilities** — capability ID, status and diagnostic detail.
4. **Failures** — recent payload-free action failure summaries.

Parameters use one `key=value` pair per line. F07 does not interpret feature-specific schemas; it parses those strings into a `Map` and invokes the selected action ID. For example:

```text
preset=audit
role=reviewer
```

## Failure privacy

`AQActionRegistry` exposes a payload-free observer contract. Observers receive only `actionId` and the resulting `AQResult`; action parameters are never supplied.

F07 intentionally stores only:

- action ID;
- result status;
- a fixed generic summary;
- local monotonic timestamp.

It does **not** store the action's result message/data, parameters, clipboard contents or command text. This remains true even if an underlying action's failure message/data contains sensitive payloads.

Cancelled actions are not treated as failures.

## Responsiveness

Tray/list callbacks queue action dispatch with a one-shot timer so GUI callbacks return before dispatch begins. F07 performs no background polling or duplicate feature work. The action registry itself is synchronous, so an inherently long in-process feature action can still serialize the resident AHK thread; F07 adds no avoidable blocking on top of that contract.

## Lifecycle

F07 is disabled by default. When enabled it registers:

- `control.show` (S0)
- `control.refresh` (S0)
- `control.reload_configuration` (S1)
- `control.emergency_disable` (S2)

Teardown unregisters those actions, unsubscribes the result observer and destroys the compact GUI. If F07 is disabled/unavailable, AHQuiver falls back to the minimal core tray rather than failing startup.

Emergency disable calls `AQModuleHost.StopAll()`, then returns the tray to minimal mode. Configuration reload can subsequently re-enable whatever the config declares.

## Configuration

```ini
[F07]
history_limit=10
action_menu=1
```

`history_limit` controls the number of payload-free recent failures retained in memory. `action_menu=0` removes the dynamic tray submenu while retaining the compact panel.

## Verification

- `tests/F07TestRunner.ahk` uses fake action/module/capability registries to prove dynamic population, late-added/removed actions, generic parameter dispatch through the same action ID, state representation, payload-free global failure observation, history limiting and module lifecycle.
- `tests/F07GuiSmoke.ahk` creates the real tray/GUI on Windows, verifies action/module/capability rows, adds an action after panel creation and confirms it appears after refresh, verifies parameter dispatch, verifies safe failure history, and destroys the UI cleanly.
- `tests/F07EnabledStartup.ini` exercises enabled-module lifecycle through the resident host.
