#Requires AutoHotkey v2.0

class F02ProcessAdapter {
    Launch(program, args, workingDir := "") {
        return AQProcess.Launch(program, args, workingDir)
    }

    IsRunning(pid) {
        if !pid
            return false
        try return ProcessExist(pid) = pid
        catch
            return false
    }
}

class F02PresetStore {
    __New(config) {
        this.Config := config
    }

    Ids() {
        ids := []
        seen := Map()
        raw := this.Config.Get("F02", "presets", "")
        for part in StrSplit(raw, ",") {
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

    Has(id) {
        for candidate in this.Ids() {
            if candidate = id
                return true
        }
        return false
    }

    Get(id) {
        if !RegExMatch(id, "^[A-Za-z0-9_.-]+$")
            return AQResult.Invalid("Invalid F02 preset id: " id)
        if !this.Has(id)
            return AQResult.Invalid("Unknown F02 preset: " id)

        section := "F02.preset." id
        kind := StrLower(Trim(this.Config.Get(section, "kind", "process")))
        if kind != "process" && kind != "windows_terminal"
            return AQResult.Invalid("Invalid preset kind for " id ": " kind)

        programDefault := kind = "windows_terminal" ? "wt.exe" : ""
        program := Trim(this.Config.Get(section, "program", programDefault))
        if program = ""
            return AQResult.Invalid("Preset " id " requires program")

        argCount := this.Config.GetInt(section, "arg_count", 0)
        if argCount < 0 || argCount > 64
            return AQResult.Invalid("Preset " id " arg_count must be between 0 and 64")
        args := []
        Loop argCount
            args.Push(this.Config.Get(section, "arg" A_Index, ""))

        identity := Trim(this.Config.Get(section, "identity", id))
        if identity = ""
            identity := id
        role := Trim(this.Config.Get(section, "role", ""))
        title := this.Config.Get(section, "title", identity)
        singleton := this.Config.GetBool(section, "singleton", false)
        singletonDefault := kind = "windows_terminal" ? "sticky" : "pid"
        singletonMode := StrLower(Trim(this.Config.Get(section, "singleton_mode", singletonDefault)))
        if singletonMode != "pid" && singletonMode != "sticky"
            return AQResult.Invalid("Preset " id " singleton_mode must be pid or sticky")

        titleModeDefault := kind = "windows_terminal" ? "cli" : "none"
        titleMode := StrLower(Trim(this.Config.Get(section, "title_mode", titleModeDefault)))
        if titleMode != "none" && titleMode != "window" && titleMode != "cli"
            return AQResult.Invalid("Preset " id " title_mode must be none, window or cli")
        if kind != "windows_terminal" && titleMode = "cli"
            return AQResult.Invalid("Preset " id " can use title_mode=cli only with windows_terminal kind")

        preset := Map(
            "id", id,
            "kind", kind,
            "identity", identity,
            "role", role,
            "program", program,
            "args", args,
            "working_dir", Trim(this.Config.Get(section, "working_dir", ".")),
            "title", title,
            "title_mode", titleMode,
            "terminal_kind", Trim(this.Config.Get(section, "terminal_kind", kind = "windows_terminal" ? "WindowsTerminal" : "unknown")),
            "profile", this.Config.Get(section, "profile", ""),
            "window_name", this.Config.Get(section, "window_name", ""),
            "singleton", singleton,
            "singleton_mode", singletonMode,
            "window_wait_ms", this.Config.GetInt(section, "window_wait_ms", 750),
            "icon", this.Config.Get(section, "icon", ""),
            "shortcut", this.Config.Get(section, "shortcut", "")
        )
        return AQResult.Ok("Preset loaded", Map("preset", preset))
    }

    ListSummaries() {
        items := []
        for id in this.Ids() {
            result := this.Get(id)
            if result.IsOk() {
                preset := result.Data["preset"]
                items.Push(Map(
                    "id", id,
                    "identity", preset["identity"],
                    "role", preset["role"],
                    "kind", preset["kind"],
                    "singleton", preset["singleton"]
                ))
            } else {
                items.Push(Map("id", id, "invalid", true, "error", result.Message))
            }
        }
        return items
    }
}

class F02TitleAdapter {
    __New(windows, capabilities) {
        this.Windows := windows
        this.Capabilities := capabilities
    }

    Apply(pid, title, terminalKind, waitMs := 750) {
        capabilityId := this._CapabilityId(terminalKind)
        if Trim(title) = "" {
            this.Capabilities.Set(capabilityId, "unsupported", "No title requested for this preset")
            return AQResult.Unsupported("No title requested")
        }
        if !pid {
            this.Capabilities.Set(capabilityId, "unsupported", "Launch did not provide a process id")
            return AQResult.Unsupported("Cannot attach a title without a launched PID")
        }

        deadline := A_TickCount + Max(waitMs, 0)
        loop {
            matches := this.Windows.FindVisibleByPid(pid)
            if matches.Length {
                snapshot := matches[1]
                result := this.Windows.RequestTitle(snapshot, title)
                if !result.IsOk() {
                    this.Capabilities.Set(capabilityId, "unsupported", result.Message)
                    return result
                }

                verified := result.Data.Has("verified") && result.Data["verified"]
                status := verified ? "supported" : "degraded"
                detail := verified
                    ? "Top-level HWND title update verified for launched process"
                    : "Top-level title request returned but could not be verified and may be overwritten"
                this.Capabilities.Set(capabilityId, status, detail)
                return AQResult.Ok("Title request completed", Map(
                    "capability_status", status,
                    "verified", verified,
                    "hwnd", snapshot["hwnd"]
                ))
            }

            if A_TickCount >= deadline
                break
            Sleep(50)
        }

        this.Capabilities.Set(capabilityId, "unknown", "No visible top-level window was attributable to the launched PID")
        return AQResult.Unsupported("No visible top-level window found for launched PID")
    }

    MarkWindowsTerminalCliTitle(title) {
        capabilityId := this._CapabilityId("WindowsTerminal")
        if Trim(title) = "" {
            this.Capabilities.Set(capabilityId, "unsupported", "No Windows Terminal title was requested")
            return "unsupported"
        }
        this.Capabilities.Set(
            capabilityId,
            "supported",
            "Title requested at launch using wt.exe --title with --suppressApplicationTitle"
        )
        return "supported"
    }

    _CapabilityId(terminalKind) {
        normalized := RegExReplace(StrLower(terminalKind), "[^a-z0-9]+", "_")
        if normalized = ""
            normalized := "unknown"
        return "terminal." normalized ".can_set_title"
    }
}

class F02LauncherService {
    __New(app, store, processAdapter := unset, titleAdapter := unset) {
        this.App := app
        this.Store := store
        this.Process := IsSet(processAdapter) ? processAdapter : F02ProcessAdapter()
        this.Title := IsSet(titleAdapter) ? titleAdapter : F02TitleAdapter(app.Windows, app.Capabilities)
    }

    Launch(presetId) {
        loaded := this.Store.Get(presetId)
        if !loaded.IsOk()
            return loaded
        preset := loaded.Data["preset"]

        singletonResult := this._CheckSingleton(preset)
        if !singletonResult.IsOk()
            return singletonResult

        workingDir := this._ResolvePath(preset["working_dir"])
        args := preset["kind"] = "windows_terminal"
            ? this._WindowsTerminalArgs(preset, workingDir)
            : preset["args"]

        launch := this.Process.Launch(preset["program"], args, workingDir)
        if !launch.IsOk()
            return launch

        pid := launch.Data.Has("pid") ? launch.Data["pid"] : 0
        metadata := Map(
            "kind", preset["kind"],
            "program", preset["program"],
            "title", preset["title"],
            "terminal_kind", preset["terminal_kind"],
            "window_name", preset["window_name"],
            "singleton_mode", preset["singleton_mode"],
            "icon", preset["icon"],
            "shortcut", preset["shortcut"]
        )
        record := this.App.Identities.Register(
            preset["id"], preset["identity"], preset["role"], pid, metadata
        )

        titleStatus := "not_requested"
        titleDetail := ""
        if preset["kind"] = "windows_terminal" && preset["title_mode"] = "cli" {
            titleStatus := this.Title.MarkWindowsTerminalCliTitle(preset["title"])
            titleDetail := "Windows Terminal CLI title requested"
        } else if preset["title_mode"] = "window" {
            titleResult := this.Title.Apply(pid, preset["title"], preset["terminal_kind"], preset["window_wait_ms"])
            titleStatus := titleResult.IsOk() && titleResult.Data.Has("capability_status")
                ? titleResult.Data["capability_status"]
                : titleResult.Status
            titleDetail := titleResult.Message
        }

        return AQResult.Ok("Terminal/project preset launched", Map(
            "preset", preset["id"],
            "identity", preset["identity"],
            "pid", pid,
            "record", record,
            "title_status", titleStatus,
            "title_detail", titleDetail
        ))
    }

    ListPresets() {
        return AQResult.Ok("F02 presets", Map("items", this.Store.ListSummaries()))
    }

    ListIdentities() {
        this._RefreshPidSingletons()
        return AQResult.Ok("Known AHQuiver identities", Map("items", this.App.Identities.List()))
    }

    Release(params) {
        presetId := params.Has("preset") ? Trim(params["preset"]) : ""
        if presetId = ""
            return AQResult.Invalid("terminal.release_identity requires preset")
        count := this.App.Identities.ReleasePreset(presetId)
        return AQResult.Ok("Identity records released", Map("preset", presetId, "released", count))
    }

    _CheckSingleton(preset) {
        if !preset["singleton"]
            return AQResult.Ok("Singleton disabled")

        active := this.App.Identities.FindActiveByPreset(preset["id"])
        if !active.Count
            return AQResult.Ok("No active singleton record")

        if preset["singleton_mode"] = "sticky"
            return AQResult.Rejected("Preset already has an active sticky singleton identity: " preset["id"])

        pid := active.Has("pid") ? active["pid"] : 0
        if pid && this.Process.IsRunning(pid)
            return AQResult.Rejected("Preset already has a running singleton process: " preset["id"])

        this.App.Identities.MarkInactive(active["id"], "process_exited")
        return AQResult.Ok("Stale singleton record retired")
    }

    _RefreshPidSingletons() {
        for record in this.App.Identities.List(true) {
            if !record.Has("singleton_mode") || record["singleton_mode"] != "pid"
                continue
            pid := record.Has("pid") ? record["pid"] : 0
            if !pid || !this.Process.IsRunning(pid)
                this.App.Identities.MarkInactive(record["id"], "process_exited")
        }
    }

    _WindowsTerminalArgs(preset, workingDir) {
        args := []
        if Trim(preset["window_name"]) != "" {
            args.Push("-w")
            args.Push(preset["window_name"])
        }
        args.Push("new-tab")
        if Trim(preset["profile"]) != "" {
            args.Push("--profile")
            args.Push(preset["profile"])
        }
        if preset["title_mode"] = "cli" && Trim(preset["title"]) != "" {
            args.Push("--title")
            args.Push(preset["title"])
            args.Push("--suppressApplicationTitle")
        }
        if workingDir != "" {
            args.Push("-d")
            args.Push(workingDir)
        }
        for arg in preset["args"]
            args.Push(arg)
        return args
    }

    _ResolvePath(path) {
        path := Trim(path)
        if path = ""
            return this.App.RootDir
        if RegExMatch(path, "i)^[A-Z]:\\") || SubStr(path, 1, 2) = "\\"
            return path
        return this.App.RootDir "\" path
    }
}

class F02TerminalIdentityModule {
    __New() {
        this.Id := "F02"
        this.Name := "Terminal identity and project launcher"
        this.Service := ""
    }

    Init(app) {
        store := F02PresetStore(app.Config)
        this.Service := F02LauncherService(app, store)
        app.Actions.Register("terminal.launch_preset", this._Launch.Bind(this), "Launch an F02 terminal/project preset", "S1")
        app.Actions.Register("terminal.list_presets", this._ListPresets.Bind(this), "List configured F02 presets", "S0")
        app.Actions.Register("terminal.list_identities", this._ListIdentities.Bind(this), "List AHQuiver-owned launch identities", "S0")
        app.Actions.Register("terminal.release_identity", this._Release.Bind(this), "Release a sticky/singleton identity record", "S1")
    }

    Teardown(app) {
        for actionId in ["terminal.launch_preset", "terminal.list_presets", "terminal.list_identities", "terminal.release_identity"]
            app.Actions.Unregister(actionId)
        this.Service := ""
    }

    _Launch(params) {
        presetId := params.Has("preset") ? Trim(params["preset"]) : ""
        if presetId = ""
            return AQResult.Invalid("terminal.launch_preset requires preset")
        return this.Service.Launch(presetId)
    }

    _ListPresets(params) {
        return this.Service.ListPresets()
    }

    _ListIdentities(params) {
        return this.Service.ListIdentities()
    }

    _Release(params) {
        return this.Service.Release(params)
    }
}
