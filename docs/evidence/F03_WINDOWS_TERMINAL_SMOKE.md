# F03 Windows Terminal manual smoke evidence

This is the reproducible real-desktop acceptance procedure for F03. Do not replace it with CI claims: GitHub-hosted Windows runners exercise the policy engine and dynamic hotkey lifecycle, but they do not constitute human observation of a Windows Terminal interaction.

## Record before running

- Windows version:
- AutoHotkey version:
- Windows Terminal version:
- AHQuiver commit:
- F03 rule/policy under test:

## Setup

1. Copy `config/ahquiver.example.ini` to `config/ahquiver.ini`.
2. Set `[modules] F03=1`.
3. Keep the default Windows Terminal `double_tap` rule (`450 ms`) or record any deliberate variation above.
4. Launch AHQuiver.
5. Open Windows Terminal and run a harmless long-running command such as `ping.exe 127.0.0.1 -t`.

## Assertions

### Accidental single chord

Press `Ctrl+C` once.

Expected:
- the first press is blocked by the guard;
- the terminal command continues;
- configured non-blocking feedback may appear;
- no terminal content is logged.

### Intentional interrupt

Press `Ctrl+C` twice within the configured interval.

Expected:
- the second press delivers the interrupt;
- the running command stops normally;
- no modifier remains stuck.

### Immediate bypass

Restart the harmless long-running command and press the configured bypass hotkey (`Ctrl+Shift+C` in the example config).

Expected:
- the underlying `Ctrl+C` is delivered immediately;
- the command stops without requiring a double tap.

### Runtime disable

Restart the command, press the configured toggle (`Ctrl+Alt+C`), then press `Ctrl+C` once.

Expected:
- the guard is disabled immediately;
- `Ctrl+C` behaves natively until the guard is re-enabled;
- applications outside Windows Terminal continue to receive ordinary `Ctrl+C` semantics.

### Foreground race sanity check

Trigger the first guarded press, switch focus to another application, and avoid completing the double tap.

Expected:
- F03 never sends a delayed interrupt to the newly focused application;
- any guarded delivery whose foreground identity changes between detection and send is rejected.

## Result

- [ ] pass
- [ ] fail
- Notes:
