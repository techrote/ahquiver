#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\Log.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\ModuleHost.ahk
#Include ..\src\modules\F04_FocusPreservingPaste.ahk
#Include F04Tests.ahk

global F04_TEST_PASSED := 0
global F04_TEST_FAILED := 0
global F04_PROGRESS := EnvGet("AQ_TEST_PROGRESS")
if F04_PROGRESS = ""
    F04_PROGRESS := A_Temp "\ahquiver-f04-progress.log"
try FileDelete(F04_PROGRESS)
F04Trace("LOADED")
SetTimer(F04Watchdog, -15000)
F04RunTest("Windows Terminal unsupported without proof", TestF04WindowsTerminalUnsupportedWithoutProof)
F04RunTest("stale target rejected", TestF04StaleTargetRejected)
F04RunTest("fallback disabled by default", TestF04FallbackDisabledByDefault)
F04RunTest("fallback explicitly degraded and restores", TestF04FallbackIsExplicitlyDegradedAndRestores)
F04RunTest("probe truth states", TestF04ProbeTruthStates)
F04RunTest("module lifecycle", TestF04ModuleLifecycle)
SetTimer(F04Watchdog, 0)
F04Trace("RESULT passed=" F04_TEST_PASSED " failed=" F04_TEST_FAILED)
FileAppend("RESULT passed=" F04_TEST_PASSED " failed=" F04_TEST_FAILED "`n", "*")
ExitApp(F04_TEST_FAILED = 0 ? 0 : 1)

F04Watchdog() {
    F04Trace("WATCHDOG suite exceeded 15 seconds")
    ExitApp(2)
}
F04RunTest(name, callback) {
    global F04_TEST_PASSED, F04_TEST_FAILED
    F04Trace("RUN " name)
    try {
        callback.Call()
        F04_TEST_PASSED += 1
        F04Trace("PASS " name)
        FileAppend("PASS " name "`n", "*")
    } catch as testError {
        F04_TEST_FAILED += 1
        F04Trace("FAIL " name ": " testError.Message)
        FileAppend("FAIL " name ": " testError.Message "`n", "*")
    }
}
F04Trace(message) {
    global F04_PROGRESS
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", F04_PROGRESS, "UTF-8")
}
AssertF04True(value, message := "Expected true") {
    if !value
        throw Error(message)
}
AssertF04False(value, message := "Expected false") {
    if value
        throw Error(message)
}
AssertF04Equal(expected, actual, message := "") {
    if expected != actual {
        detail := message != "" ? message ": " : ""
        throw Error(detail "expected=" expected " actual=" actual)
    }
}
F04TempPath(label) => A_Temp "\ahquiver-f04-" label "-" A_TickCount "-" Random(1000, 9999) ".tmp"
F04Delete(path) {
    if FileExist(path) {
        try FileDelete(path)
    }
}
