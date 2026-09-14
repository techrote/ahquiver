#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\core\Ui.ahk

class F07SmokeLog {
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

class F07SmokeConfig {
    Path := "F07GuiSmoke.ini"
    GetInt(section, key, default := 0) {
        if section = "F07" && key = "history_limit"
            return 5
        return default
    }
    GetBool(section, key, default := false) {
        if section = "F07" && key = "action_menu"
            return true
        return default
    }
}

class F07SmokeModules {
    __New() {
        this.DisabledCalls := 0
        this.Items := [
            Map("id", "F01", "state", "enabled"),
            Map("id", "F06", "state", "disabled"),
            Map("id", "F09", "state", "failed")
        ]
    }
    List() => this.Items
    Count() => this.Items.Length
    CountEnabled() => 1
    StopAll() {
        this.DisabledCalls += 1
        return AQResult.Ok("stopped")
    }
}

class F07SmokeApp {
    __New() {
        this.Config := F07SmokeConfig()
        this.Log := F07SmokeLog()
        this.Actions := AQActionRegistry(this.Log)
        this.Capabilities := AQCapabilityRegistry()
        this.Modules := F07SmokeModules()
        this.InvokedParams := Map()
        this.Stopped := false
    }
    ReloadConfiguration() => AQResult.Ok("reloaded")
    Stop() {
        this.Stopped := true
        return AQResult.Ok("stopped")
    }
}

exitCode := 1
ui := ""
try {
    app := F07SmokeApp()
    app.Actions.Register("alpha.safe", (params) => AQResult.Ok("alpha"), "safe action", "S0")
    app.Actions.Register("params.echo", (params) => F07SmokeCaptureParams(app, params), "parameter action", "S0")
    app.Actions.Register("failure.synthetic", (params) => AQResult.Failed("sensitive result should not enter history", Map("payload", "SECRET-F07")), "failure action", "S0")
    app.Capabilities.Set("terminal.windowsterminal.can_background_paste", "unknown", "no verified readback")
    app.Capabilities.Set("terminal.standard_edit.can_background_paste", "supported", "verified")

    ui := AQTrayUi(app)
    app.Ui := ui
    enabled := ui.EnableControlSurface()
    if !enabled.IsOk()
        throw Error("Could not enable F07 control surface")
    initialized := ui.Init()
    if !initialized.IsOk()
        throw Error("Could not initialize F07 tray")
    shown := ui.ShowControl()
    if !shown.IsOk()
        throw Error("Could not build/show F07 control panel")
    Sleep(100)

    if !IsObject(ui.ControlGui) || !IsObject(ui.ActionList)
        throw Error("Control GUI/list did not materialize")
    if ui.ActionList.GetCount() != 3
        throw Error("Expected three initial actions in GUI")
    if ui.ModuleList.GetCount() != 3
        throw Error("Expected module states in GUI")
    if ui.CapabilityList.GetCount() != 2
        throw Error("Expected capability states in GUI")

    app.Actions.Register("late.dynamic", (params) => AQResult.Ok("late"), "late-added action", "S0")
    ui.Refresh()
    if ui.ActionList.GetCount() != 4
        throw Error("Late-added action did not appear after refresh")
    if !F07SmokeHasActionRow(ui, "late.dynamic")
        throw Error("Late-added action row was not dynamically mapped")

    result := ui.ControlModel.Invoke("params.echo", "preset=audit`nrole=reviewer")
    if !result.IsOk()
        throw Error("Generic parameter dispatch failed")
    if app.InvokedParams["preset"] != "audit" || app.InvokedParams["role"] != "reviewer"
        throw Error("Control model did not dispatch parsed params through registry")

    app.Actions.Invoke("failure.synthetic", Map("text", "SECRET-F07"))
    ui.RefreshControl()
    failures := ui.ControlModel.RecentFailures()
    if failures.Length != 1
        throw Error("Expected one recent failure")
    if InStr(failures[1]["summary"], "SECRET-F07")
        throw Error("Sensitive payload leaked into recent-failure summary")
    if ui.FailureList.GetCount() != 1
        throw Error("Failure list did not refresh")

    ui.HideControl()
    ui.Teardown()
    FileAppend("PASS F07 real tray/GUI dynamic registry smoke`n", "*")
    exitCode := 0
} catch as smokeError {
    FileAppend("FAIL F07 GUI smoke: " smokeError.Message "`n", "*")
    exitCode := 1
} finally {
    if IsObject(ui)
        try ui.Teardown()
}

ExitApp(exitCode)

F07SmokeCaptureParams(app, params) {
    copy := Map()
    for key, value in params
        copy[key] := value
    app.InvokedParams := copy
    return AQResult.Ok("captured")
}

F07SmokeHasActionRow(ui, actionId) {
    for row, id in ui.ActionRows {
        if id = actionId
            return true
    }
    return false
}
