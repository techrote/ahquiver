# Feature catalog

The initial programme consists of 13 modules. Priority estimates reflect expected usefulness/use count, not implementation difficulty.

| ID | Feature | Priority | Expected architecture | Primary risk |
|---|---|---:|---|---|
| F01 | Close matching windows | 1 | Pure AHK action + window query | Closing unintended windows |
| F02 | Terminal identity / project launcher | 2 | AHK UI/action + shortcuts/process launch | Stable identity across terminal processes/tabs |
| F03 | Safe terminal key guard | 3 | Context-sensitive AHK hotkey interception | Blocking legitimate Ctrl+C/copy/interrupt |
| F04 | Paste without visibly drawing focus | 4 | TERM capability adapter; AHK first | Windows Terminal may reject true background input |
| F05 | Safe multiline command paste | 5 | Clipboard parser + terminal action/UI | Shell syntax/continuations and accidental execution |
| F06 | Tracker restart / relaunch | 6 | Process/action wrapper | Killing wrong worker/process |
| F07 | Unified project/control tray | 7 | UI over action registry | UI/business-logic duplication |
| F08 | External keybind/profile layer | 8 | CFG + context-sensitive bindings | Hotkey collisions / overbroad hooks |
| F09 | Hardware macro/event daemon | 9 | IPC/device adapter -> action registry | Untrusted arbitrary command execution |
| F10 | Terminal rendered-selection -> source delete | 10 | Experimental TERM/UIA + source-map contract | Generic terminal cannot infer source mapping reliably |
| F11 | Cross-app quota counter overlay | 11 | Observation adapters + local ledger/UI | No authoritative server quota source |
| F12 | PlasmaTerm randomise/profile shortcuts | 12 | Action wrapper around existing generator/control endpoints | Coupling to external project paths/interfaces |
| F13 | PlasmaTerm BPM/drift controller | 13 | Timers/state machine + external control adapter | Timing drift / AHK being wrong compute layer |

## F01 — Close matching windows

Goal: one action/hotkey closes visible windows matching the current window's configured grouping rule, useful when ungrouped taskbar buttons make Windows' built-in group close unavailable.

Requirements:
- group by executable by default, with configurable class/title refinements and exclusions;
- enumerate candidates before acting;
- use normal close semantics first (`WinClose`/WM_CLOSE), not process kill;
- protect shell/critical windows and support per-app exclusions;
- optional preview/confirmation mode;
- report count closed/failed/skipped.

## F02 — Terminal identity / project launcher

Goal: reduce confusion among many terminal/TUI windows by assigning durable human-readable identity and providing project/role launch presets.

Requirements:
- launch named terminal/project/role presets;
- set/maintain useful window titles where the terminal permits it;
- expose identity in tray/control UI;
- support working directory, command/profile and optional shortcut/icon metadata;
- do not rely only on volatile window-title substring matching;
- degrade/document icon limitations rather than claiming arbitrary taskbar icon control universally.

## F03 — Safe terminal key guard

Goal: prevent accidental destructive terminal chords, especially `Ctrl+C` interruptions caused by intending `Ctrl+X` or copy.

Requirements:
- terminal/context scoped, never globally swallow Ctrl+C by default;
- configurable policies: pass-through, double-tap, hold threshold, confirm, remap;
- distinguish known copy selection contexts when feasible;
- immediate escape/bypass mechanism;
- low latency and explicit visual/audio/tray feedback configurable off.

## F04 — Paste without visibly drawing focus

Goal: support a gesture such as left-click/target selection followed by immediate paste into a terminal without visibly moving/drawing focus to that terminal, where Windows/terminal capabilities permit.

Requirements:
- test real background techniques (`ControlSend`, control messages, supported APIs) per terminal adapter;
- never fabricate success; verify/return unsupported when injection cannot be confirmed;
- preserve the user's current foreground window when true background input works;
- if a brief focus handoff fallback is implemented, it must be separately named/configured and documented as not true background paste;
- target selection must be explicit enough to avoid pasting into the wrong terminal.

## F05 — Safe multiline command paste

Goal: make terminal clipboard blocks safer and more predictable.

Requirements:
- inspect clipboard text without destroying original clipboard state;
- modes: literal/whole block, line-by-line, confirm-each, and cancel;
- normalize line endings safely;
- identify obviously multi-line content and high-risk paste shapes;
- configurable terminal/shell profiles and delays;
- never silently rewrite shell syntax.

## F06 — Tracker restart / relaunch

Goal: restart a specific progress/audit tracker without disturbing its underlying worker.

Requirements:
- presets identify tracker process by executable + command-line/pid metadata, not title alone;
- graceful terminate first, force only when explicitly allowed;
- relaunch with configured command/working directory/arguments;
- optionally restore identity/position;
- evidence that worker processes survive tracker restart.

## F07 — Unified project/control tray

Goal: make frequent AHQuiver actions accessible from one resident tray/compact GUI.

Requirements:
- enumerate registered actions/modules dynamically;
- quick access to project launches, identities, tracker restart, close-matching, paste safety and status;
- enable/disable modules and reload configuration;
- surface unsupported capabilities and recent failures;
- no duplicate implementation of action behaviour inside UI callbacks.

## F08 — External keybind/profile layer

Goal: externalize context-sensitive bindings and profiles so remaps do not require source edits.

Requirements:
- bind action IDs to configurable hotkeys;
- profile activation by explicit selection and optional foreground context;
- conflict detection with deterministic precedence;
- hot reload or controlled reload;
- configuration errors must fail locally rather than disabling unrelated bindings.

## F09 — Hardware macro/event daemon

Goal: map trusted hardware/controller events (for example ESP32 buttons/encoders) to AHQuiver actions.

Requirements:
- one documented local transport with a small event schema;
- allowlist action IDs and validate parameters;
- no arbitrary shell command execution from network/device payloads by default;
- debouncing/rate limiting;
- connection/event diagnostics;
- test harness capable of injecting synthetic events without hardware.

## F10 — Terminal rendered-selection -> source delete

Goal: experimental bridge allowing a rendered ANSI/ASCII selection to identify and delete corresponding source content where a cooperating source renderer can provide a mapping.

Requirements:
- explicit source-map/adapter contract; do not infer arbitrary source positions from terminal glyphs alone;
- prototype selection acquisition for supported terminal(s), likely UI Automation/clipboard-assisted;
- transactional edit with preview/undo or backup;
- unsupported unless both selection capture and source mapping are available;
- keep experimental and isolated from core startup.

## F11 — Cross-app quota counter overlay

Goal: maintain a single local usage estimate across selected desktop/browser surfaces.

Requirements:
- observation adapters for configured applications/actions;
- local append-only or reconstructable usage ledger;
- tray/overlay view with session/day totals;
- explicit distinction between locally observed estimate and authoritative provider quota;
- manual correction/reset controls;
- no scraping/automation that violates service boundaries; observation must be local and configurable.

## F12 — PlasmaTerm randomise/profile shortcuts

Goal: provide convenient AHK shortcuts for randomisation/profile/seed controls in an external PlasmaTerm workflow.

Requirements:
- configure external command/API paths rather than hard-code machine paths;
- named actions for randomise, profile selection, seed cycling and timed demo cycling;
- guard against launching duplicate uncontrolled controller instances;
- surface external-command failures clearly;
- include a fake/simulated adapter for automated tests.

## F13 — PlasmaTerm BPM/drift controller

Goal: provide a desktop control layer for BPM-synchronised parameter oscillation and slow configurable drift/fades.

Requirements:
- explicit clock/state model and start/stop/reset actions;
- allow speed/sign crossing where configured;
- expose bounds, period/BPM, phase and interpolation controls;
- measure timing drift and avoid blocking hotkey responsiveness;
- if profiling demonstrates AHK is unsuitable for high-rate computation, keep AHK as UI/orchestrator and move only the timing/math engine to a small justified helper.
