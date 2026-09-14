#Requires AutoHotkey v2.0

class F08SystemHotkeys {
    __New() {
        this.Registered := Map()
    }

    Register(chord, callback) {
        try {
            Hotkey(chord, callback, "On")
            this.Registered[chord] := callback
            return AQResult.Ok("Hotkey registered", Map("hotkey", chord))
        } catch as err {
            return AQResult.Failed("Hotkey registration failed: " err.Message, Map("hotkey", chord))
        }
    }

    Disable(chord) {
        if !this.Registered.Has(chord)
            return false
        try Hotkey(chord, "Off")
        this.Registered.Delete(chord)
        return true
    }

    Teardown() {
        chords := []
        for chord, _ in this.Registered
            chords.Push(chord)
        for chord in chords
            this.Disable(chord)
    }
}

class F08ProfileStore {
    __New(config) {
        this.Config := config
        this.Items := Map()
        this.Diagnostics := []
        this._Load()
    }

    _Load() {
        ids := this._Csv(this.Config.Get("F08", "profiles", ""))
        for id in ids {
            section := "F08.profile." id
            if !this.Config.GetBool(section, "enabled", true)
                continue
            item := Map(
                "id", id,
                "priority", this.Config.GetInt(section, "priority", 0),
                "exe", StrLower(Trim(this.Config.Get(section, "exe", ""))),
                "class", StrLower(Trim(this.Config.Get(section, "class", ""))),
                "identity", StrLower(Trim(this.Config.Get(section, "identity", "")))
            )
            this.Items[id] := item
        }
    }

    Get(id) {
        return this.Items.Has(id) ? this.Items[id] : Map()
    }

    BestAutomatic(context) {
        best := ""
        bestPriority := -2147483648
        for id, profile in this.Items {
            if !this.Matches(profile, context)
                continue
            priority := profile["priority"]
            if best = "" || priority > bestPriority || (priority = bestPriority && StrCompare(id, best) < 0) {
                best := id
                bestPriority := priority
            }
        }
        return best
    }

    Matches(profile, context) {
        if profile["exe"] != "" && StrLower(context["exe"]) != profile["exe"]
            return false
        if profile["class"] != "" && StrLower(context["class"]) != profile["class"]
            return false
        if profile["identity"] != "" && StrLower(context["project_identity"]) != profile["identity"]
            return false
        return true
    }

    _Csv(raw) {
        items := []
        for part in StrSplit(raw, ",") {
            value := Trim(part)
            if value != ""
                items.Push(value)
        }
        return items
    }
}

class F08BindingStore {
    __New(config, actions, profiles) {
        this.Config := config
        this.Actions := actions
        this.Profiles := profiles
        this.Items := []
        this.Diagnostics := []
        this._Load()
        this._ResolveStaticConflicts()
    }

    _Load() {
        ids := this._Csv(this.Config.Get("F08", "bindings", ""))
        order := 0
        for id in ids {
            order += 1
            section := "F08.binding." id
            if !this.Config.GetBool(section, "enabled", true) {
                this.Diagnostics.Push(Map("binding", id, "status", "disabled", "detail", "disabled by configuration"))
                continue
            }

            chord := Trim(this.Config.Get(section, "hotkey", ""))
            action := Trim(this.Config.Get(section, "action", ""))
            profile := Trim(this.Config.Get(section, "profile", ""))
            if chord = "" {
                this.Diagnostics.Push(Map("binding", id, "status", "invalid", "detail", "hotkey is empty"))
                continue
            }
            if action = "" || !this.Actions.Has(action) {
                this.Diagnostics.Push(Map("binding", id, "status", "invalid", "detail", "unknown action: " action))
                continue
            }
            if profile != "" && !this.Profiles.Items.Has(profile) {
                this.Diagnostics.Push(Map("binding", id, "status", "invalid", "detail", "unknown profile: " profile))
                continue
            }

            params := Map()
            paramCount := Max(0, this.Config.GetInt(section, "param_count", 0))
            Loop paramCount {
                key := Trim(this.Config.Get(section, "param" A_Index "_key", ""))
                if key = ""
                    continue
                params[key] := this.Config.Get(section, "param" A_Index "_value", "")
            }

            this.Items.Push(Map(
                "id", id,
                "hotkey", chord,
                "action", action,
                "profile", profile,
                "exe", StrLower(Trim(this.Config.Get(section, "exe", ""))),
                "class", StrLower(Trim(this.Config.Get(section, "class", ""))),
                "identity", StrLower(Trim(this.Config.Get(section, "identity", ""))),
                "priority", this.Config.GetInt(section, "priority", 0),
                "params", params,
                "order", order,
                "disabled_reason", ""
            ))
        }
    }

    _ResolveStaticConflicts() {
        winners := Map()
        for binding in this.Items {
            signature := this._Signature(binding)
            if !winners.Has(signature) {
                winners[signature] := binding
                continue
            }
            incumbent := winners[signature]
            winner := StrCompare(binding["id"], incumbent["id"]) < 0 ? binding : incumbent
            loser := winner = binding ? incumbent : binding
            loser["disabled_reason"] := "conflict with " winner["id"]
            winners[signature] := winner
            this.Diagnostics.Push(Map(
                "binding", loser["id"],
                "status", "conflict",
                "detail", "same precedence/context as " winner["id"] "; lexicographic winner retained"
            ))
        }
    }

    ActiveChords() {
        seen := Map()
        output := []
        for binding in this.Items {
            if binding["disabled_reason"] != ""
                continue
            key := StrLower(binding["hotkey"])
            if seen.Has(key)
                continue
            seen[key] := true
            output.Push(binding["hotkey"])
        }
        return output
    }

    ForHotkey(chord) {
        output := []
        needle := StrLower(chord)
        for binding in this.Items {
            if binding["disabled_reason"] = "" && StrLower(binding["hotkey"]) = needle
                output.Push(binding)
        }
        return output
    }

    _Signature(binding) {
        return StrLower(binding["hotkey"]) "|" binding["profile"] "|" binding["exe"] "|" binding["class"] "|" binding["identity"] "|" binding["priority"]
    }

    _Csv(raw) {
        items := []
        for part in StrSplit(raw, ",") {
            value := Trim(part)
            if value != ""
                items.Push(value)
        }
        return items
    }
}

class F08Resolver {
    __New(app, profiles, bindings) {
        this.App := app
        this.Profiles := profiles
        this.Bindings := bindings
        this.ExplicitProfile := ""
        this.Bypass := false
    }

    SetExplicitProfile(id) {
        if id = "" {
            this.ExplicitProfile := ""
            return AQResult.Ok("Explicit keybind profile cleared")
        }
        if !this.Profiles.Items.Has(id)
            return AQResult.Invalid("Unknown profile: " id)
        this.ExplicitProfile := id
        return AQResult.Ok("Explicit keybind profile selected", Map("profile", id))
    }

    SetBypass(enabled) {
        this.Bypass := enabled ? true : false
        return AQResult.Ok(this.Bypass ? "F08 bypass enabled" : "F08 bypass disabled", Map("bypass", this.Bypass))
    }

    CurrentProfile(context := unset) {
        if this.ExplicitProfile != ""
            return this.ExplicitProfile
        ctx := IsSet(context) ? context : this.CaptureContext()
        return this.Profiles.BestAutomatic(ctx)
    }

    Resolve(chord, context := unset) {
        if this.Bypass
            return AQResult.Cancelled("F08 emergency bypass is active", Map("hotkey", chord))

        ctx := IsSet(context) ? this._EnrichContext(context) : this.CaptureContext()
        currentProfile := this.CurrentProfile(ctx)
        candidates := []
        for binding in this.Bindings.ForHotkey(chord) {
            if !this._BindingContextMatches(binding, ctx)
                continue
            profileTier := this._ProfileTier(binding, currentProfile)
            if profileTier < 0
                continue
            candidates.Push(Map(
                "binding", binding,
                "tier", profileTier,
                "priority", binding["priority"]
            ))
        }

        if !candidates.Length
            return AQResult.Unsupported("No active F08 binding for this hotkey/context", Map("hotkey", chord, "profile", currentProfile))

        winner := candidates[1]
        ties := [winner["binding"]["id"]]
        Loop candidates.Length - 1 {
            candidate := candidates[A_Index + 1]
            compare := this._CompareCandidate(candidate, winner)
            if compare > 0 {
                winner := candidate
                ties := [candidate["binding"]["id"]]
            } else if compare = 0 {
                ties.Push(candidate["binding"]["id"])
                if StrCompare(candidate["binding"]["id"], winner["binding"]["id"]) < 0
                    winner := candidate
            }
        }

        binding := winner["binding"]
        return AQResult.Ok("F08 binding resolved", Map(
            "binding", binding["id"],
            "action", binding["action"],
            "params", this._CopyMap(binding["params"]),
            "profile", currentProfile,
            "ties", ties
        ))
    }

    Dispatch(chord, context := unset) {
        resolved := IsSet(context) ? this.Resolve(chord, context) : this.Resolve(chord)
        if !resolved.IsOk()
            return resolved
        return this.App.Actions.Invoke(resolved.Data["action"], resolved.Data["params"])
    }

    CaptureContext() {
        return this._EnrichContext(this.App.Context.Capture())
    }

    _EnrichContext(context) {
        copy := Map()
        for key, value in context
            copy[key] := value
        if !copy.Has("project_identity")
            copy["project_identity"] := ""
        if copy["project_identity"] = "" && copy.Has("pid") && copy["pid"] {
            try {
                record := this.App.Identities.FindActiveByPid(copy["pid"])
                if record.Count
                    copy["project_identity"] := record["identity"]
            }
        }
        return copy
    }

    _BindingContextMatches(binding, context) {
        if binding["exe"] != "" && StrLower(context["exe"]) != binding["exe"]
            return false
        if binding["class"] != "" && StrLower(context["class"]) != binding["class"]
            return false
        if binding["identity"] != "" && StrLower(context["project_identity"]) != binding["identity"]
            return false
        return true
    }

    _ProfileTier(binding, currentProfile) {
        profile := binding["profile"]
        if profile = ""
            return 100
        if currentProfile = ""
            return -1
        if profile != currentProfile
            return -1
        return this.ExplicitProfile != "" ? 400 : 300
    }

    _CompareCandidate(left, right) {
        if left["tier"] != right["tier"]
            return left["tier"] > right["tier"] ? 1 : -1
        if left["priority"] != right["priority"]
            return left["priority"] > right["priority"] ? 1 : -1
        return 0
    }

    _CopyMap(source) {
        copy := Map()
        for key, value in source
            copy[key] := value
        return copy
    }
}

class F08KeybindProfilesModule {
    Id := "F08"

    __New(hotkeys := unset) {
        this.Hotkeys := IsSet(hotkeys) ? hotkeys : F08SystemHotkeys()
        this.Profiles := ""
        this.Bindings := ""
        this.Resolver := ""
        this.RegisteredActions := []
        this.RegisteredChords := []
        this.BypassHotkey := ""
    }

    Init(app) {
        this.App := app
        this.Profiles := F08ProfileStore(app.Config)
        this.Bindings := F08BindingStore(app.Config, app.Actions, this.Profiles)
        this.Resolver := F08Resolver(app, this.Profiles, this.Bindings)

        this._RegisterAction("keybind.profile.set", ObjBindMethod(this, "ActionSetProfile"), "Select an explicit F08 keybind profile", "S1")
        this._RegisterAction("keybind.profile.clear", ObjBindMethod(this, "ActionClearProfile"), "Return F08 to foreground-driven profile selection", "S1")
        this._RegisterAction("keybind.bypass.set", ObjBindMethod(this, "ActionSetBypass"), "Enable or disable F08 emergency bypass", "S1")
        this._RegisterAction("keybind.status", ObjBindMethod(this, "ActionStatus"), "Inspect F08 profile/binding state", "S0")

        for chord in this.Bindings.ActiveChords() {
            registration := this.Hotkeys.Register(chord, ObjBindMethod(this, "OnHotkey", chord))
            if registration.IsOk()
                this.RegisteredChords.Push(chord)
            else
                this.Bindings.Diagnostics.Push(Map("binding", "", "status", "runtime_error", "detail", registration.Message))
        }

        this.BypassHotkey := Trim(app.Config.Get("F08", "bypass_hotkey", ""))
        if this.BypassHotkey != "" {
            registration := this.Hotkeys.Register(this.BypassHotkey, ObjBindMethod(this, "ToggleBypassHotkey"))
            if registration.IsOk()
                this.RegisteredChords.Push(this.BypassHotkey)
            else
                this.Bindings.Diagnostics.Push(Map("binding", "", "status", "runtime_error", "detail", registration.Message))
        }

        app.Capabilities.Set("keybind.external_profiles", "supported", "F08 registry-driven hotkey/profile resolver active")
        return AQResult.Ok("F08 initialized", Map(
            "bindings", this.Bindings.Items.Length,
            "profiles", this.Profiles.Items.Count,
            "hotkeys", this.RegisteredChords.Length,
            "diagnostics", this.Bindings.Diagnostics.Length
        ))
    }

    Teardown(app) {
        this.Hotkeys.Teardown()
        for actionId in this.RegisteredActions
            app.Actions.Unregister(actionId)
        this.RegisteredActions := []
        this.RegisteredChords := []
        this.BypassHotkey := ""
        if IsObject(this.Resolver)
            this.Resolver.SetBypass(true)
        app.Capabilities.Set("keybind.external_profiles", "unknown", "F08 disabled")
        return AQResult.Ok("F08 disabled")
    }

    OnHotkey(chord, *) {
        result := this.Resolver.Dispatch(chord)
        if result.Status != "ok" && result.Status != "cancelled" && result.Status != "unsupported"
            this.App.Log.Warn("module=F08 hotkey=" chord " status=" result.Status)
        return result
    }

    ToggleBypassHotkey(*) {
        return this.Resolver.SetBypass(!this.Resolver.Bypass)
    }

    ActionSetProfile(params) {
        if !params.Has("profile")
            return AQResult.Invalid("keybind.profile.set requires profile")
        return this.Resolver.SetExplicitProfile(params["profile"])
    }

    ActionClearProfile(params) {
        return this.Resolver.SetExplicitProfile("")
    }

    ActionSetBypass(params) {
        if !params.Has("enabled")
            return AQResult.Invalid("keybind.bypass.set requires enabled=0|1")
        raw := StrLower(Trim(params["enabled"] ""))
        if raw = "1" || raw = "true" || raw = "on" || raw = "yes"
            return this.Resolver.SetBypass(true)
        if raw = "0" || raw = "false" || raw = "off" || raw = "no"
            return this.Resolver.SetBypass(false)
        return AQResult.Invalid("enabled must be 0/1, true/false, on/off or yes/no")
    }

    ActionStatus(params) {
        context := this.Resolver.CaptureContext()
        return AQResult.Ok("F08 status", Map(
            "explicit_profile", this.Resolver.ExplicitProfile,
            "effective_profile", this.Resolver.CurrentProfile(context),
            "bypass", this.Resolver.Bypass,
            "bindings", this.Bindings.Items.Length,
            "profiles", this.Profiles.Items.Count,
            "registered_hotkeys", this.RegisteredChords.Length,
            "diagnostics", this._CopyDiagnostics()
        ))
    }

    _RegisterAction(id, handler, description, safetyClass) {
        this.App.Actions.Register(id, handler, description, safetyClass)
        this.RegisteredActions.Push(id)
    }

    _CopyDiagnostics() {
        output := []
        for item in this.Bindings.Diagnostics {
            copy := Map()
            for key, value in item
                copy[key] := value
            output.Push(copy)
        }
        return output
    }
}
