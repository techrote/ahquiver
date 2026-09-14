# F05 — Safe multiline command paste

## Purpose

F05 removes ambiguity around terminal command blocks by making delivery semantics explicit. It does **not** parse, validate, repair, or rewrite shell syntax.

## Actions

- `terminal.multiline_inspect` — return structural clipboard metadata only.
- `terminal.multiline_paste` — use `params.mode` or `F05.default_mode`.
- `terminal.multiline_paste_whole` — paste the clipboard as one literal block.
- `terminal.multiline_paste_lines` — send each logical line followed by Enter.
- `terminal.multiline_paste_confirm_each` — confirm before each line.
- `terminal.multiline_paste_cancel` — return a structured cancellation without sending.

## Classification

Classification is intentionally conservative. F05 records line count, CR/LF normalization for classification only, trailing newline, blank lines, blocked control characters, obvious continuation-like line endings, and optional user regex matches. The original clipboard text is preserved for whole-block delivery.

No command text is logged or returned in structured results.

## Targeting and safety

The foreground window is captured as the terminal target at action start. By default only Windows Terminal/conhost-classified targets are accepted. `allow_unknown_terminal=1` is an explicit escape hatch.

Before whole-block delivery and before every line in line modes, F05 revalidates HWND/PID/executable/class and verifies that the same target remains foreground. If focus changes, remaining delivery is rejected.

The complete clipboard is wrapped by `AQClipboardGuard`, including failure/cancellation paths.

## Configuration

```ini
[F05]
default_mode=cancel
inter_line_delay_ms=100
allow_unknown_terminal=0
allow_control_chars=0
whole_hotkey=
lines_hotkey=
confirm_hotkey=
pattern_count=0
```

Optional regexes use numbered keys (`pattern1`, `pattern2`, ...). Invalid regex configuration fails only F05 initialization through the module-host isolation contract.

## Verification

`tests/F05TestRunner.ahk` covers LF/CRLF, blank lines, trailing newline, continuation-like content, line preservation, confirm-each cancellation, empty/non-text clipboard behaviour, stale targets, control characters, restore-on-failure, invalid regex configuration, and module lifecycle.

Manual Windows Terminal/PowerShell smoke should use harmless commands and exercise `whole`, `line_by_line`, `confirm_each`, and `cancel`, recording Windows Terminal/PowerShell/AHK versions. Automated CI does not claim semantic correctness of arbitrary shell commands.
