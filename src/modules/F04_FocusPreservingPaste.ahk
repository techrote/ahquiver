#Requires AutoHotkey v2.0

class F04PasteTargetStore {
    __New() {
        this.Target := Map()
    }

    Set(snapshot, controlHwnd := 0, adapter := "") {
        target := Map()
        for key, value in snapshot
            target[key] := value
        target["control_hwnd"] := controlHwnd
        target["adapter"] := adapter
        target["captured_at"] := A_TickCount
        this.Target := target
        return this.Get()
    }

    Get() {
        copy := Map()
        for key, value in this.Target
            copy[key] := value
        return copy
    }

    Clear() {
        this.Target := Map()
    }

    HasTarget() {
        return this.Target.Count > 0
    }
}

class F04ForegroundAdapter {
    ActiveHwnd() {
        try return WinGetID("A")
        catch
            return 0
    }

    Activate(hwnd, timeoutMs := 750) {
        if !hwnd
            return AQResult.Invalid("Cannot activate an empty HWND")
        selector := "ahk_id " hwnd
        try WinActivate(selector)
        catch as activateError
            return AQResult.Failed("Could not activate target: " activateError.Message)
        try WinWaitActive(selector, , Max(timeoutMs, 0) / 1000.0)
        catch
            return AQResult.Failed("Target did not become foreground within timeout")
        return AQResult.Ok("Target activated")
    }

    Restore(hwnd, timeoutMs := 750) {
        if !hwnd || !WinExist("ahk_id " hwnd)
            return AQResult.Failed("Original foreground window no longer exists")
        result := this.Activate(hwnd, timeoutMs)
        if !result.IsOk()
            return result
        if this.ActiveHwnd() != hwnd
            return AQResult.Failed("Original foreground window was not restored")
        return AQResult.Ok("Foreground restored")
    }
}

class F04SystemTransport {
    BackgroundPaste(controlHwnd) {
        if !controlHwnd
            return AQResult.Invalid("Verified background paste requires a control HWND")
        try {
            ControlSend("^v", , "ahk_id " controlHwnd)
            return AQResult.Ok("Background paste chord sent")
        } catch as sendError {
            return AQResult.Failed("Background ControlSend failed: " sendError.Message)
        }
    }

    FocusHandoffPaste(targetHwnd, controlHwnd := 0) {
        if controlHwnd {
            try ControlFocus(, "ahk_id " controlHwnd)
        }
        try {
            SendEvent("^v")
            return AQResult.Ok("Foreground paste chord sent")
        } catch as sendError {
            return AQResult.Failed("Foreground paste send failed: " sendError.Message)
        }
    }
}

class F04CapabilityProbe {
    __New(app, foreground := unset, transport := unset) {
        this.App := app
        this.Foreground := IsSet(foreground) ? foreground : F04ForegroundAdapter()
        this.Transport := IsSet(transport) ? transport : F04SystemTransport()
    }

    RunAll() {
        standard := this.ProbeStandardEdit()
        this._SetUnknown("windowsterminal", "No reliable Windows Terminal output/readback oracle is available; a successful ControlSend call alone is not proof of paste delivery")
        this._SetUnknown("conhost", "No reliable conhost paste readback probe is implemented")
        this._SetUnknown("unknown", "No verified generic background-paste adapter exists for arbitrary windows")
        return AQResult.Ok("F04 capability probe completed", Map(
            "standard_edit", standard,
            "windowsterminal", this.App.Capabilities.Get("terminal.windowsterminal.can_background_paste"),
            "conhost", this.App.Capabilities.Get("terminal.conhost.can_background_paste"),
            "unknown", this.App.Capabilities.Get("terminal.unknown.can_background_paste")
        ))
    }

    ProbeStandardEdit() {
        capabilityId := "terminal.standard_edit.can_background_paste"
        originalForeground := this.Foreground.ActiveHwnd()
        probeGui := Gui("+ToolWindow -Caption", "AHQuiver F04 probe")
        edit := probeGui.AddEdit("w220 h24", "probe-before")
        probeGui.Show("NA x-10000 y-10000 w240 h50")
        Sleep(30)
        SendMessage(0xB1, 12, 12, , "ahk_id " edit.Hwnd) ; EM_SETSEL at end.
        token := "AQF04-" A_TickCount "-" Random(1000, 9999)

        try {
            result := this.App.Clipboard.Run(this._ProbeWithClipboard.Bind(this, edit.Hwnd, token, originalForeground))
            if result.IsOk() {
                this.App.Capabilities.Set(capabilityId, "supported", "Self-probe verified ControlSend Ctrl+V into a standard Edit control while preserving foreground")
            } else {
                this.App.Capabilities.Set(capabilityId, "unsupported", result.Message)
            }
        } catch as probeError {
            result := AQResult.Failed("Standard Edit background-paste probe failed: " probeError.Message)
            this.App.Capabilities.Set(capabilityId, "unsupported", result.Message)
        } finally {
            try probeGui.Destroy()
        }

        return this.App.Capabilities.Get(capabilityId)
    }

    _ProbeWithClipboard(controlHwnd, token, originalForeground) {
        A_Clipboard := token
        if !ClipWait(0.5)
            return AQResult.Failed("Probe clipboard did not become available")
        sent := this.Transport.BackgroundPaste(controlHwnd)
        if !sent.IsOk()
            return sent
        Sleep(30)
        try observed := ControlGetText(, "ahk_id " controlHwnd)
        catch as readError
            return AQResult.Failed("Probe could not read standard Edit text: " readError.Message)
        if observed != "probe-before" token
            return AQResult.Failed("Probe could not verify expected Edit content")
        if originalForeground && this.Foreground.ActiveHwnd() != originalForeground
            return AQResult.Failed("Background-paste probe changed foreground focus")
        return AQResult.Ok("Standard Edit background paste verified")
    }

    _SetUnknown(kind, detail) {
        this.App.Capabilities.Set("terminal." kind ".can_background_paste", "unknown", detail)
    }
}

class F04PasteService {
    __New(app, targets := unset, foreground := unset, transport := unset, probe := unset) {
        this.App := app
        this.Targets := IsSet(targets) ? targets : F04PasteTargetStore()
        this.Foreground := IsSet(foreground) ? foreground : F04ForegroundAdapter()
        this.Transport := IsSet(transport) ? transport : F04SystemTransport()
        this.Probe := IsSet(probe) ? probe : F04CapabilityProbe(app, this.Foreground, this.Transport)
    }

    CaptureMouseTarget() {
        winHwnd := 0
        controlHwnd := 0
        try MouseGetPos(, , &winHwnd, &controlHwnd, 2)
        catch as mouseError
            return AQResult.Failed("Could not identify window under pointer: " mouseError.Message)
        if !winHwnd
            return AQResult.Rejected("No target window under pointer")
        return this.SetTarget(winHwnd, controlHwnd)
    }

    SetTarget(winHwnd, controlHwnd := 0) {
        snapshot := this.App.Windows.Describe(winHwnd)
        if !snapshot["pid"]
            return AQResult.Rejected("Target HWND is not a live attributable window")

        terminalKind := this.App.Context.ClassifyTerminal(snapshot["exe"])
        snapshot["terminal"] := terminalKind
        adapter := this._AdapterFor(controlHwnd, terminalKind)
        if controlHwnd {
            control := this.App.Windows.Describe(controlHwnd)
            if !control["pid"] || control["pid"] != snapshot["pid"]
                return AQResult.Rejected("Target control does not belong to target window process")
        }
        target := this.Targets.Set(snapshot, controlHwnd, adapter)
        return AQResult.Ok("F04 paste target captured", Map("target", this._PublicTarget(target)))
    }

    ClearTarget() {
        this.Targets.Clear()
        return AQResult.Ok("F04 paste target cleared")
    }

    Status() {
        target := this.Targets.Get()
        return AQResult.Ok("F04 paste target status", Map(
            "has_target", target.Count > 0,
            "target", this._PublicTarget(target),
            "capabilities", this._CapabilitySummary()
        ))
    }

    ProbeCapabilities() {
        return this.Probe.RunAll()
    }

    BackgroundPaste(params := unset) {
        targetResult := this._ValidatedTarget()
        if !targetResult.IsOk()
            return targetResult
        target := targetResult.Data["target"]
        adapter := target["adapter"]
        capabilityId := this._CapabilityId(adapter, target)
        capability := this.App.Capabilities.Get(capabilityId)

        if adapter = "standard_edit" && capability["status"] = "unknown" && this.App.Config.GetBool("F04", "auto_probe_standard_edit", true) {
            this.Probe.ProbeStandardEdit()
            capability := this.App.Capabilities.Get(capabilityId)
        }

        if capability["status"] != "supported" {
            return AQResult.Unsupported("No verified focus-preserving paste capability for this target", Map(
                "adapter", adapter,
                "capability", capability,
                "target", this._PublicTarget(target)
            ))
        }

        if adapter != "standard_edit"
            return AQResult.Unsupported("Capability is marked supported but no production adapter is implemented: " adapter)

        beforeForeground := this.Foreground.ActiveHwnd()
        operation := this._RunWithOptionalText(params, this._VerifiedEditBackgroundPaste.Bind(this, target, beforeForeground))
        afterForeground := this.Foreground.ActiveHwnd()
        if beforeForeground && afterForeground != beforeForeground {
            this.App.Capabilities.Set(capabilityId, "degraded", "A supposedly background operation changed foreground focus")
            return AQResult.Failed("Focus-preserving paste changed foreground focus", Map(
                "before_hwnd", beforeForeground,
                "after_hwnd", afterForeground,
                "mode", "background"
            ))
        }
        return operation
    }

    FocusHandoffPaste(params := unset) {
        if !this.App.Config.GetBool("F04", "allow_focus_handoff", false)
            return AQResult.Unsupported("Degraded focus-handoff paste is disabled by configuration")

        targetResult := this._ValidatedTarget()
        if !targetResult.IsOk()
            return targetResult
        target := targetResult.Data["target"]
        originalForeground := this.Foreground.ActiveHwnd()
        if !originalForeground
            return AQResult.Failed("Could not capture the original foreground window")

        action := this._RunWithOptionalText(params, this._FocusHandoffOperation.Bind(this, target, originalForeground))
        kind := this._CapabilityKind(target)
        capabilityId := "terminal." kind ".focus_handoff_paste"
        if action.IsOk()
            this.App.Capabilities.Set(capabilityId, "degraded", "Paste requires temporary target activation followed by foreground restoration; this is not true background paste")
        return action
    }

    _VerifiedEditBackgroundPaste(target, text) {
        controlHwnd := target["control_hwnd"]
        try before := ControlGetText(, "ahk_id " controlHwnd)
        catch as readError
            return AQResult.Failed("Could not read target Edit control before paste: " readError.Message)

        clipboardText := text != "" ? text : A_Clipboard
        if clipboardText = ""
            return AQResult.Invalid("Clipboard contains no text to paste")
        if InStr(clipboardText, "`n") || InStr(clipboardText, "`r")
            return AQResult.Unsupported("Verified standard-Edit background adapter currently supports single-line text only")

        try selection := SendMessage(0xB0, 0, 0, , "ahk_id " controlHwnd) ; EM_GETSEL
        catch as selectionError
            return AQResult.Failed("Could not query target Edit selection: " selectionError.Message)
        startPos := selection & 0xFFFF
        endPos := (selection >> 16) & 0xFFFF
        expected := SubStr(before, 1, startPos) clipboardText SubStr(before, endPos + 1)

        sent := this.Transport.BackgroundPaste(controlHwnd)
        if !sent.IsOk()
            return sent
        Sleep(30)
        try observed := ControlGetText(, "ahk_id " controlHwnd)
        catch as verifyError
            return AQResult.Failed("Could not verify target Edit text after paste: " verifyError.Message)
        if observed != expected
            return AQResult.Failed("Background paste could not be verified by Edit readback")

        return AQResult.Ok("Focus-preserving background paste verified", Map(
            "mode", "background",
            "adapter", "standard_edit",
            "target", this._PublicTarget(target),
            "verified", true
        ))
    }

    _FocusHandoffOperation(target, text) {
        originalForeground := this.Foreground.ActiveHwnd()
        activation := this.Foreground.Activate(target["hwnd"], this.App.Config.GetInt("F04", "activation_timeout_ms", 750))
        if !activation.IsOk()
            return activation

        sent := ""
        try sent := this.Transport.FocusHandoffPaste(target["hwnd"], target["control_hwnd"])
        finally {
            restore := this.Foreground.Restore(originalForeground, this.App.Config.GetInt("F04", "restore_timeout_ms", 750))
        }

        if !sent.IsOk()
            return sent
        if !restore.IsOk()
            return AQResult.Failed("Paste was sent but foreground restoration failed: " restore.Message)
        return AQResult.Ok("Paste sent via degraded focus handoff", Map(
            "mode", "focus_handoff",
            "capability_status", "degraded",
            "target", this._PublicTarget(target),
            "foreground_restored", true
        ))
    }

    _RunWithOptionalText(params, callback) {
        payload := IsSet(params) && IsObject(params) ? params : Map()
        if payload.Has("text") {
            text := payload["text"] ""
            return this.App.Clipboard.Run(this._WithTemporaryClipboard.Bind(this, text, callback))
        }
        return callback.Call("")
    }

    _WithTemporaryClipboard(text, callback) {
        A_Clipboard := text
        if !ClipWait(0.5)
            return AQResult.Failed("Temporary clipboard text did not become available")
        return callback.Call(text)
    }

    _ValidatedTarget() {
        target := this.Targets.Get()
        if !target.Count
            return AQResult.Invalid("No F04 paste target has been captured")

        maxAge := this.App.Config.GetInt("F04", "target_max_age_ms", 300000)
        if maxAge > 0 && target.Has("captured_at") && A_TickCount - target["captured_at"] > maxAge
            return AQResult.Rejected("Paste target expired and must be recaptured")
        if !this.App.Windows.StillMatches(target)
            return AQResult.Rejected("Paste target became stale")

        if target.Has("control_hwnd") && target["control_hwnd"] {
            control := this.App.Windows.Describe(target["control_hwnd"])
            if !control["pid"] || control["pid"] != target["pid"]
                return AQResult.Rejected("Paste target control became stale or changed process")
        }
        return AQResult.Ok("Paste target revalidated", Map("target", target))
    }

    _AdapterFor(controlHwnd, terminalKind) {
        if controlHwnd {
            control := this.App.Windows.Describe(controlHwnd)
            if StrLower(control["class"]) = "edit"
                return "standard_edit"
        }
        if terminalKind = "WindowsTerminal"
            return "windowsterminal"
        if terminalKind = "conhost"
            return "conhost"
        return "unknown"
    }

    _CapabilityId(adapter, target) {
        if adapter = "standard_edit"
            return "terminal.standard_edit.can_background_paste"
        return "terminal." this._CapabilityKind(target) ".can_background_paste"
    }

    _CapabilityKind(target) {
        terminalKind := target.Has("terminal") ? target["terminal"] : "unknown"
        normalized := RegExReplace(StrLower(terminalKind), "[^a-z0-9]+", "_")
        return normalized != "" ? normalized : "unknown"
    }

    _CapabilitySummary() {
        return Map(
            "standard_edit", this.App.Capabilities.Get("terminal.standard_edit.can_background_paste"),
            "windowsterminal", this.App.Capabilities.Get("terminal.windowsterminal.can_background_paste"),
            "conhost", this.App.Capabilities.Get("terminal.conhost.can_background_paste"),
            "unknown", this.App.Capabilities.Get("terminal.unknown.can_background_paste")
        )
    }

    _PublicTarget(target) {
        if !IsObject(target) || !target.Count
            return Map()
        return Map(
            "hwnd", target.Has("hwnd") ? target["hwnd"] : 0,
            "pid", target.Has("pid") ? target["pid"] : 0,
            "exe", target.Has("exe") ? target["exe"] : "",
            "class", target.Has("class") ? target["class"] : "",
            "terminal", target.Has("terminal") ? target["terminal"] : "unknown",
            "control_hwnd", target.Has("control_hwnd") ? target["control_hwnd"] : 0,
            "adapter", target.Has("adapter") ? target["adapter"] : "",
            "captured_at", target.Has("captured_at") ? target["captured_at"] : 0
        )
    }
}

class F04FocusPreservingPasteModule {
    __New() {
        this.Id := "F04"
        this.Name := "Focus-preserving terminal paste"
        this.Service := ""
        this.CaptureHotkey := ""
        this.PasteHotkey := ""
        this.FallbackHotkey := ""
    }

    Init(app) {
        this.Service := F04PasteService(app)
        app.Actions.Register("terminal.paste_target_capture_mouse", this._CaptureMouse.Bind(this), "Capture paste target under pointer without activation", "S0")
        app.Actions.Register("terminal.paste_target_set", this._SetTarget.Bind(this), "Set F04 paste target explicitly", "S0")
        app.Actions.Register("terminal.paste_target_clear", this._Clear.Bind(this), "Clear F04 paste target", "S0")
        app.Actions.Register("terminal.paste_target_status", this._Status.Bind(this), "Show F04 target/capability status", "S0")
        app.Actions.Register("terminal.paste_probe", this._Probe.Bind(this), "Run F04 background-paste capability probes", "S1")
        app.Actions.Register("terminal.paste_background", this._Background.Bind(this), "Paste only through a verified focus-preserving adapter", "S1")
        app.Actions.Register("terminal.paste_focus_handoff", this._Fallback.Bind(this), "Paste through explicitly degraded activate/send/restore mode", "S1")

        this.CaptureHotkey := Trim(app.Config.Get("F04", "capture_hotkey", ""))
        this.PasteHotkey := Trim(app.Config.Get("F04", "background_paste_hotkey", ""))
        this.FallbackHotkey := Trim(app.Config.Get("F04", "focus_handoff_hotkey", ""))
        this._InstallHotkeys()

        if app.Config.GetBool("F04", "probe_on_start", false)
            this.Service.ProbeCapabilities()
        else
            this._SetUnknownDefaults(app)
    }

    Teardown(app) {
        for spec in [this.CaptureHotkey, this.PasteHotkey, this.FallbackHotkey] {
            if spec != "" {
                try Hotkey(spec, "Off")
            }
        }
        for actionId in [
            "terminal.paste_target_capture_mouse",
            "terminal.paste_target_set",
            "terminal.paste_target_clear",
            "terminal.paste_target_status",
            "terminal.paste_probe",
            "terminal.paste_background",
            "terminal.paste_focus_handoff"
        ]
            app.Actions.Unregister(actionId)
        this.Service := ""
    }

    _InstallHotkeys() {
        if this.CaptureHotkey != ""
            Hotkey(this.CaptureHotkey, (*) => this.Service.CaptureMouseTarget(), "On")
        if this.PasteHotkey != ""
            Hotkey(this.PasteHotkey, (*) => this.Service.BackgroundPaste(), "On")
        if this.FallbackHotkey != ""
            Hotkey(this.FallbackHotkey, (*) => this.Service.FocusHandoffPaste(), "On")
    }

    _SetUnknownDefaults(app) {
        defaults := Map(
            "terminal.standard_edit.can_background_paste", "Run terminal.paste_probe to verify standard Edit ControlSend paste on this machine",
            "terminal.windowsterminal.can_background_paste", "Windows Terminal true background paste has not been verified",
            "terminal.conhost.can_background_paste", "conhost true background paste has not been verified",
            "terminal.unknown.can_background_paste", "No verified adapter exists for arbitrary windows"
        )
        for capabilityId, detail in defaults {
            if !app.Capabilities.Has(capabilityId)
                app.Capabilities.Set(capabilityId, "unknown", detail)
        }
    }

    _CaptureMouse(params) {
        return this.Service.CaptureMouseTarget()
    }

    _SetTarget(params) {
        if !params.Has("hwnd") || !params["hwnd"]
            return AQResult.Invalid("terminal.paste_target_set requires hwnd")
        controlHwnd := params.Has("control_hwnd") ? params["control_hwnd"] : 0
        return this.Service.SetTarget(params["hwnd"], controlHwnd)
    }

    _Clear(params) {
        return this.Service.ClearTarget()
    }

    _Status(params) {
        return this.Service.Status()
    }

    _Probe(params) {
        return this.Service.ProbeCapabilities()
    }

    _Background(params) {
        return this.Service.BackgroundPaste(params)
    }

    _Fallback(params) {
        return this.Service.FocusHandoffPaste(params)
    }
}
