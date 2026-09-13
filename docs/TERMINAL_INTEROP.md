# Terminal interoperability

This document governs features F02, F03, F04, F05 and F10.

## Capability model

A terminal adapter must report capabilities independently. Do not infer one capability from another.

Suggested flags:

- `can_identify_window`
- `can_set_title`
- `can_background_send_text`
- `can_background_paste`
- `can_detect_selection`
- `can_capture_selection`
- `can_restore_foreground`
- `can_map_rendered_selection_to_source`

Capabilities may be `supported`, `unsupported`, `degraded`, or `unknown`, with a diagnostic reason.

## Adapter targets

Initial adapters should distinguish at least:

1. Windows Terminal (`WindowsTerminal.exe` / XAML-hosted terminal surface).
2. Classic console/conhost where relevant.
3. Generic GUI terminal fallback with only conservative window/process features.

Do not promise tab-level identity/control when only a top-level HWND is observable.

## F02 terminal identity and titles

F02 separates AHQuiver-owned launch identity from visible terminal title state.

- `AQIdentityRegistry` stores preset, identity, role, PID/lifecycle and terminal metadata without rediscovering it from a title substring.
- Windows Terminal presets use documented `wt.exe` launch arguments for named-window routing, `new-tab`, `--title`, `--suppressApplicationTitle`, profile and working directory.
- A `wt.exe` launcher PID is not treated as the durable Terminal session identity because the launcher can hand work to an existing process and exit.
- Windows Terminal singleton presets therefore default to an AHQuiver `sticky` identity record; PID singletons remain available for ordinary persistent processes.
- Generic `title_mode=window` retitles only a revalidated visible HWND attributable to the launched PID. It is `supported` only when the resulting title is verified, `degraded` if the request cannot be verified, and unknown/unsupported when no safe HWND can be attributed.
- `icon`/`shortcut` are metadata only in F02. No arbitrary live taskbar-icon capability is claimed.

See `features/F02_TERMINAL_IDENTITY.md` for the concrete preset/action contract.

## F04 background paste capability

F04 implements the research order conservatively rather than treating API success as delivery proof.

1. A standard Win32 `Edit` adapter uses `ControlSend("^v")` addressed directly to the control HWND.
2. A built-in self-probe places a unique temporary clipboard token, performs the send, reads back the exact Edit text and verifies that foreground HWND did not change. Only then is `terminal.standard_edit.can_background_paste` marked `supported`.
3. Windows Terminal and conhost remain `unknown` because the current implementation has no reliable readback oracle for actual terminal input. AHQuiver does not mark them supported merely because `ControlSend` returned without error.
4. The separately named `terminal.paste_focus_handoff` path activates the target, sends normally and restores the original foreground. It records `degraded` and is never represented as true background paste.

A captured F04 target contains top-level HWND/PID/executable/class, terminal classification, optional child-control HWND, adapter and capture time. The top-level target and control PID are revalidated immediately before either delivery path. Expired or stale targets are rejected.

Supplying explicit `text` to a paste action uses `AQClipboardGuard`, so the previous complete clipboard state is restored even on failure. Existing clipboard paste does not mutate clipboard state.

See `features/F04_FOCUS_PRESERVING_PASTE.md` and `evidence/F04_WINDOWS_TERMINAL_PROBE.md`.

## Gesture semantics for F04

The motivating interaction is: identify/left-click a terminal target and immediately paste to it without visually drawing focus away from the user's current work. F04 provides `terminal.paste_target_capture_mouse`, which records the window/control under the pointer without activating it, plus separate paste actions. No global left-click interception is enabled by default.

## F03 Ctrl+C semantics

`Ctrl+C` is overloaded:

- terminal interrupt when no copy-selection handling applies;
- copy in many GUI/terminal selection contexts;
- ordinary application copy outside terminals.

F03 therefore uses ordered, explicit context rules and never assumes `Ctrl+C` means interrupt globally. The module itself is disabled by default. When enabled:

- a non-matching foreground context receives the original chord unchanged;
- a matching rule can use `pass_through`, `double_tap`, `hold`, `confirm`, or `remap`;
- the target HWND/PID/executable/class is captured again immediately before any guarded delivery;
- a changed foreground target rejects the delayed/guarded chord rather than sending it to the new application;
- `terminal.guard_disable` and the configured toggle can disable the main guard hotkey immediately without restarting AHQuiver;
- a bypass hotkey and one-shot bypass action preserve an intentional interrupt path.

Selection-aware copy bypass is evidence-gated. F03 checks `terminal.<kind>.can_detect_selection`; unless the capability is `supported`, it never queries a selection adapter or infers selection from title/state heuristics. Windows Terminal remains `unknown` by default for this capability.

F03 decision logs contain only rule/policy/outcome plus terminal/executable/PID metadata. Terminal content and titles are excluded.

See `features/F03_TERMINAL_KEY_GUARD.md` for the concrete policy/config contract.

## F05 multiline paste

Do not parse shell syntax as if AHQuiver were a shell. Classification should remain conservative: line count, trailing continuations where obvious, control characters, and user-configured patterns. Modes control *delivery*, not command rewriting.

## F10 rendered selection to source

A terminal displays rendered cells, not necessarily a reversible representation of source text. ANSI escape sequences, wrapping, tabs, combining glyphs, generated output and renderer transforms break naive coordinate reversal.

Accordingly F10 requires a cooperating producer/source-map contract, for example:

```text
render_session_id
source_document_id
cell/range -> source byte/character range mapping
source version/hash
```

The edit must be rejected if the source version no longer matches the mapping. Generic terminal text capture alone is insufficient to enable deletion.
