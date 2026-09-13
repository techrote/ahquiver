#Requires AutoHotkey v2.0

class FakeF02ProcessAdapter {
    __New(startPid := 7000) {
        this.NextPid := startPid
        this.Running := Map()
        this.Launches := []
        this.FailNext := false
    }

    Launch(program, args, workingDir := "") {
        copiedArgs := []
        for arg in args
            copiedArgs.Push(arg)
        this.Launches.Push(Map("program", program, "args", copiedArgs, "working_dir", workingDir))
        if this.FailNext {
            this.FailNext := false
            return AQResult.Failed("synthetic launch failure")
        }
        pid := this.NextPid
        this.NextPid += 1
        this.Running[pid] := true
        return AQResult.Ok("synthetic process launched", Map("pid", pid))
    }

    IsRunning(pid) {
        return this.Running.Has(pid) && this.Running[pid]
    }

    Stop(pid) {
        this.Running[pid] := false
    }
}

class FakeF02TitleAdapter {
    __New(mode := "supported") {
        this.Mode := mode
        this.Calls := []
        this.CliTitles := []
    }

    Apply(pid, title, terminalKind, waitMs := 750) {
        this.Calls.Push(Map("pid", pid, "title", title, "terminal_kind", terminalKind, "wait_ms", waitMs))
        if this.Mode = "unsupported"
            return AQResult.Unsupported("synthetic title unsupported")
        if this.Mode = "degraded"
            return AQResult.Ok("synthetic degraded title", Map("capability_status", "degraded", "verified", false))
        return AQResult.Ok("synthetic title", Map("capability_status", "supported", "verified", true))
    }

    MarkWindowsTerminalCliTitle(title) {
        this.CliTitles.Push(title)
        return Trim(title) = "" ? "unsupported" : "supported"
    }
}

class SyntheticF02App {
    __New(configPath) {
        this.RootDir := A_Temp "\ahquiver-f02-root"
        this.Config := AQConfig(configPath)
        this.Log := AQLog(A_Temp "\ahquiver-f02-test.log", false)
        this.Actions := AQActionRegistry(this.Log)
        this.Capabilities := AQCapabilityRegistry()
        this.Windows := AQWindowQuery()
        this.Identities := AQIdentityRegistry()
    }
}

F02WriteProcessPreset(path, id, identity, role := "", singleton := false, titleMode := "none") {
    IniWrite(id, path, "F02", "presets")
    section := "F02.preset." id
    IniWrite("process", path, section, "kind")
    IniWrite(identity, path, section, "identity")
    IniWrite(role, path, section, "role")
    IniWrite("tool.exe", path, section, "program")
    IniWrite(".", path, section, "working_dir")
    IniWrite(identity, path, section, "title")
    IniWrite(titleMode, path, section, "title_mode")
    IniWrite(singleton ? "1" : "0", path, section, "singleton")
    IniWrite("pid", path, section, "singleton_mode")
    IniWrite("2", path, section, "arg_count")
    IniWrite("--label", path, section, "arg1")
    IniWrite(identity, path, section, "arg2")
}

TestF02PresetParsing() {
    path := TestTempPath("f02-presets")
    try {
        IniWrite("alpha,beta", path, "F02", "presets")

        IniWrite("process", path, "F02.preset.alpha", "kind")
        IniWrite("Project Alpha", path, "F02.preset.alpha", "identity")
        IniWrite("implementer", path, "F02.preset.alpha", "role")
        IniWrite("pwsh.exe", path, "F02.preset.alpha", "program")
        IniWrite(".", path, "F02.preset.alpha", "working_dir")
        IniWrite("2", path, "F02.preset.alpha", "arg_count")
        IniWrite("-NoExit", path, "F02.preset.alpha", "arg1")
        IniWrite("two words", path, "F02.preset.alpha", "arg2")

        IniWrite("windows_terminal", path, "F02.preset.beta", "kind")
        IniWrite("Project Beta", path, "F02.preset.beta", "identity")
        IniWrite("reviewer", path, "F02.preset.beta", "role")
        IniWrite("beta-window", path, "F02.preset.beta", "window_name")
        IniWrite("PowerShell", path, "F02.preset.beta", "profile")
        IniWrite("1", path, "F02.preset.beta", "singleton")

        store := F02PresetStore(AQConfig(path))
        ids := store.Ids()
        AssertEqual(2, ids.Length)

        alphaResult := store.Get("alpha")
        AssertTrue(alphaResult.IsOk())
        alpha := alphaResult.Data["preset"]
        AssertEqual("Project Alpha", alpha["identity"])
        AssertEqual("implementer", alpha["role"])
        AssertEqual("pwsh.exe", alpha["program"])
        AssertEqual(2, alpha["args"].Length)
        AssertEqual("two words", alpha["args"][2])

        betaResult := store.Get("beta")
        AssertTrue(betaResult.IsOk())
        beta := betaResult.Data["preset"]
        AssertEqual("windows_terminal", beta["kind"])
        AssertEqual("wt.exe", beta["program"], "Windows Terminal preset should default to wt.exe")
        AssertEqual("sticky", beta["singleton_mode"], "WT singleton should default to sticky")
        AssertEqual("cli", beta["title_mode"])
        AssertEqual("invalid", store.Get("missing").Status)
    } finally {
        TestDelete(path)
    }
}

TestF02TwoIndependentIdentities() {
    path := TestTempPath("f02-two-identities")
    try {
        IniWrite("alpha,beta", path, "F02", "presets")
        for spec in [Map("id", "alpha", "identity", "Alpha Implementer", "role", "implementer"), Map("id", "beta", "identity", "Beta Reviewer", "role", "reviewer")] {
            section := "F02.preset." spec["id"]
            IniWrite("process", path, section, "kind")
            IniWrite(spec["identity"], path, section, "identity")
            IniWrite(spec["role"], path, section, "role")
            IniWrite("tool.exe", path, section, "program")
            IniWrite(".", path, section, "working_dir")
            IniWrite("none", path, section, "title_mode")
        }

        app := SyntheticF02App(path)
        process := FakeF02ProcessAdapter()
        title := FakeF02TitleAdapter()
        service := F02LauncherService(app, F02PresetStore(app.Config), process, title)

        first := service.Launch("alpha")
        second := service.Launch("beta")
        AssertTrue(first.IsOk())
        AssertTrue(second.IsOk())
        AssertEqual(2, process.Launches.Length)

        identities := app.Identities.List(true)
        AssertEqual(2, identities.Length)
        AssertEqual("Alpha Implementer", identities[1]["identity"])
        AssertEqual("implementer", identities[1]["role"])
        AssertEqual("Beta Reviewer", identities[2]["identity"])
        AssertEqual("reviewer", identities[2]["role"])
        AssertTrue(first.Data["record"]["id"] != second.Data["record"]["id"], "Launch records must have distinct durable ids")
    } finally {
        TestDelete(path)
    }
}

TestF02PidSingletonLifecycle() {
    path := TestTempPath("f02-pid-singleton")
    try {
        F02WriteProcessPreset(path, "solo", "Singleton Shell", "worker", true)
        app := SyntheticF02App(path)
        process := FakeF02ProcessAdapter()
        service := F02LauncherService(app, F02PresetStore(app.Config), process, FakeF02TitleAdapter())

        first := service.Launch("solo")
        AssertTrue(first.IsOk())
        second := service.Launch("solo")
        AssertEqual("rejected", second.Status, "Running PID singleton should reject duplicate launch")

        process.Stop(first.Data["pid"])
        third := service.Launch("solo")
        AssertTrue(third.IsOk(), "Exited PID singleton should be retired and relaunch allowed")
        AssertEqual(2, process.Launches.Length)
        AssertEqual(1, app.Identities.Count(true), "Only replacement singleton record should remain active")
    } finally {
        TestDelete(path)
    }
}

TestF02WindowsTerminalArgumentsAndStickySingleton() {
    path := TestTempPath("f02-wt")
    try {
        IniWrite("wtdev", path, "F02", "presets")
        section := "F02.preset.wtdev"
        IniWrite("windows_terminal", path, section, "kind")
        IniWrite("WT Dev", path, section, "identity")
        IniWrite("developer", path, section, "role")
        IniWrite("my-project-window", path, section, "window_name")
        IniWrite("PowerShell", path, section, "profile")
        IniWrite("1", path, section, "singleton")
        IniWrite("sticky", path, section, "singleton_mode")
        IniWrite("2", path, section, "arg_count")
        IniWrite("pwsh.exe", path, section, "arg1")
        IniWrite("-NoExit", path, section, "arg2")

        app := SyntheticF02App(path)
        process := FakeF02ProcessAdapter()
        title := FakeF02TitleAdapter()
        service := F02LauncherService(app, F02PresetStore(app.Config), process, title)

        first := service.Launch("wtdev")
        AssertTrue(first.IsOk())
        launch := process.Launches[1]
        AssertEqual("wt.exe", launch["program"])
        expected := ["-w", "my-project-window", "new-tab", "--profile", "PowerShell", "--title", "WT Dev", "--suppressApplicationTitle", "-d", app.RootDir "\.", "pwsh.exe", "-NoExit"]
        AssertEqual(expected.Length, launch["args"].Length)
        Loop expected.Length
            AssertEqual(expected[A_Index], launch["args"][A_Index], "Unexpected wt argument at index " A_Index)
        AssertEqual("supported", first.Data["title_status"])
        AssertEqual(1, title.CliTitles.Length)

        second := service.Launch("wtdev")
        AssertEqual("rejected", second.Status, "Sticky Windows Terminal identity must reject duplicate")
        released := service.Release(Map("preset", "wtdev"))
        AssertTrue(released.IsOk())
        AssertEqual(1, released.Data["released"])
        third := service.Launch("wtdev")
        AssertTrue(third.IsOk(), "Explicit identity release should allow another launch")
    } finally {
        TestDelete(path)
    }
}

TestF02UnsupportedTitleIsNonFatal() {
    path := TestTempPath("f02-title-unsupported")
    try {
        F02WriteProcessPreset(path, "untitled", "No Title Host", "utility", false, "window")
        app := SyntheticF02App(path)
        process := FakeF02ProcessAdapter()
        title := FakeF02TitleAdapter("unsupported")
        service := F02LauncherService(app, F02PresetStore(app.Config), process, title)

        result := service.Launch("untitled")
        AssertTrue(result.IsOk(), "Unsupported title capability must not turn successful process launch into failure")
        AssertEqual("unsupported", result.Data["title_status"])
        AssertEqual(1, title.Calls.Length)
        AssertEqual(1, app.Identities.Count(true))
    } finally {
        TestDelete(path)
    }
}

TestF02WindowsTerminalCapabilityRecord() {
    capabilities := AQCapabilityRegistry()
    adapter := F02TitleAdapter(AQWindowQuery(), capabilities)
    status := adapter.MarkWindowsTerminalCliTitle("Persistent Tab")
    AssertEqual("supported", status)
    capability := capabilities.Get("terminal.windowsterminal.can_set_title")
    AssertEqual("supported", capability["status"])
    AssertTrue(InStr(capability["detail"], "--suppressApplicationTitle") > 0)
}

TestF02SafeCommandQuoting() {
    q := Chr(34)
    slash := Chr(92)
    program := "C:\Program Files\Tool\tool.exe"
    command := AQProcess.BuildCommand(program, ["two words", "x" q "y", "C:\path with space" slash])
    AssertTrue(InStr(command, q program q) = 1)
    AssertTrue(InStr(command, q "two words" q) > 0)
    AssertTrue(InStr(command, q "x" slash q "y" q) > 0, "Embedded quote should be escaped")
    AssertTrue(InStr(command, "C:\path with space" slash slash q) > 0, "Trailing slash should be doubled before closing quote")
}

TestF02ModuleLifecycle() {
    path := TestTempPath("f02-module")
    try {
        IniWrite("0", path, "modules", "F02")
        IniWrite("demo", path, "F02", "presets")
        section := "F02.preset.demo"
        IniWrite("process", path, section, "kind")
        IniWrite("Demo", path, section, "identity")
        IniWrite("tool.exe", path, section, "program")
        IniWrite("none", path, section, "title_mode")

        app := SyntheticF02App(path)
        module := F02TerminalIdentityModule()
        host := AQModuleHost(app)
        host.Register(module)

        host.StartConfigured()
        AssertEqual("disabled", host.State("F02"))
        AssertFalse(app.Actions.Has("terminal.launch_preset"))

        IniWrite("1", path, "modules", "F02")
        host.Reload()
        AssertEqual("enabled", host.State("F02"))
        AssertTrue(app.Actions.Has("terminal.launch_preset"))
        AssertTrue(app.Actions.Has("terminal.list_presets"))
        listed := app.Actions.Invoke("terminal.list_presets")
        AssertTrue(listed.IsOk())
        AssertEqual(1, listed.Data["items"].Length)

        host.StopAll()
        AssertFalse(app.Actions.Has("terminal.launch_preset"))
        AssertFalse(app.Actions.Has("terminal.list_identities"))
    } finally {
        TestDelete(path)
    }
}
