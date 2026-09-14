#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\core\ModuleHost.ahk
#Include ..\src\core\Ui.ahk
#Include ..\src\modules\F07_ControlSurface.ahk
#Include F07Tests.ahk

global F07_TEST_PASSED := 0
global F07_TEST_FAILED := 0
global F07_PROGRESS := EnvGet("AQ_TEST_PROGRESS")
if F07_PROGRESS = ""
    F07_PROGRESS := A_Temp "\ahquiver-f07-progress.log"
try FileDelete(F07_PROGRESS)
F07Trace("LOADED")
SetTimer(F07Watchdog, -15000)
F07RunTest("dynamic action population", TestF07DynamicActionPopulation)
F07RunTest("dispatch uses registry action id and generic params", TestF07DispatchUsesRegistryActionIdAndGenericParams)
F07RunTest("parameter errors do not dispatch", TestF07ParameterErrorsDoNotDispatch)
F07RunTest("module and capability states represented", TestF07ModuleAndCapabilityStatesRepresented)
F07RunTest("failure history payload-free and global", TestF07FailureHistoryIsPayloadFreeAndGlobal)
F07RunTest("cancelled action omitted from failures", TestF07CancelledActionNotRecordedAsFailure)
F07RunTest("failure history limit", TestF07FailureHistoryLimit)
F07RunTest("module lifecycle and same registry path", TestF07ModuleLifecycleAndSameRegistryPath)
F07RunTest("core registry list snapshots", TestF07CoreRegistryLists)
SetTimer(F07Watchdog, 0)
F07Trace("RESULT passed=" F07_TEST_PASSED " failed=" F07_TEST_FAILED)
FileAppend("RESULT passed=" F07_TEST_PASSED " failed=" F07_TEST_FAILED "`n", "*")
ExitApp(F07_TEST_FAILED = 0 ? 0 : 1)

F07Watchdog() {
    F07Trace("WATCHDOG suite exceeded 15 seconds")
    ExitApp(2)
}

F07RunTest(name, callback) {
    global F07_TEST_PASSED, F07_TEST_FAILED
    F07Trace("RUN " name)
    try {
        callback.Call()
        F07_TEST_PASSED += 1
        F07Trace("PASS " name)
        FileAppend("PASS " name "`n", "*")
    } catch as err {
        F07_TEST_FAILED += 1
        F07Trace("FAIL " name ": " err.Message)
        FileAppend("FAIL " name ": " err.Message "`n", "*")
    }
}

F07Trace(message) {
    global F07_PROGRESS
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", F07_PROGRESS, "UTF-8")
}

AssertF07True(value, message := "Expected true") {
    if !value
        throw Error(message)
}
AssertF07False(value, message := "Expected false") {
    if value
        throw Error(message)
}
AssertF07Equal(expected, actual, message := "") {
    if expected != actual
        throw Error((message != "" ? message ": " : "") "expected=" expected " actual=" actual)
}
