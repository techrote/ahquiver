#Requires AutoHotkey v2.0

class FakeF01WindowQuery {
    __New(windows, staleHwnds := unset, failedHwnds := unset) {
        this.Windows := windows
        this.Stale := Map()
        this.Fail := Map()
        this.CloseRequests := []
        if IsSet(staleHwnds) {
            for hwnd in staleHwnds
                this.Stale[hwnd] := true
        }
        if IsSet(failedHwnds) {
            for hwnd in failedHwnds
                this.Fail[hwnd] := true
        }
    }

    EnumerateVisible() {
        return this.Windows
    }

    StillMatches(snapshot) {
        return snapshot.Has("hwnd") && !this.Stale.Has(snapshot["hwnd"])
    }

    RequestClose(snapshot, timeoutMs := 750) {
        this.CloseRequests.Push(snapshot["hwnd"])
        if this.Fail.Has(snapshot["hwnd"])
            return AQResult.Failed("synthetic close failure")
        return AQResult.Ok("synthetic close")
    }
}

F01Window(hwnd, pid, exe, className, title := "") {
    return Map(
        "hwnd", hwnd,
        "pid", pid,
        "exe", exe,
        "path", "C:\\synthetic\\" exe,
        "class", className,
        "title", title,
        "style", 0x10000000,
        "timestamp", 1
    )
}

TestF01ExecutableGroupingPreview() {
    target := F01Window(100, 10, "app.exe", "ClassA", "Alpha")
    windows := [
        target,
        F01Window(101, 11, "APP.EXE", "ClassB", "Beta"),
        F01Window(102, 12, "other.exe", "ClassA", "Alpha")
    ]
    fake := FakeF01WindowQuery(windows)
    service := F01CloseMatchingWindowsService(fake, Map("protect_self", false, "protect_shell", false, "confirm", false))

    result := service.Execute(target, Map("preview", true))
    AssertTrue(result.IsOk())
    AssertEqual(2, result.Data["candidate"], "Default grouping should be executable-only")
    AssertEqual(2, result.Data["windows"].Length, "Preview should expose only closable matches")
    AssertEqual(0, fake.CloseRequests.Length, "Preview must not close windows")
}

TestF01ClassAndTitleRefinement() {
    target := F01Window(200, 20, "app.exe", "ClassA", "Alpha")
    windows := [
        target,
        F01Window(201, 21, "app.exe", "ClassA", "Beta"),
        F01Window(202, 22, "app.exe", "ClassB", "Alpha")
    ]
    fake := FakeF01WindowQuery(windows)

    classService := F01CloseMatchingWindowsService(fake, Map("protect_self", false, "protect_shell", false, "match_class", true, "confirm", false))
    classPreview := classService.Execute(target, Map("preview", true))
    AssertEqual(2, classPreview.Data["candidate"], "Class refinement should exclude different classes")

    titleService := F01CloseMatchingWindowsService(fake, Map("protect_self", false, "protect_shell", false, "match_class", true, "match_title", true, "confirm", false))
    titlePreview := titleService.Execute(target, Map("preview", true))
    AssertEqual(1, titlePreview.Data["candidate"], "Title refinement should require an exact title")
}

TestF01SafetyAndCloseAccounting() {
    target := F01Window(300, 30, "app.exe", "ClassA", "Alpha")
    windows := [
        target,
        F01Window(301, 31, "app.exe", "ClassB", "Beta"),
        F01Window(302, 32, "other.exe", "ClassA", "Alpha"),
        F01Window(303, 33, "app.exe", "Shell_TrayWnd", "Synthetic shell"),
        F01Window(304, 34, "app.exe", "ClassA", "Stale"),
        F01Window(305, 35, "app.exe", "ClassA", "Failure")
    ]
    fake := FakeF01WindowQuery(windows, [304], [305])
    service := F01CloseMatchingWindowsService(fake, Map("protect_self", false, "protect_shell", true, "confirm", false))

    result := service.Execute(target)
    AssertEqual("failed", result.Status, "A close failure should be surfaced")
    AssertEqual(5, result.Data["candidate"], "Only same-executable windows are candidates")
    AssertEqual(1, result.Data["skipped"], "Protected shell window should be skipped")
    AssertEqual(1, result.Data["stale"], "Stale window should be rejected before close")
    AssertEqual(2, result.Data["closed"], "Two synthetic closes should succeed")
    AssertEqual(1, result.Data["failed"], "One synthetic close should fail")
    AssertEqual(3, fake.CloseRequests.Length, "Only revalidated, non-protected matches receive close requests")
    AssertEqual(300, fake.CloseRequests[1])
    AssertEqual(301, fake.CloseRequests[2])
    AssertEqual(305, fake.CloseRequests[3])
}

TestF01ExclusionsAndConfirmationCancel() {
    target := F01Window(400, 40, "app.exe", "ClassA", "Alpha")
    windows := [
        target,
        F01Window(401, 41, "app.exe", "IgnoredClass", "Beta"),
        F01Window(402, 42, "app.exe", "ClassA", "Gamma")
    ]
    fake := FakeF01WindowQuery(windows)
    confirmer := (*) => false
    service := F01CloseMatchingWindowsService(fake, Map(
        "protect_self", false,
        "protect_shell", false,
        "exclude_classes", "IgnoredClass",
        "confirm", true,
        "confirm_min", 2
    ), confirmer)

    result := service.Execute(target)
    AssertEqual("cancelled", result.Status)
    AssertEqual(3, result.Data["candidate"])
    AssertEqual(1, result.Data["skipped"])
    AssertEqual(0, fake.CloseRequests.Length, "Cancelled confirmation must not close anything")
}

class SyntheticF01Context {
    Capture() {
        return F01Window(500, 50, "app.exe", "ClassA", "Alpha")
    }
}

class SyntheticF01App {
    __New(configPath) {
        this.Config := AQConfig(configPath)
        this.Log := AQLog(TestTempPath("f01-log"), false)
        this.Actions := AQActionRegistry(this.Log)
        this.Windows := FakeF01WindowQuery([F01Window(500, 50, "app.exe", "ClassA", "Alpha")])
        this.Context := SyntheticF01Context()
    }
}

TestF01ModuleLifecycle() {
    path := TestTempPath("f01-module")
    try {
        IniWrite("0", path, "modules", "F01")
        app := SyntheticF01App(path)
        module := F01CloseMatchingWindowsModule()
        host := AQModuleHost(app)
        host.Register(module)

        host.StartConfigured()
        AssertEqual("disabled", host.State("F01"))
        AssertFalse(app.Actions.Has("windows.close_matching"), "Disabled F01 must not register its action")

        IniWrite("1", path, "modules", "F01")
        IniWrite("", path, "F01", "hotkey")
        IniWrite("0", path, "F01", "confirm")
        host.Reload()
        AssertEqual("enabled", host.State("F01"))
        AssertTrue(app.Actions.Has("windows.close_matching"), "Enabled F01 should register its action")

        preview := app.Actions.Invoke("windows.close_matching", Map("preview", true))
        AssertTrue(preview.IsOk())
        AssertEqual(1, preview.Data["candidate"])

        host.StopAll()
        AssertFalse(app.Actions.Has("windows.close_matching"), "F01 teardown must unregister its action")
    } finally {
        TestDelete(path)
    }
}
