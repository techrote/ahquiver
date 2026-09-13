#Requires AutoHotkey v2.0

class AQSystemClipboardBackend {
    Save() {
        return ClipboardAll()
    }

    Restore(snapshot) {
        A_Clipboard := snapshot
    }
}

class AQClipboardGuard {
    __New(backend := unset) {
        this.Backend := IsSet(backend) ? backend : AQSystemClipboardBackend()
    }

    Run(callback) {
        snapshot := this.Backend.Save()
        try {
            return callback.Call()
        } finally {
            this.Backend.Restore(snapshot)
        }
    }
}
