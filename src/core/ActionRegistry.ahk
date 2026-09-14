#Requires AutoHotkey v2.0

class AQActionRegistry {
    __New(log := unset) {
        this.Actions := Map()
        this.Log := IsSet(log) ? log : ""
        this.Observers := Map()
        this.NextObserverId := 1
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

    Subscribe(observer) {
        if !IsObject(observer)
            throw TypeError("Action observer must be callable")
        token := this.NextObserverId
        this.NextObserverId += 1
        this.Observers[token] := observer
        return token
    }

    Unsubscribe(token) {
        if !this.Observers.Has(token)
            return false
        this.Observers.Delete(token)
        return true
    }

    Invoke(id, params := unset) {
        if !this.Actions.Has(id) {
            result := AQResult.Invalid("Unknown action: " id)
            this._Notify(id, result)
            return result
        }

        entry := this.Actions[id]
        payload := IsSet(params) ? params : Map()
        try {
            result := entry["handler"].Call(payload)
            if !(IsObject(result) && HasProp(result, "Status"))
                result := AQResult.Ok("Action completed", Map("value", result))
        } catch as err {
            this._LogFailure(id, err.Message)
            result := AQResult.Failed("Action failed: " id " — " err.Message)
        }
        this._Notify(id, result)
        return result
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
        this._SortById(items)
        return items
    }

    _Notify(id, result) {
        for token, observer in this.Observers {
            try observer.Call(id, result)
        }
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

    _LogFailure(id, message) {
        if IsObject(this.Log)
            this.Log.Error("action=" id " failed=" message)
    }
}
