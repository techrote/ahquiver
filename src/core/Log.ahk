#Requires AutoHotkey v2.0

class AQLog {
    __New(path, enabled := true) {
        this.Path := path
        this.Enabled := enabled
        if this.Enabled
            this._EnsureParentDirectory()
    }

    Debug(message) {
        this.Write("DEBUG", message)
    }

    Info(message) {
        this.Write("INFO", message)
    }

    Warn(message) {
        this.Write("WARN", message)
    }

    Error(message) {
        this.Write("ERROR", message)
    }

    Write(level, message) {
        if !this.Enabled
            return
        stamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        line := stamp " [" level "] " message "`n"
        try FileAppend(line, this.Path, "UTF-8")
    }

    _EnsureParentDirectory() {
        fileName := ""
        dir := ""
        SplitPath(this.Path, &fileName, &dir)
        if dir = ""
            return
        if !InStr(FileExist(dir), "D")
            DirCreate(dir)
    }
}
