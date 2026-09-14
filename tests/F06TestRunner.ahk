#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\Log.ahk
#Include ..\src\core\Config.ahk
#Include ..\src\core\Context.ahk
#Include ..\src\core\WindowQuery.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\Process.ahk
#Include ..\src\modules\F06_TrackerRestart.ahk
#Include F06Tests.ahk

global F06_TEST_PASSED := 0
global F06_TEST_FAILED := 0
global F06_PROGRESS := EnvGet("AQ_TEST_PROGRESS")
if F06_PROGRESS = ""
    F06_PROGRESS := A_Temp "\ahquiver-f06-progress.log"
try FileDelete(F06_PROGRESS)
F06Trace("LOADED")
SetTimer(F06Watchdog, -15000)
F06RunTest("no running tracker launches", TestF06NoRunningLaunchesTracker)
F06RunTest("one tracker graceful restart", TestF06OneTrackerGracefulRestart)
F06RunTest("stale PID becomes fresh launch", TestF06StalePidBecomesFreshLaunch)
F06RunTest("duplicate tracker rejected", TestF06DuplicateTrackerRejected)
F06RunTest("graceful failure does not force by default", TestF06GracefulFailureDoesNotForceByDefault)
F06RunTest("explicit force fallback", TestF06ExplicitForceFallback)
F06RunTest("worker exclusion blocks adoption and termination", TestF06WorkerExclusionBlocksAdoptionAndTermination)
F06RunTest("changed executable rejected", TestF06ExecutableChangedBeforeTerminationRejected)
F06RunTest("relaunch failure reports old PID", TestF06RelaunchFailureReportsOldPid)
F06RunTest("module lifecycle", TestF06ModuleLifecycle)
SetTimer(F06Watchdog, 0)
F06Trace("RESULT passed=" F06_TEST_PASSED " failed=" F06_TEST_FAILED)
FileAppend("RESULT passed=" F06_TEST_PASSED " failed=" F06_TEST_FAILED "`n", "*")
ExitApp(F06_TEST_FAILED = 0 ? 0 : 1)

F06Watchdog() {
    F06Trace("WATCHDOG suite exceeded 15 seconds")
    ExitApp(2)
}

F06RunTest(name, callback) {
    global F06_TEST_PASSED, F06_TEST_FAILED
    F06Trace("RUN " name)
    try {
        callback.Call()
        F06_TEST_PASSED += 1
        F06Trace("PASS " name)
        FileAppend("PASS " name "`n", "*")
    } catch as err {
        F06_TEST_FAILED += 1
        F06Trace("FAIL " name ": " err.Message)
        FileAppend("FAIL " name ": " err.Message "`n", "*")
    }
}

F06Trace(message) {
    global F06_PROGRESS
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", F06_PROGRESS, "UTF-8")
}

AssertF06True(value, message := "Expected true") {
    if !value
        throw Error(message)
}
AssertF06False(value, message := "Expected false") {
    if value
        throw Error(message)
}
AssertF06Equal(expected, actual, message := "") {
    if expected != actual
        throw Error((message != "" ? message ": " : "") "expected=" expected " actual=" actual)
}
