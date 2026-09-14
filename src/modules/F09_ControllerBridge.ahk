#Requires AutoHotkey v2.0

class F09Clock {
    Now() {
        return A_TickCount
    }
}

class F09Protocol {
    Parse(line) {
        text := Trim(line, " `t`r`n")
        if text = ""
            return AQResult.Invalid("Empty controller event")
        parts := StrSplit(text, "|")
        if parts.Length != 4
            return AQResult.Invalid("Controller event must contain four fields")
        if parts[1] != "AQ1"
            return AQResult.Unsupported("Unsupported controller event version")
        eventId := Trim(parts[2])
        value := parts[3]
        seqText := Trim(parts[4])
        if !RegExMatch(eventId, "^[A-Za-z0-9_.-]{1,64}$")
            return AQResult.Invalid("Invalid controller event ID")
        if StrLen(value) > 128
            return AQResult.Invalid("Controller event value too long")
        if !RegExMatch(seqText, "^\d{1,10}$")
            return AQResult.Invalid("Controller event sequence must be an unsigned integer")
        sequence := seqText + 0
        if sequence > 2147483647
            return AQResult.Invalid("Controller event sequence out of range")
        return AQResult.Ok("Controller event parsed", Map("version", "AQ1", "event", eventId, "value", value, "sequence", sequence))
    }
}

class F09MappingStore {
    __New(config, actions) {
        this.Config := config
        this.Actions := actions
        this.Items := Map()
        this.Diagnostics := []
        this._Load()
    }
    Get(eventId) {
        return this.Items.Has(eventId) ? this.Items[eventId] : Map()
    }
    _Load() {
        for id in this._Csv(this.Config.Get("F09", "mappings", "")) {
            section := "F09.mapping." id
            if !this.Config.GetBool(section, "enabled", true)
                continue
            eventId := Trim(this.Config.Get(section, "event", ""))
            action := Trim(this.Config.Get(section, "action", ""))
            if !RegExMatch(eventId, "^[A-Za-z0-9_.-]{1,64}$") {
                this.Diagnostics.Push(Map("mapping", id, "status", "invalid", "detail", "invalid event ID"))
                continue
            }
            if action = "" || !this.Actions.Has(action) {
                this.Diagnostics.Push(Map("mapping", id, "status", "invalid", "detail", "unknown action: " action))
                continue
            }
            if this.Items.Has(eventId) {
                this.Diagnostics.Push(Map("mapping", id, "status", "conflict", "detail", "duplicate event mapping: " eventId))
                continue
            }
            valueType := StrLower(Trim(this.Config.Get(section, "value_type", "string")))
            if valueType != "string" && valueType != "int" && valueType != "enum" {
                this.Diagnostics.Push(Map("mapping", id, "status", "invalid", "detail", "value_type must be string, int or enum"))
                continue
            }
            params := Map()
            Loop Max(0, this.Config.GetInt(section, "param_count", 0)) {
                key := Trim(this.Config.Get(section, "param" A_Index "_key", ""))
                if key != ""
                    params[key] := this.Config.Get(section, "param" A_Index "_value", "")
            }
            this.Items[eventId] := Map(
                "id", id, "event", eventId, "action", action,
                "value_param", Trim(this.Config.Get(section, "value_param", "")),
                "value_type", valueType,
                "min", this.Config.GetInt(section, "min", -2147483648),
                "max", this.Config.GetInt(section, "max", 2147483647),
                "allowed_values", this._Csv(this.Config.Get(section, "allowed_values", "")),
                "debounce_ms", Max(0, this.Config.GetInt(section, "debounce_ms", 0)),
                "params", params)
        }
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
}

class F09SyntheticSource {
    __New(lines := unset) {
        this.Lines := IsSet(lines) ? lines.Clone() : []
        this.Connected := false
        this.OpenCalls := 0
        this.CloseCalls := 0
        this.FailReads := false
    }
    Open() {
        this.OpenCalls += 1
        this.Connected := true
        return AQResult.Ok("Synthetic controller source connected")
    }
    Close() {
        this.CloseCalls += 1
        this.Connected := false
    }
    Push(line) {
        this.Lines.Push(line)
    }
    ReadLines(maxLines := 16) {
        if !this.Connected
            throw Error("Controller source disconnected")
        if this.FailReads {
            this.Connected := false
            throw Error("Synthetic read failure")
        }
        output := []
        Loop Min(maxLines, this.Lines.Length)
            output.Push(this.Lines.RemoveAt(1))
        return output
    }
}

class F09SerialLineSource {
    __New(device, baud := 115200) {
        this.Device := device
        this.Baud := baud
        this.File := ""
        this.Connected := false
        this.Buffer := ""
    }
    Open() {
        this.Close()
        devicePath := RegExMatch(this.Device, "i)^COM\d+$") ? "\\.\" this.Device : this.Device
        try {
            serialFile := FileOpen(devicePath, "r", "UTF-8-RAW")
            if !IsObject(serialFile)
                return AQResult.Failed("Could not open serial controller device")
            this.File := serialFile
            this._Configure(serialFile.Handle)
            this.Connected := true
            return AQResult.Ok("Serial controller connected", Map("device", this.Device, "baud", this.Baud))
        } catch as serialError {
            this.Close()
            return AQResult.Failed("Serial controller connection failed: " serialError.Message)
        }
    }
    Close() {
        if IsObject(this.File) {
            try this.File.Close()
        }
        this.File := ""
        this.Connected := false
        this.Buffer := ""
    }
    ReadLines(maxLines := 16) {
        if !this.Connected || !IsObject(this.File)
            throw Error("Serial controller source disconnected")
        output := []
        try {
            chunk := this.File.Read(512)
            if chunk != ""
                this.Buffer .= chunk
        } catch as readError {
            this.Close()
            throw readError
        }
        while output.Length < maxLines {
            pos := InStr(this.Buffer, "`n")
            if !pos
                break
            line := SubStr(this.Buffer, 1, pos - 1)
            this.Buffer := SubStr(this.Buffer, pos + 1)
            output.Push(RTrim(line, "`r"))
        }
        if StrLen(this.Buffer) > 2048 {
            this.Buffer := ""
            throw Error("Serial controller line exceeded buffer limit")
        }
        return output
    }
    _Configure(handle) {
        dcb := Buffer(28, 0)
        NumPut("UInt", 28, dcb, 0)
        config := "baud=" this.Baud " parity=n data=8 stop=1"
        if !DllCall("Kernel32\BuildCommDCBW", "WStr", config, "Ptr", dcb.Ptr, "Int")
            throw OSError(A_LastError, "BuildCommDCB failed")
        if !DllCall("Kernel32\SetCommState", "Ptr", handle, "Ptr", dcb.Ptr, "Int")
            throw OSError(A_LastError, "SetCommState failed")
        timeouts := Buffer(20, 0)
        NumPut("UInt", 1, timeouts, 0)
        NumPut("UInt", 0, timeouts, 4)
        NumPut("UInt", 1, timeouts, 8)
        if !DllCall("Kernel32\SetCommTimeouts", "Ptr", handle, "Ptr", timeouts.Ptr, "Int")
            throw OSError(A_LastError, "SetCommTimeouts failed")
    }
}

class F09ControllerService {
    __New(app, source, mappings, clock := unset) {
        this.App := app
        this.Source := source
        this.Mappings := mappings
        this.Clock := IsSet(clock) ? clock : F09Clock()
        this.Protocol := F09Protocol()
        this.Enabled := true
        this.LastAcceptedAt := Map()
        this.LastSequence := Map()
        this.RateWindowStart := 0
        this.RateCount := 0
        this.MaxEventsPerSecond := Max(1, app.Config.GetInt("F09", "max_events_per_second", 60))
        this.MaxEventsPerPoll := Max(1, app.Config.GetInt("F09", "max_events_per_poll", 16))
        this.Stats := Map("accepted", 0, "rejected", 0, "malformed", 0, "dispatch_failed", 0, "reconnects", 0)
    }
    SetEnabled(enabled) {
        this.Enabled := enabled ? true : false
        return AQResult.Ok(this.Enabled ? "F09 enabled" : "F09 disabled")
    }
    ProcessLine(line) {
        if !this.Enabled
            return AQResult.Cancelled("F09 is disabled")
        parsed := this.Protocol.Parse(line)
        if !parsed.IsOk() {
            this.Stats["malformed"] += 1
            return parsed
        }
        event := parsed.Data
        mapping := this.Mappings.Get(event["event"])
        if !mapping.Count {
            this.Stats["rejected"] += 1
            return AQResult.Rejected("Unmapped controller event", Map("event", event["event"]))
        }
        if !this._AcceptSequence(event) {
            this.Stats["rejected"] += 1
            return AQResult.Rejected("Duplicate or stale controller sequence", Map("event", event["event"]))
        }
        now := this.Clock.Now()
        if !this._AcceptRate(now) {
            this.Stats["rejected"] += 1
            return AQResult.Rejected("Controller event rate limit exceeded")
        }
        if mapping["debounce_ms"] > 0 && this.LastAcceptedAt.Has(event["event"]) {
            if now - this.LastAcceptedAt[event["event"]] < mapping["debounce_ms"] {
                this.Stats["rejected"] += 1
                return AQResult.Rejected("Controller event debounced", Map("event", event["event"]))
            }
        }
        validated := this._ValidatedValue(mapping, event["value"])
        if !validated.IsOk() {
            this.Stats["rejected"] += 1
            return validated
        }
        params := Map()
        for key, value in mapping["params"]
            params[key] := value
        if mapping["value_param"] != ""
            params[mapping["value_param"]] := validated.Data["value"]
        this.LastAcceptedAt[event["event"]] := now
        dispatchResult := this.App.Actions.Invoke(mapping["action"], params)
        if !dispatchResult.IsOk() {
            this.Stats["dispatch_failed"] += 1
            return dispatchResult
        }
        this.Stats["accepted"] += 1
        return AQResult.Ok("Controller event dispatched", Map("event", event["event"], "action", mapping["action"]))
    }
    Poll() {
        if !this.Enabled
            return AQResult.Cancelled("F09 is disabled")
        if !this.Source.Connected {
            opened := this.Source.Open()
            if !opened.IsOk()
                return opened
            this.Stats["reconnects"] += 1
        }
        try lines := this.Source.ReadLines(this.MaxEventsPerPoll)
        catch as sourceError {
            try this.Source.Close()
            return AQResult.Failed("Controller source read failed: " sourceError.Message)
        }
        results := []
        for line in lines
            results.Push(this.ProcessLine(line))
        return AQResult.Ok("Controller poll complete", Map("processed", results.Length, "results", results))
    }
    _AcceptSequence(event) {
        id := event["event"]
        seq := event["sequence"]
        if this.LastSequence.Has(id) && seq <= this.LastSequence[id]
            return false
        this.LastSequence[id] := seq
        return true
    }
    _AcceptRate(now) {
        if this.RateWindowStart = 0 || now - this.RateWindowStart >= 1000 {
            this.RateWindowStart := now
            this.RateCount := 0
        }
        if this.RateCount >= this.MaxEventsPerSecond
            return false
        this.RateCount += 1
        return true
    }
    _ValidatedValue(mapping, raw) {
        valueType := mapping["value_type"]
        if valueType = "int" {
            if !RegExMatch(Trim(raw), "^-?\d+$")
                return AQResult.Invalid("Controller value must be an integer")
            value := raw + 0
            if value < mapping["min"] || value > mapping["max"]
                return AQResult.Invalid("Controller integer value out of configured range")
            return AQResult.Ok("Value valid", Map("value", value))
        }
        if valueType = "enum" {
            for allowed in mapping["allowed_values"] {
                if raw = allowed
                    return AQResult.Ok("Value valid", Map("value", raw))
            }
            return AQResult.Invalid("Controller value is not allowed")
        }
        return AQResult.Ok("Value valid", Map("value", raw))
    }
}

class F09ControllerBridgeModule {
    Id := "F09"
    __New(source := unset, clock := unset) {
        this.InjectedSource := IsSet(source) ? source : ""
        this.InjectedClock := IsSet(clock) ? clock : ""
        this.Source := ""
        this.Service := ""
        this.TimerCallback := ""
        this.RegisteredActions := []
    }
    Init(app) {
        this.App := app
        mappings := F09MappingStore(app.Config, app.Actions)
        transport := StrLower(Trim(app.Config.Get("F09", "transport", "serial")))
        if IsObject(this.InjectedSource) {
            this.Source := this.InjectedSource
        } else if transport = "serial" {
            device := Trim(app.Config.Get("F09", "device", ""))
            if device = ""
                throw ValueError("F09 serial transport requires device")
            this.Source := F09SerialLineSource(device, app.Config.GetInt("F09", "baud", 115200))
        } else if transport = "synthetic" {
            this.Source := F09SyntheticSource()
        } else {
            throw ValueError("Unsupported F09 transport: " transport)
        }
        clock := IsObject(this.InjectedClock) ? this.InjectedClock : F09Clock()
        this.Service := F09ControllerService(app, this.Source, mappings, clock)
        this._RegisterAction("controller.status", ObjBindMethod(this, "ActionStatus"), "Inspect F09 controller bridge state", "S0")
        this._RegisterAction("controller.enable", ObjBindMethod(this, "ActionEnable"), "Enable or disable F09 controller dispatch", "S1")
        pollMs := Max(10, app.Config.GetInt("F09", "poll_ms", 25))
        this.TimerCallback := ObjBindMethod(this, "OnTimer")
        SetTimer(this.TimerCallback, pollMs)
        app.Capabilities.Set("controller.local_serial", transport = "serial" ? "unknown" : "supported", transport = "serial" ? "awaiting serial connection" : "synthetic controller source")
        return AQResult.Ok("F09 initialized", Map("mappings", mappings.Items.Count, "diagnostics", mappings.Diagnostics.Length))
    }
    Teardown(app) {
        if IsObject(this.TimerCallback)
            SetTimer(this.TimerCallback, 0)
        this.TimerCallback := ""
        if IsObject(this.Source)
            try this.Source.Close()
        for id in this.RegisteredActions
            app.Actions.Unregister(id)
        this.RegisteredActions := []
        if IsObject(this.Service)
            this.Service.SetEnabled(false)
        app.Capabilities.Set("controller.local_serial", "unknown", "F09 disabled")
        return AQResult.Ok("F09 disabled")
    }
    OnTimer() {
        pollResult := this.Service.Poll()
        if pollResult.IsOk() {
            if this.Source.Connected
                this.App.Capabilities.Set("controller.local_serial", "supported", "controller source connected")
        } else if pollResult.Status = "failed" {
            this.App.Capabilities.Set("controller.local_serial", "degraded", pollResult.Message)
        }
    }
    ActionStatus(params) {
        return AQResult.Ok("F09 status", Map("enabled", this.Service.Enabled, "connected", this.Source.Connected, "stats", this._CopyMap(this.Service.Stats)))
    }
    ActionEnable(params) {
        if !params.Has("enabled")
            return AQResult.Invalid("controller.enable requires enabled=0|1")
        raw := StrLower(Trim(params["enabled"] ""))
        if raw = "1" || raw = "true" || raw = "on" || raw = "yes"
            return this.Service.SetEnabled(true)
        if raw = "0" || raw = "false" || raw = "off" || raw = "no"
            return this.Service.SetEnabled(false)
        return AQResult.Invalid("enabled must be a boolean value")
    }
    _RegisterAction(id, handler, description, safetyClass) {
        this.App.Actions.Register(id, handler, description, safetyClass)
        this.RegisteredActions.Push(id)
    }
    _CopyMap(source) {
        copy := Map()
        for key, value in source
            copy[key] := value
        return copy
    }
}
