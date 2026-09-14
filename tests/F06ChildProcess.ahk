#Requires AutoHotkey v2.0
#SingleInstance Off

role := A_Args.Length ? A_Args[1] : "unknown"
childGui := Gui(, "AHQuiver F06 synthetic " role)
childGui.AddText("w260", "Synthetic F06 process: " role)
childGui.OnEvent("Close", (*) => ExitApp(0))
childGui.Show("w300 h90")
Persistent(true)
