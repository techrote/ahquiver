#Requires AutoHotkey v2.0

class AHQuiverApp {
    __New(args := unset) {
        this.RootDir := A_ScriptDir "\.."
        this.Options := this._ParseArgs(IsSet(args) ? args : [])

        defaultConfig := this.RootDir "\config\ahquiver.ini"
        exampleConfig := this.RootDir "\config\ahquiver.example.ini"
        if this.Options.Has("config")
            configPath := this._ResolvePath(this.Options["config"])
        else if FileExist(defaultConfig)
            configPath := defaultConfig
        else
            configPath := exampleConfig

        this.Config := AQConfig(configPath)
        logPath := this._ResolvePath(this.Config.Get("core", "log_path", "logs\ahquiver.log"))
        logEnabled := this.Config.GetBool("core", "log_enabled", true)
        this.Log := AQLog(logPath, logEnabled)
        this.Capabilities := AQCapabilityRegistry()
        this.Context := AQContextService()
        this.Windows := AQWindowQuery()
        this.Actions := AQActionRegistry(this.Log)
        this.Clipboard := AQClipboardGuard()
        this.Identities := AQIdentityRegistry()
        this.Modules := AQModuleHost(this)
        this.Modules.Register(F01CloseMatchingWindowsModule())
        this.Modules.Register(F02TerminalIdentityModule())
        this.Modules.Register(F03TerminalKeyGuardModule())
        this.Modules.Register(F04FocusPreservingPasteModule())
        this.Ui := AQTrayUi(this)
        this.Started := false
    }

    Start() {
        if this.Started
            return AQResult.Ok("AHQuiver already started")

        configResult := this.Config.Reload()
        if !configResult.IsOk()
            throw Error(configResult.Message)

        this.Log.Info("host=start config=" this.Config.Path)
        this.Modules.StartConfigured()
        if !this.Options.Has("headless")
            this.Ui.Init()
        this.Started := true
        return AQResult.Ok("AHQuiver started")
    }

    ReloadConfiguration() {
        configResult := this.Config.Reload()
        if !configResult.IsOk()
            return configResult
        modulesResult := this.Modules.Reload()
        this.Log.Info("host=config_reloaded")
        return modulesResult
    }

    Stop() {
        if !this.Started
            return AQResult.Ok("AHQuiver already stopped")
        this.Modules.StopAll()
        this.Ui.Teardown()
        this.Log.Info("host=stop")
        this.Started := false
        return AQResult.Ok("AHQuiver stopped")
    }

    _ResolvePath(path) {
        if RegExMatch(path, "i)^[A-Z]:\\") || SubStr(path, 1, 2) = "\\"
            return path
        return this.RootDir "\" path
    }

    _ParseArgs(args) {
        options := Map()
        i := 1
        while i <= args.Length {
            arg := args[i]
            if arg = "--config" {
                if i = args.Length
                    throw ValueError("--config requires a path")
                i += 1
                options["config"] := args[i]
            } else if arg = "--headless" {
                options["headless"] := true
            } else if arg = "--probe-startup" {
                options["probe-startup"] := true
            } else {
                throw ValueError("Unknown argument: " arg)
            }
            i += 1
        }
        return options
    }
}
