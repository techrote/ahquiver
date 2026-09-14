$ErrorActionPreference = 'Stop'

if (-not $env:AHK_EXE) { throw 'AHK_EXE is not set.' }

function Invoke-AhkGate {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [int]$TimeoutMs = 20000
    )
    Write-Host "=== $Name ==="
    $slug = ($Name -replace '[^A-Za-z0-9]+','-').Trim('-').ToLowerInvariant()
    $stdout = Join-Path $env:RUNNER_TEMP "$slug.stdout.txt"
    $stderr = Join-Path $env:RUNNER_TEMP "$slug.stderr.txt"
    $progress = Join-Path $env:RUNNER_TEMP "$slug.progress.txt"
    $oldProgress = $env:AQ_TEST_PROGRESS
    $env:AQ_TEST_PROGRESS = $progress
    try {
        $process = Start-Process -FilePath $env:AHK_EXE -ArgumentList $Arguments -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        $timedOut = -not $process.WaitForExit($TimeoutMs)
        if ($timedOut) {
            try { $process.Kill($true) } catch { $process.Kill() }
            $process.WaitForExit()
        }
        if (Test-Path $progress) { Get-Content $progress | ForEach-Object { Write-Host $_ } }
        if (Test-Path $stdout) { Get-Content $stdout | ForEach-Object { Write-Host $_ } }
        if (Test-Path $stderr) { Get-Content $stderr | ForEach-Object { Write-Host "STDERR: $_" } }
        if ($timedOut) { throw "$Name exceeded timeout." }
        if ($process.ExitCode -ne 0) { throw "$Name failed with AutoHotkey exit code $($process.ExitCode)." }
    } finally {
        $env:AQ_TEST_PROGRESS = $oldProgress
    }
}

Invoke-AhkGate 'Foundation tests' @('/ErrorStdOut', '.\tests\TestRunner.ahk')
Invoke-AhkGate 'F01 feature tests' @('/ErrorStdOut', '.\tests\F01TestRunner.ahk')
Invoke-AhkGate 'F01 real window-close smoke' @('/ErrorStdOut', '.\tests\F01WindowSmoke.ahk')
Invoke-AhkGate 'F02 feature tests' @('/ErrorStdOut', '.\tests\F02TestRunner.ahk')
Invoke-AhkGate 'F02 real process/title smoke' @('/ErrorStdOut', '.\tests\F02ProcessSmoke.ahk')

Write-Host '=== Windows Terminal CLI availability probe ==='
$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($wt) {
    & $wt.Source -? | Select-Object -First 20 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "wt.exe help probe failed: $LASTEXITCODE" }
} else {
    Write-Host 'SKIP: wt.exe not installed'
}

Invoke-AhkGate 'F03 feature tests' @('/ErrorStdOut', '.\tests\F03TestRunner.ahk')
Invoke-AhkGate 'F03 enabled hotkey lifecycle probe' @('/ErrorStdOut', '.\src\AHQuiver.ahk', '--probe-startup', '--headless', '--config', '.\tests\F03EnabledStartup.ini')
Invoke-AhkGate 'F04 feature tests' @('/ErrorStdOut', '.\tests\F04TestRunner.ahk')
Invoke-AhkGate 'F04 real focus-preserving paste smoke' @('/ErrorStdOut', '.\tests\F04RealPasteSmoke.ahk')
Invoke-AhkGate 'F05 feature tests' @('/ErrorStdOut', '.\tests\F05TestRunner.ahk')
Invoke-AhkGate 'F05 enabled module startup probe' @('/ErrorStdOut', '.\src\AHQuiver.ahk', '--probe-startup', '--headless', '--config', '.\tests\F05EnabledStartup.ini')
Invoke-AhkGate 'F06 feature tests' @('/ErrorStdOut', '.\tests\F06TestRunner.ahk')
Invoke-AhkGate 'F06 real worker-safe tracker restart smoke' @('/ErrorStdOut', '.\tests\F06ProcessSmoke.ahk') 30000
Invoke-AhkGate 'F06 enabled module startup probe' @('/ErrorStdOut', '.\src\AHQuiver.ahk', '--probe-startup', '--headless', '--config', '.\tests\F06EnabledStartup.ini')
Invoke-AhkGate 'F07 feature tests' @('/ErrorStdOut', '.\tests\F07TestRunner.ahk')
Invoke-AhkGate 'F07 real tray/GUI dynamic registry smoke' @('/ErrorStdOut', '.\tests\F07GuiSmoke.ahk')
Invoke-AhkGate 'F07 enabled module and tray startup probe' @('/ErrorStdOut', '.\src\AHQuiver.ahk', '--probe-startup', '--config', '.\tests\F07EnabledStartup.ini')
Invoke-AhkGate 'F08 feature tests' @('/ErrorStdOut', '.\tests\F08TestRunner.ahk')
Invoke-AhkGate 'F08 enabled profile/hotkey lifecycle probe' @('/ErrorStdOut', '.\src\AHQuiver.ahk', '--probe-startup', '--headless', '--config', '.\tests\F08EnabledStartup.ini')
Invoke-AhkGate 'F09 feature tests' @('/ErrorStdOut', '.\tests\F09TestRunner.ahk')
Invoke-AhkGate 'F09 enabled synthetic-source lifecycle probe' @('/ErrorStdOut', '.\src\AHQuiver.ahk', '--probe-startup', '--headless', '--config', '.\tests\F09EnabledStartup.ini')
Invoke-AhkGate 'F10 feature tests' @('/ErrorStdOut', '.\tests\F10TestRunner.ahk')
Invoke-AhkGate 'F10 unsupported-safe startup probe' @('/ErrorStdOut', '.\src\AHQuiver.ahk', '--probe-startup', '--headless', '--config', '.\tests\F10EnabledStartup.ini')
Invoke-AhkGate 'Headless startup probe' @('/ErrorStdOut', '.\src\AHQuiver.ahk', '--probe-startup', '--headless', '--config', '.\config\ahquiver.example.ini')

Write-Host 'ALL WINDOWS CI GATES PASSED'
