# F02 Windows Terminal manual smoke evidence

This file is intentionally an evidence template until a real packaged Windows Terminal desktop is available to the executor. GitHub Actions currently provides Windows Server GUI/process coverage but must not be represented as a substitute for Windows Terminal tab-level visual verification.

Environment: Windows version; AutoHotkey version; Windows Terminal version

Scenario:
- enable F02 in local `config/ahquiver.ini`;
- configure a distinctive Windows Terminal preset identity/title/window_name;
- invoke `terminal.launch_preset`;
- inspect the tab title and named-window behavior;
- invoke the same sticky singleton preset again;
- release the identity and invoke again.

Expected:
- tab shows the configured title;
- application title changes do not immediately overwrite it because `--suppressApplicationTitle` is requested;
- named window is used/created as configured;
- second AHQuiver launch is rejected while sticky identity is active;
- launch succeeds after `terminal.release_identity`.

Observed: PENDING REAL WINDOWS TERMINAL DESKTOP

Safety check:
- no process is force-terminated;
- no machine-specific path is required;
- failure to find/launch `wt.exe` is reported as launch failure rather than fabricated capability success.

Result: PENDING
