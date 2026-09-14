#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\Log.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\Context.ahk
#Include ..\src\core\WindowQuery.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\ClipboardGuard.ahk
#Include ..\src\modules\F05_MultilinePaste.ahk
#Include F05Tests.ahk

global F05_TEST_PASSED := 0
global F05_TEST_FAILED := 0
global F05_PROGRESS := EnvGet("AQ_TEST_PROGRESS")
if F05_PROGRESS = ""
    F05_PROGRESS := A_Temp "\ahquiver-f05-progress.log"
try FileDelete(F05_PROGRESS)
F05Trace("LOADED")
SetTimer(F05Watchdog, -15000)
F05RunTest("line endings blank lines trailing newline", TestF05ClassifierLineEndingsAndTrailingNewline)
F05RunTest("continuation classification", TestF05ContinuationClassification)
F05RunTest("line-by-line preserves lines", TestF05LineByLinePreservesLines)
F05RunTest("confirm-each cancellation", TestF05ConfirmEachCancellation)
F05RunTest("clipboard restore on failure", TestF05ClipboardRestoresOnFailure)
F05RunTest("empty/non-text clipboard rejected", TestF05EmptyClipboardRejected)
F05RunTest("stale target rejected", TestF05StaleTargetRejected)
F05RunTest("control characters rejected", TestF05ControlCharactersRejected)
F05RunTest("invalid pattern local failure", TestF05InvalidPatternIsLocalConfigFailure)
F05RunTest("module lifecycle", TestF05ModuleLifecycle)
SetTimer(F05Watchdog, 0)
F05Trace("RESULT passed=" F05_TEST_PASSED " failed=" F05_TEST_FAILED)
FileAppend("RESULT passed=" F05_TEST_PASSED " failed=" F05_TEST_FAILED "`n", "*")
ExitApp(F05_TEST_FAILED = 0 ? 0 : 1)

F05Watchdog() {
    F05Trace("WATCHDOG suite exceeded 15 seconds")
    ExitApp(2)
}
F05RunTest(name, callback) {
    global F05_TEST_PASSED, F05_TEST_FAILED
    F05Trace("RUN " name)
    try {
        callback.Call()
        F05_TEST_PASSED += 1
        F05Trace("PASS " name)
        FileAppend("PASS " name "`n", "*")
    } catch as err {
        F05_TEST_FAILED += 1
        F05Trace("FAIL " name ": " err.Message)
        FileAppend("FAIL " name ": " err.Message "`n", "*")
    }
}
F05Trace(message) {
    global F05_PROGRESS
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", F05_PROGRESS, "UTF-8")
}
AssertF05True(value, message := "Expected true") {
    if !value
        throw Error(message)
}
AssertF05False(value, message := "Expected false") {
    if value
        throw Error(message)
}
AssertF05Equal(expected, actual, message := "") {
    if expected != actual
        throw Error((message != "" ? message ": " : "") "expected=" expected " actual=" actual)
}
F05TempPath(label) => A_Temp "\ahquiver-f05-" label "-" A_TickCount "-" Random(1000, 9999) ".ini"
F05Delete(path) {
    if FileExist(path)
        try FileDelete(path)
}
