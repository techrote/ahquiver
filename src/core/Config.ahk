#Requires AutoHotkey v2.0

class AQConfig {
    __New(path) {
        this.Path := path
    }

    Exists() {
        return FileExist(this.Path) != ""
    }

    Get(section, key, default := "") {
        if !this.Exists()
            return default
        try return IniRead(this.Path, section, key, default)
        catch
            return default
    }

    GetBool(section, key, default := false) {
        fallback := default ? "1" : "0"
        raw := StrLower(Trim(this.Get(section, key, fallback)))
        if raw = "1" || raw = "true" || raw = "yes" || raw = "on"
            return true
        if raw = "0" || raw = "false" || raw = "no" || raw = "off"
            return false
        return default
    }

    GetInt(section, key, default := 0) {
        raw := Trim(this.Get(section, key, default ""))
        if RegExMatch(raw, "^-?\d+$")
            return raw + 0
        return default
    }

    Reload() {
        if !this.Exists()
            return AQResult.Invalid("Configuration file not found: " this.Path)
        return AQResult.Ok("Configuration source is readable", Map("path", this.Path))
    }
}
