#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\Log.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\core\WindowQuery.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\Process.ahk
#Include ..\src\core\IdentityRegistry.ahk
#Include ..\src\modules\F02_TerminalIdentity.ahk

class F02SmokeApp {
    __New(configPath) {
        this.RootDir := A_ScriptDir "\.."
        this.Config := AQConfig(configPath)
        this.Log := AQLog(A_Temp "\ahquiver-f02-smoke.log", false)
        this.Capabilities := AQCapabilityRegistry()
        this.Windows := AQWindowQuery()
        this.Actions := AQActionRegistry(this.Log)
        this.Identities := AQIdentityRegistry()
    }
}

F02_SMOKE_CONFIG := A_Temp "\ahquiver-f02-smoke-" A_TickCount ".ini"
F02_SMOKE_PID := 0
try {
    IniWrite("smoke", F02_SMOKE_CONFIG, "F02", "presets")
    F02_SMOKE_SECTION := "F02.preset.smoke"
    IniWrite("process", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "kind")
    IniWrite("F02 Real Smoke Identity", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "identity")
    IniWrite("smoke", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "role")
    IniWrite(A_AhkPath, F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "program")
    IniWrite(".", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "working_dir")
    IniWrite("F02 Real Smoke Identity", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "title")
    IniWrite("window", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "title_mode")
    IniWrite("generic", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "terminal_kind")
    IniWrite("1", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "singleton")
    IniWrite("pid", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "singleton_mode")
    IniWrite("3000", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "window_wait_ms")
    IniWrite("2", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "arg_count")
    IniWrite(A_ScriptDir "\F02ChildWindow.ahk", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "arg1")
    IniWrite("argument with spaces", F02_SMOKE_CONFIG, F02_SMOKE_SECTION, "arg2")

    F02_SMOKE_APP := F02SmokeApp(F02_SMOKE_CONFIG)
    F02_SMOKE_SERVICE := F02LauncherService(F02_SMOKE_APP, F02PresetStore(F02_SMOKE_APP.Config))
    F02_SMOKE_RESULT := F02_SMOKE_SERVICE.Launch("smoke")
    if !F02_SMOKE_RESULT.IsOk()
        throw Error("F02 real launch failed: " F02_SMOKE_RESULT.Message)

    F02_SMOKE_PID := F02_SMOKE_RESULT.Data["pid"]
    if !F02_SMOKE_PID
        throw Error("F02 real launch returned no PID")
    if F02_SMOKE_RESULT.Data["title_status"] != "supported"
        throw Error("Expected verified supported title, got " F02_SMOKE_RESULT.Data["title_status"] " — " F02_SMOKE_RESULT.Data["title_detail"])

    F02_SMOKE_WINDOWS := F02_SMOKE_APP.Windows.FindVisibleByPid(F02_SMOKE_PID)
    if F02_SMOKE_WINDOWS.Length != 1
        throw Error("Expected exactly one visible child window for launched PID, got " F02_SMOKE_WINDOWS.Length)
    if F02_SMOKE_WINDOWS[1]["title"] != "F02 Real Smoke Identity"
        throw Error("Child window title was not updated: " F02_SMOKE_WINDOWS[1]["title"])

    F02_SMOKE_IDENTITIES := F02_SMOKE_APP.Identities.List(true)
    if F02_SMOKE_IDENTITIES.Length != 1
        throw Error("Expected one active identity record, got " F02_SMOKE_IDENTITIES.Length)
    if F02_SMOKE_IDENTITIES[1]["identity"] != "F02 Real Smoke Identity"
        throw Error("Identity registry mismatch")

    F02_SMOKE_DUPLICATE := F02_SMOKE_SERVICE.Launch("smoke")
    if F02_SMOKE_DUPLICATE.Status != "rejected"
        throw Error("Running PID singleton did not reject duplicate launch")

    F02_SMOKE_CLOSE := F02_SMOKE_APP.Windows.RequestClose(F02_SMOKE_WINDOWS[1], 2000)
    if !F02_SMOKE_CLOSE.IsOk()
        throw Error("Could not close F02 smoke child normally: " F02_SMOKE_CLOSE.Message)
    try ProcessWaitClose(F02_SMOKE_PID, 3)

    FileAppend("PASS F02 real process launch/title/singleton smoke`n", "*")
    ExitApp(0)
} catch as F02_SMOKE_ERR {
    if F02_SMOKE_PID {
        try ProcessClose(F02_SMOKE_PID)
    }
    FileAppend("FAIL F02 real process launch/title/singleton smoke: " F02_SMOKE_ERR.Message "`n", "*")
    ExitApp(1)
} finally {
    try FileDelete(F02_SMOKE_CONFIG)
}
