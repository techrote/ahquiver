#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\Log.ahk
#Include ..\src\core\Context.ahk
#Include ..\src\core\WindowQuery.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\Process.ahk
#Include ..\src\modules\F06_TrackerRestart.ahk

class F06SmokeApp {
    __New() {
        this.Log := F06SmokeLog()
        this.Actions := AQActionRegistry(this.Log)
        this.Windows := AQWindowQuery()
        this.Context := AQContextService()
    }
}

class F06SmokeLog {
    Info(*) {
        return
    }
    Warn(*) {
        return
    }
    Error(*) {
        return
    }
}

childPath := A_ScriptDir "\F06ChildProcess.ahk"
workerPid := 0
newTrackerPid := 0
oldTrackerPid := 0

try {
    app := F06SmokeApp()
    adapter := F06SystemProcessAdapter(app)
    expectedExe := ""
    SplitPath(A_AhkPath, &expectedExe)
    preset := Map(
        "id", "smoke",
        "program", A_AhkPath,
        "args", [childPath, "tracker"],
        "working_dir", A_ScriptDir,
        "allow_force", false,
        "graceful_timeout_ms", 3000,
        "force_timeout_ms", 1000,
        "worker_exclude_exes", [],
        "expected_exe", StrLower(expectedExe),
        "expected_path", A_AhkPath,
        "identity", "F06 smoke tracker",
        "title", "",
        "restore_title", false,
        "window_wait_ms", 1000
    )
    service := F06TrackerService(app, Map("smoke", preset), F06TrackerRegistry(), adapter)

    workerLaunch := AQProcess.Launch(A_AhkPath, [childPath, "worker"], A_ScriptDir)
    if !workerLaunch.IsOk()
        throw Error("Could not launch synthetic worker: " workerLaunch.Message)
    workerPid := workerLaunch.Data["pid"]

    trackerLaunch := service.Launch("smoke")
    if !trackerLaunch.IsOk()
        throw Error("Could not launch synthetic tracker: " trackerLaunch.Message)
    oldTrackerPid := trackerLaunch.Data["pid"]
    if oldTrackerPid = workerPid
        throw Error("Tracker and worker unexpectedly share a PID")

    Sleep(500)
    if !ProcessExist(workerPid) || !ProcessExist(oldTrackerPid)
        throw Error("Synthetic worker/tracker did not remain alive before restart")

    restarted := service.Restart("smoke")
    if !restarted.IsOk()
        throw Error("Tracker restart failed: " restarted.Message)
    newTrackerPid := restarted.Data["new_pid"]
    if restarted.Data["old_pid"] != oldTrackerPid
        throw Error("Restart reported wrong old tracker PID")
    if restarted.Data["termination_mode"] != "graceful"
        throw Error("Expected graceful tracker termination")
    if !newTrackerPid || newTrackerPid = oldTrackerPid || newTrackerPid = workerPid
        throw Error("Restart returned invalid new tracker PID")
    if ProcessExist(oldTrackerPid)
        throw Error("Old tracker remained alive after restart")
    if !ProcessExist(newTrackerPid)
        throw Error("New tracker is not alive after restart")
    if !ProcessExist(workerPid)
        throw Error("Synthetic worker was disturbed by tracker restart")

    FileAppend("PASS F06 real tracker restart preserved synthetic worker`n", "*")
    ExitApp(0)
} catch as smokeError {
    FileAppend("FAIL F06 real tracker smoke: " smokeError.Message "`n", "*")
    ExitApp(1)
} finally {
    if newTrackerPid && ProcessExist(newTrackerPid)
        try ProcessClose(newTrackerPid)
    if oldTrackerPid && ProcessExist(oldTrackerPid)
        try ProcessClose(oldTrackerPid)
    if workerPid && ProcessExist(workerPid)
        try ProcessClose(workerPid)
}
