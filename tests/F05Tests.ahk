#Requires AutoHotkey v2.0

class F05FakeContext {
    __New(captures) {
        this.Captures := captures
        this.Index := 1
    }
    Capture() {
        index := Min(this.Index, this.Captures.Length)
        item := this.Captures[index]
        this.Index += 1
        return item
    }
}

class F05FakeWindows {
    __New(stillMatches := true) => this.Match := stillMatches
    StillMatches(*) => this.Match
}

class F05FakeTransport {
    __New() {
        this.Lines := []
        this.PasteCount := 0
        this.FailPaste := false
        this.FailLineAt := 0
        this.MutateClipboard := false
    }
    PasteClipboard() {
        this.PasteCount += 1
        if this.MutateClipboard
            A_Clipboard := "F05-MUTATED"
        return this.FailPaste ? AQResult.Failed("synthetic paste failure") : AQResult.Ok("paste")
    }
    SendLine(text, execute := true) {
        this.Lines.Push(Map("text", text, "execute", execute))
        if this.FailLineAt && this.Lines.Length = this.FailLineAt
            return AQResult.Failed("synthetic line failure")
        return AQResult.Ok("line")
    }
}

class F05FakeConfirmer {
    __New(answers) {
        this.Answers := answers
        this.Index := 1
    }
    Confirm(*) {
        if this.Index > this.Answers.Length
            return false
        answer := this.Answers[this.Index]
        this.Index += 1
        return answer
    }
}

class F05TestLog {
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

class F05TestApp {
    __New(configPath, context, windows) {
        this.Config := AQConfig(configPath)
        this.Context := context
        this.Windows := windows
        this.Actions := AQActionRegistry(F05TestLog())
        this.Clipboard := AQClipboardGuard()
        this.Log := F05TestLog()
    }
}

F05Target(hwnd := 100, pid := 200, terminal := "WindowsTerminal") => Map(
    "hwnd", hwnd,
    "pid", pid,
    "exe", terminal = "WindowsTerminal" ? "WindowsTerminal.exe" : "openconsole.exe",
    "class", "CASCADIA_HOSTING_WINDOW_CLASS",
    "title", "",
    "terminal", terminal,
    "timestamp", A_TickCount,
    "modifiers", Map(),
    "project_identity", ""
)

F05Config(extra := "") {
    path := F05TempPath("config")
    FileAppend("[F05]`ndefault_mode=cancel`ninter_line_delay_ms=0`nallow_unknown_terminal=0`nallow_control_chars=0`npattern_count=0`n" extra, path, "UTF-8")
    return path
}

TestF05ClassifierLineEndingsAndTrailingNewline() {
    classifier := F05Classifier()
    a := classifier.Analyze("one`r`ntwo`r`n")
    AssertF05Equal(2, a["line_count"])
    AssertF05True(a["trailing_newline"])
    b := classifier.Analyze("one`n`ntwo")
    AssertF05Equal(3, b["line_count"])
    AssertF05Equal(1, b["blank_lines"])
}

TestF05ContinuationClassification() {
    classifier := F05Classifier()
    a := classifier.Analyze("Write-Host foo `` `nbar")
    AssertF05True(a["continuation_like"])
    b := classifier.Analyze("echo hello")
    AssertF05False(b["continuation_like"])
}

TestF05LineByLinePreservesLines() {
    config := F05Config()
    try {
        target := F05Target()
        transport := F05FakeTransport()
        app := F05TestApp(config, F05FakeContext([target, target, target, target]), F05FakeWindows(true))
        service := F05MultilinePasteService(app, transport, F05FakeConfirmer([]))
        A_Clipboard := " first `n`nthird  `n"
        result := service.Deliver("line_by_line")
        AssertF05True(result.IsOk(), result.Message)
        AssertF05Equal(3, transport.Lines.Length)
        AssertF05Equal(" first ", transport.Lines[1]["text"])
        AssertF05Equal("", transport.Lines[2]["text"])
        AssertF05Equal("third  ", transport.Lines[3]["text"])
        AssertF05True(result.Data["trailing_newline"])
    } finally F05Delete(config)
}

TestF05ConfirmEachCancellation() {
    config := F05Config()
    try {
        target := F05Target()
        transport := F05FakeTransport()
        app := F05TestApp(config, F05FakeContext([target, target, target]), F05FakeWindows(true))
        service := F05MultilinePasteService(app, transport, F05FakeConfirmer([true, false]))
        A_Clipboard := "one`ntwo`nthree"
        result := service.Deliver("confirm_each")
        AssertF05Equal("cancelled", result.Status)
        AssertF05Equal(1, result.Data["sent_count"])
        AssertF05Equal(1, transport.Lines.Length)
    } finally F05Delete(config)
}

TestF05ClipboardRestoresOnFailure() {
    config := F05Config()
    try {
        target := F05Target()
        transport := F05FakeTransport()
        transport.FailPaste := true
        transport.MutateClipboard := true
        app := F05TestApp(config, F05FakeContext([target, target]), F05FakeWindows(true))
        service := F05MultilinePasteService(app, transport)
        A_Clipboard := "ORIGINAL-F05"
        result := service.Deliver("whole")
        AssertF05Equal("failed", result.Status)
        AssertF05Equal("ORIGINAL-F05", A_Clipboard)
    } finally F05Delete(config)
}

TestF05EmptyClipboardRejected() {
    config := F05Config()
    try {
        target := F05Target()
        app := F05TestApp(config, F05FakeContext([target]), F05FakeWindows(true))
        service := F05MultilinePasteService(app, F05FakeTransport())
        A_Clipboard := ""
        result := service.Deliver("whole")
        AssertF05Equal("unsupported", result.Status)
    } finally F05Delete(config)
}

TestF05StaleTargetRejected() {
    config := F05Config()
    try {
        target := F05Target()
        app := F05TestApp(config, F05FakeContext([target]), F05FakeWindows(false))
        service := F05MultilinePasteService(app, F05FakeTransport())
        A_Clipboard := "echo safe"
        result := service.Deliver("whole")
        AssertF05Equal("rejected", result.Status)
    } finally F05Delete(config)
}

TestF05ControlCharactersRejected() {
    config := F05Config()
    try {
        target := F05Target()
        app := F05TestApp(config, F05FakeContext([target]), F05FakeWindows(true))
        service := F05MultilinePasteService(app, F05FakeTransport())
        A_Clipboard := "abc" Chr(1) "def"
        result := service.Deliver("whole")
        AssertF05Equal("rejected", result.Status)
    } finally F05Delete(config)
}

TestF05InvalidPatternIsLocalConfigFailure() {
    config := F05TempPath("bad-regex-config")
    FileAppend("[F05]`npattern_count=1`npattern1=\`n", config, "UTF-8")
    try {
        target := F05Target()
        app := F05TestApp(config, F05FakeContext([target]), F05FakeWindows(true))
        AssertF05Equal("\", app.Config.Get("F05", "pattern1", ""), "fixture must preserve trailing backslash")
        threw := false
        try F05MultilinePasteService(app, F05FakeTransport())
        catch
            threw := true
        AssertF05True(threw, "invalid regex must reject F05 initialization")
    } finally F05Delete(config)
}

TestF05ModuleLifecycle() {
    config := F05Config()
    try {
        target := F05Target()
        app := F05TestApp(config, F05FakeContext([target]), F05FakeWindows(true))
        module := F05MultilinePasteModule()
        module.Init(app)
        AssertF05True(app.Actions.Has("terminal.multiline_paste_lines"))
        module.Teardown(app)
        AssertF05False(app.Actions.Has("terminal.multiline_paste_lines"))
    } finally F05Delete(config)
}
