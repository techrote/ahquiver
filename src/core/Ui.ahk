#Requires AutoHotkey v2.0

class AQTrayUi {
    __New(app) {
        this.App := app
        this.Initialized := false
    }

    Init() {
        menu := A_TrayMenu
        menu.Delete()
        menu.Add("Status", ObjBindMethod(this, "ShowStatus"))
        menu.Add("Reload configuration", ObjBindMethod(this, "ReloadConfiguration"))
        menu.Add()
        menu.Add("Exit AHQuiver", ObjBindMethod(this, "ExitApplication"))
        this.Initialized := true
    }

    ShowStatus(*) {
        text := "AHQuiver`n"
        text .= "Actions: " this.App.Actions.Count() "`n"
        text .= "Modules: " this.App.Modules.Count() " registered / " this.App.Modules.CountEnabled() " enabled`n"
        text .= "Config: " this.App.Config.Path
        MsgBox(text, "AHQuiver status", "Iconi")
    }

    ReloadConfiguration(*) {
        result := this.App.ReloadConfiguration()
        if result.IsOk()
            TrayTip("AHQuiver", "Configuration reloaded")
        else
            MsgBox(result.Message, "AHQuiver configuration", "Iconx")
    }

    ExitApplication(*) {
        ExitApp(0)
    }

    Teardown() {
        this.Initialized := false
    }
}
