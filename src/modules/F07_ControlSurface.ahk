#Requires AutoHotkey v2.0

class F07ControlSurfaceModule {
    Id := "F07"

    Init(app) {
        this.App := app
        this.ActionIds := []
        try {
            this._Register("control.show", (*) => app.Ui.ShowControl(), "Open the AHQuiver control panel", "S0")
            this._Register("control.refresh", (*) => app.Ui.Refresh(), "Refresh tray and control-panel registry views", "S0")
            this._Register("control.reload_configuration", (*) => app.Ui.ReloadConfiguration(), "Reload AHQuiver configuration and module states", "S1")
            this._Register("control.emergency_disable", (*) => app.Ui.EmergencyDisable(), "Disable all feature modules for this session", "S2")
            app.Ui.EnableControlSurface()
            return AQResult.Ok("F07 control surface initialized")
        } catch as err {
            for actionId in this.ActionIds
                try app.Actions.Unregister(actionId)
            try app.Ui.DisableControlSurface()
            throw err
        }
    }

    _Register(id, callback, description, safetyClass) {
        this.App.Actions.Register(id, callback, description, safetyClass)
        this.ActionIds.Push(id)
    }

    Teardown(app) {
        if HasProp(this, "ActionIds") {
            for actionId in this.ActionIds
                app.Actions.Unregister(actionId)
        }
        app.Ui.DisableControlSurface()
        return AQResult.Ok("F07 control surface stopped")
    }
}
