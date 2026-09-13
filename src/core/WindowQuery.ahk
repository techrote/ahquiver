#Requires AutoHotkey v2.0

class AQWindowQuery {
    Describe(hwnd) {
        selector := "ahk_id " hwnd
        return Map(
            "hwnd", hwnd,
            "pid", this._Safe(() => WinGetPID(selector), 0),
            "exe", this._Safe(() => WinGetProcessName(selector), ""),
            "path", this._Safe(() => WinGetProcessPath(selector), ""),
            "class", this._Safe(() => WinGetClass(selector), ""),
            "title", this._Safe(() => WinGetTitle(selector), ""),
            "style", this._Safe(() => WinGetStyle(selector), 0),
            "timestamp", A_TickCount
        )
    }

    EnumerateVisible() {
        windows := []
        try hwnds := WinGetList()
        catch
            return windows

        for hwnd in hwnds {
            info := this.Describe(hwnd)
            if info["style"] & 0x10000000
                windows.Push(info)
        }
        return windows
    }

    StillMatches(snapshot) {
        if !snapshot.Has("hwnd") || !snapshot["hwnd"]
            return false
        current := this.Describe(snapshot["hwnd"])
        if !current["pid"]
            return false
        if snapshot.Has("pid") && snapshot["pid"] && current["pid"] != snapshot["pid"]
            return false
        if snapshot.Has("exe") && snapshot["exe"] != "" && current["exe"] != snapshot["exe"]
            return false
        if snapshot.Has("class") && snapshot["class"] != "" && current["class"] != snapshot["class"]
            return false
        return true
    }

    _Safe(callback, fallback) {
        try return callback.Call()
        catch
            return fallback
    }
}
