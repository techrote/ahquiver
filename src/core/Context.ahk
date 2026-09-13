#Requires AutoHotkey v2.0

class AQContextService {
    Capture() {
        hwnd := this._Safe(() => WinGetID("A"), 0)
        if !hwnd
            return this._EmptyContext()

        selector := "ahk_id " hwnd
        pid := this._Safe(() => WinGetPID(selector), 0)
        exe := this._Safe(() => WinGetProcessName(selector), "")
        path := this._Safe(() => WinGetProcessPath(selector), "")
        className := this._Safe(() => WinGetClass(selector), "")
        title := this._Safe(() => WinGetTitle(selector), "")

        return Map(
            "hwnd", hwnd,
            "pid", pid,
            "exe", exe,
            "path", path,
            "class", className,
            "title", title,
            "terminal", this.ClassifyTerminal(exe),
            "modifiers", this.Modifiers(),
            "project_identity", "",
            "timestamp", A_TickCount
        )
    }

    ClassifyTerminal(exe) {
        name := StrLower(exe)
        if name = "windowsterminal.exe"
            return "WindowsTerminal"
        if name = "conhost.exe" || name = "openconsole.exe"
            return "conhost"
        return "unknown"
    }

    Modifiers() {
        return Map(
            "ctrl", GetKeyState("Ctrl", "P"),
            "alt", GetKeyState("Alt", "P"),
            "shift", GetKeyState("Shift", "P"),
            "win", GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
        )
    }

    _EmptyContext() {
        return Map(
            "hwnd", 0,
            "pid", 0,
            "exe", "",
            "path", "",
            "class", "",
            "title", "",
            "terminal", "unknown",
            "modifiers", this.Modifiers(),
            "project_identity", "",
            "timestamp", A_TickCount
        )
    }

    _Safe(callback, fallback) {
        try return callback.Call()
        catch
            return fallback
    }
}
