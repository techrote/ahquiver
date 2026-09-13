# F03 — Context-sensitive terminal key guard

Status: implemented by issue #4.

## Purpose

F03 protects high-impact terminal chords such as `Ctrl+C` from accidental activation without globally changing ordinary copy or interrupt semantics.

The module is disabled by default. When enabled, the configured guard hotkey is intercepted only long enough to evaluate the current context. If no configured rule matches, the original chord is delivered unchanged. A matching terminal rule may apply one of five policies.

## Policies

- `pass_through` — deliver the original chord after foreground revalidation.
- `double_tap` — block the first press, then deliver if the second press arrives within `double_tap_ms`.
- `hold` — deliver only when the physical key remains held for at least `hold_ms`.
- `confirm` — ask for explicit confirmation before delivery.
- `remap` — deliver `remap_chord` instead of the guarded chord.

Rules are evaluated in `F03.rules` order and may narrow by terminal kind, executable, window class, title substring, and PID-attributable F02 identity/role metadata.

## Safety model

- F03 is disabled unless `[modules] F03=1`.
- The main dynamic hotkey uses the AHK `$` prefix so synthetic delivery does not recursively re-trigger the guard.
- Outside matching rules, the original chord is passed through.
- Immediately before a guarded delivery, F03 captures the foreground context again and requires HWND/PID/executable/class to match the context that triggered the decision.
- A foreground change rejects the delivery instead of sending the chord to the newly focused application.
- Runtime disable turns the main guard hotkey off immediately; Windows receives the original chord natively until re-enabled.
- One-shot bypass and a dedicated bypass hotkey remain available for intentional interrupts.
- Decision logging contains rule/policy/outcome/terminal/executable/PID only. Terminal text and titles are not logged.

## Selection-aware copy

F03 does **not** guess whether Windows Terminal currently has a selection. `selection_copy_passthrough=1` is honored only when the relevant terminal adapter has registered `terminal.<kind>.can_detect_selection=supported`. With `unknown`, `degraded`, or `unsupported`, the selection probe is not called.

The default Windows Terminal capability remains `unknown` because no reliable generic detector has yet been proven in AHQuiver.

## Actions

- `terminal.guard_status`
- `terminal.guard_bypass_once`
- `terminal.guard_enable`
- `terminal.guard_disable`
- `terminal.guard_toggle`

These actions allow F07 or future IPC/hardware adapters to control the guard without importing F03 internals.

## Default example

The checked-in example config uses:

- guard chord: `Ctrl+C`
- Windows Terminal policy: `double_tap`
- interval: 450 ms
- bypass hotkey: `Ctrl+Shift+C`
- toggle hotkey: `Ctrl+Alt+C`

Because F03 itself is disabled by default, these hotkeys are inert until explicitly enabled.

## Verification

Automated coverage includes:

- rule/config validation and F02 role matching;
- ordinary non-terminal Ctrl+C pass-through;
- pass-through, double-tap, hold, confirm, and remap policies;
- exact double-tap timing boundary and expiry;
- one-shot bypass and instant runtime disable;
- selection capability gating;
- stale/changed foreground rejection;
- disabled/enabled module lifecycle;
- resident-host startup with the real dynamic hotkeys installed and torn down.

See `docs/evidence/F03_WINDOWS_TERMINAL_SMOKE.md` for the real-desktop smoke procedure.
