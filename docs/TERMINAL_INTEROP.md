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

## F04 background paste research order

Evaluate in this order and record reproducible evidence:

1. AHK `ControlSend` / `ControlSendText` against the target HWND/control.
2. Window/control messages where the terminal genuinely exposes a compatible control.
3. Documented terminal/application automation interfaces, if present.
4. A separately named degraded mode that performs a very brief activation/send/restore cycle.

A degraded focus-handoff mode is not equivalent to true background paste and must never be labelled as such.

The implementation must verify target identity immediately before sending. If success cannot be observed reliably, report `unsupported` or `unknown`; do not return a false success solely because an API call did not throw.

## Gesture semantics for F04

The motivating interaction is: identify/left-click a terminal target and immediately paste to it without visually drawing focus away from the user's current work. Exact gesture design may evolve, but targeting must be explicit and race-resistant. A click used purely as target selection should not accidentally activate unrelated controls or execute terminal content.

## F03 Ctrl+C semantics

`Ctrl+C` is overloaded:

- terminal interrupt when no copy-selection handling applies;
- copy in many GUI/terminal selection contexts;
- ordinary application copy outside terminals.

Therefore the guard must be scoped by adapter/context and must support bypass/pass-through. Never globally convert Ctrl+C into a confirmation workflow by default.

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
