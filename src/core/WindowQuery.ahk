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

    FindVisibleByPid(pid) {
        matches := []
        if !pid
            return matches
        for info in this.EnumerateVisible() {
            if info["pid"] = pid
                matches.Push(info)
        }
        return matches
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

    RequestTitle(snapshot, title) {
        if !this.StillMatches(snapshot)
            return AQResult.Rejected("Window target became stale before title update")
        if Trim(title) = ""
            return AQResult.Invalid("Window title cannot be empty")

        selector := "ahk_id " snapshot["hwnd"]
        try WinSetTitle(title, selector)
        catch as err
            return AQResult.Failed("Window title request failed: " err.Message)

        observed := this._Safe(() => WinGetTitle(selector), "")
        return AQResult.Ok("Window title request sent", Map(
            "verified", observed = title,
            "observed_title", observed
        ))
    }

    RequestClose(snapshot, timeoutMs := 750) {
        if !this.StillMatches(snapshot)
            return AQResult.Rejected("Window target became stale before close")

        selector := "ahk_id " snapshot["hwnd"]
        waitSeconds := Max(timeoutMs, 0) / 1000.0
        try WinClose(selector, , waitSeconds)
        catch as err
            return AQResult.Failed("Window close request failed: " err.Message)

        if WinExist(selector)
            return AQResult.Failed("Window did not close within configured timeout")
        return AQResult.Ok("Window closed normally")
    }

    _Safe(callback, fallback) {
        try return callback.Call()
        catch
            return fallback
    }
}
