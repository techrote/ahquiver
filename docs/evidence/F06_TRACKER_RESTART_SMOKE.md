# F06 manual tracker restart smoke

Record Windows, AutoHotkey, tracker runtime, AHQuiver commit, and the local preset id. Use a harmless tracker configuration before applying it to a long-running audit/worker workflow.

## First ownership

If AHQuiver did not launch the current tracker, focus the tracker window and invoke `tracker.adopt_foreground` with the intended preset. Verify adoption succeeds only when executable/path metadata matches. Focus a worker and verify adoption is rejected when its executable is worker-protected.

## Restart

1. Record tracker PID and worker PID(s).
2. Invoke `tracker.restart` for the preset.
3. Verify the result reports the recorded tracker as `old_pid`, a distinct `new_pid`, and `termination_mode=graceful` under normal conditions.
4. Verify the previous tracker PID is gone and the new tracker is alive.
5. Verify all worker PIDs are unchanged and still alive.
6. If title restoration is configured/supported, confirm the replacement tracker receives the requested identity/title.

## Failure checks

- With two live owned records for one preset, restart must reject rather than choose one.
- With graceful shutdown intentionally prevented and `allow_force=0`, restart must fail without killing the process.
- Enable `allow_force=1` only for a disposable smoke process and confirm the result explicitly reports `termination_mode=force`.
- Change/replace the owned process so PID metadata no longer matches and verify restart rejects before termination.

Never use the force-fallback smoke against a real worker or irreplaceable interactive process.
