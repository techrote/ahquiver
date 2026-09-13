#Requires AutoHotkey v2.0

class AQResult {
    __New(status, message := "", data := unset) {
        this.Status := status
        this.Message := message
        this.Data := IsSet(data) ? data : Map()
    }

    IsOk() {
        return this.Status = "ok"
    }

    static Ok(message := "", data := unset) {
        return IsSet(data) ? AQResult("ok", message, data) : AQResult("ok", message)
    }

    static Cancelled(message := "Cancelled", data := unset) {
        return IsSet(data) ? AQResult("cancelled", message, data) : AQResult("cancelled", message)
    }

    static Unsupported(message := "Unsupported", data := unset) {
        return IsSet(data) ? AQResult("unsupported", message, data) : AQResult("unsupported", message)
    }

    static Invalid(message := "Invalid configuration or input", data := unset) {
        return IsSet(data) ? AQResult("invalid", message, data) : AQResult("invalid", message)
    }

    static Rejected(message := "Target rejected", data := unset) {
        return IsSet(data) ? AQResult("rejected", message, data) : AQResult("rejected", message)
    }

    static Failed(message := "Execution failed", data := unset) {
        return IsSet(data) ? AQResult("failed", message, data) : AQResult("failed", message)
    }
}
