#Requires AutoHotkey v2.0

class AQControlParameterParser {
    Parse(text) {
        params := Map()
        normalized := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
        for rawLine in StrSplit(normalized, "`n") {
            line := Trim(rawLine)
            if line = ""
                continue
            separator := InStr(line, "=")
            if !separator
                return AQResult.Invalid("Parameters must use one key=value pair per line")
            key := Trim(SubStr(line, 1, separator - 1))
            value := SubStr(line, separator + 1)
            if key = ""
                return AQResult.Invalid("Parameter key cannot be empty")
            if params.Has(key)
                return AQResult.Invalid("Duplicate parameter key: " key)
            params[key] := value
        }
        return AQResult.Ok("Parameters parsed", Map("params", params))
    }
}

class AQControlSurfaceModel {
    __New(app, historyLimit := 10) {
        this.App := app
        this.HistoryLimit := Max(1, historyLimit)
        this.Parser := AQControlParameterParser()
        this.Failures := []
        this.ObserverToken := 0
        try this.ObserverToken := this.App.Actions.Subscribe(ObjBindMethod(this, "ObserveAction"))
    }

    Close() {
        if this.ObserverToken {
            try this.App.Actions.Unsubscribe(this.ObserverToken)
            this.ObserverToken := 0
        }
    }

    Snapshot() {
        return Map(
            "actions", this.App.Actions.List(),
            "modules", this.App.Modules.List(),
            "capabilities", this.App.Capabilities.List(),
            "failures", this.RecentFailures()
        )
    }

    Invoke(actionId, parameterText := "") {
        parsed := this.Parser.Parse(parameterText)
        if !parsed.IsOk()
            return parsed
        return this.App.Actions.Invoke(actionId, parsed.Data["params"])
    }

    ObserveAction(actionId, actionResult) {
        if !IsObject(actionResult) || !HasProp(actionResult, "Status")
            return
        status := actionResult.Status
        if status = "ok" || status = "cancelled"
            return
        this.Failures.InsertAt(1, Map(
            "action", actionId,
            "status", status,
            "summary", this._StatusSummary(status),
            "at", A_TickCount
        ))
        while this.Failures.Length > this.HistoryLimit
            this.Failures.Pop()
    }

    RecentFailures() {
        items := []
        for item in this.Failures {
            copy := Map()
            for key, value in item
                copy[key] := value
            items.Push(copy)
        }
        return items
    }

    _StatusSummary(status) {
        switch status {
            case "failed":
                return "Action reported failure"
            case "rejected":
                return "Action was rejected by its safety/target checks"
            case "invalid":
                return "Action request was invalid"
            case "unsupported":
                return "Action/capability is unsupported in this context"
            default:
                return "Action did not complete successfully"
        }
    }
}

class AQTrayUi {
    __New(app) {
        this.App := app
        this.Initialized := false
        this.ControlEnabled := false
        this.ControlModel := ""
        this.ControlGui := ""
        this.ActionList := ""
        this.ModuleList := ""
        this.CapabilityList := ""
        this.FailureList := ""
        this.ParameterEdit := ""
        this.ActionRows := Map()
    }

    EnableControlSurface() {
        this.ControlEnabled := true
        if !IsObject(this.ControlModel) {
            historyLimit := Max(1, this.App.Config.GetInt("F07", "history_limit", 10))
            this.ControlModel := AQControlSurfaceModel(this.App, historyLimit)
        }
        if this.Initialized
            this.Refresh()
        return AQResult.Ok("F07 control surface enabled")
    }

    DisableControlSurface() {
        this.ControlEnabled := false
        if IsObject(this.ControlModel)
            this.ControlModel.Close()
        this.ControlModel := ""
        this._DestroyControlGui()
        return AQResult.Ok("F07 control surface disabled")
    }

    Init() {
        this._BuildTray()
        this.Initialized := true
        if this.ControlEnabled && IsObject(this.ControlGui)
            this.RefreshControl()
        return AQResult.Ok("Tray initialized")
    }

    _BuildTray() {
        trayMenu := A_TrayMenu
        trayMenu.Delete()

        if this.ControlEnabled {
            trayMenu.Add("Open AHQuiver control panel", ObjBindMethod(this, "ShowControl"))
            if this.App.Config.GetBool("F07", "action_menu", true)
                this._AddActionMenu(trayMenu)
            trayMenu.Add()
        } else {
            trayMenu.Add("AHQuiver status", ObjBindMethod(this, "ShowStatus"))
            trayMenu.Add()
        }

        trayMenu.Add("Reload configuration", ObjBindMethod(this, "ReloadConfiguration"))
        if this.ControlEnabled
            trayMenu.Add("Emergency disable modules", ObjBindMethod(this, "EmergencyDisable"))
        trayMenu.Add()
        trayMenu.Add("Exit AHQuiver", ObjBindMethod(this, "ExitApplication"))
        A_IconTip := this.ControlEnabled ? "AHQuiver — control surface" : "AHQuiver"
    }

    _AddActionMenu(trayMenu) {
        actionMenu := Menu()
        actions := this.App.Actions.List()
        if !actions.Length {
            actionMenu.Add("(no registered actions)", (*) => 0)
            actionMenu.Disable("(no registered actions)")
        } else {
            for action in actions {
                label := action["id"] "  [" action["safety_class"] "]"
                actionMenu.Add(label, ObjBindMethod(this, "QueueTrayAction", action["id"]))
            }
        }
        trayMenu.Add("Actions", actionMenu)
    }

    ShowStatus(*) {
        text := "AHQuiver`n"
        text .= "Actions: " this.App.Actions.Count() "`n"
        text .= "Modules: " this.App.Modules.Count() " registered / " this.App.Modules.CountEnabled() " enabled`n"
        text .= "Capabilities: " this.App.Capabilities.Count() " recorded`n"
        text .= "Config: " this.App.Config.Path
        MsgBox(text, "AHQuiver status", "Iconi")
    }

    ShowControl(*) {
        if !this.ControlEnabled || !IsObject(this.ControlModel) {
            this.ShowStatus()
            return AQResult.Unsupported("F07 control surface is not enabled")
        }
        if !IsObject(this.ControlGui)
            this._BuildControlGui()
        this.RefreshControl()
        this.ControlGui.Show("AutoSize")
        return AQResult.Ok("Control panel shown")
    }

    HideControl(*) {
        if IsObject(this.ControlGui)
            this.ControlGui.Hide()
    }

    _BuildControlGui() {
        panel := Gui("+Resize", "AHQuiver control")
        panel.SetFont("s9", "Segoe UI")
        tabs := panel.AddTab3("w820 h470", ["Actions", "Modules", "Capabilities", "Failures"])

        tabs.UseTab(1)
        this.ActionList := panel.AddListView("w790 r12 Grid", ["Action", "Risk", "Description"])
        this.ActionList.OnEvent("DoubleClick", ObjBindMethod(this, "RunSelectedAction"))
        panel.AddText("w790", "Parameters (optional; one key=value pair per line):")
        this.ParameterEdit := panel.AddEdit("w790 r4")
        runButton := panel.AddButton("w120 Default", "Run selected")
        runButton.OnEvent("Click", ObjBindMethod(this, "RunSelectedAction"))
        clearButton := panel.AddButton("x+8 w120", "Clear parameters")
        clearButton.OnEvent("Click", ObjBindMethod(this, "ClearParameters"))

        tabs.UseTab(2)
        this.ModuleList := panel.AddListView("w790 r17 Grid", ["Module", "State"])

        tabs.UseTab(3)
        this.CapabilityList := panel.AddListView("w790 r17 Grid", ["Capability", "Status", "Detail"])

        tabs.UseTab(4)
        this.FailureList := panel.AddListView("w790 r17 Grid", ["Action", "Status", "Safe summary"])
        panel.AddText("w790", "Failure history intentionally excludes action parameters, clipboard contents, command text and result payload data.")

        tabs.UseTab()
        refreshButton := panel.AddButton("xm y+12 w110", "Refresh")
        refreshButton.OnEvent("Click", ObjBindMethod(this, "RefreshControl"))
        reloadButton := panel.AddButton("x+8 w150", "Reload configuration")
        reloadButton.OnEvent("Click", ObjBindMethod(this, "ReloadConfiguration"))
        disableButton := panel.AddButton("x+8 w170", "Emergency disable")
        disableButton.OnEvent("Click", ObjBindMethod(this, "EmergencyDisable"))
        closeButton := panel.AddButton("x+8 w100", "Close")
        closeButton.OnEvent("Click", ObjBindMethod(this, "HideControl"))
        exitButton := panel.AddButton("x+8 w100", "Exit")
        exitButton.OnEvent("Click", ObjBindMethod(this, "ExitApplication"))

        panel.OnEvent("Close", ObjBindMethod(this, "HideControl"))
        panel.OnEvent("Escape", ObjBindMethod(this, "HideControl"))
        this.ControlGui := panel
    }

    Refresh(*) {
        if this.Initialized
            this._BuildTray()
        if this.ControlEnabled && IsObject(this.ControlGui)
            this.RefreshControl()
        return AQResult.Ok("Control surface refreshed")
    }

    RefreshControl(*) {
        if !this.ControlEnabled || !IsObject(this.ControlModel) || !IsObject(this.ControlGui)
            return AQResult.Unsupported("Control panel is not active")

        snapshot := this.ControlModel.Snapshot()
        this.ActionRows := Map()
        this.ActionList.Delete()
        for action in snapshot["actions"] {
            row := this.ActionList.Add("", action["id"], action["safety_class"], action["description"])
            this.ActionRows[row] := action["id"]
        }
        this.ActionList.ModifyCol(1, 260)
        this.ActionList.ModifyCol(2, 55)
        this.ActionList.ModifyCol(3, 450)

        this.ModuleList.Delete()
        for module in snapshot["modules"]
            this.ModuleList.Add("", module["id"], module["state"])
        this.ModuleList.ModifyCol(1, 160)
        this.ModuleList.ModifyCol(2, 160)

        this.CapabilityList.Delete()
        for capability in snapshot["capabilities"]
            this.CapabilityList.Add("", capability["id"], capability["status"], capability["detail"])
        this.CapabilityList.ModifyCol(1, 280)
        this.CapabilityList.ModifyCol(2, 100)
        this.CapabilityList.ModifyCol(3, 380)

        this.FailureList.Delete()
        for failure in snapshot["failures"]
            this.FailureList.Add("", failure["action"], failure["status"], failure["summary"])
        this.FailureList.ModifyCol(1, 300)
        this.FailureList.ModifyCol(2, 90)
        this.FailureList.ModifyCol(3, 360)
        return AQResult.Ok("Control panel refreshed")
    }

    ClearParameters(*) {
        if IsObject(this.ParameterEdit)
            this.ParameterEdit.Value := ""
    }

    RunSelectedAction(*) {
        if !IsObject(this.ActionList)
            return
        row := this.ActionList.GetNext(0, "F")
        if !row
            row := this.ActionList.GetNext()
        if !row || !this.ActionRows.Has(row) {
            TrayTip("AHQuiver", "Select an action first")
            return
        }
        parameterText := IsObject(this.ParameterEdit) ? this.ParameterEdit.Value : ""
        this.QueueAction(this.ActionRows[row], parameterText, "panel")
    }

    QueueTrayAction(actionId, *) {
        this.QueueAction(actionId, "", "tray")
    }

    QueueAction(actionId, parameterText := "", source := "panel") {
        SetTimer(ObjBindMethod(this, "_ExecuteQueuedAction", actionId, parameterText, source), -1)
    }

    _ExecuteQueuedAction(actionId, parameterText, source) {
        if !this.ControlEnabled || !IsObject(this.ControlModel)
            return

        descriptor := this.App.Actions.Describe(actionId)
        if !descriptor.Count {
            TrayTip("AHQuiver", actionId " is no longer available")
            this.Refresh()
            return
        }
        if descriptor["safety_class"] = "S2" {
            choice := MsgBox(
                "Run high-impact action?`n`n" actionId "`n`nFeature-level safety checks and confirmations still apply.",
                "AHQuiver confirmation",
                "YesNo Icon!"
            )
            if choice != "Yes"
                return
        }

        actionResult := this.ControlModel.Invoke(actionId, parameterText)
        TrayTip("AHQuiver", actionId ": " actionResult.Status)
        if source = "tray" && actionResult.Status = "invalid" {
            this.ShowControl()
            this._SelectAction(actionId)
        } else {
            this.Refresh()
        }
    }

    _SelectAction(actionId) {
        if !IsObject(this.ActionList)
            return
        for row, id in this.ActionRows {
            if id = actionId {
                this.ActionList.Modify(row, "Select Focus Vis")
                break
            }
        }
    }

    ReloadConfiguration(*) {
        reloadResult := this.App.ReloadConfiguration()
        this.Init()
        if reloadResult.IsOk()
            TrayTip("AHQuiver", "Configuration reloaded")
        else
            MsgBox(reloadResult.Message, "AHQuiver configuration", "Iconx")
        return reloadResult
    }

    EmergencyDisable(*) {
        disableResult := this.App.Modules.StopAll()
        this.DisableControlSurface()
        this.Init()
        TrayTip("AHQuiver", "All feature modules disabled for this session")
        return disableResult
    }

    ExitApplication(*) {
        this.App.Stop()
        ExitApp(0)
    }

    Teardown() {
        this._DestroyControlGui()
        if IsObject(this.ControlModel)
            this.ControlModel.Close()
        this.ControlModel := ""
        try A_TrayMenu.Delete()
        this.Initialized := false
    }

    _DestroyControlGui() {
        if IsObject(this.ControlGui) {
            try this.ControlGui.Destroy()
        }
        this.ControlGui := ""
        this.ActionList := ""
        this.ModuleList := ""
        this.CapabilityList := ""
        this.FailureList := ""
        this.ParameterEdit := ""
        this.ActionRows := Map()
    }
}
