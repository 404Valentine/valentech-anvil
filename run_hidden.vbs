Set oShell = CreateObject("WScript.Shell")
oShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & WScript.Arguments(0) & """", 0, False
