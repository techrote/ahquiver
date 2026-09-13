# F02 — Terminal identity and project/role launcher

Status: implemented behind `[modules] F02=1`.

F02 launches named project/role presets and records durable AHQuiver-owned identity metadata independently of volatile window-title matching.

## Actions

- `terminal.launch_preset` — S1. Parameter: `preset`.
- `terminal.list_presets` — S0. Returns configured preset summaries.
- `terminal.list_identities` — S0. Returns AHQuiver-owned launch records, including inactive history.
- `terminal.release_identity` — S1. Parameter: `preset`. Releases active sticky/singleton records without killing a process.

F07 and other UI layers should consume these actions and `app.Identities`; they must not import F02 internals.

## Preset configuration

`[F02] presets=` is an explicit comma-separated allowlist of preset IDs. Each preset uses `[F02.preset.<id>]`.

Common keys:

- `kind=process|windows_terminal`
- `identity=` required conceptually; defaults to the preset ID
- `role=` optional human/agent role label
- `program=` executable/command name; Windows Terminal defaults to `wt.exe`
- `working_dir=` relative paths resolve from the AHQuiver repository root
- `title=` defaults to identity
- `title_mode=none|window|cli`
- `singleton=0|1`
- `singleton_mode=pid|sticky`
- `arg_count=N`, followed by `arg1=...` through `argN=...`
- `icon=` and `shortcut=` optional metadata for future helper/integration work

Arguments are stored as numbered tokens rather than a shell command string. `AQProcess` quotes each token independently using Windows command-line escaping, including embedded quotes and trailing backslashes before a closing quote.

## Windows Terminal presets

For `kind=windows_terminal`, AHQuiver builds a `wt.exe` invocation from structured fields. With all optional identity fields populated, the shape is:

```text
wt.exe -w <window_name> new-tab --profile <profile> --title <title> --suppressApplicationTitle -d <working_dir> [commandline args...]
```

Microsoft documents `-w/--window` named-window routing, `new-tab --title`, `-d`, and `--suppressApplicationTitle`. Suppressing application title changes is important when the configured identity should persist.

Reference: https://learn.microsoft.com/windows/terminal/command-line-arguments

AHQuiver records `terminal.windowsterminal.can_set_title=supported` when it successfully launches a Windows Terminal preset that requests the documented CLI title mechanism. This is a launch-time capability statement; it is not a claim that AHQuiver has generic tab-level UI Automation control.

### Singleton semantics

Windows Terminal launch aliases commonly hand work to an existing terminal process and then exit. PID-only singleton tracking is therefore insufficient for a durable WT destination.

For that reason:

- a WT preset with `singleton=1` defaults to `singleton_mode=sticky`;
- a sticky identity rejects another AHQuiver launch until `terminal.release_identity` is called;
- `window_name` lets repeated external `wt -w <name>` calls route to a stable named Terminal window, but AHQuiver still treats its own sticky identity record as the duplicate-launch guard.

## Generic process presets

`kind=process` launches the configured program directly. `singleton_mode=pid` rejects duplicates while the tracked PID is alive, then automatically retires the stale record after the process exits.

`title_mode=window` is best-effort. AHQuiver waits briefly for a visible top-level HWND owned by the launched PID, revalidates it, requests `WinSetTitle`, and records capability as:

- `supported` when the resulting title is verified;
- `degraded` when the request succeeds but the observed title differs;
- `unknown`/`unsupported` when no attributable HWND or usable target exists.

Console and terminal hosts can use a different process as the top-level window owner, so `title_mode=none` is the portable generic default.

## Identity records

`AQIdentityRegistry` is a core service. Each launch record has a stable AHQuiver record ID plus:

- preset ID;
- identity;
- role;
- launched PID when available;
- state (`active`/`inactive`);
- creation tick;
- kind/program/title/terminal/window-name metadata.

This metadata is deliberately more durable and machine-readable than title substring matching. It is also the integration surface for F07.

## Taskbar icons and shortcuts

F02 stores optional `icon` and `shortcut` metadata but does not claim arbitrary live taskbar-icon mutation. Windows taskbar identity can depend on application shortcuts, package identity, AppUserModelID, and the hosting terminal process. A future helper may use preset metadata to create controlled shortcuts or other Windows-native identity plumbing, but unsupported icon behavior must remain explicit.

## Verification

Automated coverage includes:

- preset parsing and invalid lookup;
- two independently launched project/role identities;
- PID singleton retirement/relaunch;
- sticky Windows Terminal singleton/release;
- exact structured WT argument construction;
- unsupported title capability remaining non-fatal to a successful launch;
- capability registration;
- Windows command-line quoting edge cases;
- module enable/disable/action teardown;
- a real child AutoHotkey process whose top-level HWND is discovered by PID, retitled, recorded, duplicate-guarded, and then normally closed.

### Manual Windows Terminal smoke

On a Windows desktop with Windows Terminal installed:

1. Copy `config/ahquiver.example.ini` to `config/ahquiver.ini`.
2. Set `[modules] F02=1`.
3. Adapt `example_terminal` if desired, keeping a distinctive `identity`, `title`, and `window_name`.
4. Invoke `terminal.launch_preset` through an action caller/control surface.
5. Verify the created Terminal tab displays the configured title and that the application does not immediately overwrite it.
6. Attempt the same sticky singleton preset again and verify AHQuiver rejects it until `terminal.release_identity` is invoked.

GitHub's Windows Server runner is used for deterministic and generic Win32 process/title smoke coverage; it is not treated as proof of a user's packaged Windows Terminal desktop behavior.
