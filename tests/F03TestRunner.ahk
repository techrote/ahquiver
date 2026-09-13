#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\Log.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\IdentityRegistry.ahk
#Include ..\src\core\ModuleHost.ahk
#Include ..\src\modules\F03_TerminalKeyGuard.ahk
#Include F03Tests.ahk

global F03_TEST_PASSED := 0
global F03_TEST_FAILED := 0
global F03_PROGRESS := EnvGet("AQ_TEST_PROGRESS")
if F03_PROGRESS = ""
    F03_PROGRESS := A_Temp "\ahquiver-f03-progress.log"
try FileDelete(F03_PROGRESS)
F03Trace("LOADED")

SetTimer(F03Watchdog, -15000)
F03RunTest("config and rule matching", TestF03ConfigAndRuleMatching)
F03RunTest("non-terminal Ctrl+C pass-through", TestF03NonTerminalPassThrough)
F03RunTest("pass-through policy", TestF03PassThroughPolicy)
F03RunTest("double-tap timing boundary", TestF03DoubleTapBoundary)
F03RunTest("hold policy", TestF03HoldPolicy)
F03RunTest("confirm policy", TestF03ConfirmPolicy)
F03RunTest("remap policy", TestF03RemapPolicy)
F03RunTest("bypass and instant disable", TestF03BypassAndInstantDisable)
F03RunTest("selection capability gate", TestF03SelectionCapabilityGate)
F03RunTest("stale foreground rejection", TestF03StaleForegroundRejected)
F03RunTest("module lifecycle", TestF03ModuleLifecycle)
SetTimer(F03Watchdog, 0)

F03Trace("RESULT passed=" F03_TEST_PASSED " failed=" F03_TEST_FAILED)
FileAppend("RESULT passed=" F03_TEST_PASSED " failed=" F03_TEST_FAILED "`n", "*")
ExitApp(F03_TEST_FAILED = 0 ? 0 : 1)

F03Watchdog() {
    F03Trace("WATCHDOG suite exceeded 15 seconds")
    ExitApp(2)
}

F03RunTest(name, callback) {
    global F03_TEST_PASSED, F03_TEST_FAILED
    F03Trace("RUN " name)
    try {
        callback.Call()
        F03_TEST_PASSED += 1
        F03Trace("PASS " name)
        FileAppend("PASS " name "`n", "*")
    } catch as testError {
        F03_TEST_FAILED += 1
        F03Trace("FAIL " name ": " testError.Message)
        FileAppend("FAIL " name ": " testError.Message "`n", "*")
    }
}

F03Trace(message) {
    global F03_PROGRESS
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", F03_PROGRESS, "UTF-8")
}

AssertF03True(value, message := "Expected true") {
    if !value
        throw Error(message)
}

AssertF03False(value, message := "Expected false") {
    if value
        throw Error(message)
}

AssertF03Equal(expected, actual, message := "") {
    if expected != actual {
        detail := message != "" ? message ": " : ""
        throw Error(detail "expected=" expected " actual=" actual)
    }
}

F03TempPath(label) {
    return A_Temp "\ahquiver-f03-" label "-" A_TickCount "-" Random(1000, 9999) ".tmp"
}

F03Delete(path) {
    if FileExist(path) {
        try FileDelete(path)
    }
}
