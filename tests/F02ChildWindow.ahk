#Requires AutoHotkey v2.0
#SingleInstance Off

childGui := Gui(, "AHQuiver F02 Child Original")
childGui.AddText(, "AHQuiver F02 launcher smoke child")
childGui.OnEvent("Close", (*) => ExitApp())
childGui.Show("w320 h100")
Persistent(true)
