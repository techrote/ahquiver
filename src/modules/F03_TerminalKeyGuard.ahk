#Requires AutoHotkey v2.0

class F03RuleStore {
    __New(config) {
        this.Config := config
    }

    Ids() {
        ids := []
        seen := Map()
        for part in StrSplit(this.Config.Get("F03", "rules", ""), ",") {
            id := Trim(part)
            if id = "" || seen.Has(id)
                continue
            if !RegExMatch(id, "^[A-Za-z0-9_.-]+$")
                continue
            seen[id] := true
            ids.Push(id)
        }
        return ids
    }

    Get(id) {
        if !RegExMatch(id, "^[A-Za-z0-9_.-]+$")
            return AQResult.Invalid("Invalid F03 rule id: " id)

        found := false
        for candidate in this.Ids() {
            if candidate = id {
                found := true
                break
            }
        }
        if !found
            return AQResult.Invalid("Unknown F03 rule: " id)

        section := "F03.rule." id
        policy := StrLower(Trim(this.Config.Get(section, "policy", "pass_through")))
        allowed := Map(
            "pass_through", true,
            "double_tap", true,
            "hold", true,
            "confirm", true,
            "remap", true
        )
        if !allowed.Has(policy)
            return AQResult.Invalid("Invalid F03 policy for " id ": " policy)

        doubleTapMs := this.Config.GetInt(section, "double_tap_ms", 450)
        holdMs := this.Config.GetInt(section, "hold_ms", 450)
        if doubleTapMs < 50 || doubleTapMs > 5000
            return AQResult.Invalid("F03 rule " id " double_tap_ms must be between 50 and 5000")
        if holdMs < 50 || holdMs > 5000
            return AQResult.Invalid("F03 rule " id " hold_ms must be between 50 and 5000")

        remapChord := Trim(this.Config.Get(section, "remap_chord", ""))
        if policy = "remap" && remapChord = ""
            return AQResult.Invalid("F03 remap rule " id " requires remap_chord")

        rule := Map(
            "id", id,
            "policy", policy,
            "terminal", Trim(this.Config.Get(section, "terminal", "")),
            "exe", Trim(this.Config.Get(section, "exe", "")),
            "class", Trim(this.Config.Get(section, "class", "")),
            "title_contains", this.Config.Get(section, "title_contains", ""),
            "identity", this.Config.Get(section, "identity", ""),
            "role", this.Config.Get(section, "role", ""),
            "double_tap_ms", doubleTapMs,
            "hold_ms", holdMs,
            "remap_chord", remapChord,
            "selection_copy_passthrough", this.Config.GetBool(section, "selection_copy_passthrough", true)
        )
        return AQResult.Ok("F03 rule loaded", Map("rule", rule))
    }

    ValidateAll() {
        for id in this.Ids() {
            loaded := this.Get(id)
            if !loaded.IsOk()
                return loaded
        }
        return AQResult.Ok("F03 rules valid", Map("count", this.Ids().Length))
    }

    Match(context, identityRecord := unset) {
        identity := IsSet(identityRecord) ? identityRecord : Map()
        for id in this.Ids() {
            loaded := this.Get(id)
            if !loaded.IsOk()
                continue
            rule := loaded.Data["rule"]
            if this._Matches(rule, context, identity)
                return rule
        }
        return Map()
    }

    _Matches(rule, context, identity) {
        if rule["terminal"] != "" {
            actual := context.Has("terminal") ? context["terminal"] : ""
            if StrLower(actual) != StrLower(rule["terminal"])
                return false
        }
        if rule["exe"] != "" {
            actual := context.Has("exe") ? context["exe"] : ""
            if StrLower(actual) != StrLower(rule["exe"])
                return false
        }
        if rule["class"] != "" {
            actual := context.Has("class") ? context["class"] : ""
            if StrLower(actual) != StrLower(rule["class"])
                return false
        }
        if rule["title_contains"] != "" {
            actual := context.Has("title") ? context["title"] : ""
            if !InStr(StrLower(actual), StrLower(rule["title_contains"]))
                return false
        }
        if rule["identity"] != "" {
            actual := identity.Has("identity") ? identity["identity"] : ""
            if StrLower(actual) != StrLower(rule["identity"])
                return false
        }
        if rule["role"] != "" {
            actual := identity.Has("role") ? identity["role"] : ""
            if StrLower(actual) != StrLower(rule["role"])
                return false
        }
        return true
    }
}

class F03Clock {
    Now() {
        return A_TickCount
    }
}

class F03Sender {
    Send(chord) {
        try {
            SendEvent(chord)
            return AQResult.Ok("Chord delivered", Map("chord", chord))
        } catch as sendError {
            return AQResult.Failed("Could not deliver chord: " sendError.Message)
        }
    }
}

class F03HoldProbe {
    HeldFor(keyName, thresholdMs) {
        if Trim(keyName) = ""
            return false
        timeoutSeconds := Max(thresholdMs, 0) / 1000.0
        try released := KeyWait(keyName, "T" timeoutSeconds)
        catch
            return false
        return !released
    }
}

class F03Confirmer {
    Confirm(rule, context) {
        answer := MsgBox(
            "Send guarded terminal chord?`n`nPolicy: " rule["id"],
            "AHQuiver terminal guard",
            "YesNo Icon!"
        )
        return answer = "Yes"
    }
}

class F03SelectionProbe {
    HasSelection(context) {
        ; No generic reliable selection detector is assumed. A future adapter may
        ; replace this only after registering a supported capability.
        return false
    }
}

class F03Feedback {
    __New(config) {
        this.Config := config
    }

    Emit(message) {
        mode := StrLower(Trim(this.Config.Get("F03", "feedback", "tray")))
        if mode = "none"
            return
        if mode = "sound" {
            try SoundBeep(900, 70)
            return
        }
        try TrayTip("AHQuiver terminal guard", message)
    }
}

class F03GuardService {
    __New(app, store, sender := unset, clock := unset, holdProbe := unset, confirmer := unset, selectionProbe := unset, feedback := unset) {
        this.App := app
        this.Store := store
        this.Sender := IsSet(sender) ? sender : F03Sender()
        this.Clock := IsSet(clock) ? clock : F03Clock()
        this.HoldProbe := IsSet(holdProbe) ? holdProbe : F03HoldProbe()
        this.Confirmer := IsSet(confirmer) ? confirmer : F03Confirmer()
        this.Selection := IsSet(selectionProbe) ? selectionProbe : F03SelectionProbe()
        this.Feedback := IsSet(feedback) ? feedback : F03Feedback(app.Config)
        this.GuardEnabled := true
        this.BypassOnce := false
        this.LastTap := Map()
    }

    Handle(chord, holdKey := "c") {
        if !this.GuardEnabled
            return this.Sender.Send(chord)

        context := this.App.Context.Capture()
        identity := this._IdentityFor(context)
        rule := this.Store.Match(context, identity)
        if !rule.Count
            return this.Sender.Send(chord)

        if this.BypassOnce {
            this.BypassOnce := false
            return this._Deliver(chord, context, rule, "bypass_once")
        }

        if rule["selection_copy_passthrough"] && this._SelectionIsKnownAndActive(context)
            return this._Deliver(chord, context, rule, "selection_copy")

        policy := rule["policy"]
        if policy = "pass_through"
            return this._Deliver(chord, context, rule, "pass_through")

        if policy = "double_tap" {
            now := this.Clock.Now()
            previous := this.LastTap.Has(rule["id"]) ? this.LastTap[rule["id"]] : -1
            if previous >= 0 && now >= previous && now - previous <= rule["double_tap_ms"] {
                this.LastTap.Delete(rule["id"])
                return this._Deliver(chord, context, rule, "double_tap_confirmed")
            }
            this.LastTap[rule["id"]] := now
            this.Feedback.Emit("Guarded: press again to send " chord)
            this._LogDecision(rule, context, "blocked_first_tap")
            return AQResult.Cancelled("First guarded tap blocked", Map("policy", policy, "rule", rule["id"]))
        }

        if policy = "hold" {
            if this.HoldProbe.HeldFor(holdKey, rule["hold_ms"])
                return this._Deliver(chord, context, rule, "hold_confirmed")
            this.Feedback.Emit("Guarded: hold the key to send " chord)
            this._LogDecision(rule, context, "blocked_short_hold")
            return AQResult.Cancelled("Guarded chord was not held long enough", Map("policy", policy, "rule", rule["id"]))
        }

        if policy = "confirm" {
            if this.Confirmer.Confirm(rule, context)
                return this._Deliver(chord, context, rule, "confirmed")
            this._LogDecision(rule, context, "confirmation_cancelled")
            return AQResult.Cancelled("Guarded chord cancelled", Map("policy", policy, "rule", rule["id"]))
        }

        if policy = "remap"
            return this._Deliver(rule["remap_chord"], context, rule, "remapped")

        return AQResult.Invalid("Unhandled F03 policy: " policy)
    }

    BypassCurrent(chord) {
        context := this.App.Context.Capture()
        identity := this._IdentityFor(context)
        rule := this.Store.Match(context, identity)
        if !rule.Count
            return this.Sender.Send(chord)
        return this._Deliver(chord, context, rule, "bypass_hotkey")
    }

    ArmBypassOnce() {
        this.BypassOnce := true
        this.Feedback.Emit("Next guarded chord will pass through")
        return AQResult.Ok("One-shot bypass armed")
    }

    SetEnabled(enabled) {
        this.GuardEnabled := !!enabled
        if !this.GuardEnabled {
            this.BypassOnce := false
            this.LastTap.Clear()
        }
        return AQResult.Ok("Terminal guard runtime state changed", Map("enabled", this.GuardEnabled))
    }

    Toggle() {
        return this.SetEnabled(!this.GuardEnabled)
    }

    Status() {
        return AQResult.Ok("Terminal guard status", Map(
            "enabled", this.GuardEnabled,
            "bypass_once", this.BypassOnce,
            "rule_count", this.Store.Ids().Length
        ))
    }

    _Deliver(chord, expectedContext, rule, outcome) {
        current := this.App.Context.Capture()
        if !this._SameTarget(expectedContext, current) {
            this.Feedback.Emit("Guarded chord cancelled: foreground changed")
            this._LogDecision(rule, expectedContext, "stale_context")
            return AQResult.Rejected("Foreground terminal changed before guarded action")
        }

        sent := this.Sender.Send(chord)
        if sent.IsOk()
            this._LogDecision(rule, current, outcome)
        else
            this._LogDecision(rule, current, "send_failed")
        return sent
    }

    _SameTarget(expected, current) {
        for key in ["hwnd", "pid", "exe", "class"] {
            expectedValue := expected.Has(key) ? expected[key] : ""
            currentValue := current.Has(key) ? current[key] : ""
            if expectedValue != currentValue
                return false
        }
        return true
    }

    _IdentityFor(context) {
        if !context.Has("pid") || !context["pid"]
            return Map()
        if !HasProp(this.App, "Identities") || !IsObject(this.App.Identities)
            return Map()
        return this.App.Identities.FindActiveByPid(context["pid"])
    }

    _SelectionIsKnownAndActive(context) {
        terminalKind := context.Has("terminal") ? context["terminal"] : "unknown"
        normalized := RegExReplace(StrLower(terminalKind), "[^a-z0-9]+", "_")
        if normalized = ""
            normalized := "unknown"
        capability := this.App.Capabilities.Get("terminal." normalized ".can_detect_selection")
        if capability["status"] != "supported"
            return false
        try return !!this.Selection.HasSelection(context)
        catch
            return false
    }

    _LogDecision(rule, context, outcome) {
        if !this.App.Config.GetBool("F03", "log_decisions", true)
            return
        terminalKind := context.Has("terminal") ? context["terminal"] : "unknown"
        exeName := context.Has("exe") ? context["exe"] : ""
        pid := context.Has("pid") ? context["pid"] : 0
        this.App.Log.Info(
            "f03 rule=" rule["id"]
            " policy=" rule["policy"]
            " outcome=" outcome
            " terminal=" terminalKind
            " exe=" exeName
            " pid=" pid
        )
    }
}

class F03TerminalKeyGuardModule {
    __New() {
        this.Id := "F03"
        this.Name := "Context-sensitive safe terminal key guard"
        this.App := ""
        this.Service := ""
        this.GuardHotkey := ""
        this.BypassHotkey := ""
        this.ToggleHotkey := ""
        this.Chord := "^c"
        this.HoldKey := "c"
    }

    Init(app) {
        store := F03RuleStore(app.Config)
        validation := store.ValidateAll()
        if !validation.IsOk()
            throw Error(validation.Message)

        this.App := app
        this.Chord := Trim(app.Config.Get("F03", "chord", "^c"))
        this.HoldKey := Trim(app.Config.Get("F03", "hold_key", "c"))
        if this.Chord = ""
            throw Error("F03 chord cannot be empty")

        this.Service := F03GuardService(app, store)
        app.Actions.Register("terminal.guard_status", this._Status.Bind(this), "Show F03 terminal guard state", "S0")
        app.Actions.Register("terminal.guard_bypass_once", this._BypassOnce.Bind(this), "Allow the next guarded chord once", "S0")
        app.Actions.Register("terminal.guard_enable", this._Enable.Bind(this), "Enable the F03 runtime guard", "S0")
        app.Actions.Register("terminal.guard_disable", this._Disable.Bind(this), "Disable the F03 runtime guard immediately", "S0")
        app.Actions.Register("terminal.guard_toggle", this._Toggle.Bind(this), "Toggle the F03 runtime guard", "S0")

        this.GuardHotkey := this._GuardSpec(app.Config.Get("F03", "hotkey", "^c"))
        this.BypassHotkey := Trim(app.Config.Get("F03", "bypass_hotkey", "^+c"))
        this.ToggleHotkey := Trim(app.Config.Get("F03", "toggle_hotkey", "^!c"))
        this._ValidateHotkeys()
        this._InstallHotkeys()

        capabilityId := "terminal.windowsterminal.can_detect_selection"
        if !app.Capabilities.Has(capabilityId)
            app.Capabilities.Set(capabilityId, "unknown", "F03 has no proven generic Windows Terminal selection detector")
    }

    Teardown(app) {
        this._DisableHotkey(this.GuardHotkey)
        this._DisableHotkey(this.BypassHotkey)
        this._DisableHotkey(this.ToggleHotkey)
        for actionId in [
            "terminal.guard_status",
            "terminal.guard_bypass_once",
            "terminal.guard_enable",
            "terminal.guard_disable",
            "terminal.guard_toggle"
        ]
            app.Actions.Unregister(actionId)
        this.Service := ""
        this.App := ""
    }

    _InstallHotkeys() {
        if this.GuardHotkey != ""
            Hotkey(this.GuardHotkey, this._GuardPressed.Bind(this), "On")
        if this.BypassHotkey != ""
            Hotkey(this.BypassHotkey, this._BypassPressed.Bind(this), "On")
        if this.ToggleHotkey != ""
            Hotkey(this.ToggleHotkey, this._TogglePressed.Bind(this), "On")
    }

    _ValidateHotkeys() {
        plainGuard := StrReplace(this.GuardHotkey, "$", "")
        if plainGuard != "" && (plainGuard = this.BypassHotkey || plainGuard = this.ToggleHotkey)
            throw Error("F03 guard hotkey must differ from bypass/toggle hotkeys")
        if this.BypassHotkey != "" && this.BypassHotkey = this.ToggleHotkey
            throw Error("F03 bypass_hotkey and toggle_hotkey must differ")
    }

    _GuardSpec(raw) {
        spec := Trim(raw)
        if spec = ""
            return ""
        if SubStr(spec, 1, 1) = "$"
            return spec
        return "$" spec
    }

    _SetGuardHotkeyEnabled(enabled) {
        if this.GuardHotkey = ""
            return
        try Hotkey(this.GuardHotkey, enabled ? "On" : "Off")
    }

    _DisableHotkey(spec) {
        if spec = ""
            return
        try Hotkey(spec, "Off")
    }

    _GuardPressed(*) {
        this.Service.Handle(this.Chord, this.HoldKey)
    }

    _BypassPressed(*) {
        this.Service.BypassCurrent(this.Chord)
    }

    _TogglePressed(*) {
        result := this.Service.Toggle()
        this._SetGuardHotkeyEnabled(result.Data["enabled"])
        try TrayTip("AHQuiver terminal guard", result.Data["enabled"] ? "Enabled" : "Disabled")
    }

    _Status(params) {
        return this.Service.Status()
    }

    _BypassOnce(params) {
        return this.Service.ArmBypassOnce()
    }

    _Enable(params) {
        result := this.Service.SetEnabled(true)
        this._SetGuardHotkeyEnabled(true)
        return result
    }

    _Disable(params) {
        result := this.Service.SetEnabled(false)
        this._SetGuardHotkeyEnabled(false)
        return result
    }

    _Toggle(params) {
        result := this.Service.Toggle()
        this._SetGuardHotkeyEnabled(result.Data["enabled"])
        return result
    }
}
