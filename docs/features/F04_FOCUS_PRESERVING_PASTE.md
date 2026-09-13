# F04 — Focus-preserving paste capability and degraded fallback

Status: implemented by issue #5.

## Purpose

F04 separates **target selection** from **paste delivery** so a window/control can be identified under the pointer without activating it, then used by a later paste action.

The motivating gesture is the user's proposed “point/click at a terminal and immediately paste without drawing focus”. F04 supplies the target/action primitives without globally hijacking left-click by default.

## Actions

- `terminal.paste_target_capture_mouse` — capture top-level HWND plus control HWND under the pointer without activating it.
- `terminal.paste_target_set` — explicitly set `hwnd` and optional `control_hwnd`.
- `terminal.paste_target_clear`
- `terminal.paste_target_status`
- `terminal.paste_probe` — run capability probes.
- `terminal.paste_background` — true focus-preserving path; runs **only** for a verified supported adapter.
- `terminal.paste_focus_handoff` — separately named degraded activate/send/restore fallback.

## Capability truth

`terminal.<kind>.can_background_paste` uses the normal AHQuiver capability states.

Current evidence:

- `standard_edit`: can become `supported` after the built-in self-probe verifies `ControlSend Ctrl+V`, content readback, foreground preservation and clipboard restoration on the current machine.
- `windowsterminal`: `unknown` by default. AHQuiver does not infer successful paste because `ControlSend` returned without error.
- `conhost`: `unknown` until a reliable content/readback probe exists.
- arbitrary windows: `unknown`.

Therefore `terminal.paste_background` refuses Windows Terminal rather than fabricating success. This is a deliberate acceptance of the issue's truthful `unsupported/unknown` outcome.

## Standard Edit verified adapter

The built-in probe creates a temporary standard Win32 Edit control, records the current foreground HWND, temporarily places a unique token on the clipboard through `AQClipboardGuard`, sends `Ctrl+V` directly to the Edit control HWND using `ControlSend`, reads back the control text, verifies the exact expected content, verifies foreground did not change, then restores the original clipboard.

The production standard-Edit path repeats readback verification for each paste. It currently limits verified mode to single-line text because multiline Edit normalization complicates exact transactional readback.

## Target safety

A captured target stores HWND, PID, executable, class, terminal classification, optional control HWND, adapter and capture timestamp. Immediately before either delivery path:

- the top-level HWND is revalidated through `AQWindowQuery.StillMatches`;
- the child control, when present, must still belong to the same PID;
- expired targets are rejected according to `target_max_age_ms`.

## Clipboard semantics

Using the existing clipboard requires no clipboard mutation. Supplying action parameter `text` uses `AQClipboardGuard`; the prior full clipboard state is restored in `finally`, including failure paths.

## Degraded focus handoff

`terminal.paste_focus_handoff` is not true background paste and is disabled by default (`allow_focus_handoff=0`). When enabled it:

1. captures the current foreground HWND;
2. revalidates and activates the target;
3. optionally focuses the captured child control;
4. sends `Ctrl+V` normally;
5. restores and verifies the original foreground HWND.

Successful use records `terminal.<kind>.focus_handoff_paste=degraded` and returns `mode=focus_handoff` / `capability_status=degraded`.

## Default configuration

F04 itself is disabled by default. No capture or paste hotkeys are assigned. This avoids claiming a global left-click gesture or stealing focus until the user deliberately configures the workflow.

## Verification

- deterministic tests cover unsupported Windows Terminal behavior, stale targets, fallback disabled state, explicit degraded fallback/restoration, capability truth states and module lifecycle;
- `tests/F04RealPasteSmoke.ahk` is a rerunnable Windows capability probe proving real standard-Edit background paste, foreground preservation, degraded fallback restoration and clipboard restoration;
- `docs/evidence/F04_WINDOWS_TERMINAL_PROBE.md` records the real Windows Terminal probe procedure and explicitly requires version + before/after foreground evidence.
