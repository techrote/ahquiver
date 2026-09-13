#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\Log.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\WindowQuery.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\ModuleHost.ahk
#Include ..\src\modules\F01_CloseMatchingWindows.ahk
#Include F01Tests.ahk

global F01_TEST_PASSED := 0
global F01_TEST_FAILED := 0
global F01_PROGRESS := EnvGet("AQ_TEST_PROGRESS")
if F01_PROGRESS = ""
    F01_PROGRESS := A_Temp "\ahquiver-f01-progress.log"
try FileDelete(F01_PROGRESS)
F01Trace("LOADED")

SetTimer(F01Watchdog, -15000)
F01RunTest("executable grouping preview", TestF01ExecutableGroupingPreview)
F01RunTest("class and title refinement", TestF01ClassAndTitleRefinement)
F01RunTest("safety and close accounting", TestF01SafetyAndCloseAccounting)
F01RunTest("exclusions and confirmation cancel", TestF01ExclusionsAndConfirmationCancel)
F01RunTest("module lifecycle", TestF01ModuleLifecycle)
SetTimer(F01Watchdog, 0)

F01Trace("RESULT passed=" F01_TEST_PASSED " failed=" F01_TEST_FAILED)
FileAppend("RESULT passed=" F01_TEST_PASSED " failed=" F01_TEST_FAILED "`n", "*")
ExitApp(F01_TEST_FAILED = 0 ? 0 : 1)

F01Watchdog() {
    F01Trace("WATCHDOG suite exceeded 15 seconds")
    ExitApp(2)
}

F01RunTest(name, callback) {
    global F01_TEST_PASSED, F01_TEST_FAILED
    F01Trace("RUN " name)
    try {
        callback.Call()
        F01_TEST_PASSED += 1
        F01Trace("PASS " name)
        FileAppend("PASS " name "`n", "*")
    } catch as err {
        F01_TEST_FAILED += 1
        F01Trace("FAIL " name ": " err.Message)
        FileAppend("FAIL " name ": " err.Message "`n", "*")
    }
}

F01Trace(message) {
    global F01_PROGRESS
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", F01_PROGRESS, "UTF-8")
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
    return A_Temp "\ahquiver-f01-" label "-" A_TickCount "-" Random(1000, 9999) ".tmp"
}

TestDelete(path) {
    if FileExist(path) {
        try FileDelete(path)
    }
}
