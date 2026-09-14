#Requires AutoHotkey v2.0

class F07FakeActions {
    __New() {
        this.Items := Map()
        this.Observers := Map()
        this.NextObserver := 1
        this.Invocations := []
    }

    Add(id, result := unset, description := "", risk := "S0") {
        this.Items[id] := Map(
            "id", id,
            "description", description,
            "safety_class", risk,
            "result", IsSet(result) ? result : AQResult.Ok("ok")
        )
    }

    Remove(id) {
        if this.Items.Has(id)
            this.Items.Delete(id)
    }

    List() {
        items := []
        for id, item in this.Items
            items.Push(Map("id", id, "description", item["description"], "safety_class", item["safety_class"]))
        return items
    }

    Describe(id) {
        if !this.Items.Has(id)
            return Map()
        item := this.Items[id]
        return Map("id", id, "description", item["description"], "safety_class", item["safety_class"])
    }

    Invoke(id, params := unset) {
        payload := IsSet(params) ? params : Map()
        this.Invocations.Push(Map("id", id, "params", payload))
        result := this.Items.Has(id) ? this.Items[id]["result"] : AQResult.Invalid("unknown")
        for _, observer in this.Observers
            observer.Call(id, result)
        return result
    }

    Subscribe(observer) {
        token := this.NextObserver
        this.NextObserver += 1
        this.Observers[token] := observer
        return token
    }

    Unsubscribe(token) {
        if !this.Observers.Has(token)
            return false
        this.Observers.Delete(token)
        return true
    }
}

class F07FakeModules {
    __New(items := unset) => this.Items := IsSet(items) ? items : []
    List() => this.Items
}

class F07FakeCapabilities {
    __New(items := unset) => this.Items := IsSet(items) ? items : []
    List() => this.Items
}

class F07FakeApp {
    __New() {
        this.Actions := F07FakeActions()
        this.Modules := F07FakeModules()
        this.Capabilities := F07FakeCapabilities()
    }
}

class F07ModuleTestLog {
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

class F07FakeUi {
    __New() {
        this.Enabled := false
        this.ShowCalls := 0
        this.RefreshCalls := 0
        this.ReloadCalls := 0
        this.DisableCalls := 0
    }
    EnableControlSurface() {
        this.Enabled := true
        return AQResult.Ok("enabled")
    }
    DisableControlSurface() {
        this.Enabled := false
        this.DisableCalls += 1
        return AQResult.Ok("disabled")
    }
    ShowControl(*) {
        this.ShowCalls += 1
        return AQResult.Ok("shown")
    }
    Refresh(*) {
        this.RefreshCalls += 1
        return AQResult.Ok("refreshed")
    }
    ReloadConfiguration(*) {
        this.ReloadCalls += 1
        return AQResult.Ok("reloaded")
    }
    EmergencyDisable(*) {
        return AQResult.Ok("emergency")
    }
}

class F07ModuleApp {
    __New() {
        this.Actions := AQActionRegistry(F07ModuleTestLog())
        this.Ui := F07FakeUi()
    }
}

TestF07DynamicActionPopulation() {
    app := F07FakeApp()
    app.Actions.Add("alpha.action", AQResult.Ok("alpha"))
    model := AQControlSurfaceModel(app, 5)
    try {
        first := model.Snapshot()
        AssertF07Equal(1, first["actions"].Length)
        app.Actions.Add("beta.action", AQResult.Ok("beta"))
        second := model.Snapshot()
        AssertF07Equal(2, second["actions"].Length)
        AssertF07True(F07ContainsId(second["actions"], "beta.action"), "late-added action must appear without UI wiring")
        app.Actions.Remove("alpha.action")
        third := model.Snapshot()
        AssertF07Equal(1, third["actions"].Length)
        AssertF07False(F07ContainsId(third["actions"], "alpha.action"))
    } finally model.Close()
}

TestF07DispatchUsesRegistryActionIdAndGenericParams() {
    app := F07FakeApp()
    app.Actions.Add("tracker.restart", AQResult.Ok("done"), "restart", "S2")
    model := AQControlSurfaceModel(app, 5)
    try {
        result := model.Invoke("tracker.restart", "preset=audit`nmode=gentle")
        AssertF07True(result.IsOk())
        AssertF07Equal(1, app.Actions.Invocations.Length)
        invocation := app.Actions.Invocations[1]
        AssertF07Equal("tracker.restart", invocation["id"])
        AssertF07Equal("audit", invocation["params"]["preset"])
        AssertF07Equal("gentle", invocation["params"]["mode"])
    } finally model.Close()
}

TestF07ParameterErrorsDoNotDispatch() {
    app := F07FakeApp()
    app.Actions.Add("alpha.action")
    model := AQControlSurfaceModel(app, 5)
    try {
        result := model.Invoke("alpha.action", "missing-separator")
        AssertF07Equal("invalid", result.Status)
        AssertF07Equal(0, app.Actions.Invocations.Length)
        duplicate := model.Invoke("alpha.action", "x=1`nx=2")
        AssertF07Equal("invalid", duplicate.Status)
        AssertF07Equal(0, app.Actions.Invocations.Length)
    } finally model.Close()
}

TestF07ModuleAndCapabilityStatesRepresented() {
    app := F07FakeApp()
    app.Modules := F07FakeModules([
        Map("id", "F01", "state", "enabled"),
        Map("id", "F06", "state", "disabled"),
        Map("id", "F09", "state", "failed")
    ])
    app.Capabilities := F07FakeCapabilities([
        Map("id", "terminal.windowsterminal.can_background_paste", "status", "unknown", "detail", "no readback"),
        Map("id", "terminal.standard_edit.can_background_paste", "status", "supported", "detail", "verified"),
        Map("id", "hardware.serial", "status", "degraded", "detail", "bridge unavailable")
    ])
    model := AQControlSurfaceModel(app, 5)
    try {
        snapshot := model.Snapshot()
        AssertF07True(F07ContainsState(snapshot["modules"], "F06", "disabled"))
        AssertF07True(F07ContainsState(snapshot["modules"], "F09", "failed"))
        AssertF07True(F07ContainsState(snapshot["capabilities"], "hardware.serial", "degraded"))
        AssertF07True(F07ContainsState(snapshot["capabilities"], "terminal.windowsterminal.can_background_paste", "unknown"))
    } finally model.Close()
}

TestF07FailureHistoryIsPayloadFreeAndGlobal() {
    app := F07FakeApp()
    secret := "SECRET-COMMAND-PAYLOAD"
    app.Actions.Add("terminal.multiline_paste", AQResult.Failed("failure contained " secret, Map("payload", secret)))
    model := AQControlSurfaceModel(app, 5)
    try {
        app.Actions.Invoke("terminal.multiline_paste", Map("text", secret))
        failures := model.RecentFailures()
        AssertF07Equal(1, failures.Length)
        AssertF07Equal("terminal.multiline_paste", failures[1]["action"])
        AssertF07Equal("failed", failures[1]["status"])
        AssertF07False(InStr(failures[1]["summary"], secret) > 0, "safe history must not echo result payload/message")
        AssertF07False(failures[1].Has("params"), "safe history must not store action params")
        AssertF07False(failures[1].Has("data"), "safe history must not store result data")
    } finally model.Close()
}

TestF07CancelledActionNotRecordedAsFailure() {
    app := F07FakeApp()
    app.Actions.Add("safe.cancel", AQResult.Cancelled("user cancelled"))
    model := AQControlSurfaceModel(app, 5)
    try {
        app.Actions.Invoke("safe.cancel")
        AssertF07Equal(0, model.RecentFailures().Length)
    } finally model.Close()
}

TestF07FailureHistoryLimit() {
    app := F07FakeApp()
    app.Actions.Add("fail.one", AQResult.Failed("one"))
    app.Actions.Add("fail.two", AQResult.Rejected("two"))
    app.Actions.Add("fail.three", AQResult.Invalid("three"))
    model := AQControlSurfaceModel(app, 2)
    try {
        app.Actions.Invoke("fail.one")
        app.Actions.Invoke("fail.two")
        app.Actions.Invoke("fail.three")
        failures := model.RecentFailures()
        AssertF07Equal(2, failures.Length)
        AssertF07Equal("fail.three", failures[1]["action"])
        AssertF07Equal("fail.two", failures[2]["action"])
    } finally model.Close()
}

TestF07ModuleLifecycleAndSameRegistryPath() {
    app := F07ModuleApp()
    module := F07ControlSurfaceModule()
    module.Init(app)
    AssertF07True(app.Ui.Enabled)
    AssertF07True(app.Actions.Has("control.show"))
    result := app.Actions.Invoke("control.show")
    AssertF07True(result.IsOk())
    AssertF07Equal(1, app.Ui.ShowCalls)
    module.Teardown(app)
    AssertF07False(app.Ui.Enabled)
    AssertF07False(app.Actions.Has("control.show"))
}

TestF07CoreRegistryLists() {
    caps := AQCapabilityRegistry()
    caps.Set("z.cap", "degraded", "z")
    caps.Set("a.cap", "unsupported", "a")
    listedCaps := caps.List()
    AssertF07Equal("a.cap", listedCaps[1]["id"])
    AssertF07Equal("unsupported", listedCaps[1]["status"])

    fakeHostApp := Map()
    host := AQModuleHost(fakeHostApp)
    host.Register(F07ListModule("F09"))
    host.Register(F07ListModule("F01"))
    host.States["F09"] := "failed"
    host.States["F01"] := "disabled"
    listedModules := host.List()
    AssertF07Equal("F01", listedModules[1]["id"])
    AssertF07Equal("disabled", listedModules[1]["state"])
    AssertF07Equal("F09", listedModules[2]["id"])
    AssertF07Equal("failed", listedModules[2]["state"])
}

class F07ListModule {
    __New(id) => this.Id := id
}

F07ContainsId(items, id) {
    for item in items {
        if item["id"] = id
            return true
    }
    return false
}

F07ContainsState(items, id, state) {
    for item in items {
        if item["id"] != id
            continue
        if item.Has("state") && item["state"] = state
            return true
        if item.Has("status") && item["status"] = state
            return true
    }
    return false
}
