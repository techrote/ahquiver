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

configPath := A_Temp "\ahquiver-f02-smoke-" A_TickCount ".ini"
pid := 0
try {
    IniWrite("smoke", configPath, "F02", "presets")
    section := "F02.preset.smoke"
    IniWrite("process", configPath, section, "kind")
    IniWrite("F02 Real Smoke Identity", configPath, section, "identity")
    IniWrite("smoke", configPath, section, "role")
    IniWrite(A_AhkPath, configPath, section, "program")
    IniWrite(".", configPath, section, "working_dir")
    IniWrite("F02 Real Smoke Identity", configPath, section, "title")
    IniWrite("window", configPath, section, "title_mode")
    IniWrite("generic", configPath, section, "terminal_kind")
    IniWrite("1", configPath, section, "singleton")
    IniWrite("pid", configPath, section, "singleton_mode")
    IniWrite("3000", configPath, section, "window_wait_ms")
    IniWrite("2", configPath, section, "arg_count")
    IniWrite(A_ScriptDir "\F02ChildWindow.ahk", configPath, section, "arg1")
    IniWrite("argument with spaces", configPath, section, "arg2")

    app := F02SmokeApp(configPath)
    service := F02LauncherService(app, F02PresetStore(app.Config))
    result := service.Launch("smoke")
    if !result.IsOk()
        throw Error("F02 real launch failed: " result.Message)

    pid := result.Data["pid"]
    if !pid
        throw Error("F02 real launch returned no PID")
    if result.Data["title_status"] != "supported"
        throw Error("Expected verified supported title, got " result.Data["title_status"] " — " result.Data["title_detail"])

    windows := app.Windows.FindVisibleByPid(pid)
    if windows.Length != 1
        throw Error("Expected exactly one visible child window for launched PID, got " windows.Length)
    if windows[1]["title"] != "F02 Real Smoke Identity"
        throw Error("Child window title was not updated: " windows[1]["title"])

    identities := app.Identities.List(true)
    if identities.Length != 1
        throw Error("Expected one active identity record, got " identities.Length)
    if identities[1]["identity"] != "F02 Real Smoke Identity"
        throw Error("Identity registry mismatch")

    duplicate := service.Launch("smoke")
    if duplicate.Status != "rejected"
        throw Error("Running PID singleton did not reject duplicate launch")

    closeResult := app.Windows.RequestClose(windows[1], 2000)
    if !closeResult.IsOk()
        throw Error("Could not close F02 smoke child normally: " closeResult.Message)
    try ProcessWaitClose(pid, 3)

    FileAppend("PASS F02 real process launch/title/singleton smoke`n", "*")
    ExitApp(0)
} catch as err {
    if pid {
        try ProcessClose(pid)
    }
    FileAppend("FAIL F02 real process launch/title/singleton smoke: " err.Message "`n", "*")
    ExitApp(1)
} finally {
    try FileDelete(configPath)
}
