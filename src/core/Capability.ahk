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
            return this.Items[id]
        return Map("status", "unknown", "detail", "", "updated_at", 0)
    }

    Has(id) {
        return this.Items.Has(id)
    }

    Count() {
        return this.Items.Count
    }
}
