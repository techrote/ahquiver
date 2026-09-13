#Requires AutoHotkey v2.0

class F01CloseMatchingWindowsService {
    __New(windowQuery, options := unset, confirmer := unset) {
        this.Windows := windowQuery
        this.Options := IsSet(options) ? options : Map()
        this.Confirmer := IsSet(confirmer) ? confirmer : ""
    }

    Execute(target, params := unset) {
        if !IsObject(target) || !target.Has("hwnd") || !target["hwnd"]
            return AQResult.Rejected("No active target window")
        if !target.Has("exe") || Trim(target["exe"]) = ""
            return AQResult.Rejected("Target executable is unavailable")

        request := IsSet(params) && IsObject(params) ? params : Map()
        preview := this._ParamBool(request, "preview", this._OptionBool("preview", false))
        confirm := this._ParamBool(request, "confirm", this._OptionBool("confirm", true))
        confirmMin := this._ParamInt(request, "confirm_min", this._OptionInt("confirm_min", 2))
        closeTimeoutMs := this._ParamInt(request, "close_timeout_ms", this._OptionInt("close_timeout_ms", 750))

        counts := Map("candidate", 0, "closed", 0, "skipped", 0, "failed", 0, "stale", 0)
        closable := []
        previewItems := []

        for info in this.Windows.EnumerateVisible() {
            if !this._SameGroup(target, info)
                continue

            counts["candidate"] += 1
            reason := this._SkipReason(info)
            if reason != "" {
                counts["skipped"] += 1
                continue
            }

            closable.Push(info)
            previewItems.Push(this._PublicWindowInfo(info))
        }

        data := this._ResultData(counts, previewItems)
        if preview
            return AQResult.Ok("Close-matching preview", data)

        if closable.Length = 0
            return AQResult.Ok("No closable matching windows", data)

        if confirm && closable.Length >= Max(confirmMin, 1) {
            if !this._Confirm(closable.Length, target)
                return AQResult.Cancelled("Close-matching action cancelled", data)
        }

        for info in closable {
            if !this.Windows.StillMatches(info) {
                counts["stale"] += 1
                continue
            }

            result := this.Windows.RequestClose(info, closeTimeoutMs)
            if result.IsOk()
                counts["closed"] += 1
            else if result.Status = "rejected"
                counts["stale"] += 1
            else
                counts["failed"] += 1
        }

        data := this._ResultData(counts, previewItems)
        if counts["failed"] > 0
            return AQResult.Failed("One or more matching windows failed to close", data)
        return AQResult.Ok("Close-matching action completed", data)
    }

    _SameGroup(target, candidate) {
        if !candidate.Has("exe") || StrLower(candidate["exe"]) != StrLower(target["exe"])
            return false

        if this._OptionBool("match_class", false) {
            if !candidate.Has("class") || !target.Has("class") || candidate["class"] != target["class"]
                return false
        }

        if this._OptionBool("match_title", false) {
            if !candidate.Has("title") || !target.Has("title") || candidate["title"] != target["title"]
                return false
        }

        return true
    }

    _SkipReason(info) {
        if this._OptionBool("protect_self", true) && info.Has("pid") && info["pid"] = A_Pid
            return "self"

        className := info.Has("class") ? StrLower(info["class"]) : ""
        if this._OptionBool("protect_shell", true) {
            protectedClasses := Map(
                "shell_traywnd", true,
                "shell_secondarytraywnd", true,
                "progman", true,
                "workerw", true
            )
            if protectedClasses.Has(className)
                return "shell"
        }

        exeName := info.Has("exe") ? StrLower(info["exe"]) : ""
        if this._CsvSet(this._Option("exclude_exes", "")).Has(exeName)
            return "excluded_exe"
        if this._CsvSet(this._Option("exclude_classes", "")).Has(className)
            return "excluded_class"

        return ""
    }

    _Confirm(count, target) {
        if IsObject(this.Confirmer)
            return !!this.Confirmer.Call(count, target)

        exeName := target.Has("exe") ? target["exe"] : "matching application"
        answer := MsgBox("Close " count " matching " exeName " windows?", "AHQuiver", "YesNo Icon!")
        return answer = "Yes"
    }

    _PublicWindowInfo(info) {
        return Map(
            "hwnd", info.Has("hwnd") ? info["hwnd"] : 0,
            "pid", info.Has("pid") ? info["pid"] : 0,
            "exe", info.Has("exe") ? info["exe"] : "",
            "class", info.Has("class") ? info["class"] : ""
        )
    }

    _ResultData(counts, items) {
        return Map(
            "candidate", counts["candidate"],
            "closed", counts["closed"],
            "skipped", counts["skipped"],
            "failed", counts["failed"],
            "stale", counts["stale"],
            "windows", items
        )
    }

    _CsvSet(raw) {
        values := Map()
        for item in StrSplit(raw, ",") {
            normalized := StrLower(Trim(item))
            if normalized != ""
                values[normalized] := true
        }
        return values
    }

    _Option(key, fallback := "") {
        return this.Options.Has(key) ? this.Options[key] : fallback
    }

    _OptionBool(key, fallback := false) {
        raw := StrLower(Trim(this._Option(key, fallback ? "1" : "0") ""))
        if raw = "1" || raw = "true" || raw = "yes" || raw = "on"
            return true
        if raw = "0" || raw = "false" || raw = "no" || raw = "off"
            return false
        return fallback
    }

    _OptionInt(key, fallback := 0) {
        raw := Trim(this._Option(key, fallback) "")
        return RegExMatch(raw, "^-?\d+$") ? raw + 0 : fallback
    }

    _ParamBool(params, key, fallback) {
        if !params.Has(key)
            return fallback
        raw := params[key]
        if Type(raw) = "Integer"
            return raw != 0
        text := StrLower(Trim(raw ""))
        if text = "1" || text = "true" || text = "yes" || text = "on"
            return true
        if text = "0" || text = "false" || text = "no" || text = "off"
            return false
        return fallback
    }

    _ParamInt(params, key, fallback) {
        if !params.Has(key)
            return fallback
        raw := Trim(params[key] "")
        return RegExMatch(raw, "^-?\d+$") ? raw + 0 : fallback
    }
}

class F01CloseMatchingWindowsModule {
    __New() {
        this.Id := "F01"
        this.Name := "Close matching windows"
        this.App := ""
        this.Service := ""
        this.HotkeySpec := ""
        this.HotkeyCallback := ""
    }

    Init(app) {
        this.App := app
        options := Map(
            "match_class", app.Config.GetBool("F01", "match_class", false),
            "match_title", app.Config.GetBool("F01", "match_title", false),
            "protect_self", app.Config.GetBool("F01", "protect_self", true),
            "protect_shell", app.Config.GetBool("F01", "protect_shell", true),
            "exclude_exes", app.Config.Get("F01", "exclude_exes", ""),
            "exclude_classes", app.Config.Get("F01", "exclude_classes", ""),
            "preview", app.Config.GetBool("F01", "preview", false),
            "confirm", app.Config.GetBool("F01", "confirm", true),
            "confirm_min", app.Config.GetInt("F01", "confirm_min", 2),
            "close_timeout_ms", app.Config.GetInt("F01", "close_timeout_ms", 750)
        )

        this.Service := F01CloseMatchingWindowsService(app.Windows, options)
        app.Actions.Register("windows.close_matching", this._Invoke.Bind(this), "Close visible windows matching the active application", "S2")

        this.HotkeySpec := Trim(app.Config.Get("F01", "hotkey", ""))
        if this.HotkeySpec != "" {
            this.HotkeyCallback := this._OnHotkey.Bind(this)
            Hotkey(this.HotkeySpec, this.HotkeyCallback, "On")
        }
    }

    Teardown(app) {
        if this.HotkeySpec != "" {
            try Hotkey(this.HotkeySpec, "Off")
        }
        if app.Actions.Has("windows.close_matching")
            app.Actions.Unregister("windows.close_matching")
        this.Service := ""
        this.App := ""
        this.HotkeySpec := ""
        this.HotkeyCallback := ""
    }

    _Invoke(params) {
        target := this.App.Context.Capture()
        return this.Service.Execute(target, params)
    }

    _OnHotkey(*) {
        result := this.App.Actions.Invoke("windows.close_matching")
        if result.Status = "failed"
            this.App.Log.Warn("F01 action failed: " result.Message)
    }
}
