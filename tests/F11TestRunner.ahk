#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\modules\F11_ObservationLedger.ahk

class F11FakeClock {
    __New(now := 1000) {
        this.Value := now
    }
    Now() {
        return this.Value
    }
    Advance(seconds) {
        this.Value += seconds
    }
}

class F11TestConfig {
    __New() {
        this.Values := Map()
        this.Path := "F11Test.ini"
    }
    Set(section, key, value) {
        this.Values[section "|" key] := value ""
    }
    Get(section, key, default := "") {
        token := section "|" key
        return this.Values.Has(token) ? this.Values[token] : default
    }
    GetInt(section, key, default := 0) {
        raw := this.Get(section, key, default "")
        return RegExMatch(raw, "^-?\d+$") ? raw + 0 : default
    }
    GetBool(section, key, default := false) {
        raw := StrLower(Trim(this.Get(section, key, default ? "1" : "0")))
        return raw = "1" || raw = "true" || raw = "yes" || raw = "on"
    }
}

class F11TestLog {
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

class F11TestApp {
    __New(config) {
        this.Config := config
        this.Log := F11TestLog()
        this.Actions := AQActionRegistry(this.Log)
        this.Capabilities := AQCapabilityRegistry()
        this.RootDir := A_Temp
        this.Calls := 0
    }
}

F11Windows() {
    return Map("chatgpt", 100, "codex", 50)
}

TestF11RollingBoundariesAndPruning() {
    clock := F11FakeClock(1000)
    ledger := F11Ledger(F11Windows(), clock)
    ledger.Observe("chatgpt", "manual", 900)
    ledger.Observe("chatgpt", "manual", 901)
    ledger.Observe("chatgpt", "manual", 999)
    E11(2, ledger.Count("chatgpt", 1000), "cutoff is exclusive")
    clock.Advance(2)
    E11(2, ledger.Count("chatgpt"))
    ledger.Prune()
    E11(2, ledger.Events.Length)
}

TestF11IndependentServicesAndReset() {
    clock := F11FakeClock(1000)
    ledger := F11Ledger(F11Windows(), clock)
    ledger.Observe("chatgpt", "manual")
    ledger.Observe("codex", "manual")
    E11(1, ledger.Count("chatgpt"))
    E11(1, ledger.Count("codex"))
    reset := ledger.Reset("chatgpt")
    A11(reset.IsOk())
    E11(0, ledger.Count("chatgpt"))
    E11(1, ledger.Count("codex"))
    E11("invalid", ledger.Reset("missing").Status)
}

TestF11SnapshotAlwaysNonAuthoritative() {
    ledger := F11Ledger(F11Windows(), F11FakeClock())
    ledger.Observe("chatgpt", "manual")
    snapshot := ledger.Snapshot()
    A11(snapshot.Length = 2)
    for item in snapshot {
        A11(!item["authoritative"])
        E11("local observed estimate", item["label"])
        A11(item["window_end"] >= item["window_start"])
    }
}

TestF11PersistenceRoundTripAndMalformedIsolation() {
    path := A_Temp "\\ahquiver-f11-" A_TickCount ".tsv"
    try {
        clock := F11FakeClock(1000)
        ledger := F11Ledger(F11Windows(), clock)
        ledger.Observe("chatgpt", "manual", 999)
        ledger.Observe("codex", "action:keybind.status", 998)
        persistence := F11Persistence(path)
        A11(persistence.Save(ledger).IsOk())
        FileAppend("not-a-valid-line`n12`tmissing`tbad`n", path)
        loaded := F11Ledger(F11Windows(), clock)
        result := persistence.LoadInto(loaded)
        A11(result.IsOk())
        E11(2, result.Data["accepted"])
        E11(2, result.Data["rejected"])
        E11(1, loaded.Count("chatgpt"))
        E11(1, loaded.Count("codex"))
    } finally {
        try FileDelete(path)
    }
}

TestF11ActionObserverCountsConfiguredSignalWithoutPayload() {
    cfg := F11TestConfig()
    cfg.Set("F11", "services", "chatgpt")
    cfg.Set("F11.service.chatgpt", "window_seconds", "100")
    cfg.Set("F11", "action_mappings", "submit")
    cfg.Set("F11.action.submit", "action", "submit.signal")
    cfg.Set("F11.action.submit", "service", "chatgpt")
    cfg.Set("F11", "persistence_path", "")
    app := F11TestApp(cfg)
    app.Actions.Register("submit.signal", (params) => AQResult.Ok("done", Map("secret", "DO-NOT-STORE")), "fixture", "S0")
    module := F11ObservationModule(F11FakeClock(1000))
    module.Init(app)
    try {
        app.Actions.Invoke("submit.signal", Map("prompt", "TOP SECRET PROMPT"))
        E11(1, module.Ledger.Count("chatgpt"))
        event := module.Ledger.Events[1]
        E11("action:submit.signal", event["source"])
        A11(!InStr(event["source"], "SECRET"))
        status := app.Actions.Invoke("observation.status")
        A11(status.IsOk())
        A11(!status.Data["authoritative"])
    } finally module.Teardown(app)
}

TestF11ManualObservationSanitisesSource() {
    ledger := F11Ledger(F11Windows(), F11FakeClock())
    ledger.Observe("chatgpt", "manual`tbad`ncontent")
    source := ledger.Events[1]["source"]
    A11(!InStr(source, "`t"))
    A11(!InStr(source, "`n"))
}

TestF11ModuleLifecycleAndCapability() {
    cfg := F11TestConfig()
    cfg.Set("F11", "services", "chatgpt")
    cfg.Set("F11.service.chatgpt", "window_seconds", "100")
    cfg.Set("F11", "action_mappings", "")
    cfg.Set("F11", "persistence_path", "")
    app := F11TestApp(cfg)
    module := F11ObservationModule(F11FakeClock())
    result := module.Init(app)
    A11(result.IsOk())
    A11(app.Actions.Has("observation.observe"))
    E11("supported", app.Capabilities.Get("observation.local_usage_estimate")["status"])
    module.Teardown(app)
    A11(!app.Actions.Has("observation.observe"))
    E11("unknown", app.Capabilities.Get("observation.local_usage_estimate")["status"])
}

passed := 0
failed := 0
tests := [
    TestF11RollingBoundariesAndPruning,
    TestF11IndependentServicesAndReset,
    TestF11SnapshotAlwaysNonAuthoritative,
    TestF11PersistenceRoundTripAndMalformedIsolation,
    TestF11ActionObserverCountsConfiguredSignalWithoutPayload,
    TestF11ManualObservationSanitisesSource,
    TestF11ModuleLifecycleAndCapability
]
for fn in tests {
    try {
        fn.Call()
        passed += 1
        FileAppend("PASS " fn.Name "`n", "*")
    } catch as testError {
        failed += 1
        FileAppend("FAIL " fn.Name ": " testError.Message "`n", "*")
    }
}
FileAppend("RESULT passed=" passed " failed=" failed "`n", "*")
ExitApp(failed ? 1 : 0)

A11(value, message := "expected true") {
    if !value
        throw Error(message)
}
E11(expected, actual, message := "") {
    if expected != actual
        throw Error((message != "" ? message ": " : "") "expected=" expected " actual=" actual)
}
