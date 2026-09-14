# F07 manual control-surface smoke

Record Windows version, AutoHotkey version, AHQuiver commit and enabled module set.

Enable F07 plus several implemented feature modules that are safe for the local machine. Suggested mix: F01, F02, F04/F05 and F06 with a harmless tracker preset.

## Tray

1. Confirm the tray shows **Open AHQuiver control panel**, a dynamic **Actions** submenu, reload, emergency disable and exit.
2. Confirm enabled modules' registered actions appear without F07-specific configuration.
3. Disable one module in config and reload. Confirm its actions disappear and the Modules tab reports it disabled.
4. Trigger a no-parameter S0/S1 action from the tray and confirm it follows the same behavior/result as invoking that action through another surface.
5. Select an action requiring parameters from the tray; an invalid empty invocation should open the panel so generic `key=value` parameters can be entered.
6. Confirm an S2 action receives F07's generic confirmation and still retains the feature's own safety checks.

## Compact panel

1. Actions tab lists ID, risk and description.
2. Enter valid generic parameters (for example `preset=<local preset>`) and run a selected action.
3. Modules tab visibly distinguishes enabled, disabled and failed state if a disposable intentionally failing module/config is available.
4. Capabilities tab shows supported plus unknown/degraded/unsupported records when those states exist.
5. Cause a harmless action rejection/failure and confirm the Failures tab contains only action ID, status and generic summary — no command text, clipboard contents, supplied parameters or result payload.
6. Register/enable a later module, reload and verify its actions appear without an F07 code change.

## Emergency path

Use **Emergency disable** and confirm all feature modules stop for the current session and the UI falls back to the minimal tray. Reload configuration to restore configured modules, or exit AHQuiver.

No screenshots are required for automated acceptance; if documenting a local desktop run, screenshots should avoid terminals containing secrets or private command output.
