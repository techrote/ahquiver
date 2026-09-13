#Requires AutoHotkey v2.0

class AQActionRegistry {
    __New(log := unset) {
        this.Actions := Map()
        this.Log := IsSet(log) ? log : ""
    }

    Register(id, handler, description := "", safetyClass := "S0") {
        id := Trim(id)
        if id = ""
            throw ValueError("Action ID cannot be empty")
        if this.Actions.Has(id)
            throw ValueError("Action already registered: " id)
        if !IsObject(handler)
            throw TypeError("Action handler must be callable")

        this.Actions[id] := Map(
            "handler", handler,
            "description", description,
            "safety_class", safetyClass
        )
        return id
    }

    Unregister(id) {
        if !this.Actions.Has(id)
            return false
        this.Actions.Delete(id)
        return true
    }

    Has(id) {
        return this.Actions.Has(id)
    }

    Count() {
        return this.Actions.Count
    }

    Invoke(id, params := unset) {
        if !this.Actions.Has(id)
            return AQResult.Invalid("Unknown action: " id)

        entry := this.Actions[id]
        payload := IsSet(params) ? params : Map()
        try {
            result := entry["handler"].Call(payload)
            if IsObject(result) && HasProp(result, "Status")
                return result
            return AQResult.Ok("Action completed", Map("value", result))
        } catch as err {
            this._LogFailure(id, err.Message)
            return AQResult.Failed("Action failed: " id " — " err.Message)
        }
    }

    Describe(id) {
        if !this.Actions.Has(id)
            return Map()
        entry := this.Actions[id]
        return Map(
            "id", id,
            "description", entry["description"],
            "safety_class", entry["safety_class"]
        )
    }

    List() {
        items := []
        for id, entry in this.Actions {
            items.Push(Map(
                "id", id,
                "description", entry["description"],
                "safety_class", entry["safety_class"]
            ))
        }
        return items
    }

    _LogFailure(id, message) {
        if IsObject(this.Log)
            this.Log.Error("action=" id " failed=" message)
    }
}
