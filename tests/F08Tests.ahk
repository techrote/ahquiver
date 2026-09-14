#Requires AutoHotkey v2.0

class F08TestConfig {
    __New(values := unset) {
        this.Values := IsSet(values) ? values : Map()
        this.Path := "F08Test.ini"
    }
    Set(section, key, value) {
        this.Values[section "|" key] := value ""
    }
    Get(section, key, default := "") {
        token := section "|" key
        return this.Values.Has(token) ? this.Values[token] : default
    }
    GetBool(section, key, default := false) {
        raw := StrLower(Trim(this.Get(section, key, default ? "1" : "0")))
        return raw = "1" || raw = "true" || raw = "yes" || raw = "on"
    }
    GetInt(section, key, default := 0) {
        raw := Trim(this.Get(section, key, default ""))
        return RegExMatch(raw, "^-?\d+$") ? raw + 0 : default
    }
}

class F08TestLog {
    Info(*) { return }
    Warn(*) { return }
    Error(*) { return }
}

class F08TestContext {
    __New(context := unset) {
        this.Current := IsSet(context) ? context : F08Context("none.exe")
    }
    Capture() {
        copy := Map()
        for key, value in this.Current
            copy[key] := value
        return copy
    }
}

class F08TestHotkeys {
    __New() {
        this.Items := Map()
        this.Disabled := []
    }
    Register(chord, callback) {
        this.Items[chord] := callback
        return AQResult.Ok("registered")
    }
    Disable(chord) {
        if this.Items.Has(chord)
            this.Items.Delete(chord)
        this.Disabled.Push(chord)
        return true
    }
    Teardown() {
        chords := []
        for chord, _ in this.Items
            chords.Push(chord)
        for chord in chords
            this.Disable(chord)
    }
}

class F08TestApp {
    __New(config, context := unset) {
        this.Config := config
        this.Log := F08TestLog()
        this.Actions := AQActionRegistry(this.Log)
        this.Capabilities := AQCapabilityRegistry()
        this.Context := F08TestContext(IsSet(context) ? context : F08Context("none.exe"))
        this.Identities := AQIdentityRegistry()
        this.Calls := []
    }
    AddAction(id) {
        this.Actions.Register(id, (params) => F08CaptureAction(this, id, params), "test", "S0")
    }
}

F08CaptureAction(app, id, params) {
    copy := Map()
    for key, value in params
        copy[key] := value
    app.Calls.Push(Map("id", id, "params", copy))
    return AQResult.Ok("captured")
}

F08Context(exe, className := "", identity := "", pid := 0) {
    return Map(
        "hwnd", 1,
        "pid", pid,
        "exe", exe,
        "path", "C:\\" exe,
        "class", className,
        "title", "test",
        "terminal", "unknown",
        "modifiers", Map(),
        "project_identity", identity,
        "timestamp", A_TickCount
    )
}

F08BaseConfig() {
    cfg := F08TestConfig()
    cfg.Set("F08", "profiles", "terminal,browser")
    cfg.Set("F08.profile.terminal", "enabled", "1")
    cfg.Set("F08.profile.terminal", "priority", "20")
    cfg.Set("F08.profile.terminal", "exe", "WindowsTerminal.exe")
    cfg.Set("F08.profile.browser", "enabled", "1")
    cfg.Set("F08.profile.browser", "priority", "10")
    cfg.Set("F08.profile.browser", "exe", "chrome.exe")
    return cfg
}

F08AddBinding(cfg, id, hotkey, action, profile := "", priority := 0) {
    ids := Trim(cfg.Get("F08", "bindings", ""))
    cfg.Set("F08", "bindings", ids = "" ? id : ids "," id)
    section := "F08.binding." id
    cfg.Set(section, "enabled", "1")
    cfg.Set(section, "hotkey", hotkey)
    cfg.Set(section, "action", action)
    cfg.Set(section, "profile", profile)
    cfg.Set(section, "priority", priority)
    cfg.Set(section, "param_count", "0")
}

TestF08ParsingAndParameters() {
    cfg := F08BaseConfig()
    F08AddBinding(cfg, "terminal_alpha", "^!s", "alpha", "terminal", 5)
    cfg.Set("F08.binding.terminal_alpha", "param_count", "2")
    cfg.Set("F08.binding.terminal_alpha", "param1_key", "mode")
    cfg.Set("F08.binding.terminal_alpha", "param1_value", "safe")
    cfg.Set("F08.binding.terminal_alpha", "param2_key", "slot")
    cfg.Set("F08.binding.terminal_alpha", "param2_value", "3")
    app := F08TestApp(cfg, F08Context("WindowsTerminal.exe"))
    app.AddAction("alpha")
    profiles := F08ProfileStore(cfg)
    bindings := F08BindingStore(cfg, app.Actions, profiles)
    resolver := F08Resolver(app, profiles, bindings)
    resolved := resolver.Resolve("^!s")
    AssertF08True(resolved.IsOk())
    AssertF08Equal("terminal_alpha", resolved.Data["binding"])
    AssertF08Equal("safe", resolved.Data["params"]["mode"])
    AssertF08Equal("3", resolved.Data["params"]["slot"])
    dispatched := resolver.Dispatch("^!s")
    AssertF08True(dispatched.IsOk())
    AssertF08Equal("alpha", app.Calls[1]["id"])
}

TestF08StaticConflictDeterministicWinner() {
    cfg := F08BaseConfig()
    F08AddBinding(cfg, "zeta", "^!s", "alpha", "terminal", 5)
    F08AddBinding(cfg, "alpha_id", "^!s", "bravo", "terminal", 5)
    app := F08TestApp(cfg, F08Context("WindowsTerminal.exe"))
    app.AddAction("alpha")
    app.AddAction("bravo")
    profiles := F08ProfileStore(cfg)
    bindings := F08BindingStore(cfg, app.Actions, profiles)
    resolver := F08Resolver(app, profiles, bindings)
    resolved := resolver.Resolve("^!s")
    AssertF08True(resolved.IsOk())
    AssertF08Equal("alpha_id", resolved.Data["binding"])
    AssertF08Equal(1, bindings.Diagnostics.Length)
    AssertF08Equal("conflict", bindings.Diagnostics[1]["status"])
}

TestF08ProfilePrecedenceAndExplicitOverride() {
    cfg := F08BaseConfig()
    cfg.Set("F08.profile.browser", "exe", "WindowsTerminal.exe")
    F08AddBinding(cfg, "terminal_alpha", "^!s", "alpha", "terminal", 1)
    F08AddBinding(cfg, "browser_bravo", "^!s", "bravo", "browser", 50)
    F08AddBinding(cfg, "global", "^!s", "global", "", 99)
    app := F08TestApp(cfg, F08Context("WindowsTerminal.exe"))
    app.AddAction("alpha")
    app.AddAction("bravo")
    app.AddAction("global")
    profiles := F08ProfileStore(cfg)
    bindings := F08BindingStore(cfg, app.Actions, profiles)
    resolver := F08Resolver(app, profiles, bindings)
    automatic := resolver.Resolve("^!s")
    AssertF08Equal("terminal_alpha", automatic.Data["binding"])
    AssertF08Equal("terminal", automatic.Data["profile"])
    setResult := resolver.SetExplicitProfile("browser")
    AssertF08True(setResult.IsOk())
    explicit := resolver.Resolve("^!s")
    AssertF08Equal("browser_bravo", explicit.Data["binding"])
    AssertF08Equal("browser", explicit.Data["profile"])
}

TestF08ContextEnterLeaveAndGlobalFallback() {
    cfg := F08BaseConfig()
    F08AddBinding(cfg, "terminal", "^!s", "alpha", "terminal", 0)
    F08AddBinding(cfg, "browser", "^!s", "bravo", "browser", 0)
    F08AddBinding(cfg, "global", "^!s", "global", "", 0)
    app := F08TestApp(cfg)
    app.AddAction("alpha")
    app.AddAction("bravo")
    app.AddAction("global")
    profiles := F08ProfileStore(cfg)
    bindings := F08BindingStore(cfg, app.Actions, profiles)
    resolver := F08Resolver(app, profiles, bindings)
    AssertF08Equal("terminal", resolver.Resolve("^!s", F08Context("WindowsTerminal.exe")).Data["binding"])
    AssertF08Equal("browser", resolver.Resolve("^!s", F08Context("chrome.exe")).Data["binding"])
    AssertF08Equal("global", resolver.Resolve("^!s", F08Context("notepad.exe")).Data["binding"])
}

TestF08InvalidActionIsLocal() {
    cfg := F08BaseConfig()
    F08AddBinding(cfg, "bad", "^!x", "missing.action", "terminal", 0)
    F08AddBinding(cfg, "good", "^!s", "alpha", "terminal", 0)
    app := F08TestApp(cfg, F08Context("WindowsTerminal.exe"))
    app.AddAction("alpha")
    profiles := F08ProfileStore(cfg)
    bindings := F08BindingStore(cfg, app.Actions, profiles)
    AssertF08Equal(1, bindings.Items.Length)
    AssertF08Equal("good", bindings.Items[1]["id"])
    AssertF08Equal("invalid", bindings.Diagnostics[1]["status"])
}

TestF08EmergencyBypass() {
    cfg := F08BaseConfig()
    F08AddBinding(cfg, "terminal", "^!s", "alpha", "terminal", 0)
    app := F08TestApp(cfg, F08Context("WindowsTerminal.exe"))
    app.AddAction("alpha")
    profiles := F08ProfileStore(cfg)
    bindings := F08BindingStore(cfg, app.Actions, profiles)
    resolver := F08Resolver(app, profiles, bindings)
    resolver.SetBypass(true)
    result := resolver.Dispatch("^!s")
    AssertF08Equal("cancelled", result.Status)
    AssertF08Equal(0, app.Calls.Length)
    resolver.SetBypass(false)
    AssertF08True(resolver.Dispatch("^!s").IsOk())
    AssertF08Equal(1, app.Calls.Length)
}

TestF08IdentityContextUsesSharedRegistry() {
    cfg := F08TestConfig()
    cfg.Set("F08", "profiles", "project")
    cfg.Set("F08.profile.project", "enabled", "1")
    cfg.Set("F08.profile.project", "priority", "10")
    cfg.Set("F08.profile.project", "identity", "Audit Worker")
    F08AddBinding(cfg, "identity_binding", "^!i", "alpha", "project", 0)
    app := F08TestApp(cfg, F08Context("WindowsTerminal.exe", "", "", 4242))
    app.AddAction("alpha")
    app.Identities.Register("preset", "Audit Worker", "worker", 4242)
    profiles := F08ProfileStore(cfg)
    bindings := F08BindingStore(cfg, app.Actions, profiles)
    resolver := F08Resolver(app, profiles, bindings)
    result := resolver.Resolve("^!i")
    AssertF08True(result.IsOk())
    AssertF08Equal("identity_binding", result.Data["binding"])
}

TestF08ModuleReloadAndTeardown() {
    cfg := F08TestConfig()
    F08AddBinding(cfg, "first", "^!1", "alpha", "", 0)
    app := F08TestApp(cfg)
    app.AddAction("alpha")
    hotkeys := F08TestHotkeys()
    module := F08KeybindProfilesModule(hotkeys)
    firstInit := module.Init(app)
    AssertF08True(firstInit.IsOk())
    AssertF08True(hotkeys.Items.Has("^!1"))
    AssertF08True(app.Actions.Has("keybind.status"))
    module.Teardown(app)
    AssertF08Equal(0, hotkeys.Items.Count)
    AssertF08False(app.Actions.Has("keybind.status"))

    cfg.Set("F08", "bindings", "second")
    section := "F08.binding.second"
    cfg.Set(section, "enabled", "1")
    cfg.Set(section, "hotkey", "^!2")
    cfg.Set(section, "action", "alpha")
    cfg.Set(section, "profile", "")
    cfg.Set(section, "priority", "0")
    cfg.Set(section, "param_count", "0")
    secondInit := module.Init(app)
    AssertF08True(secondInit.IsOk())
    AssertF08False(hotkeys.Items.Has("^!1"))
    AssertF08True(hotkeys.Items.Has("^!2"))
    module.Teardown(app)
    AssertF08Equal(0, hotkeys.Items.Count)
}

TestF08SamePhysicalHotkeyDifferentProfilesDispatchesDifferentActions() {
    cfg := F08BaseConfig()
    F08AddBinding(cfg, "terminal_action", "^!s", "alpha", "terminal", 0)
    F08AddBinding(cfg, "browser_action", "^!s", "bravo", "browser", 0)
    app := F08TestApp(cfg, F08Context("WindowsTerminal.exe"))
    app.AddAction("alpha")
    app.AddAction("bravo")
    hotkeys := F08TestHotkeys()
    module := F08KeybindProfilesModule(hotkeys)
    module.Init(app)
    try {
        hotkeys.Items["^!s"].Call()
        AssertF08Equal("alpha", app.Calls[1]["id"])
        app.Context.Current := F08Context("chrome.exe")
        hotkeys.Items["^!s"].Call()
        AssertF08Equal("bravo", app.Calls[2]["id"])
    } finally module.Teardown(app)
    AssertF08Equal(0, hotkeys.Items.Count)
}
