# F05 Windows Terminal / PowerShell smoke

This is a reproducible manual acceptance procedure. CI verifies the delivery engine and safety contracts but does not claim arbitrary shell-semantic correctness.

Record:

- Windows version
- AutoHotkey version
- Windows Terminal version
- PowerShell version/profile
- AHQuiver commit

Use a disposable PowerShell tab and harmless clipboard text such as:

```powershell
Write-Host "F05-one"
Write-Host "F05-two"
```

Check each mode:

1. `whole` — both lines appear as one pasted block; AHQuiver does not rewrite text.
2. `line_by_line` — each logical line is sent followed by Enter with the configured delay.
3. `confirm_each` — reject the second line and verify only the first executes.
4. `cancel` — verify nothing is sent.

Also verify:

- moving focus to another window during a delayed multi-line delivery rejects remaining lines;
- the clipboard is byte-for-byte functionally restored for its formats after completion/failure;
- blank lines and leading/trailing spaces in lines are preserved;
- command text does not appear in AHQuiver logs/result metadata.

Do not use destructive commands for this smoke.
