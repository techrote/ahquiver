# F06 — Tracker restart / relaunch

## Purpose

F06 provides a one-action restart path for progress/audit tracker processes while explicitly protecting worker processes. It never uses a window title as process identity and never performs executable-wide termination.

## Ownership model

F06 stores tracker ownership in `F06TrackerRegistry`. A record includes preset id, exact PID, observed executable/path, source (`launched` or `adopted`), optional identity metadata, and lifecycle state.

A tracker becomes owned in one of two ways:

1. AHQuiver launches it with `tracker.launch` / `tracker.restart` when no live owned tracker exists.
2. The user explicitly invokes `tracker.adopt_foreground` for a preset. Adoption verifies the foreground PID against preset executable/path metadata and worker exclusions before registering it.

F06 does not scan arbitrary windows/processes by title and does not infer ownership from an executable name alone.

## Actions

- `tracker.restart` — restart an owned tracker; if none is live, launch the preset.
- `tracker.launch` — launch only when no owned live tracker exists.
- `tracker.adopt_foreground` — explicitly adopt the foreground process after metadata checks.
- `tracker.status` — report owned registry state without process payload/command text.

Action parameters use `preset=<id>`.

## Restart sequence

1. Resolve active owned records for the preset.
2. Mark dead PIDs stale.
3. Reject if more than one live record remains; never guess between duplicates.
4. Immediately revalidate PID, executable, path (when known), preset metadata, and worker exclusions.
5. Request graceful close first through attributed top-level windows.
6. If graceful close fails, force termination is attempted only when `allow_force=1`.
7. Revalidate again before force fallback.
8. Mark the old record inactive only after termination succeeds.
9. Relaunch using `AQProcess` argument quoting.
10. Verify the new PID's process metadata, register it, and optionally request a best-effort title restoration.

Structured restart results expose `old_pid`, `new_pid`, `termination_mode`, preset and prior state where relevant.

## Worker protection

`worker_exclude_exes` is an explicit lower-cased executable list. A worker-protected executable cannot be adopted or terminated by the preset. In addition, F06 targets only owned PIDs, so unrelated processes are not matched even if they use the same executable as the tracker.

This second property is intentionally exercised by `tests/F06ProcessSmoke.ahk`: tracker and worker are two AutoHotkey processes using the same executable, yet only the owned tracker PID is restarted.

## Configuration

No presets are active by default:

```ini
[F06]
presets=
```

Machine-specific tracker paths belong only in local configuration. See the commented example in `config/ahquiver.example.ini`.

Force fallback is disabled by default per preset. `expected_exe` should normally identify the actual host executable (for example `python.exe`), while `expected_path` can add an exact path check where stable.

## Verification

`tests/F06TestRunner.ahk` covers no-running state, single tracker restart, stale PID, duplicate ownership, graceful failure, explicit force fallback, worker exclusion, process metadata change, relaunch failure and module lifecycle.

`tests/F06ProcessSmoke.ahk` launches synthetic tracker and worker GUI processes, restarts only the tracker via the production Windows process adapter, and verifies the worker PID remains alive throughout.
