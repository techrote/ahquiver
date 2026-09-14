#Requires AutoHotkey v2.0

class F06TrackerRegistry {
    __New() {
        this.Records := Map()
        this.NextId := 1
    }

    Register(presetId, pid, metadata := unset) {
        recordId := "tracker-" this.NextId
        this.NextId += 1
        record := Map(
            "id", recordId,
            "preset", presetId,
            "pid", pid,
            "state", "active",
            "created_at", A_TickCount,
            "inactive_reason", ""
        )
        if IsSet(metadata) && IsObject(metadata) {
            for key, value in metadata
                record[key] := value
        }
        this.Records[recordId] := record
        return this._Copy(record)
    }

    ActiveByPreset(presetId) {
        items := []
        for _, record in this.Records {
            if record["preset"] = presetId && record["state"] = "active"
                items.Push(this._Copy(record))
        }
        return items
    }

    MarkInactive(recordId, reason := "") {
        if !this.Records.Has(recordId)
            return false
        this.Records[recordId]["state"] := "inactive"
        this.Records[recordId]["inactive_reason"] := reason
        return true
    }

    List(activeOnly := false) {
        items := []
        for _, record in this.Records {
            if activeOnly && record["state"] != "active"
                continue
            items.Push(this._Copy(record))
        }
        return items
    }

    _Copy(record) {
        copy := Map()
        for key, value in record
            copy[key] := value
        return copy
    }
}

class F06SystemProcessAdapter {
    __New(app) {
        this.App := app
    }

    Exists(pid) {
        if !pid
            return false
        try return ProcessExist(pid) = pid
        catch
            return false
    }

    Describe(pid) {
        if !this.Exists(pid)
            return Map("pid", pid, "exists", false, "exe", "", "path", "")
        exe := ""
        path := ""
        try exe := ProcessGetName(pid)
        try path := ProcessGetPath(pid)
        return Map("pid", pid, "exists", true, "exe", exe, "path", path)
    }

    Launch(program, args := unset, workingDir := "") {
        return IsSet(args) ? AQProcess.Launch(program, args, workingDir) : AQProcess.Launch(program, , workingDir)
    }

    GracefulClose(pid, timeoutMs := 1500) {
        if !this.Exists(pid)
            return AQResult.Ok("Tracker already exited", Map("already_exited", true))

        windows := this.App.Windows.FindVisibleByPid(pid)
        if !windows.Length
            return AQResult.Failed("Tracker exposes no visible top-level window for graceful close")

        requested := 0
        for snapshot in windows {
            if !this.App.Windows.StillMatches(snapshot)
                continue
            selector := "ahk_id " snapshot["hwnd"]
            try {
                WinClose(selector)
                requested += 1
            }
        }
        if !requested
            return AQResult.Failed("No revalidated tracker window accepted a graceful close request")

        if this._WaitGone(pid, timeoutMs)
            return AQResult.Ok("Tracker exited after graceful close", Map("windows_requested", requested))
        return AQResult.Failed("Tracker remained alive after graceful close timeout", Map("windows_requested", requested))
    }

    ForceClose(pid, timeoutMs := 1000) {
        if !this.Exists(pid)
            return AQResult.Ok("Tracker already exited", Map("already_exited", true))
        try ProcessClose(pid)
        catch as err
            return AQResult.Failed("Force termination failed: " err.Message)
        if this._WaitGone(pid, timeoutMs)
            return AQResult.Ok("Tracker force-terminated")
        return AQResult.Failed("Tracker remained alive after force termination")
    }

    _WaitGone(pid, timeoutMs) {
        deadline := A_TickCount + Max(timeoutMs, 0)
        loop {
            if !this.Exists(pid)
                return true
            if A_TickCount >= deadline
                return false
            Sleep(25)
        }
    }
}

class F06PresetStore {
    __New(app, injected := unset) {
        this.App := app
        this.Presets := IsSet(injected) ? injected : this._Load()
    }

    Has(id) => this.Presets.Has(id)

    Get(id) {
        if !this.Presets.Has(id)
            return Map()
        return this._Copy(this.Presets[id])
    }

    List() {
        items := []
        for _, preset in this.Presets
            items.Push(this._Copy(preset))
        return items
    }

    _Load() {
        presets := Map()
        raw := Trim(this.App.Config.Get("F06", "presets", ""))
        if raw = ""
            return presets
        for presetIdRaw in StrSplit(raw, ",") {
            presetId := Trim(presetIdRaw)
            if presetId = ""
                continue
            section := "F06.tracker." presetId
            program := Trim(this.App.Config.Get(section, "program", ""))
            if program = ""
                throw ValueError("F06 tracker preset '" presetId "' requires program")
            args := []
            argCount := Max(0, this.App.Config.GetInt(section, "arg_count", 0))
            Loop argCount
                args.Push(this.App.Config.Get(section, "arg" A_Index, ""))
            excludes := this._Csv(this.App.Config.Get(section, "worker_exclude_exes", ""))
            preset := Map(
                "id", presetId,
                "program", program,
                "args", args,
                "working_dir", this.App.Config.Get(section, "working_dir", ""),
                "allow_force", this.App.Config.GetBool(section, "allow_force", false),
                "graceful_timeout_ms", Max(0, this.App.Config.GetInt(section, "graceful_timeout_ms", 1500)),
                "force_timeout_ms", Max(0, this.App.Config.GetInt(section, "force_timeout_ms", 1000)),
                "worker_exclude_exes", excludes,
                "expected_exe", StrLower(Trim(this.App.Config.Get(section, "expected_exe", this._BaseName(program)))),
                "expected_path", Trim(this.App.Config.Get(section, "expected_path", "")),
                "identity", this.App.Config.Get(section, "identity", ""),
                "title", this.App.Config.Get(section, "title", ""),
                "restore_title", this.App.Config.GetBool(section, "restore_title", false),
                "window_wait_ms", Max(0, this.App.Config.GetInt(section, "window_wait_ms", 750))
            )
            if this._Contains(excludes, preset["expected_exe"])
                throw ValueError("F06 tracker preset '" presetId "' executable is also worker-excluded")
            presets[presetId] := preset
        }
        return presets
    }

    _Csv(value) {
        items := []
        for item in StrSplit(value, ",") {
            clean := StrLower(Trim(item))
            if clean != ""
                items.Push(clean)
        }
        return items
    }

    _Contains(items, value) {
        needle := StrLower(value)
        for item in items {
            if StrLower(item) = needle
                return true
        }
        return false
    }

    _BaseName(path) {
        SplitPath(path, &name)
        return name
    }

    _Copy(source) {
        copy := Map()
        for key, value in source
            copy[key] := value
        return copy
    }
}

class F06TrackerService {
    __New(app, presets := unset, registry := unset, processes := unset) {
        this.App := app
        this.Presets := IsSet(presets) ? F06PresetStore(app, presets) : F06PresetStore(app)
        this.Registry := IsSet(registry) ? registry : F06TrackerRegistry()
        this.Processes := IsSet(processes) ? processes : F06SystemProcessAdapter(app)
    }

    Restart(presetId) {
        presetResult := this._Preset(presetId)
        if !presetResult.IsOk()
            return presetResult
        preset := presetResult.Data["preset"]

        state := this._ResolveOwned(preset)
        if !state.IsOk()
            return state
        records := state.Data["live"]
        stalePid := state.Data["stale_pid"]

        if records.Length > 1 {
            return AQResult.Rejected("Multiple live tracker records exist; refusing to guess", Map(
                "preset", presetId,
                "live_count", records.Length,
                "old_pid", 0,
                "new_pid", 0,
                "termination_mode", "none"
            ))
        }

        if !records.Length {
            launch := this._Launch(preset)
            if !launch.IsOk()
                return launch
            return AQResult.Ok("Tracker launched because no live owned tracker existed", Map(
                "preset", presetId,
                "old_pid", stalePid,
                "new_pid", launch.Data["pid"],
                "termination_mode", stalePid ? "stale" : "none",
                "prior_state", stalePid ? "stale" : "not_running"
            ))
        }

        record := records[1]
        oldPid := record["pid"]
        valid := this._Revalidate(record, preset)
        if !valid.IsOk()
            return AQResult.Rejected(valid.Message, Map(
                "preset", presetId,
                "old_pid", oldPid,
                "new_pid", 0,
                "termination_mode", "none"
            ))

        terminationMode := "graceful"
        stopped := this.Processes.GracefulClose(oldPid, preset["graceful_timeout_ms"])
        if !stopped.IsOk() {
            if !preset["allow_force"] {
                return AQResult.Failed("Graceful tracker termination failed and force fallback is disabled: " stopped.Message, Map(
                    "preset", presetId,
                    "old_pid", oldPid,
                    "new_pid", 0,
                    "termination_mode", "graceful_failed"
                ))
            }
            validForce := this._Revalidate(record, preset)
            if !validForce.IsOk()
                return AQResult.Rejected("Tracker changed before force fallback: " validForce.Message, Map(
                    "preset", presetId,
                    "old_pid", oldPid,
                    "new_pid", 0,
                    "termination_mode", "force_rejected"
                ))
            terminationMode := "force"
            stopped := this.Processes.ForceClose(oldPid, preset["force_timeout_ms"])
            if !stopped.IsOk()
                return AQResult.Failed(stopped.Message, Map(
                    "preset", presetId,
                    "old_pid", oldPid,
                    "new_pid", 0,
                    "termination_mode", "force_failed"
                ))
        }

        this.Registry.MarkInactive(record["id"], "restarted")
        launch := this._Launch(preset)
        if !launch.IsOk()
            return AQResult.Failed("Old tracker stopped but relaunch failed: " launch.Message, Map(
                "preset", presetId,
                "old_pid", oldPid,
                "new_pid", 0,
                "termination_mode", terminationMode
            ))
        return AQResult.Ok("Tracker restarted", Map(
            "preset", presetId,
            "old_pid", oldPid,
            "new_pid", launch.Data["pid"],
            "termination_mode", terminationMode,
            "prior_state", "running"
        ))
    }

    Launch(presetId) {
        presetResult := this._Preset(presetId)
        if !presetResult.IsOk()
            return presetResult
        preset := presetResult.Data["preset"]
        state := this._ResolveOwned(preset)
        if !state.IsOk()
            return state
        if state.Data["live"].Length
            return AQResult.Rejected("Tracker preset already has a live owned process")
        return this._Launch(preset)
    }

    AdoptForeground(presetId) {
        presetResult := this._Preset(presetId)
        if !presetResult.IsOk()
            return presetResult
        preset := presetResult.Data["preset"]
        context := this.App.Context.Capture()
        if !context["pid"]
            return AQResult.Rejected("No attributable foreground process to adopt")
        if this._IsExcluded(preset, context["exe"])
            return AQResult.Rejected("Foreground process is explicitly worker-protected")

        description := this.Processes.Describe(context["pid"])
        validation := this._ValidateDescription(description, preset)
        if !validation.IsOk()
            return validation

        existing := this._ResolveOwned(preset)
        if !existing.IsOk()
            return existing
        if existing.Data["live"].Length
            return AQResult.Rejected("Tracker preset already has a live owned process")

        record := this.Registry.Register(presetId, context["pid"], this._RecordMetadata(description, preset, "adopted"))
        return AQResult.Ok("Foreground tracker adopted", Map("preset", presetId, "pid", context["pid"], "record_id", record["id"]))
    }

    Status(presetId := "") {
        if presetId != "" {
            presetResult := this._Preset(presetId)
            if !presetResult.IsOk()
                return presetResult
            state := this._ResolveOwned(presetResult.Data["preset"])
            if !state.IsOk()
                return state
            return AQResult.Ok("Tracker status", Map(
                "preset", presetId,
                "live_count", state.Data["live"].Length,
                "stale_pid", state.Data["stale_pid"]
            ))
        }
        return AQResult.Ok("Tracker registry status", Map(
            "preset_count", this.Presets.Presets.Count,
            "records", this.Registry.List(true)
        ))
    }

    _ResolveOwned(preset) {
        live := []
        stalePid := 0
        for record in this.Registry.ActiveByPreset(preset["id"]) {
            if !this.Processes.Exists(record["pid"]) {
                stalePid := record["pid"]
                this.Registry.MarkInactive(record["id"], "stale")
                continue
            }
            live.Push(record)
        }
        return AQResult.Ok("Owned tracker records resolved", Map("live", live, "stale_pid", stalePid))
    }

    _Revalidate(record, preset) {
        if !this.Processes.Exists(record["pid"])
            return AQResult.Rejected("Owned tracker PID is stale")
        description := this.Processes.Describe(record["pid"])
        if this._IsExcluded(preset, description["exe"])
            return AQResult.Rejected("Owned PID now resolves to a worker-protected executable")
        if record.Has("exe") && record["exe"] != "" && StrLower(description["exe"]) != StrLower(record["exe"])
            return AQResult.Rejected("Owned tracker executable changed before termination")
        if record.Has("path") && record["path"] != "" && description["path"] != "" && StrLower(description["path"]) != StrLower(record["path"])
            return AQResult.Rejected("Owned tracker path changed before termination")
        return this._ValidateDescription(description, preset)
    }

    _ValidateDescription(description, preset) {
        if !description["exists"]
            return AQResult.Rejected("Tracker process is not running")
        if this._IsExcluded(preset, description["exe"])
            return AQResult.Rejected("Process executable is explicitly worker-protected")
        if preset["expected_exe"] != "" && description["exe"] != "" && StrLower(description["exe"]) != StrLower(preset["expected_exe"])
            return AQResult.Rejected("Process executable does not match tracker preset")
        if preset["expected_path"] != "" && description["path"] != "" && StrLower(description["path"]) != StrLower(preset["expected_path"])
            return AQResult.Rejected("Process path does not match tracker preset")
        return AQResult.Ok("Tracker process metadata verified")
    }

    _Launch(preset) {
        launch := this.Processes.Launch(preset["program"], preset["args"], preset["working_dir"])
        if !launch.IsOk()
            return launch
        pid := launch.Data["pid"]
        if !pid
            return AQResult.Failed("Tracker launch returned no PID")

        description := this.Processes.Describe(pid)
        validation := this._ValidateDescription(description, preset)
        if !validation.IsOk()
            return AQResult.Failed("Launched tracker metadata did not verify: " validation.Message, Map("pid", pid))

        record := this.Registry.Register(preset["id"], pid, this._RecordMetadata(description, preset, "launched"))
        restore := this._RestoreWindowMetadata(preset, pid)
        return AQResult.Ok("Tracker launched and registered", Map(
            "pid", pid,
            "record_id", record["id"],
            "window_restore", restore.Status
        ))
    }

    _RestoreWindowMetadata(preset, pid) {
        if !preset["restore_title"] || Trim(preset["title"]) = ""
            return AQResult.Unsupported("Tracker title restoration not requested")
        deadline := A_TickCount + preset["window_wait_ms"]
        loop {
            windows := this.App.Windows.FindVisibleByPid(pid)
            if windows.Length {
                return this.App.Windows.RequestTitle(windows[1], preset["title"])
            }
            if A_TickCount >= deadline
                return AQResult.Failed("No tracker window appeared for title restoration")
            Sleep(25)
        }
    }

    _RecordMetadata(description, preset, source) {
        return Map(
            "exe", description["exe"],
            "path", description["path"],
            "source", source,
            "identity", preset["identity"]
        )
    }

    _IsExcluded(preset, exe) {
        needle := StrLower(Trim(exe))
        if needle = ""
            return false
        for excluded in preset["worker_exclude_exes"] {
            if needle = StrLower(excluded)
                return true
        }
        return false
    }

    _Preset(presetId) {
        id := Trim(presetId)
        if id = ""
            return AQResult.Invalid("Tracker preset id is required")
        if !this.Presets.Has(id)
            return AQResult.Invalid("Unknown tracker preset: " id)
        return AQResult.Ok("Tracker preset resolved", Map("preset", this.Presets.Get(id)))
    }
}

class F06TrackerRestartModule {
    Id := "F06"

    Init(app) {
        this.App := app
        this.Service := F06TrackerService(app)
        app.Actions.Register("tracker.restart", (params) => this.Service.Restart(params.Has("preset") ? params["preset"] : ""), "Restart or launch an owned tracker preset", "S2")
        app.Actions.Register("tracker.launch", (params) => this.Service.Launch(params.Has("preset") ? params["preset"] : ""), "Launch a tracker preset when none is owned", "S1")
        app.Actions.Register("tracker.adopt_foreground", (params) => this.Service.AdoptForeground(params.Has("preset") ? params["preset"] : ""), "Explicitly adopt the foreground process as a tracker preset", "S2")
        app.Actions.Register("tracker.status", (params) => this.Service.Status(params.Has("preset") ? params["preset"] : ""), "Show owned tracker registry state", "S0")
        this.ActionIds := ["tracker.restart", "tracker.launch", "tracker.adopt_foreground", "tracker.status"]
        return AQResult.Ok("F06 initialized")
    }

    Teardown(app) {
        if HasProp(this, "ActionIds") {
            for actionId in this.ActionIds
                app.Actions.Unregister(actionId)
        }
        return AQResult.Ok("F06 stopped")
    }
}
