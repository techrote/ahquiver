#Requires AutoHotkey v2.0

class AQProcess {
    static QuoteArg(value) {
        text := value ""
        quote := Chr(34)
        if text = ""
            return quote quote
        if !InStr(text, " ") && !InStr(text, "`t") && !InStr(text, quote)
            return text
        escaped := StrReplace(text, quote, Chr(92) quote)
        return quote escaped quote
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
}
