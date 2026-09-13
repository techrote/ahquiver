#Requires AutoHotkey v2.0

class AQIdentityRegistry {
    __New() {
        this.Records := Map()
        this.NextId := 1
    }

    Register(presetId, identity, role := "", pid := 0, metadata := unset) {
        recordId := "identity-" this.NextId
        this.NextId += 1
        record := Map(
            "id", recordId,
            "preset", presetId,
            "identity", identity,
            "role", role,
            "pid", pid,
            "state", "active",
            "created_at", A_TickCount,
            "inactive_reason", ""
        )

        if IsSet(metadata) && IsObject(metadata) {
            for key, value in metadata
                record[key] := value
        }

        this.Records[recordId] := record
        return this._Copy(record)
    }

    Get(recordId) {
        if !this.Records.Has(recordId)
            return Map()
        return this._Copy(this.Records[recordId])
    }

    List(activeOnly := false) {
        items := []
        for _, record in this.Records {
            if activeOnly && record["state"] != "active"
                continue
            items.Push(this._Copy(record))
        }
        return items
    }

    FindActiveByPreset(presetId) {
        for _, record in this.Records {
            if record["preset"] = presetId && record["state"] = "active"
                return this._Copy(record)
        }
        return Map()
    }

    MarkInactive(recordId, reason := "") {
        if !this.Records.Has(recordId)
            return false
        this.Records[recordId]["state"] := "inactive"
        this.Records[recordId]["inactive_reason"] := reason
        return true
    }

    ReleasePreset(presetId, reason := "released") {
        count := 0
        for recordId, record in this.Records {
            if record["preset"] = presetId && record["state"] = "active" {
                this.MarkInactive(recordId, reason)
                count += 1
            }
        }
        return count
    }

    Count(activeOnly := false) {
        if !activeOnly
            return this.Records.Count
        count := 0
        for _, record in this.Records {
            if record["state"] = "active"
                count += 1
        }
        return count
    }

    _Copy(record) {
        copy := Map()
        for key, value in record
            copy[key] := value
        return copy
    }
}
