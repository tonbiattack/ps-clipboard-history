Option Explicit

' Start the long-running watcher without creating a console window.
Dim shell, fileSystem, scriptDirectory, powershellPath, watcherPath, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
powershellPath = fileSystem.BuildPath(fileSystem.GetSpecialFolder(0), "System32\\WindowsPowerShell\\v1.0\\powershell.exe")
watcherPath = fileSystem.BuildPath(scriptDirectory, "clipboard-watch.ps1")

command = Chr(34) & powershellPath & Chr(34) & _
    " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File " & _
    Chr(34) & watcherPath & Chr(34)

shell.Run command, 0, False
