#Requires AutoHotkey v2.0

#Include ..\src\core\Result.ahk
#Include ..\src\core\WindowQuery.ahk
#Include ..\src\modules\F01_CloseMatchingWindows.ahk

smokeTitle := "AHQuiver F01 Smoke Target"
controlTitle := "AHQuiver F01 Smoke Control"

targetGui := Gui(, smokeTitle)
peerGui := Gui(, smokeTitle)
controlGui := Gui(, controlTitle)

targetGui.OnEvent("Close", (*) => targetGui.Destroy())
peerGui.OnEvent("Close", (*) => peerGui.Destroy())
controlGui.OnEvent("Close", (*) => controlGui.Destroy())

targetGui.Show("w240 h80")
peerGui.Show("w240 h80")
controlGui.Show("w240 h80")
Sleep(100)

windows := AQWindowQuery()
target := windows.Describe(targetGui.Hwnd)
service := F01CloseMatchingWindowsService(windows, Map(
    "protect_self", false,
    "protect_shell", true,
    "match_title", true,
    "confirm", false,
    "close_timeout_ms", 1000
))

try {
    result := service.Execute(target)
    if !result.IsOk()
        throw Error("F01 smoke action failed: " result.Message)
    if result.Data["candidate"] != 2
        throw Error("Expected 2 matching GUI candidates, got " result.Data["candidate"])
    if result.Data["closed"] != 2
        throw Error("Expected 2 GUI windows closed, got " result.Data["closed"])
    if WinExist("ahk_id " controlGui.Hwnd) = 0
        throw Error("Control GUI was closed unexpectedly")

    FileAppend("PASS F01 real Win32 window-close smoke`n", "*")
    controlGui.Destroy()
    ExitApp(0)
} catch as err {
    try targetGui.Destroy()
    try peerGui.Destroy()
    try controlGui.Destroy()
    FileAppend("FAIL F01 real Win32 window-close smoke: " err.Message "`n", "*")
    ExitApp(1)
}
