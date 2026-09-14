#Requires AutoHotkey v2.0

class AQModuleHost {
    __New(app) {
        this.App := app
        this.Modules := Map()
        this.States := Map()
    }

    Register(module) {
        try id := module.Id
        catch
            throw ValueError("Module must expose Id")
        if Trim(id) = ""
            throw ValueError("Module Id cannot be empty")
        if this.Modules.Has(id)
            throw ValueError("Module already registered: " id)
        this.Modules[id] := module
        this.States[id] := "registered"
        return id
    }

    StartConfigured() {
        for id, module in this.Modules {
            enabled := this.App.Config.GetBool("modules", id, false)
            if !enabled {
                this.States[id] := "disabled"
                continue
            }

            try {
                module.Init(this.App)
                this.States[id] := "enabled"
                this.App.Log.Info("module=" id " state=enabled")
            } catch as err {
                this.States[id] := "failed"
                this.App.Log.Error("module=" id " state=failed error=" err.Message)
            }
        }
        return AQResult.Ok("Configured modules evaluated")
    }

    StopAll() {
        for id, module in this.Modules {
            if this.States[id] != "enabled"
                continue
            try module.Teardown(this.App)
            catch as err
                this.App.Log.Warn("module=" id " teardown_error=" err.Message)
            this.States[id] := "disabled"
        }
        return AQResult.Ok("Modules stopped")
    }

    Reload() {
        this.StopAll()
        return this.StartConfigured()
    }

    Count() {
        return this.Modules.Count
    }

    CountEnabled() {
        count := 0
        for id, state in this.States {
            if state = "enabled"
                count += 1
        }
        return count
    }

    State(id) {
        return this.States.Has(id) ? this.States[id] : "unknown"
    }

    List() {
        items := []
        for id, module in this.Modules {
            items.Push(Map(
                "id", id,
                "state", this.State(id)
            ))
        }
        this._SortById(items)
        return items
    }

    _SortById(items) {
        count := items.Length
        if count < 2
            return
        Loop count - 1 {
            left := A_Index
            Loop count - left {
                right := left + A_Index
                if StrCompare(items[left]["id"], items[right]["id"], false) > 0 {
                    swap := items[left]
                    items[left] := items[right]
                    items[right] := swap
                }
            }
        }
    }
}
