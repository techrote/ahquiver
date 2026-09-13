#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\Log.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\core\WindowQuery.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\Process.ahk
#Include ..\src\core\IdentityRegistry.ahk
#Include ..\src\core\ModuleHost.ahk
#Include ..\src\modules\F02_TerminalIdentity.ahk
#Include F02Tests.ahk

global F02_TEST_PASSED := 0
global F02_TEST_FAILED := 0
global F02_PROGRESS := EnvGet("AQ_TEST_PROGRESS")
if F02_PROGRESS = ""
    F02_PROGRESS := A_Temp "\ahquiver-f02-progress.log"
try FileDelete(F02_PROGRESS)
F02Trace("LOADED")

SetTimer(F02Watchdog, -15000)
F02RunTest("preset parsing", TestF02PresetParsing)
F02RunTest("two independent identities", TestF02TwoIndependentIdentities)
F02RunTest("PID singleton lifecycle", TestF02PidSingletonLifecycle)
F02RunTest("Windows Terminal args and sticky singleton", TestF02WindowsTerminalArgumentsAndStickySingleton)
F02RunTest("unsupported title remains non-fatal", TestF02UnsupportedTitleIsNonFatal)
F02RunTest("Windows Terminal capability record", TestF02WindowsTerminalCapabilityRecord)
F02RunTest("safe command quoting", TestF02SafeCommandQuoting)
F02RunTest("module lifecycle", TestF02ModuleLifecycle)
SetTimer(F02Watchdog, 0)

F02Trace("RESULT passed=" F02_TEST_PASSED " failed=" F02_TEST_FAILED)
FileAppend("RESULT passed=" F02_TEST_PASSED " failed=" F02_TEST_FAILED "`n", "*")
ExitApp(F02_TEST_FAILED = 0 ? 0 : 1)

F02Watchdog() {
    F02Trace("WATCHDOG suite exceeded 15 seconds")
    ExitApp(2)
}

F02RunTest(name, callback) {
    global F02_TEST_PASSED, F02_TEST_FAILED
    F02Trace("RUN " name)
    try {
        callback.Call()
        F02_TEST_PASSED += 1
        F02Trace("PASS " name)
        FileAppend("PASS " name "`n", "*")
    } catch as err {
        F02_TEST_FAILED += 1
        F02Trace("FAIL " name ": " err.Message)
        FileAppend("FAIL " name ": " err.Message "`n", "*")
    }
}

F02Trace(message) {
    global F02_PROGRESS
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", F02_PROGRESS, "UTF-8")
}

AssertTrue(value, message := "Expected true") {
    if !value
        throw Error(message)
}

AssertFalse(value, message := "Expected false") {
    if value
        throw Error(message)
}

AssertEqual(expected, actual, message := "") {
    if expected != actual {
        detail := message != "" ? message ": " : ""
        throw Error(detail "expected=" expected " actual=" actual)
    }
}

TestTempPath(label) {
    return A_Temp "\ahquiver-f02-" label "-" A_TickCount "-" Random(1000, 9999) ".tmp"
}

TestDelete(path) {
    if FileExist(path) {
        try FileDelete(path)
    }
}
