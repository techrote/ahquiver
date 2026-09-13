#Requires AutoHotkey v2.0

F04Snapshot(hwnd, pid, exe := "WindowsTerminal.exe", className := "WTClass") {
    return Map("hwnd", hwnd, "pid", pid, "exe", exe, "path", "C:\\fake\\" exe, "class", className, "title", "", "style", 0x10000000, "timestamp", 1)
}

class FakeF04Windows {
    __New(items := unset) {
        this.Items := IsSet(items) ? items : Map()
        this.Stale := Map()
    }
    Describe(hwnd) => this.Items.Has(hwnd) ? this.Items[hwnd] : F04Snapshot(hwnd, 0, "", "")
    StillMatches(snapshot) => snapshot.Has("hwnd") && !this.Stale.Has(snapshot["hwnd"])
}

class FakeF04Context {
    ClassifyTerminal(exe) {
        return StrLower(exe) = "windowsterminal.exe" ? "WindowsTerminal" : "unknown"
    }
}

class FakeF04Foreground {
    __New(active := 900) {
        this.Active := active
        this.Activations := []
        this.FailRestore := false
    }
    ActiveHwnd() => this.Active
    Activate(hwnd, timeoutMs := 750) {
        this.Active := hwnd
        this.Activations.Push(hwnd)
        return AQResult.Ok("fake activate")
    }
    Restore(hwnd, timeoutMs := 750) {
        if this.FailRestore
            return AQResult.Failed("fake restore failure")
        this.Active := hwnd
        this.Activations.Push(hwnd)
        return AQResult.Ok("fake restore")
    }
}

class FakeF04Transport {
    __New() {
        this.BackgroundCalls := 0
        this.FallbackCalls := 0
    }
    BackgroundPaste(controlHwnd) {
        this.BackgroundCalls += 1
        return AQResult.Ok("fake background")
    }
    FocusHandoffPaste(targetHwnd, controlHwnd := 0) {
        this.FallbackCalls += 1
        return AQResult.Ok("fake fallback")
    }
}

class FakeF04Probe {
    __New(app) => this.App := app
    RunAll() {
        this.App.Capabilities.Set("terminal.standard_edit.can_background_paste", "supported", "fake")
        this.App.Capabilities.Set("terminal.windowsterminal.can_background_paste", "unknown", "unverified")
        return AQResult.Ok("fake probe")
    }
    ProbeStandardEdit() {
        this.App.Capabilities.Set("terminal.standard_edit.can_background_paste", "supported", "fake")
        return this.App.Capabilities.Get("terminal.standard_edit.can_background_paste")
    }
}

class F04NoopClipboard {
    Run(callback) => callback.Call()
}

class SyntheticF04App {
    __New(configPath, windows) {
        this.Config := AQConfig(configPath)
        this.Log := AQLog(F04TempPath("log"), false)
        this.Capabilities := AQCapabilityRegistry()
        this.Windows := windows
        this.Context := FakeF04Context()
        this.Actions := AQActionRegistry(this.Log)
        this.Clipboard := F04NoopClipboard()
    }
}

F04BaseConfig(path, allowFallback := false) {
    IniWrite(allowFallback ? "1" : "0", path, "F04", "allow_focus_handoff")
    IniWrite("0", path, "F04", "auto_probe_standard_edit")
    IniWrite("300000", path, "F04", "target_max_age_ms")
    IniWrite("750", path, "F04", "activation_timeout_ms")
    IniWrite("750", path, "F04", "restore_timeout_ms")
    IniWrite("", path, "F04", "capture_hotkey")
    IniWrite("", path, "F04", "background_paste_hotkey")
    IniWrite("", path, "F04", "focus_handoff_hotkey")
}

TestF04WindowsTerminalUnsupportedWithoutProof() {
    path := F04TempPath("wt")
    try {
        F04BaseConfig(path)
        windows := FakeF04Windows(Map(100, F04Snapshot(100, 10)))
        app := SyntheticF04App(path, windows)
        app.Capabilities.Set("terminal.windowsterminal.can_background_paste", "unknown", "unverified")
        transport := FakeF04Transport()
        service := F04PasteService(app, unset, FakeF04Foreground(), transport, FakeF04Probe(app))
        AssertF04True(service.SetTarget(100).IsOk())
        result := service.BackgroundPaste()
        AssertF04Equal("unsupported", result.Status)
        AssertF04Equal(0, transport.BackgroundCalls, "Unverified Windows Terminal must receive no injection attempt")
    } finally F04Delete(path)
}

TestF04StaleTargetRejected() {
    path := F04TempPath("stale")
    try {
        F04BaseConfig(path)
        windows := FakeF04Windows(Map(101, F04Snapshot(101, 11)))
        app := SyntheticF04App(path, windows)
        service := F04PasteService(app, unset, FakeF04Foreground(), FakeF04Transport(), FakeF04Probe(app))
        service.SetTarget(101)
        windows.Stale[101] := true
        AssertF04Equal("rejected", service.BackgroundPaste().Status)
    } finally F04Delete(path)
}

TestF04FallbackDisabledByDefault() {
    path := F04TempPath("fallback-off")
    try {
        F04BaseConfig(path, false)
        windows := FakeF04Windows(Map(102, F04Snapshot(102, 12)))
        app := SyntheticF04App(path, windows)
        service := F04PasteService(app, unset, FakeF04Foreground(), FakeF04Transport(), FakeF04Probe(app))
        service.SetTarget(102)
        AssertF04Equal("unsupported", service.FocusHandoffPaste().Status)
    } finally F04Delete(path)
}

TestF04FallbackIsExplicitlyDegradedAndRestores() {
    path := F04TempPath("fallback-on")
    try {
        F04BaseConfig(path, true)
        windows := FakeF04Windows(Map(103, F04Snapshot(103, 13)))
        app := SyntheticF04App(path, windows)
        foreground := FakeF04Foreground(900)
        transport := FakeF04Transport()
        service := F04PasteService(app, unset, foreground, transport, FakeF04Probe(app))
        service.SetTarget(103)
        result := service.FocusHandoffPaste()
        AssertF04True(result.IsOk())
        AssertF04Equal("focus_handoff", result.Data["mode"])
        AssertF04Equal("degraded", result.Data["capability_status"])
        AssertF04Equal(900, foreground.ActiveHwnd())
        AssertF04Equal(1, transport.FallbackCalls)
        cap := app.Capabilities.Get("terminal.windowsterminal.focus_handoff_paste")
        AssertF04Equal("degraded", cap["status"])
    } finally F04Delete(path)
}

TestF04ProbeTruthStates() {
    path := F04TempPath("probe")
    try {
        F04BaseConfig(path)
        app := SyntheticF04App(path, FakeF04Windows())
        probe := FakeF04Probe(app)
        AssertF04True(probe.RunAll().IsOk())
        AssertF04Equal("supported", app.Capabilities.Get("terminal.standard_edit.can_background_paste")["status"])
        AssertF04Equal("unknown", app.Capabilities.Get("terminal.windowsterminal.can_background_paste")["status"])
    } finally F04Delete(path)
}

TestF04ModuleLifecycle() {
    path := F04TempPath("module")
    try {
        F04BaseConfig(path)
        IniWrite("0", path, "modules", "F04")
        app := SyntheticF04App(path, FakeF04Windows())
        module := F04FocusPreservingPasteModule()
        host := AQModuleHost(app)
        host.Register(module)
        host.StartConfigured()
        AssertF04Equal("disabled", host.State("F04"))
        AssertF04False(app.Actions.Has("terminal.paste_background"))
        IniWrite("1", path, "modules", "F04")
        host.Reload()
        AssertF04Equal("enabled", host.State("F04"))
        AssertF04True(app.Actions.Has("terminal.paste_background"))
        AssertF04Equal("unknown", app.Capabilities.Get("terminal.windowsterminal.can_background_paste")["status"])
        host.StopAll()
        AssertF04False(app.Actions.Has("terminal.paste_background"))
    } finally F04Delete(path)
}
