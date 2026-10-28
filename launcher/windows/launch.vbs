' Spoustec BUZZOONS Downloaderu - spusti launch.bat bez viditelneho okna
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "cmd /c """ & dir & "\launch.bat""", 0, False
