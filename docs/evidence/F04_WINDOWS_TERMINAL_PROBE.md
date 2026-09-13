# F04 Windows Terminal focus-preserving paste probe

This procedure records real-desktop evidence for Windows Terminal. CI can prove AHQuiver's generic control mechanism and fallback behavior, but **must not** convert Windows Terminal to `supported` without observable delivery evidence.

## Record environment

- Windows version:
- AutoHotkey version:
- Windows Terminal version:
- AHQuiver commit:
- terminal profile/shell:
- foreground HWND before probe:
- target Windows Terminal HWND/PID/class:

## True background probe

1. Enable F04 but leave `allow_focus_handoff=0`.
2. Open Windows Terminal at a harmless prompt and a second ordinary application that remains foreground.
3. Capture the Windows Terminal target using `terminal.paste_target_capture_mouse` or explicit `terminal.paste_target_set` without activating it.
4. Run `terminal.paste_probe` and record the returned `terminal.windowsterminal.can_background_paste` capability.
5. Invoke `terminal.paste_background` with an unmistakable harmless text token.
6. Record foreground HWND immediately afterward and inspect the terminal for actual delivered text.

Expected with the current implementation:
- capability remains `unknown` because AHQuiver has no reliable Windows Terminal readback oracle;
- `terminal.paste_background` returns `unsupported` and sends nothing;
- foreground does not change.

Do **not** mark Windows Terminal supported merely because a low-level send API returned without throwing.

## Degraded focus-handoff probe

1. Set `allow_focus_handoff=1`.
2. Keep another application foreground and capture its HWND.
3. Capture Windows Terminal as the F04 target.
4. Invoke `terminal.paste_focus_handoff` with harmless text.
5. Observe that Windows Terminal briefly receives focus/paste and that the original application becomes foreground again.
6. Record the before/after foreground HWNDs and whether paste content arrived correctly.

Expected:
- action reports `mode=focus_handoff`;
- capability is recorded as `degraded`, never `supported` background paste;
- original foreground HWND is restored.

## Result

True background Windows Terminal:
- [ ] supported with reproducible readback evidence
- [ ] unknown / unsupported as expected

Degraded focus handoff:
- [ ] pass
- [ ] fail

Notes/evidence:
