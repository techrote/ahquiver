#Requires AutoHotkey v2.0

class F11Clock {
    Now() {
        return DateDiff(A_NowUTC, "19700101000000", "Seconds")
    }
}

class F11Ledger {
    __New(serviceWindows, clock := unset) {
        this.ServiceWindows := serviceWindows
        this.Clock := IsSet(clock) ? clock : F11Clock()
        this.Events := []
    }

    Observe(service, source := "manual", at := unset) {
        if !this.ServiceWindows.Has(service)
            return AQResult.Invalid("Unknown observation service: " service)
        timestamp := IsSet(at) ? at : this.Clock.Now()
        if !IsNumber(timestamp) || timestamp < 0
            return AQResult.Invalid("Observation timestamp must be non-negative")
        this.Events.Push(Map("at", timestamp + 0, "service", service, "source", this._SafeLabel(source)))
        this.Prune(timestamp)
        return AQResult.Ok("Local observation recorded", Map("service", service, "count", this.Count(service, timestamp)))
    }

    Count(service, now := unset) {
        if !this.ServiceWindows.Has(service)
            return 0
        t := IsSet(now) ? now : this.Clock.Now()
        window := this.ServiceWindows[service]
        count := 0
        for event in this.Events {
            if event["service"] = service && event["at"] > t - window && event["at"] <= t
                count += 1
        }
        return count
    }

    Snapshot(now := unset) {
        t := IsSet(now) ? now : this.Clock.Now()
        this.Prune(t)
        output := []
        for service, window in this.ServiceWindows {
            output.Push(Map(
                "service", service,
                "observed_count", this.Count(service, t),
                "window_seconds", window,
                "window_start", Max(0, t - window),
                "window_end", t,
                "authoritative", false,
                "label", "local observed estimate"
            ))
        }
        return output
    }

    Reset(service := "") {
        if service != "" && !this.ServiceWindows.Has(service)
            return AQResult.Invalid("Unknown observation service: " service)
        kept := []
        removed := 0
        for event in this.Events {
            if service = "" || event["service"] = service
                removed += 1
            else
                kept.Push(event)
        }
        this.Events := kept
        return AQResult.Ok("Observation ledger reset", Map("removed", removed, "service", service))
    }

    Prune(now := unset) {
        t := IsSet(now) ? now : this.Clock.Now()
        maxWindow := 0
        for _, window in this.ServiceWindows
            maxWindow := Max(maxWindow, window)
        cutoff := t - maxWindow
        kept := []
        for event in this.Events {
            if event["at"] > cutoff && event["at"] <= t
                kept.Push(event)
        }
        this.Events := kept
    }

    ImportEvent(timestamp, service, source) {
        if !this.ServiceWindows.Has(service)
            return false
        if !IsNumber(timestamp) || timestamp < 0
            return false
        this.Events.Push(Map("at", timestamp + 0, "service", service, "source", this._SafeLabel(source)))
        return true
    }

    _SafeLabel(value) {
        label := StrReplace(StrReplace(value "", "`t", " "), "`r", " ")
        label := StrReplace(label, "`n", " ")
        return SubStr(label, 1, 128)
    }
}

class F11Persistence {
    __New(path) {
        this.Path := path
    }

    LoadInto(ledger) {
        if this.Path = "" || !FileExist(this.Path)
            return AQResult.Ok("No persisted observation ledger")
        accepted := 0
        rejected := 0
        try {
            content := FileRead(this.Path)
            for line in StrSplit(StrReplace(content, "`r`n", "`n"), "`n") {
                if Trim(line) = ""
                    continue
                fields := StrSplit(line, "`t")
                if fields.Length != 3 || !RegExMatch(fields[1], "^\d+$") {
                    rejected += 1
                    continue
                }
                if ledger.ImportEvent(fields[1] + 0, fields[2], fields[3])
                    accepted += 1
                else
                    rejected += 1
            }
            ledger.Prune()
            return AQResult.Ok("Persisted observations loaded", Map("accepted", accepted, "rejected", rejected))
        } catch as loadError {
            return AQResult.Failed("Observation persistence load failed: " loadError.Message)
        }
    }

    Save(ledger) {
        if this.Path = ""
            return AQResult.Ok("Observation persistence disabled")
        try {
            SplitPath(this.Path, , &dir)
            if dir != "" && !DirExist(dir)
                DirCreate(dir)
            tempPath := this.Path ".tmp"
            text := ""
            for event in ledger.Events
                text .= event["at"] "`t" event["service"] "`t" event["source"] "`n"
            tempFile := FileOpen(tempPath, "w", "UTF-8-RAW")
            if !IsObject(tempFile)
                return AQResult.Failed("Could not create observation persistence temp file")
            tempFile.Write(text)
            tempFile.Close()
            FileMove(tempPath, this.Path, 1)
            return AQResult.Ok("Observation ledger persisted")
        } catch as saveError {
            return AQResult.Failed("Observation persistence save failed: " saveError.Message)
        }
    }
}

class F11ObservationModule {
    Id := "F11"

    __New(clock := unset) {
        this.InjectedClock := IsSet(clock) ? clock : ""
        this.Ledger := ""
        this.Persistence := ""
        this.ObserverToken := 0
        this.ActionMappings := Map()
        this.RegisteredActions := []
        this.Overlay := ""
        this.OverlayText := ""
        this.OverlayTimer := ""
    }

    Init(app) {
        this.App := app
        serviceWindows := this._LoadServices(app.Config)
        if !serviceWindows.Count
            throw ValueError("F11 requires at least one configured service")
        clock := IsObject(this.InjectedClock) ? this.InjectedClock : F11Clock()
        this.Ledger := F11Ledger(serviceWindows, clock)
        persistPath := Trim(app.Config.Get("F11", "persistence_path", ""))
        if persistPath != "" && !RegExMatch(persistPath, "i)^[A-Z]:\\") && SubStr(persistPath, 1, 2) != "\\"
            persistPath := app.RootDir "\\" persistPath
        this.Persistence := F11Persistence(persistPath)
        loadResult := this.Persistence.LoadInto(this.Ledger)
        if !loadResult.IsOk()
            app.Log.Warn("module=F11 persistence_load=" loadResult.Message)
        this.ActionMappings := this._LoadActionMappings(app.Config, app.Actions)
        this.ObserverToken := app.Actions.Subscribe(ObjBindMethod(this, "ObserveAction"))
        this._Register("observation.observe", ObjBindMethod(this, "ActionObserve"), "Record one local usage observation", "S0")
        this._Register("observation.status", ObjBindMethod(this, "ActionStatus"), "Inspect local rolling observation estimates", "S0")
        this._Register("observation.reset", ObjBindMethod(this, "ActionReset"), "Reset local observation estimates", "S1")
        this._Register("observation.overlay.toggle", ObjBindMethod(this, "ActionOverlayToggle"), "Show or hide local observation estimate overlay", "S1")
        app.Capabilities.Set("observation.local_usage_estimate", "supported", "local event ledger only; not an authoritative service quota")
        return AQResult.Ok("F11 initialized", Map("services", serviceWindows.Count, "observed_actions", this.ActionMappings.Count))
    }

    Teardown(app) {
        if this.ObserverToken {
            app.Actions.Unsubscribe(this.ObserverToken)
            this.ObserverToken := 0
        }
        this._DestroyOverlay()
        if IsObject(this.Persistence) && IsObject(this.Ledger)
            this.Persistence.Save(this.Ledger)
        for id in this.RegisteredActions
            app.Actions.Unregister(id)
        this.RegisteredActions := []
        app.Capabilities.Set("observation.local_usage_estimate", "unknown", "F11 disabled")
        return AQResult.Ok("F11 disabled")
    }

    ObserveAction(actionId, actionResult) {
        if !this.ActionMappings.Has(actionId)
            return
        if !IsObject(actionResult) || !HasProp(actionResult, "Status") || actionResult.Status = "cancelled"
            return
        service := this.ActionMappings[actionId]
        this.Ledger.Observe(service, "action:" actionId)
        this.Persistence.Save(this.Ledger)
        this._RefreshOverlay()
    }

    ActionObserve(params) {
        if !params.Has("service")
            return AQResult.Invalid("observation.observe requires service")
        source := params.Has("source") ? params["source"] : "manual"
        result := this.Ledger.Observe(params["service"], source)
        if result.IsOk()
            this.Persistence.Save(this.Ledger)
        this._RefreshOverlay()
        return result
    }

    ActionStatus(params) {
        return AQResult.Ok("Local observed usage estimate", Map(
            "authoritative", false,
            "disclaimer", "Observed local interaction signals only; not service quota truth",
            "services", this.Ledger.Snapshot()
        ))
    }

    ActionReset(params) {
        service := params.Has("service") ? params["service"] : ""
        result := this.Ledger.Reset(service)
        if result.IsOk()
            this.Persistence.Save(this.Ledger)
        this._RefreshOverlay()
        return result
    }

    ActionOverlayToggle(params) {
        if IsObject(this.Overlay) {
            this._DestroyOverlay()
            return AQResult.Ok("Observation overlay hidden")
        }
        this._CreateOverlay()
        return AQResult.Ok("Observation overlay shown")
    }

    _CreateOverlay() {
        panel := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow", "AHQuiver local estimate")
        panel.SetFont("s9", "Segoe UI")
        panel.AddText("w320", "Local observed usage estimate — not authoritative quota")
        this.OverlayText := panel.AddText("w320 r8", "")
        panel.OnEvent("Close", (*) => this._DestroyOverlay())
        this.Overlay := panel
        this._RefreshOverlay()
        panel.Show("AutoSize NoActivate")
        this.OverlayTimer := ObjBindMethod(this, "_RefreshOverlay")
        SetTimer(this.OverlayTimer, 1000)
    }

    _DestroyOverlay() {
        if IsObject(this.OverlayTimer)
            SetTimer(this.OverlayTimer, 0)
        this.OverlayTimer := ""
        if IsObject(this.Overlay)
            try this.Overlay.Destroy()
        this.Overlay := ""
        this.OverlayText := ""
    }

    _RefreshOverlay(*) {
        if !IsObject(this.OverlayText)
            return
        text := ""
        for item in this.Ledger.Snapshot()
            text .= item["service"] ": " item["observed_count"] " observed / " item["window_seconds"] "s window`n"
        this.OverlayText.Value := RTrim(text, "`n")
    }

    _LoadServices(config) {
        output := Map()
        for id in this._Csv(config.Get("F11", "services", "")) {
            window := Max(1, config.GetInt("F11.service." id, "window_seconds", 10800))
            output[id] := window
        }
        return output
    }

    _LoadActionMappings(config, actions) {
        output := Map()
        for id in this._Csv(config.Get("F11", "action_mappings", "")) {
            section := "F11.action." id
            action := Trim(config.Get(section, "action", ""))
            service := Trim(config.Get(section, "service", ""))
            if action != "" && service != "" && actions.Has(action) && this.Ledger.ServiceWindows.Has(service)
                output[action] := service
        }
        return output
    }

    _Csv(raw) {
        output := []
        for part in StrSplit(raw, ",") {
            item := Trim(part)
            if item != ""
                output.Push(item)
        }
        return output
    }

    _Register(id, handler, description, safetyClass) {
        this.App.Actions.Register(id, handler, description, safetyClass)
        this.RegisteredActions.Push(id)
    }
}
