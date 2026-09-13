#Requires AutoHotkey v2.0

class F04PasteTargetStore {
    __New() => this.Target := Map()
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
    Clear() => this.Target := Map()
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
        catch as activationError
            return AQResult.Failed("Could not activate target: " activationError.Message)
        active := 0
        try active := WinWaitActive(selector, , Max(timeoutMs, 0) / 1000.0)
        catch
            active := 0
        return active ? AQResult.Ok("Target activated") : AQResult.Failed("Target did not become foreground within timeout")
    }
    Restore(hwnd, timeoutMs := 750) {
        if !hwnd || !WinExist("ahk_id " hwnd)
            return AQResult.Failed("Original foreground window no longer exists")
        result := this.Activate(hwnd, timeoutMs)
        if !result.IsOk()
            return result
        return this.ActiveHwnd() = hwnd ? AQResult.Ok("Foreground restored") : AQResult.Failed("Original foreground window was not restored")
    }
}

class F04SystemTransport {
    BackgroundPaste(controlHwnd) {
        if !controlHwnd
            return AQResult.Invalid("Verified background paste requires a control HWND")
        try ControlSend("^v", controlHwnd)
        catch as sendError
            return AQResult.Failed("Background ControlSend failed: " sendError.Message)
        return AQResult.Ok("Background paste chord sent")
    }
    FocusHandoffPaste(targetHwnd, controlHwnd := 0) {
        if controlHwnd {
            try ControlFocus(controlHwnd)
        }
        try SendEvent("^v")
        catch as sendError
            return AQResult.Failed("Foreground paste send failed: " sendError.Message)
        return AQResult.Ok("Foreground paste chord sent")
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
        this._SetUnknown("windowsterminal", "No reliable Windows Terminal output/readback oracle is available; a successful ControlSend call alone is not proof")
        this._SetUnknown("conhost", "No reliable conhost paste readback oracle is implemented")
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
        SendMessage(0xB1, 12, 12, edit.Hwnd)
        token := "AQF04-" A_TickCount "-" Random(1000, 9999)
        try {
            result := this.App.Clipboard.Run(this._ProbeWithClipboard.Bind(this, edit.Hwnd, token, originalForeground))
            if result.IsOk()
                this.App.Capabilities.Set(capabilityId, "supported", "Self-probe verified ControlSend Ctrl+V into standard Edit while preserving foreground")
            else
                this.App.Capabilities.Set(capabilityId, "unsupported", result.Message)
        } catch as probeError {
            this.App.Capabilities.Set(capabilityId, "unsupported", "Standard Edit probe failed: " probeError.Message)
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
        try observed := ControlGetText(controlHwnd)
        catch as readError
            return AQResult.Failed("Probe could not read standard Edit text: " readError.Message)
        if observed != "probe-before" token
            return AQResult.Failed("Probe could not verify expected Edit content")
        if originalForeground && this.Foreground.ActiveHwnd() != originalForeground
            return AQResult.Failed("Background-paste probe changed foreground focus")
        return AQResult.Ok("Standard Edit background paste verified")
    }
    _SetUnknown(kind, detail) => this.App.Capabilities.Set("terminal." kind ".can_background_paste", "unknown", detail)
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
        winHwnd := 0, controlHwnd := 0
        try MouseGetPos(, , &winHwnd, &controlHwnd, 2)
        catch as mouseError
            return AQResult.Failed("Could not identify window under pointer: " mouseError.Message)
        return winHwnd ? this.SetTarget(winHwnd, controlHwnd) : AQResult.Rejected("No target window under pointer")
    }
    SetTarget(winHwnd, controlHwnd := 0) {
        snapshot := this.App.Windows.Describe(winHwnd)
        if !snapshot["pid"]
            return AQResult.Rejected("Target HWND is not a live attributable window")
        snapshot["terminal"] := this.App.Context.ClassifyTerminal(snapshot["exe"])
        if controlHwnd {
            control := this.App.Windows.Describe(controlHwnd)
            if !control["pid"] || control["pid"] != snapshot["pid"]
                return AQResult.Rejected("Target control does not belong to target process")
        }
        adapter := this._AdapterFor(controlHwnd, snapshot["terminal"])
        target := this.Targets.Set(snapshot, controlHwnd, adapter)
        return AQResult.Ok("F04 paste target captured", Map("target", this._PublicTarget(target)))
    }
    ClearTarget() {
        this.Targets.Clear()
        return AQResult.Ok("F04 paste target cleared")
    }
    Status() {
        target := this.Targets.Get()
        return AQResult.Ok("F04 paste target status", Map("has_target", target.Count > 0, "target", this._PublicTarget(target), "capabilities", this._CapabilitySummary()))
    }
    ProbeCapabilities() => this.Probe.RunAll()

    BackgroundPaste(params := unset) {
        checked := this._ValidatedTarget()
        if !checked.IsOk()
            return checked
        target := checked.Data["target"]
        capabilityId := this._CapabilityId(target)
        capability := this.App.Capabilities.Get(capabilityId)
        if target["adapter"] = "standard_edit" && capability["status"] = "unknown" && this.App.Config.GetBool("F04", "auto_probe_standard_edit", true) {
            this.Probe.ProbeStandardEdit()
            capability := this.App.Capabilities.Get(capabilityId)
        }
        if capability["status"] != "supported"
            return AQResult.Unsupported("No verified focus-preserving paste capability for this target", Map("capability", capability, "target", this._PublicTarget(target)))
        if target["adapter"] != "standard_edit"
            return AQResult.Unsupported("No production background adapter is implemented for " target["adapter"])
        beforeForeground := this.Foreground.ActiveHwnd()
        operation := this._RunWithOptionalText(params, this._VerifiedEditBackgroundPaste.Bind(this, target))
        afterForeground := this.Foreground.ActiveHwnd()
        if beforeForeground && afterForeground != beforeForeground {
            this.App.Capabilities.Set(capabilityId, "degraded", "A supposedly background operation changed foreground focus")
            return AQResult.Failed("Focus-preserving paste changed foreground focus", Map("before_hwnd", beforeForeground, "after_hwnd", afterForeground))
        }
        return operation
    }

    FocusHandoffPaste(params := unset) {
        if !this.App.Config.GetBool("F04", "allow_focus_handoff", false)
            return AQResult.Unsupported("Degraded focus-handoff paste is disabled by configuration")
        checked := this._ValidatedTarget()
        if !checked.IsOk()
            return checked
        target := checked.Data["target"]
        originalForeground := this.Foreground.ActiveHwnd()
        if !originalForeground
            return AQResult.Failed("Could not capture original foreground window")
        action := this._RunWithOptionalText(params, this._FocusHandoffOperation.Bind(this, target, originalForeground))
        if action.IsOk()
            this.App.Capabilities.Set("terminal." this._CapabilityKind(target) ".focus_handoff_paste", "degraded", "Requires temporary activation/send/restore; not true background paste")
        return action
    }

    _VerifiedEditBackgroundPaste(target, text) {
        controlHwnd := target["control_hwnd"]
        try before := ControlGetText(controlHwnd)
        catch as readError
            return AQResult.Failed("Could not read Edit control before paste: " readError.Message)
        clipboardText := text != "" ? text : A_Clipboard
        if clipboardText = ""
            return AQResult.Invalid("Clipboard contains no text to paste")
        if InStr(clipboardText, "`n") || InStr(clipboardText, "`r")
            return AQResult.Unsupported("Verified standard-Edit adapter currently supports single-line text only")
        try selection := SendMessage(0xB0, 0, 0, controlHwnd)
        catch as selectionError
            return AQResult.Failed("Could not query Edit selection: " selectionError.Message)
        startPos := selection & 0xFFFF
        endPos := (selection >> 16) & 0xFFFF
        expected := SubStr(before, 1, startPos) clipboardText SubStr(before, endPos + 1)
        sent := this.Transport.BackgroundPaste(controlHwnd)
        if !sent.IsOk()
            return sent
        Sleep(30)
        try observed := ControlGetText(controlHwnd)
        catch as verifyError
            return AQResult.Failed("Could not verify Edit text after paste: " verifyError.Message)
        if observed != expected
            return AQResult.Failed("Background paste could not be verified by Edit readback")
        return AQResult.Ok("Focus-preserving background paste verified", Map("mode", "background", "adapter", "standard_edit", "verified", true, "target", this._PublicTarget(target)))
    }

    _FocusHandoffOperation(target, originalForeground, text) {
        activation := this.Foreground.Activate(target["hwnd"], this.App.Config.GetInt("F04", "activation_timeout_ms", 750))
        if !activation.IsOk()
            return activation
        sent := ""
        restore := ""
        try sent := this.Transport.FocusHandoffPaste(target["hwnd"], target["control_hwnd"])
        finally restore := this.Foreground.Restore(originalForeground, this.App.Config.GetInt("F04", "restore_timeout_ms", 750))
        if !sent.IsOk()
            return sent
        if !restore.IsOk()
            return AQResult.Failed("Paste was sent but foreground restoration failed: " restore.Message)
        return AQResult.Ok("Paste sent via degraded focus handoff", Map("mode", "focus_handoff", "capability_status", "degraded", "foreground_restored", true, "target", this._PublicTarget(target)))
    }

    _RunWithOptionalText(params, callback) {
        payload := IsSet(params) && IsObject(params) ? params : Map()
        if payload.Has("text")
            return this.App.Clipboard.Run(this._WithTemporaryClipboard.Bind(this, payload["text"] "", callback))
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
        if maxAge > 0 && A_TickCount - target["captured_at"] > maxAge
            return AQResult.Rejected("Paste target expired and must be recaptured")
        if !this.App.Windows.StillMatches(target)
            return AQResult.Rejected("Paste target became stale")
        if target["control_hwnd"] {
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
    _CapabilityId(target) => target["adapter"] = "standard_edit" ? "terminal.standard_edit.can_background_paste" : "terminal." this._CapabilityKind(target) ".can_background_paste"
    _CapabilityKind(target) {
        kind := target.Has("terminal") ? target["terminal"] : "unknown"
        normalized := RegExReplace(StrLower(kind), "[^a-z0-9]+", "_")
        return normalized != "" ? normalized : "unknown"
    }
    _CapabilitySummary() => Map(
        "standard_edit", this.App.Capabilities.Get("terminal.standard_edit.can_background_paste"),
        "windowsterminal", this.App.Capabilities.Get("terminal.windowsterminal.can_background_paste"),
        "conhost", this.App.Capabilities.Get("terminal.conhost.can_background_paste"),
        "unknown", this.App.Capabilities.Get("terminal.unknown.can_background_paste")
    )
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
        this.Id := "F04", this.Name := "Focus-preserving terminal paste", this.Service := ""
        this.CaptureHotkey := "", this.PasteHotkey := "", this.FallbackHotkey := ""
    }
    Init(app) {
        this.Service := F04PasteService(app)
        app.Actions.Register("terminal.paste_target_capture_mouse", (*) => this.Service.CaptureMouseTarget(), "Capture paste target under pointer without activation", "S0")
        app.Actions.Register("terminal.paste_target_set", this._SetTarget.Bind(this), "Set F04 paste target explicitly", "S0")
        app.Actions.Register("terminal.paste_target_clear", (*) => this.Service.ClearTarget(), "Clear F04 paste target", "S0")
        app.Actions.Register("terminal.paste_target_status", (*) => this.Service.Status(), "Show F04 target/capability status", "S0")
        app.Actions.Register("terminal.paste_probe", (*) => this.Service.ProbeCapabilities(), "Run F04 background-paste capability probes", "S1")
        app.Actions.Register("terminal.paste_background", this._Background.Bind(this), "Paste only through a verified focus-preserving adapter", "S1")
        app.Actions.Register("terminal.paste_focus_handoff", this._Fallback.Bind(this), "Paste through explicitly degraded activate/send/restore mode", "S1")
        this.CaptureHotkey := Trim(app.Config.Get("F04", "capture_hotkey", ""))
        this.PasteHotkey := Trim(app.Config.Get("F04", "background_paste_hotkey", ""))
        this.FallbackHotkey := Trim(app.Config.Get("F04", "focus_handoff_hotkey", ""))
        if this.CaptureHotkey != ""
            Hotkey(this.CaptureHotkey, (*) => this.Service.CaptureMouseTarget(), "On")
        if this.PasteHotkey != ""
            Hotkey(this.PasteHotkey, (*) => this.Service.BackgroundPaste(), "On")
        if this.FallbackHotkey != ""
            Hotkey(this.FallbackHotkey, (*) => this.Service.FocusHandoffPaste(), "On")
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
        for actionId in ["terminal.paste_target_capture_mouse", "terminal.paste_target_set", "terminal.paste_target_clear", "terminal.paste_target_status", "terminal.paste_probe", "terminal.paste_background", "terminal.paste_focus_handoff"]
            app.Actions.Unregister(actionId)
        this.Service := ""
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
    _SetTarget(params) {
        if !params.Has("hwnd") || !params["hwnd"]
            return AQResult.Invalid("terminal.paste_target_set requires hwnd")
        return this.Service.SetTarget(params["hwnd"], params.Has("control_hwnd") ? params["control_hwnd"] : 0)
    }
    _Background(params) => this.Service.BackgroundPaste(params)
    _Fallback(params) => this.Service.FocusHandoffPaste(params)
}
