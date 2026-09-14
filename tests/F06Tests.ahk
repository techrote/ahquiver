#Requires AutoHotkey v2.0

class F06TestLog {
    Info(*) {
        return
    }
    Warn(*) {
        return
    }
    Error(*) {
        return
    }
}

class F06FakeContext {
    __New(snapshot := unset) {
        this.Snapshot := IsSet(snapshot) ? snapshot : Map("pid", 0, "exe", "", "hwnd", 0)
    }
    Capture() => this.Snapshot
}

class F06FakeWindows {
    FindVisibleByPid(*) => []
    StillMatches(*) => true
    RequestTitle(*) => AQResult.Ok("title")
}

class F06FakeProcessAdapter {
    __New() {
        this.Processes := Map()
        this.NextPid := 900
        this.GracefulFails := Map()
        this.ForceFails := Map()
        this.LaunchFails := false
        this.GracefulCalls := []
        this.ForceCalls := []
        this.LaunchCalls := []
    }

    Add(pid, exe := "tracker.exe", path := "C:\Tools\tracker.exe") {
        this.Processes[pid] := Map("pid", pid, "exists", true, "exe", exe, "path", path)
    }

    Exists(pid) => this.Processes.Has(pid) && this.Processes[pid]["exists"]

    Describe(pid) {
        if !this.Exists(pid)
            return Map("pid", pid, "exists", false, "exe", "", "path", "")
        source := this.Processes[pid]
        return Map("pid", pid, "exists", true, "exe", source["exe"], "path", source["path"])
    }

    Launch(program, args := unset, workingDir := "") {
        this.LaunchCalls.Push(Map("program", program, "args", IsSet(args) ? args : [], "working_dir", workingDir))
        if this.LaunchFails
            return AQResult.Failed("synthetic launch failure")
        this.NextPid += 1
        pid := this.NextPid
        this.Add(pid, F06BaseName(program), program)
        return AQResult.Ok("launched", Map("pid", pid))
    }

    GracefulClose(pid, timeoutMs := 0) {
        this.GracefulCalls.Push(pid)
        if this.GracefulFails.Has(pid) && this.GracefulFails[pid]
            return AQResult.Failed("synthetic graceful failure")
        if this.Processes.Has(pid)
            this.Processes[pid]["exists"] := false
        return AQResult.Ok("graceful")
    }

    ForceClose(pid, timeoutMs := 0) {
        this.ForceCalls.Push(pid)
        if this.ForceFails.Has(pid) && this.ForceFails[pid]
            return AQResult.Failed("synthetic force failure")
        if this.Processes.Has(pid)
            this.Processes[pid]["exists"] := false
        return AQResult.Ok("force")
    }
}

class F06TestApp {
    __New() {
        this.Log := F06TestLog()
        this.Actions := AQActionRegistry(this.Log)
        this.Windows := F06FakeWindows()
        this.Context := F06FakeContext()
    }
}

F06Preset(id := "audit", allowForce := false, workerExcludes := unset) {
    excludes := IsSet(workerExcludes) ? workerExcludes : ["worker.exe"]
    return Map(
        "id", id,
        "program", "C:\Tools\tracker.exe",
        "args", ["--audit", "repo path"],
        "working_dir", "C:\Work",
        "allow_force", allowForce,
        "graceful_timeout_ms", 100,
        "force_timeout_ms", 100,
        "worker_exclude_exes", excludes,
        "expected_exe", "tracker.exe",
        "expected_path", "",
        "identity", "Audit tracker",
        "title", "Audit tracker",
        "restore_title", false,
        "window_wait_ms", 0
    )
}

F06Presets(preset := unset) {
    chosen := IsSet(preset) ? preset : F06Preset()
    return Map(chosen["id"], chosen)
}

TestF06NoRunningLaunchesTracker() {
    app := F06TestApp()
    adapter := F06FakeProcessAdapter()
    service := F06TrackerService(app, F06Presets(), F06TrackerRegistry(), adapter)
    result := service.Restart("audit")
    AssertF06True(result.IsOk(), result.Message)
    AssertF06Equal(0, result.Data["old_pid"])
    AssertF06True(result.Data["new_pid"] > 0)
    AssertF06Equal("none", result.Data["termination_mode"])
}

TestF06OneTrackerGracefulRestart() {
    app := F06TestApp()
    adapter := F06FakeProcessAdapter()
    adapter.Add(401)
    registry := F06TrackerRegistry()
    registry.Register("audit", 401, Map("exe", "tracker.exe", "path", "C:\Tools\tracker.exe"))
    service := F06TrackerService(app, F06Presets(), registry, adapter)
    result := service.Restart("audit")
    AssertF06True(result.IsOk(), result.Message)
    AssertF06Equal(401, result.Data["old_pid"])
    AssertF06Equal("graceful", result.Data["termination_mode"])
    AssertF06Equal(1, adapter.GracefulCalls.Length)
    AssertF06Equal(0, adapter.ForceCalls.Length)
    AssertF06True(result.Data["new_pid"] != 401)
}

TestF06StalePidBecomesFreshLaunch() {
    app := F06TestApp()
    adapter := F06FakeProcessAdapter()
    registry := F06TrackerRegistry()
    registry.Register("audit", 402, Map("exe", "tracker.exe", "path", "C:\Tools\tracker.exe"))
    service := F06TrackerService(app, F06Presets(), registry, adapter)
    result := service.Restart("audit")
    AssertF06True(result.IsOk(), result.Message)
    AssertF06Equal(402, result.Data["old_pid"])
    AssertF06Equal("stale", result.Data["termination_mode"])
    AssertF06Equal(0, adapter.GracefulCalls.Length)
}

TestF06DuplicateTrackerRejected() {
    app := F06TestApp()
    adapter := F06FakeProcessAdapter()
    adapter.Add(403)
    adapter.Add(404)
    registry := F06TrackerRegistry()
    registry.Register("audit", 403, Map("exe", "tracker.exe", "path", "C:\Tools\tracker.exe"))
    registry.Register("audit", 404, Map("exe", "tracker.exe", "path", "C:\Tools\tracker.exe"))
    service := F06TrackerService(app, F06Presets(), registry, adapter)
    result := service.Restart("audit")
    AssertF06Equal("rejected", result.Status)
    AssertF06Equal(0, adapter.GracefulCalls.Length)
    AssertF06Equal(0, adapter.ForceCalls.Length)
}

TestF06GracefulFailureDoesNotForceByDefault() {
    app := F06TestApp()
    adapter := F06FakeProcessAdapter()
    adapter.Add(405)
    adapter.GracefulFails[405] := true
    registry := F06TrackerRegistry()
    registry.Register("audit", 405, Map("exe", "tracker.exe", "path", "C:\Tools\tracker.exe"))
    service := F06TrackerService(app, F06Presets(F06Preset("audit", false)), registry, adapter)
    result := service.Restart("audit")
    AssertF06Equal("failed", result.Status)
    AssertF06Equal("graceful_failed", result.Data["termination_mode"])
    AssertF06Equal(0, adapter.ForceCalls.Length)
    AssertF06True(adapter.Exists(405))
}

TestF06ExplicitForceFallback() {
    app := F06TestApp()
    adapter := F06FakeProcessAdapter()
    adapter.Add(406)
    adapter.GracefulFails[406] := true
    registry := F06TrackerRegistry()
    registry.Register("audit", 406, Map("exe", "tracker.exe", "path", "C:\Tools\tracker.exe"))
    service := F06TrackerService(app, F06Presets(F06Preset("audit", true)), registry, adapter)
    result := service.Restart("audit")
    AssertF06True(result.IsOk(), result.Message)
    AssertF06Equal("force", result.Data["termination_mode"])
    AssertF06Equal(1, adapter.ForceCalls.Length)
    AssertF06False(adapter.Exists(406))
}

TestF06WorkerExclusionBlocksAdoptionAndTermination() {
    app := F06TestApp()
    adapter := F06FakeProcessAdapter()
    adapter.Add(407, "worker.exe", "C:\Tools\worker.exe")
    app.Context := F06FakeContext(Map("pid", 407, "exe", "worker.exe", "hwnd", 700))
    registry := F06TrackerRegistry()
    service := F06TrackerService(app, F06Presets(), registry, adapter)
    adopted := service.AdoptForeground("audit")
    AssertF06Equal("rejected", adopted.Status)

    registry.Register("audit", 407, Map("exe", "worker.exe", "path", "C:\Tools\worker.exe"))
    restarted := service.Restart("audit")
    AssertF06Equal("rejected", restarted.Status)
    AssertF06True(adapter.Exists(407))
    AssertF06Equal(0, adapter.GracefulCalls.Length)
}

TestF06ExecutableChangedBeforeTerminationRejected() {
    app := F06TestApp()
    adapter := F06FakeProcessAdapter()
    adapter.Add(408, "other.exe", "C:\Other\other.exe")
    registry := F06TrackerRegistry()
    registry.Register("audit", 408, Map("exe", "tracker.exe", "path", "C:\Tools\tracker.exe"))
    service := F06TrackerService(app, F06Presets(), registry, adapter)
    result := service.Restart("audit")
    AssertF06Equal("rejected", result.Status)
    AssertF06Equal(0, adapter.GracefulCalls.Length)
}

TestF06RelaunchFailureReportsOldPid() {
    app := F06TestApp()
    adapter := F06FakeProcessAdapter()
    adapter.Add(409)
    adapter.LaunchFails := true
    registry := F06TrackerRegistry()
    registry.Register("audit", 409, Map("exe", "tracker.exe", "path", "C:\Tools\tracker.exe"))
    service := F06TrackerService(app, F06Presets(), registry, adapter)
    result := service.Restart("audit")
    AssertF06Equal("failed", result.Status)
    AssertF06Equal(409, result.Data["old_pid"])
    AssertF06Equal(0, result.Data["new_pid"])
    AssertF06Equal("graceful", result.Data["termination_mode"])
}

TestF06ModuleLifecycle() {
    app := F06TestApp()
    app.Config := F06EmptyConfig()
    module := F06TrackerRestartModule()
    module.Init(app)
    AssertF06True(app.Actions.Has("tracker.restart"))
    AssertF06True(app.Actions.Has("tracker.adopt_foreground"))
    module.Teardown(app)
    AssertF06False(app.Actions.Has("tracker.restart"))
}

class F06EmptyConfig {
    Get(section, key, default := "") => default
    GetInt(section, key, default := 0) => default
    GetBool(section, key, default := false) => default
}

F06BaseName(path) {
    SplitPath(path, &name)
    return name
}
