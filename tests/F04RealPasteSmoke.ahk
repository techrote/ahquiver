#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\Log.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\core\Context.ahk
#Include ..\src\core\WindowQuery.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\ClipboardGuard.ahk
#Include ..\src\modules\F04_FocusPreservingPaste.ahk

class F04SmokeApp {
    __New(configPath) {
        this.Config := AQConfig(configPath)
        this.Log := AQLog(A_Temp "\ahquiver-f04-smoke.log", false)
        this.Capabilities := AQCapabilityRegistry()
        this.Context := AQContextService()
        this.Windows := AQWindowQuery()
        this.Actions := AQActionRegistry(this.Log)
        this.Clipboard := AQClipboardGuard()
    }
}

configPath := A_Temp "\ahquiver-f04-smoke-" A_TickCount ".ini"
sourceGui := Gui("+AlwaysOnTop", "F04 foreground source")
sourceGui.AddText("w220", "This window must remain foreground")
targetGui := Gui(, "F04 background target")
targetEdit := targetGui.AddEdit("w240 h24", "before")
originalClipboard := ClipboardAll()

try {
    IniWrite("1", configPath, "F04", "allow_focus_handoff")
    IniWrite("1", configPath, "F04", "auto_probe_standard_edit")
    IniWrite("300000", configPath, "F04", "target_max_age_ms")
    IniWrite("1000", configPath, "F04", "activation_timeout_ms")
    IniWrite("1000", configPath, "F04", "restore_timeout_ms")

    targetGui.Show("x200 y200 w280 h80")
    sourceGui.Show("x520 y200 w260 h80")
    WinActivate("ahk_id " sourceGui.Hwnd)
    if !WinWaitActive("ahk_id " sourceGui.Hwnd, , 1)
        throw Error("Could not establish source foreground window")

    app := F04SmokeApp(configPath)
    service := F04PasteService(app)
    targetSet := service.SetTarget(targetGui.Hwnd, targetEdit.Hwnd)
    if !targetSet.IsOk()
        throw Error("Could not set F04 smoke target: " targetSet.Message)

    A_Clipboard := "SENTINEL-F04"
    if !ClipWait(0.5)
        throw Error("Could not establish clipboard sentinel")
    SendMessage(0xB1, 6, 6, targetEdit.Hwnd)
    foregroundBefore := WinGetID("A")
    backgroundResult := service.BackgroundPaste(Map("text", "BG"))
    if !backgroundResult.IsOk()
        throw Error("Verified background paste failed: " backgroundResult.Message)
    if ControlGetText(targetEdit.Hwnd) != "beforeBG"
        throw Error("Background target text mismatch: " ControlGetText(targetEdit.Hwnd))
    if WinGetID("A") != foregroundBefore || foregroundBefore != sourceGui.Hwnd
        throw Error("Verified background paste changed foreground window")
    if A_Clipboard != "SENTINEL-F04"
        throw Error("Clipboard was not restored after background paste")
    if app.Capabilities.Get("terminal.standard_edit.can_background_paste")["status"] != "supported"
        throw Error("Standard Edit capability was not verified supported")

    probeResult := service.ProbeCapabilities()
    if !probeResult.IsOk()
        throw Error("Capability probe failed")
    if app.Capabilities.Get("terminal.windowsterminal.can_background_paste")["status"] != "unknown"
        throw Error("Windows Terminal true background capability must remain unknown without readback evidence")

    ControlSetText("before2", targetEdit.Hwnd)
    SendMessage(0xB1, 7, 7, targetEdit.Hwnd)
    WinActivate("ahk_id " sourceGui.Hwnd)
    WinWaitActive("ahk_id " sourceGui.Hwnd, , 1)
    A_Clipboard := "SENTINEL-F04"
    fallbackResult := service.FocusHandoffPaste(Map("text", "FH"))
    if !fallbackResult.IsOk()
        throw Error("Focus-handoff fallback failed: " fallbackResult.Message)
    if fallbackResult.Data["mode"] != "focus_handoff" || fallbackResult.Data["capability_status"] != "degraded"
        throw Error("Fallback did not identify itself as degraded focus_handoff")
    if ControlGetText(targetEdit.Hwnd) != "before2FH"
        throw Error("Fallback target text mismatch: " ControlGetText(targetEdit.Hwnd))
    if WinGetID("A") != sourceGui.Hwnd
        throw Error("Fallback did not restore original foreground")
    if A_Clipboard != "SENTINEL-F04"
        throw Error("Clipboard was not restored after fallback paste")

    FileAppend("PASS F04 real focus-preserving and degraded fallback paste smoke`n", "*")
    ExitApp(0)
} catch as smokeError {
    FileAppend("FAIL F04 real paste smoke: " smokeError.Message "`n", "*")
    ExitApp(1)
} finally {
    try sourceGui.Destroy()
    try targetGui.Destroy()
    try A_Clipboard := originalClipboard
    try FileDelete(configPath)
}
