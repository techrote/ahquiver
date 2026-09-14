#Requires AutoHotkey v2.0
#SingleInstance Force

#Include core\Result.ahk
#Include core\Log.ahk
#Include core\Config.ahk
#Include core\Capability.ahk
#Include core\Context.ahk
#Include core\WindowQuery.ahk
#Include core\ActionRegistry.ahk
#Include core\ClipboardGuard.ahk
#Include core\Process.ahk
#Include core\IdentityRegistry.ahk
#Include core\ModuleHost.ahk
#Include core\Ui.ahk
#Include modules\F01_CloseMatchingWindows.ahk
#Include modules\F02_TerminalIdentity.ahk
#Include modules\F03_TerminalKeyGuard.ahk
#Include modules\F04_FocusPreservingPaste.ahk
#Include modules\F05_MultilinePaste.ahk
#Include modules\F06_TrackerRestart.ahk
#Include modules\F07_ControlSurface.ahk
#Include core\App.ahk

global AQ_APP := ""

try {
    AQ_APP := AHQuiverApp(A_Args)
    AQ_APP.Start()
    OnExit(AQ_OnExit)

    if AQ_APP.Options.Has("probe-startup") {
        AQ_APP.Stop()
        ExitApp(0)
    }

    Persistent(true)
} catch as err {
    try FileAppend("AHQuiver startup failed: " err.Message "`n", "**")
    if !AQ_IsHeadlessArg()
        MsgBox("AHQuiver startup failed:`n`n" err.Message, "AHQuiver", "Iconx")
    ExitApp(1)
}

AQ_OnExit(exitReason, exitCode) {
    global AQ_APP
    if IsObject(AQ_APP)
        try AQ_APP.Stop()
}

AQ_IsHeadlessArg() {
    for arg in A_Args {
        if arg = "--headless"
            return true
    }
    return false
}
