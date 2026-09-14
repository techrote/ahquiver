#Requires AutoHotkey v2.0

class F05SystemTransport {
    PasteClipboard() {
        try SendEvent("^v")
        catch as err
            return AQResult.Failed("Paste send failed: " err.Message)
        return AQResult.Ok("Clipboard paste chord sent")
    }

    SendLine(text, execute := true) {
        try {
            SendText(text)
            if execute
                SendEvent("{Enter}")
        } catch as err {
            return AQResult.Failed("Line delivery failed: " err.Message)
        }
        return AQResult.Ok("Line delivered")
    }
}

class F05Confirmer {
    Confirm(lineNumber, totalLines, metadata := unset) {
        choice := MsgBox(
            "Send line " lineNumber " of " totalLines "?`n`nThe command text is intentionally not repeated here.",
            "AHQuiver multiline paste",
            "YesNo Icon?"
        )
        return choice = "Yes"
    }
}

class F05Classifier {
    Analyze(text, patterns := unset) {
        normalized := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
        trailingNewline := SubStr(normalized, -1) = "`n"
        lines := StrSplit(normalized, "`n")
        if trailingNewline && lines.Length && lines[lines.Length] = ""
            lines.Pop()
        if !lines.Length
            lines.Push("")

        blankLines := 0
        continuationLike := false
        for line in lines {
            if line = ""
                blankLines += 1
            trimmedRight := RTrim(line, " `t")
            if RegExMatch(trimmedRight, "(?:\\|\^|\||``)$")
                continuationLike := true
        }

        matchedPatterns := []
        if IsSet(patterns) {
            for pattern in patterns {
                if RegExMatch(text, pattern)
                    matchedPatterns.Push(pattern)
            }
        }

        return Map(
            "line_count", lines.Length,
            "lines", lines,
            "trailing_newline", trailingNewline,
            "blank_lines", blankLines,
            "has_control_chars", RegExMatch(text, "[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]") ? true : false,
            "continuation_like", continuationLike,
            "configured_pattern_matches", matchedPatterns.Length
        )
    }
}

class F05MultilinePasteService {
    static Modes := Map(
        "whole", true,
        "line_by_line", true,
        "confirm_each", true,
        "cancel", true
    )

    __New(app, transport := unset, confirmer := unset, classifier := unset) {
        this.App := app
        this.Transport := IsSet(transport) ? transport : F05SystemTransport()
        this.Confirmer := IsSet(confirmer) ? confirmer : F05Confirmer()
        this.Classifier := IsSet(classifier) ? classifier : F05Classifier()
        this.Patterns := this._LoadPatterns()
    }

    Inspect(params := unset) {
        return this.App.Clipboard.Run(this._InspectGuarded.Bind(this))
    }

    Deliver(mode := "", params := unset) {
        selectedMode := mode != "" ? StrLower(Trim(mode)) : StrLower(Trim(this.App.Config.Get("F05", "default_mode", "cancel")))
        if !F05MultilinePasteService.Modes.Has(selectedMode)
            return AQResult.Invalid("Unknown F05 delivery mode: " selectedMode)
        return this.App.Clipboard.Run(this._DeliverGuarded.Bind(this, selectedMode))
    }

    _InspectGuarded() {
        text := A_Clipboard
        if text = ""
            return AQResult.Unsupported("Clipboard contains no text")
        analysis := this.Classifier.Analyze(text, this.Patterns)
        return AQResult.Ok("Clipboard block inspected", this._PublicMetadata("inspect", analysis))
    }

    _DeliverGuarded(mode) {
        text := A_Clipboard
        if text = ""
            return AQResult.Unsupported("Clipboard contains no text")

        analysis := this.Classifier.Analyze(text, this.Patterns)
        if analysis["has_control_chars"] && !this.App.Config.GetBool("F05", "allow_control_chars", false)
            return AQResult.Rejected("Clipboard contains control characters blocked by F05", this._PublicMetadata(mode, analysis))

        if mode = "cancel"
            return AQResult.Cancelled("Multiline paste cancelled", this._PublicMetadata(mode, analysis))

        target := this.App.Context.Capture()
        if !target["hwnd"]
            return AQResult.Rejected("No foreground target is available", this._PublicMetadata(mode, analysis))
        allowUnknown := this.App.Config.GetBool("F05", "allow_unknown_terminal", false)
        if target["terminal"] = "unknown" && !allowUnknown
            return AQResult.Rejected("Foreground target is not a recognised terminal", this._PublicMetadata(mode, analysis))

        if mode = "whole"
            return this._DeliverWhole(target, text, analysis)
        return this._DeliverLines(target, analysis, mode = "confirm_each")
    }

    _DeliverWhole(target, text, analysis) {
        checked := this._RevalidateTarget(target)
        if !checked.IsOk()
            return this._WithMetadata(checked, "whole", analysis)
        A_Clipboard := text
        if !ClipWait(0.5)
            return AQResult.Failed("Clipboard text was unavailable before paste", this._PublicMetadata("whole", analysis))
        sent := this.Transport.PasteClipboard()
        return this._WithMetadata(sent, "whole", analysis)
    }

    _DeliverLines(target, analysis, confirmEach) {
        delayMs := Max(0, this.App.Config.GetInt("F05", "inter_line_delay_ms", 100))
        lines := analysis["lines"]
        sentCount := 0
        for index, line in lines {
            checked := this._RevalidateTarget(target)
            if !checked.IsOk()
                return AQResult.Rejected("Terminal target changed during multiline delivery", this._PublicMetadata(confirmEach ? "confirm_each" : "line_by_line", analysis, sentCount))

            if confirmEach && !this.Confirmer.Confirm(index, lines.Length, Map("blank", line = ""))
                return AQResult.Cancelled("Multiline paste cancelled before line " index, this._PublicMetadata("confirm_each", analysis, sentCount))

            sent := this.Transport.SendLine(line, true)
            if !sent.IsOk()
                return AQResult.Failed(sent.Message, this._PublicMetadata(confirmEach ? "confirm_each" : "line_by_line", analysis, sentCount))
            sentCount += 1
            if delayMs > 0 && index < lines.Length
                Sleep(delayMs)
        }

        return AQResult.Ok("Multiline block delivered", this._PublicMetadata(confirmEach ? "confirm_each" : "line_by_line", analysis, sentCount))
    }

    _RevalidateTarget(target) {
        if !this.App.Windows.StillMatches(target)
            return AQResult.Rejected("Terminal target became stale")
        current := this.App.Context.Capture()
        if current["hwnd"] != target["hwnd"] || current["pid"] != target["pid"]
            return AQResult.Rejected("Foreground terminal changed")
        return AQResult.Ok("Terminal target revalidated")
    }

    _LoadPatterns() {
        patterns := []
        count := Max(0, this.App.Config.GetInt("F05", "pattern_count", 0))
        Loop count {
            pattern := this.App.Config.Get("F05", "pattern" A_Index, "")
            if pattern = ""
                continue
            try RegExMatch("", pattern)
            catch as err
                throw ValueError("Invalid F05 pattern" A_Index ": " err.Message)
            patterns.Push(pattern)
        }
        return patterns
    }

    _PublicMetadata(mode, analysis, sentCount := 0) {
        return Map(
            "mode", mode,
            "line_count", analysis["line_count"],
            "sent_count", sentCount,
            "trailing_newline", analysis["trailing_newline"],
            "blank_lines", analysis["blank_lines"],
            "has_control_chars", analysis["has_control_chars"],
            "continuation_like", analysis["continuation_like"],
            "configured_pattern_matches", analysis["configured_pattern_matches"]
        )
    }

    _WithMetadata(result, mode, analysis) {
        data := this._PublicMetadata(mode, analysis, result.IsOk() ? analysis["line_count"] : 0)
        if result.IsOk()
            return AQResult.Ok(result.Message, data)
        if result.Status = "cancelled"
            return AQResult.Cancelled(result.Message, data)
        if result.Status = "unsupported"
            return AQResult.Unsupported(result.Message, data)
        if result.Status = "invalid"
            return AQResult.Invalid(result.Message, data)
        if result.Status = "rejected"
            return AQResult.Rejected(result.Message, data)
        return AQResult.Failed(result.Message, data)
    }
}

class F05MultilinePasteModule {
    Id := "F05"

    Init(app) {
        this.App := app
        this.Service := F05MultilinePasteService(app)
        app.Actions.Register("terminal.multiline_inspect", (*) => this.Service.Inspect(), "Inspect multiline clipboard metadata", "S0")
        app.Actions.Register("terminal.multiline_paste", (params) => this.Service.Deliver(params.Has("mode") ? params["mode"] : "", params), "Deliver clipboard block using configured/selected mode", "S1")
        app.Actions.Register("terminal.multiline_paste_whole", (*) => this.Service.Deliver("whole"), "Paste clipboard block literally as one block", "S1")
        app.Actions.Register("terminal.multiline_paste_lines", (*) => this.Service.Deliver("line_by_line"), "Deliver clipboard block line by line", "S1")
        app.Actions.Register("terminal.multiline_paste_confirm_each", (*) => this.Service.Deliver("confirm_each"), "Confirm each line before delivery", "S1")
        app.Actions.Register("terminal.multiline_paste_cancel", (*) => this.Service.Deliver("cancel"), "Cancel multiline delivery", "S0")
        this.ActionIds := [
            "terminal.multiline_inspect",
            "terminal.multiline_paste",
            "terminal.multiline_paste_whole",
            "terminal.multiline_paste_lines",
            "terminal.multiline_paste_confirm_each",
            "terminal.multiline_paste_cancel"
        ]
        this.Hotkeys := []
        this._BindConfiguredHotkey("whole_hotkey", "terminal.multiline_paste_whole")
        this._BindConfiguredHotkey("lines_hotkey", "terminal.multiline_paste_lines")
        this._BindConfiguredHotkey("confirm_hotkey", "terminal.multiline_paste_confirm_each")
        return AQResult.Ok("F05 initialized")
    }

    _BindConfiguredHotkey(configKey, actionId) {
        hotkeySpec := Trim(this.App.Config.Get("F05", configKey, ""))
        if hotkeySpec = ""
            return
        callback := (*) => this.App.Actions.Invoke(actionId)
        Hotkey(hotkeySpec, callback, "On")
        this.Hotkeys.Push(Map("spec", hotkeySpec, "callback", callback))
    }

    Teardown(app) {
        if HasProp(this, "Hotkeys") {
            for binding in this.Hotkeys {
                try Hotkey(binding["spec"], binding["callback"], "Off")
            }
        }
        if HasProp(this, "ActionIds") {
            for id in this.ActionIds
                app.Actions.Unregister(id)
        }
        return AQResult.Ok("F05 stopped")
    }
}
