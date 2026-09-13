#Requires AutoHotkey v2.0

class AQProcess {
    static QuoteArg(value) {
        text := value ""
        quote := Chr(34)
        slash := Chr(92)
        if text = ""
            return quote quote
        if !InStr(text, " ") && !InStr(text, "`t") && !InStr(text, quote)
            return text

        result := quote
        slashCount := 0
        Loop Parse text {
            ch := A_LoopField
            if ch = slash {
                slashCount += 1
                continue
            }

            if ch = quote {
                result .= AQProcess._Repeat(slash, slashCount * 2 + 1) quote
                slashCount := 0
                continue
            }

            if slashCount {
                result .= AQProcess._Repeat(slash, slashCount)
                slashCount := 0
            }
            result .= ch
        }

        if slashCount
            result .= AQProcess._Repeat(slash, slashCount * 2)
        return result quote
    }

    static BuildCommand(program, args := unset) {
        command := AQProcess.QuoteArg(program)
        if IsSet(args) {
            for arg in args
                command .= " " AQProcess.QuoteArg(arg)
        }
        return command
    }

    static Launch(program, args := unset, workingDir := "") {
        command := IsSet(args) ? AQProcess.BuildCommand(program, args) : AQProcess.BuildCommand(program)
        pid := 0
        try {
            Run(command, workingDir, , &pid)
            return AQResult.Ok("Process launched", Map("pid", pid))
        } catch as err {
            return AQResult.Failed("Process launch failed: " err.Message)
        }
    }

    static _Repeat(text, count) {
        output := ""
        Loop Max(count, 0)
            output .= text
        return output
    }
}
