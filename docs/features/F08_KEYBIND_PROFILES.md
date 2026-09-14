# F08 — External keybind and context-profile layer

Status: implemented, disabled by default.

F08 maps externally configured AutoHotkey chords to the existing AHQuiver action registry. It does not implement feature behavior itself: a binding always resolves to an action ID already registered by the host/modules.

## Configuration model

`[F08]` defines comma-separated `profiles` and `bindings`, plus an optional `bypass_hotkey`.

Profiles live in `[F08.profile.<id>]` and may constrain foreground `exe`, window `class`, and AHQuiver `identity`. A numeric `priority` decides between multiple automatically matching profiles. Empty constraints mean the profile matches broadly.

Bindings live in `[F08.binding.<id>]` with:

- `hotkey`: AutoHotkey v2 chord;
- `action`: registered AHQuiver action ID;
- optional `profile`;
- optional direct `exe`, `class`, or `identity` constraints;
- numeric `priority`;
- optional numbered parameters `paramN_key` / `paramN_value`.

Malformed bindings are skipped locally and exposed through F08 diagnostics. Unknown action IDs are invalid and are not registered.

## Resolution and precedence

F08 registers one callback per distinct physical hotkey and resolves the active binding when the key is pressed.

Precedence is:

1. explicit profile selected with `keybind.profile.set`;
2. highest-priority foreground-matching profile;
3. global bindings with no profile.

Within a tier, binding `priority` wins. Exact static duplicates (same hotkey/profile/context/priority) are resolved deterministically by binding ID; the lexicographically first binding remains active and the loser is recorded as a conflict diagnostic.

Foreground matching uses `AQContextService`. Project identity is enriched from `AQIdentityRegistry` by PID; F08 does not duplicate title/window probing.

## Registered actions

- `keybind.profile.set` (`profile=<id>`)
- `keybind.profile.clear`
- `keybind.bypass.set` (`enabled=0|1`)
- `keybind.status`

These automatically appear in F07 when F07 is enabled.

## Emergency bypass and lifecycle

The optional `bypass_hotkey` toggles an in-memory emergency bypass. While bypassed, F08 handlers return `cancelled` without invoking actions.

Configuration reload uses the normal `AQModuleHost.Reload()` path: F08 tears down every hotkey and action it registered, then rebuilds from the new INI. Teardown leaves no F08 hotkeys active.

## Module-specific hotkeys

F08 is additive. If the user wants F08 to own a physical key already used by a module-specific binding, leave that module's native hotkey empty and bind the module's registered action through F08. This avoids hidden callback replacement and keeps ownership explicit/reversible on reload.

## Verification

`tests/F08TestRunner.ahk` covers parsing/parameters, deterministic conflicts, profile precedence, context transitions, invalid action isolation, bypass, identity context, reload/teardown, and same-hotkey/different-profile dispatch.

`tests/F08EnabledStartup.ini` is used by Windows CI to prove an enabled F08 instance can register and tear down a real AutoHotkey hotkey without destabilizing host startup.
