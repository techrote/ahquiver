#Requires AutoHotkey v2.0
#Warn All, StdOut

#Include ..\src\core\Result.ahk
#Include ..\src\core\ActionRegistry.ahk
#Include ..\src\core\Capability.ahk
#Include ..\src\core\IdentityRegistry.ahk
#Include ..\src\modules\F08_KeybindProfiles.ahk
#Include F08Tests.ahk

passed := 0
failed := 0
progressPath := EnvGet("AQ_TEST_PROGRESS")

tests := [
    ["parsing and parameters", TestF08ParsingAndParameters],
    ["static conflict deterministic winner", TestF08StaticConflictDeterministicWinner],
    ["profile precedence and explicit override", TestF08ProfilePrecedenceAndExplicitOverride],
    ["context enter leave and global fallback", TestF08ContextEnterLeaveAndGlobalFallback],
    ["invalid action local failure", TestF08InvalidActionIsLocal],
    ["emergency bypass", TestF08EmergencyBypass],
    ["identity context shared registry", TestF08IdentityContextUsesSharedRegistry],
    ["module reload and teardown", TestF08ModuleReloadAndTeardown],
    ["same hotkey different profiles dispatch", TestF08SamePhysicalHotkeyDifferentProfilesDispatchesDifferentActions]
]

F08Progress("LOADED")
for test in tests {
    name := test[1]
    callback := test[2]
    F08Progress("RUN " name)
    try {
        callback.Call()
        passed += 1
        F08Progress("PASS " name)
        FileAppend("PASS " name "`n", "*")
    } catch as testError {
        failed += 1
        F08Progress("FAIL " name ": " testError.Message)
        FileAppend("FAIL " name ": " testError.Message "`n", "*")
    }
}

F08Progress("RESULT passed=" passed " failed=" failed)
FileAppend("RESULT passed=" passed " failed=" failed "`n", "*")
ExitApp(failed ? 1 : 0)

F08Progress(message) {
    global progressPath
    if progressPath != ""
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", progressPath)
}

AssertF08True(value, message := "expected true") {
    if !value
        throw Error(message)
}

AssertF08False(value, message := "expected false") {
    if value
        throw Error(message)
}

AssertF08Equal(expected, actual, message := "") {
    if expected != actual
        throw Error((message != "" ? message ": " : "") "expected=" expected " actual=" actual)
}
