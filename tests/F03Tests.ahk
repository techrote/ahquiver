#Requires AutoHotkey v2.0

F03Context(hwnd, pid, exe, className, terminalKind, title := "") {
    return Map(
        "hwnd", hwnd,
        "pid", pid,
        "exe", exe,
        "path", "C:\\synthetic\\" exe,
        "class", className,
        "title", title,
        "terminal", terminalKind,
        "modifiers", Map("ctrl", true, "alt", false, "shift", false, "win", false),
        "project_identity", "",
        "timestamp", 1
    )
}

class FakeF03ContextService {
    __New(contexts := unset) {
        this.Items := IsSet(contexts) ? contexts : []
        this.Index := 1
    }

    Capture() {
        if this.Items.Length = 0
            return F03Context(0, 0, "", "", "unknown")
        if this.Index > this.Items.Length
            return this.Items[this.Items.Length]
        item := this.Items[this.Index]
        this.Index += 1
        return item
    }
}

class FakeF03Sender {
    __New() {
        this.Sent := []
        this.Fail := false
    }

    Send(chord) {
        this.Sent.Push(chord)
        if this.Fail
            return AQResult.Failed("synthetic send failure")
        return AQResult.Ok("synthetic send", Map("chord", chord))
    }
}

class FakeF03Clock {
    __New(value := 1000) {
        this.Value := value
    }

    Now() {
        return this.Value
    }

    Advance(ms) {
        this.Value += ms
    }
}

class FakeF03HoldProbe {
    __New(held := false) {
        this.Held := held
        this.Calls := 0
    }

    HeldFor(keyName, thresholdMs) {
        this.Calls += 1
        return this.Held
    }
}

class FakeF03Confirmer {
    __New(answer := false) {
        this.Answer := answer
        this.Calls := 0
    }

    Confirm(rule, context) {
        this.Calls += 1
        return this.Answer
    }
}

class FakeF03SelectionProbe {
    __New(selected := false) {
        this.Selected := selected
        this.Calls := 0
    }

    HasSelection(context) {
        this.Calls += 1
        return this.Selected
    }
}

class FakeF03Feedback {
    __New() {
        this.Messages := []
    }

    Emit(message) {
        this.Messages.Push(message)
    }
}

class SyntheticF03App {
    __New(configPath, contexts := unset) {
        this.RootDir := A_Temp
        this.Config := AQConfig(configPath)
        this.Log := AQLog(F03TempPath("log"), false)
        this.Capabilities := AQCapabilityRegistry()
        this.Context := FakeF03ContextService(IsSet(contexts) ? contexts : [])
        this.Actions := AQActionRegistry(this.Log)
        this.Identities := AQIdentityRegistry()
    }
}

F03WriteBaseConfig(path, policy := "double_tap", terminalKind := "WindowsTerminal") {
    IniWrite("wt", path, "F03", "rules")
    IniWrite("", path, "F03", "hotkey")
    IniWrite("", path, "F03", "bypass_hotkey")
    IniWrite("", path, "F03", "toggle_hotkey")
    IniWrite("none", path, "F03", "feedback")
    IniWrite("0", path, "F03", "log_decisions")
    IniWrite(terminalKind, path, "F03.rule.wt", "terminal")
    IniWrite(policy, path, "F03.rule.wt", "policy")
    IniWrite("450", path, "F03.rule.wt", "double_tap_ms")
    IniWrite("450", path, "F03.rule.wt", "hold_ms")
    IniWrite("1", path, "F03.rule.wt", "selection_copy_passthrough")
}

F03BuildService(path, contexts, sender := unset, clock := unset, holdProbe := unset, confirmer := unset, selectionProbe := unset, feedback := unset) {
    app := SyntheticF03App(path, contexts)
    store := F03RuleStore(app.Config)
    service := F03GuardService(
        app,
        store,
        IsSet(sender) ? sender : FakeF03Sender(),
        IsSet(clock) ? clock : FakeF03Clock(),
        IsSet(holdProbe) ? holdProbe : FakeF03HoldProbe(),
        IsSet(confirmer) ? confirmer : FakeF03Confirmer(),
        IsSet(selectionProbe) ? selectionProbe : FakeF03SelectionProbe(),
        IsSet(feedback) ? feedback : FakeF03Feedback()
    )
    return Map("app", app, "store", store, "service", service)
}

TestF03ConfigAndRuleMatching() {
    path := F03TempPath("config")
    try {
        F03WriteBaseConfig(path, "double_tap")
        IniWrite("implementer", path, "F03.rule.wt", "role")
        app := SyntheticF03App(path)
        app.Identities.Register("terminal", "Project Alpha", "implementer", 42)
        store := F03RuleStore(app.Config)
        AssertF03True(store.ValidateAll().IsOk())
        context := F03Context(100, 42, "WindowsTerminal.exe", "CASCADIA_HOSTING_WINDOW_CLASS", "WindowsTerminal")
        identity := app.Identities.FindActiveByPid(42)
        matched := store.Match(context, identity)
        AssertF03Equal("wt", matched["id"])
        AssertF03Equal("double_tap", matched["policy"])

        IniWrite("nonsense", path, "F03.rule.wt", "policy")
        invalidStore := F03RuleStore(AQConfig(path))
        AssertF03Equal("invalid", invalidStore.ValidateAll().Status)
    } finally {
        F03Delete(path)
    }
}

TestF03NonTerminalPassThrough() {
    path := F03TempPath("nonterminal")
    try {
        F03WriteBaseConfig(path, "double_tap")
        sender := FakeF03Sender()
        context := F03Context(1, 10, "notepad.exe", "Notepad", "unknown")
        built := F03BuildService(path, [context], sender)
        result := built["service"].Handle("^c")
        AssertF03True(result.IsOk())
        AssertF03Equal(1, sender.Sent.Length)
        AssertF03Equal("^c", sender.Sent[1])
    } finally {
        F03Delete(path)
    }
}

TestF03PassThroughPolicy() {
    path := F03TempPath("pass")
    try {
        F03WriteBaseConfig(path, "pass_through")
        sender := FakeF03Sender()
        context := F03Context(10, 20, "WindowsTerminal.exe", "WT", "WindowsTerminal")
        built := F03BuildService(path, [context, context], sender)
        result := built["service"].Handle("^c")
        AssertF03True(result.IsOk())
        AssertF03Equal("^c", sender.Sent[1])
    } finally {
        F03Delete(path)
    }
}

TestF03DoubleTapBoundary() {
    path := F03TempPath("double")
    try {
        F03WriteBaseConfig(path, "double_tap")
        sender := FakeF03Sender()
        clock := FakeF03Clock(1000)
        context := F03Context(11, 21, "WindowsTerminal.exe", "WT", "WindowsTerminal")
        built := F03BuildService(path, [context, context, context], sender, clock)
        first := built["service"].Handle("^c")
        AssertF03Equal("cancelled", first.Status)
        AssertF03Equal(0, sender.Sent.Length)
        clock.Advance(450)
        second := built["service"].Handle("^c")
        AssertF03True(second.IsOk())
        AssertF03Equal(1, sender.Sent.Length)

        sender2 := FakeF03Sender()
        clock2 := FakeF03Clock(2000)
        built2 := F03BuildService(path, [context, context], sender2, clock2)
        built2["service"].Handle("^c")
        clock2.Advance(451)
        expired := built2["service"].Handle("^c")
        AssertF03Equal("cancelled", expired.Status)
        AssertF03Equal(0, sender2.Sent.Length)
    } finally {
        F03Delete(path)
    }
}

TestF03HoldPolicy() {
    path := F03TempPath("hold")
    try {
        F03WriteBaseConfig(path, "hold")
        context := F03Context(12, 22, "WindowsTerminal.exe", "WT", "WindowsTerminal")
        sender := FakeF03Sender()
        shortProbe := FakeF03HoldProbe(false)
        built := F03BuildService(path, [context], sender, unset, shortProbe)
        blocked := built["service"].Handle("^c", "c")
        AssertF03Equal("cancelled", blocked.Status)
        AssertF03Equal(0, sender.Sent.Length)

        sender2 := FakeF03Sender()
        heldProbe := FakeF03HoldProbe(true)
        built2 := F03BuildService(path, [context, context], sender2, unset, heldProbe)
        allowed := built2["service"].Handle("^c", "c")
        AssertF03True(allowed.IsOk())
        AssertF03Equal(1, sender2.Sent.Length)
    } finally {
        F03Delete(path)
    }
}

TestF03ConfirmPolicy() {
    path := F03TempPath("confirm")
    try {
        F03WriteBaseConfig(path, "confirm")
        context := F03Context(13, 23, "WindowsTerminal.exe", "WT", "WindowsTerminal")
        sender := FakeF03Sender()
        no := FakeF03Confirmer(false)
        built := F03BuildService(path, [context], sender, unset, unset, no)
        cancelled := built["service"].Handle("^c")
        AssertF03Equal("cancelled", cancelled.Status)
        AssertF03Equal(0, sender.Sent.Length)

        sender2 := FakeF03Sender()
        yes := FakeF03Confirmer(true)
        built2 := F03BuildService(path, [context, context], sender2, unset, unset, yes)
        allowed := built2["service"].Handle("^c")
        AssertF03True(allowed.IsOk())
        AssertF03Equal("^c", sender2.Sent[1])
    } finally {
        F03Delete(path)
    }
}

TestF03RemapPolicy() {
    path := F03TempPath("remap")
    try {
        F03WriteBaseConfig(path, "remap")
        IniWrite("^+c", path, "F03.rule.wt", "remap_chord")
        context := F03Context(14, 24, "WindowsTerminal.exe", "WT", "WindowsTerminal")
        sender := FakeF03Sender()
        built := F03BuildService(path, [context, context], sender)
        result := built["service"].Handle("^c")
        AssertF03True(result.IsOk())
        AssertF03Equal("^+c", sender.Sent[1])
    } finally {
        F03Delete(path)
    }
}

TestF03BypassAndInstantDisable() {
    path := F03TempPath("bypass")
    try {
        F03WriteBaseConfig(path, "double_tap")
        context := F03Context(15, 25, "WindowsTerminal.exe", "WT", "WindowsTerminal")
        sender := FakeF03Sender()
        built := F03BuildService(path, [context, context, context], sender)
        built["service"].ArmBypassOnce()
        bypassed := built["service"].Handle("^c")
        AssertF03True(bypassed.IsOk())
        AssertF03Equal(1, sender.Sent.Length)
        nextPress := built["service"].Handle("^c")
        AssertF03Equal("cancelled", nextPress.Status)

        sender2 := FakeF03Sender()
        built2 := F03BuildService(path, [], sender2)
        built2["service"].SetEnabled(false)
        disabled := built2["service"].Handle("^c")
        AssertF03True(disabled.IsOk())
        AssertF03Equal("^c", sender2.Sent[1])
    } finally {
        F03Delete(path)
    }
}

TestF03SelectionCapabilityGate() {
    path := F03TempPath("selection")
    try {
        F03WriteBaseConfig(path, "double_tap")
        context := F03Context(16, 26, "WindowsTerminal.exe", "WT", "WindowsTerminal")
        sender := FakeF03Sender()
        selection := FakeF03SelectionProbe(true)
        built := F03BuildService(path, [context, context], sender, unset, unset, unset, selection)
        built["app"].Capabilities.Set("terminal.windowsterminal.can_detect_selection", "supported", "synthetic evidence")
        result := built["service"].Handle("^c")
        AssertF03True(result.IsOk())
        AssertF03Equal(1, selection.Calls)
        AssertF03Equal(1, sender.Sent.Length)

        sender2 := FakeF03Sender()
        selection2 := FakeF03SelectionProbe(true)
        built2 := F03BuildService(path, [context], sender2, unset, unset, unset, selection2)
        blocked := built2["service"].Handle("^c")
        AssertF03Equal("cancelled", blocked.Status)
        AssertF03Equal(0, selection2.Calls, "Selection must not be queried without supported capability evidence")
        AssertF03Equal(0, sender2.Sent.Length)
    } finally {
        F03Delete(path)
    }
}

TestF03StaleForegroundRejected() {
    path := F03TempPath("stale")
    try {
        F03WriteBaseConfig(path, "pass_through")
        first := F03Context(17, 27, "WindowsTerminal.exe", "WT", "WindowsTerminal")
        changed := F03Context(18, 28, "WindowsTerminal.exe", "WT", "WindowsTerminal")
        sender := FakeF03Sender()
        built := F03BuildService(path, [first, changed], sender)
        result := built["service"].Handle("^c")
        AssertF03Equal("rejected", result.Status)
        AssertF03Equal(0, sender.Sent.Length)
    } finally {
        F03Delete(path)
    }
}

TestF03ModuleLifecycle() {
    path := F03TempPath("module")
    try {
        F03WriteBaseConfig(path, "double_tap")
        IniWrite("0", path, "modules", "F03")
        app := SyntheticF03App(path)
        module := F03TerminalKeyGuardModule()
        host := AQModuleHost(app)
        host.Register(module)
        host.StartConfigured()
        AssertF03Equal("disabled", host.State("F03"))
        AssertF03False(app.Actions.Has("terminal.guard_status"))

        IniWrite("1", path, "modules", "F03")
        host.Reload()
        AssertF03Equal("enabled", host.State("F03"))
        AssertF03True(app.Actions.Has("terminal.guard_status"))
        disabled := app.Actions.Invoke("terminal.guard_disable")
        AssertF03True(disabled.IsOk())
        AssertF03False(disabled.Data["enabled"])
        enabled := app.Actions.Invoke("terminal.guard_enable")
        AssertF03True(enabled.IsOk())
        AssertF03True(enabled.Data["enabled"])

        host.StopAll()
        AssertF03False(app.Actions.Has("terminal.guard_status"))
    } finally {
        F03Delete(path)
    }
}
