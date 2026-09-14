#Requires AutoHotkey v2.0

class AQCapabilityRegistry {
    __New() {
        this.Items := Map()
    }

    Set(id, status, detail := "") {
        allowed := Map("supported", true, "unsupported", true, "degraded", true, "unknown", true)
        if !allowed.Has(status)
            throw ValueError("Invalid capability status: " status)
        this.Items[id] := Map("status", status, "detail", detail, "updated_at", A_TickCount)
        return this.Items[id]
    }

    Get(id) {
        if this.Items.Has(id)
            return this._Copy(this.Items[id])
        return Map("status", "unknown", "detail", "", "updated_at", 0)
    }

    Has(id) {
        return this.Items.Has(id)
    }

    Count() {
        return this.Items.Count
    }

    List() {
        items := []
        for id, entry in this.Items {
            item := this._Copy(entry)
            item["id"] := id
            items.Push(item)
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

    _Copy(source) {
        copy := Map()
        for key, value in source
            copy[key] := value
        return copy
    }
}
