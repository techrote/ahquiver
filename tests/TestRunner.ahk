#Requires AutoHotkey v2.0

#Include ..\src\core\Result.ahk
#Include ..\src\core\Log.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\core\Context.ahk
#Include ..\src\core\WindowQuery.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\ClipboardGuard.ahk
#Include ..\src\core\Process.ahk
#Include ..\src\core\ModuleHost.ahk

global AQ_TEST_PASSED := 0
global AQ_TEST_FAILED := 0

RunTest("result states", TestResultStates)
RunTest("configuration parsing", TestConfiguration)
RunTest("action registry", TestActionRegistry)
RunTest("capability registry", TestCapabilityRegistry)
RunTest("context contract", TestContextContract)
RunTest("window stale-target rejection", TestWindowRevalidation)
RunTest("clipboard restore on failure", TestClipboardRestore)
RunTest("process command quoting", TestProcessQuoting)
RunTest("disabled and enabled module lifecycle", TestModuleLifecycle)

FileAppend("`nRESULT passed=" AQ_TEST_PASSED " failed=" AQ_TEST_FAILED "`n", "*")
ExitApp(AQ_TEST_FAILED = 0 ? 0 : 1)

RunTest(name, callback) {
    global AQ_TEST_PASSED, AQ_TEST_FAILED
    try {
        callback.Call()
        AQ_TEST_PASSED += 1
        FileAppend("PASS " name "`n", "*")
    } catch as err {
        AQ_TEST_FAILED += 1
        FileAppend("FAIL " name ": " err.Message "`n", "*")
    }
}

AssertTrue(value, message := "Expected true") {
    if !value
        throw Error(message)
}

AssertFalse(value, message := "Expected false") {
    if value
        throw Error(message)
}

AssertEqual(expected, actual, message := "") {
    if expected != actual {
        detail := message != "" ? message ": " : ""
        throw Error(detail "expected=" expected " actual=" actual)
    }
}

TestResultStates() {
    ok := AQResult.Ok("done")
    AssertTrue(ok.IsOk())
    AssertEqual("ok", ok.Status)
    AssertEqual("cancelled", AQResult.Cancelled().Status)
    AssertEqual("unsupported", AQResult.Unsupported().Status)
    AssertEqual("invalid", AQResult.Invalid().Status)
    AssertEqual("rejected", AQResult.Rejected().Status)
    AssertEqual("failed", AQResult.Failed().Status)
}

TestConfiguration() {
    path := TestTempPath("config")
    try {
        FileAppend("[core]`nenabled=yes`nretries=3`nbad_int=nope`n", path, "UTF-8")
        config := AQConfig(path)
        AssertTrue(config.Exists())
        AssertTrue(config.GetBool("core", "enabled", false))
        AssertEqual(3, config.GetInt("core", "retries", 0))
        AssertEqual(7, config.GetInt("core", "bad_int", 7))
        AssertEqual("fallback", config.Get("missing", "key", "fallback"))
        AssertTrue(config.Reload().IsOk())
    } finally {
        TestDelete(path)
    }
}

TestActionRegistry() {
    registry := AQActionRegistry()
    registry.Register("test.echo", TestEchoAction, "Synthetic echo", "S0")
    AssertTrue(registry.Has("test.echo"))
    AssertEqual(1, registry.Count())

    result := registry.Invoke("test.echo", Map("value", 42))
    AssertTrue(result.IsOk())
    AssertEqual(42, result.Data["value"])
    AssertEqual("invalid", registry.Invoke("missing.action").Status)

    registry.Register("test.throw", TestThrowAction)
    failed := registry.Invoke("test.throw")
    AssertEqual("failed", failed.Status)
}

TestEchoAction(params) {
    return AQResult.Ok("echo", Map("value", params["value"]))
}

TestThrowAction(params) {
    throw Error("synthetic action failure")
}

TestCapabilityRegistry() {
    capabilities := AQCapabilityRegistry()
    capabilities.Set("terminal.background", "unsupported", "probe says no")
    info := capabilities.Get("terminal.background")
    AssertEqual("unsupported", info["status"])
    AssertEqual(1, capabilities.Count())
    AssertEqual("unknown", capabilities.Get("missing")["status"])

    threw := false
    try capabilities.Set("bad", "optimistic")
    catch
        threw := true
    AssertTrue(threw, "Invalid capability state must throw")
}

TestContextContract() {
    context := AQContextService()
    AssertEqual("WindowsTerminal", context.ClassifyTerminal("WindowsTerminal.exe"))
    AssertEqual("conhost", context.ClassifyTerminal("conhost.exe"))
    AssertEqual("unknown", context.ClassifyTerminal("notepad.exe"))

    snapshot := context.Capture()
    for key in ["hwnd", "pid", "exe", "path", "class", "title", "terminal", "modifiers", "project_identity", "timestamp"]
        AssertTrue(snapshot.Has(key), "Missing context key: " key)
}

TestWindowRevalidation() {
    windows := AQWindowQuery()
    AssertFalse(windows.StillMatches(Map("hwnd", 0)), "HWND zero must be rejected")
}

class FakeClipboardBackend {
    __New() {
        this.Value := "before"
        this.RestoreCount := 0
    }

    Save() {
        return this.Value
    }

    Restore(snapshot) {
        this.Value := snapshot
        this.RestoreCount += 1
    }
}

TestClipboardRestore() {
    backend := FakeClipboardBackend()
    guard := AQClipboardGuard(backend)
    threw := false
    try guard.Run(ClipboardMutation.Bind(backend))
    catch
        threw := true

    AssertTrue(threw, "Synthetic callback should throw")
    AssertEqual("before", backend.Value, "Clipboard snapshot was not restored")
    AssertEqual(1, backend.RestoreCount, "Restore should run exactly once")
}

ClipboardMutation(backend) {
    backend.Value := "changed"
    throw Error("expected clipboard failure")
}

TestProcessQuoting() {
    q := Chr(34)
    AssertEqual("simple", AQProcess.QuoteArg("simple"))
    AssertEqual(q "two words" q, AQProcess.QuoteArg("two words"))
    command := AQProcess.BuildCommand("C:\Program Files\Tool\tool.exe", ["one", "two words"])
    AssertTrue(InStr(command, q "C:\Program Files\Tool\tool.exe" q) = 1)
}

class SyntheticTestModule {
    __New() {
        this.Id := "test.synthetic"
        this.Name := "Synthetic test module"
        this.InitCount := 0
        this.TeardownCount := 0
    }

    Init(app) {
        this.InitCount += 1
        app.Actions.Register("test.synthetic.echo", TestEchoAction, "Synthetic module action", "S0")
    }

    Teardown(app) {
        this.TeardownCount += 1
        app.Actions.Unregister("test.synthetic.echo")
    }
}

class SyntheticTestApp {
    __New(configPath) {
        this.Config := AQConfig(configPath)
        this.Log := AQLog(TestTempPath("unused-log"), false)
        this.Actions := AQActionRegistry(this.Log)
    }
}

TestModuleLifecycle() {
    path := TestTempPath("modules")
    try {
        FileAppend("[modules]`ntest.synthetic=0`n", path, "UTF-8")
        app := SyntheticTestApp(path)
        module := SyntheticTestModule()
        host := AQModuleHost(app)
        host.Register(module)

        host.StartConfigured()
        AssertEqual("disabled", host.State(module.Id))
        AssertEqual(0, module.InitCount)
        AssertFalse(app.Actions.Has("test.synthetic.echo"))

        IniWrite("1", path, "modules", "test.synthetic")
        host.Reload()
        AssertEqual("enabled", host.State(module.Id))
        AssertEqual(1, module.InitCount)
        AssertTrue(app.Actions.Has("test.synthetic.echo"))

        host.StopAll()
        AssertEqual(1, module.TeardownCount)
        AssertFalse(app.Actions.Has("test.synthetic.echo"))
    } finally {
        TestDelete(path)
    }
}

TestTempPath(label) {
    return A_Temp "\ahquiver-" label "-" A_TickCount "-" Random(1000, 9999) ".tmp"
}

TestDelete(path) {
    if FileExist(path) {
        try FileDelete(path)
    }
}
