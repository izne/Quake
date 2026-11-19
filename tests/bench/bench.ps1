# Automated timedemo benchmark harness for the Quake Watcom/DOS4GW port.
#
# Runs a DOS exe (our quake486.exe or stock QUAKE.EXE) under DOSBox with a
# fixed cycle count, starts the timedemo from the command line (no keystrokes
# needed - SendKeys proved unreliable due to focus stealing) and polls for the
# result file:
#   - our build  : timedemo.txt   (hook in CL_FinishTimeDemo, cl_demo.c)
#   - stock build: id1\qconsole.log  (run with -condebug)
#
# Examples:
#   # benchmark the current Watcom build (copy it into the run dir first)
#   .\bench.ps1 -GameExe quake486.exe -GameArgs "+timedemo demo1"
#
#   # A/B: q_rsqrt off vs on (build with `wmake QRSQRT=` / `wmake`)
#   .\bench.ps1 -GameSrc ..\..\WinQuake\quake486.exe -GameExe quake486.exe `
#               -ResultName timedemo.txt -DonePattern "fps"
#
#   # stock Quake 1.06 baseline (DJGPP/CWSDPMI binary, needs CWSDPMI.EXE)
#   .\bench.ps1 -GameExe QUAKE.EXE -GameArgs "-condebug +timedemo demo1" `
#               -ResultName "id1\qconsole.log" -DonePattern "fps"
#
param(
    # DOSBox install
    [string]$DosBox = "${env:ProgramFiles(x86)}\DOSBox-0.74-3\DOSBox.exe",
    # directory holding ID1\PAK0.PAK, dos4gw.exe, QUAKE.EXE, CWSDPMI.EXE
    [string]$QuakeData = 'C:\Users\izne\Downloads\_Quake1',
    # local (non-UNC!) working dir that DOSBox mounts as C:
    [string]$RunDir = 'C:\Users\izne\AppData\Local\Temp\opencode\run',
    # scratch dir for generated conf / log / screenshot
    [string]$Scratch = 'C:\Users\izne\AppData\Local\Temp\opencode',
    # optional: copy this built exe into $RunDir before running
    [string]$GameSrc = '',
    [string]$GameExe = 'quake486.exe',
    [string]$GameArgs = '+timedemo demo1',
    # file (relative to $RunDir) that receives the result
    [string]$ResultName = 'timedemo.txt',
    # wait until the result file both has content AND matches this regex
    [string]$DonePattern = '',
    [string]$Cycles = 'fixed 80000',
    [int]$BootWait = 8,
    [int]$MaxWait = 600,
    [string]$Out = ''
)
if ($Out -eq '') { $Out = Join-Path $Scratch 'bench_shot.png' }

# generate a per-run DOSBox conf (cycles / exe / args are parameterised)
$confBody = @"
[sdl]
autofit=false
output=surface
waitonerror=false

[dosbox]
memsize=16
machine=svga_s3

[cpu]
core=dynamic
cputype=486
cycles=$Cycles

[mixer]
[midi]
[sblaster]
sbtype=sb16
[gus]
gus=false

[autoexec]
@echo off
mount c "$RunDir"
c:
$GameExe $GameArgs
"@
$runConf = Join-Path $Scratch 'bench_run.conf'
Set-Content -Path $runConf -Value $confBody
Write-Output "conf: $GameExe $GameArgs @ cycles=$Cycles"

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32b {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

# --- ensure run-dir prerequisites (the OS temp cleaner may purge big files) ---
$srcPak  = Join-Path $QuakeData 'ID1\PAK0.PAK'
$srcStub = Join-Path $QuakeData 'dos4gw.exe'
if (-not (Test-Path (Join-Path $RunDir 'dos4gw.exe'))) {
    Copy-Item $srcStub $RunDir -Force; Write-Output "restored dos4gw.exe"
}
if (-not (Test-Path (Join-Path $RunDir 'id1\PAK0.PAK'))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $RunDir 'id1') | Out-Null
    Copy-Item $srcPak (Join-Path $RunDir 'id1') -Force; Write-Output "restored PAK0.PAK"
}
if (-not (Test-Path (Join-Path $RunDir 'id1\autoexec.cfg'))) {
    Set-Content -Path (Join-Path $RunDir 'id1\autoexec.cfg') -Value @(
        '// test-driver bindings for automated runs (F-keys are layout independent)',
        'bind "F1" "toggleconsole"',
        'bind "F2" "map start"',
        'bind "F3" "timedemo demo1"'
    ); Write-Output "restored autoexec.cfg"
}
# stock DJGPP binary needs its DPMI host next to it
if (-not (Test-Path (Join-Path $RunDir 'CWSDPMI.EXE'))) {
    $cws = Join-Path $QuakeData 'CWSDPMI.EXE'
    if (Test-Path $cws) { Copy-Item $cws $RunDir -Force; Write-Output "restored CWSDPMI.EXE" }
}
if ($GameSrc -ne '') {
    Copy-Item $GameSrc (Join-Path $RunDir $GameExe) -Force
    Write-Output "copied $GameSrc -> $RunDir\$GameExe"
}

# kill any leftover DOSBox from previous runs (they would confuse screenshots)
Get-Process -Name DOSBox -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

# fresh result file for this run
$resultFile = Join-Path $RunDir $ResultName
if (Test-Path $resultFile) { Remove-Item $resultFile -Force }

$p = Start-Process -FilePath $DosBox `
     -ArgumentList @("-conf", $runConf, "-noconsole") -PassThru
Write-Output "dosbox pid $($p.Id)"

$script:found = New-Object System.Collections.Generic.List[IntPtr]
$script:cb = [Win32b+EnumWindowsProc]{
    param($h, $l)
    if ([Win32b]::IsWindowVisible($h)) {
        $sb = New-Object System.Text.StringBuilder 512
        [Win32b]::GetWindowText($h, $sb, 512) | Out-Null
        if ($sb.ToString() -like "*DOSBox*") { $script:found.Add($h) }
    }
    return $true
}

$deadline = (Get-Date).AddSeconds(30)
$hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline -and $hwnd -eq [IntPtr]::Zero) {
    if ($p.HasExited) { Write-Output "dosbox exited early"; break }
    $script:found.Clear()
    [Win32b]::EnumWindows($script:cb, [IntPtr]::Zero) | Out-Null
    if ($script:found.Count -gt 0) { $hwnd = $script:found[0] }
    else { Start-Sleep -Milliseconds 400 }
}
if ($hwnd -eq [IntPtr]::Zero) { Write-Output "NO WINDOW"; if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }; exit 1 }

Start-Sleep -Seconds $BootWait
Write-Output "booted, polling for result file '$ResultName'..."

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$titleLogged = $false
while ($sw.Elapsed.TotalSeconds -lt $MaxWait) {
    # result is complete when the file has content (and matches DonePattern if given)
    if (Test-Path $resultFile) {
        $content = Get-Content $resultFile -Raw -ErrorAction SilentlyContinue
        if ($content -and ($DonePattern -eq "" -or $content -match $DonePattern)) { break }
    }
    if (-not $titleLogged -and $sw.Elapsed.TotalSeconds -gt 15) {
        # report what is actually on screen
        $script:found.Clear()
        [Win32b]::EnumWindows($script:cb, [IntPtr]::Zero) | Out-Null
        foreach ($h in $script:found) {
            $sb = New-Object System.Text.StringBuilder 512
            [Win32b]::GetWindowText($h, $sb, 512) | Out-Null
            Write-Output "window: $($sb.ToString())"
        }
        $titleLogged = $true
    }
    Start-Sleep -Seconds 3
}

$benchLog = Join-Path $Scratch 'bench_log.txt'
if (Test-Path $resultFile) {
    Write-Output "RESULT after $([int]$sw.Elapsed.TotalSeconds)s:"
    Get-Content $resultFile | ForEach-Object { Write-Output "  $_" }
    # append to master benchmark log (context + result line)
    $logLine = @("$GameExe | args: $GameArgs | cycles: $Cycles") + (Get-Content $resultFile)
    Add-Content -Path $benchLog -Value $logLine
} else {
    Write-Output "TIMEOUT after $([int]$sw.Elapsed.TotalSeconds)s - no result file"
    Add-Content -Path $benchLog -Value @("$GameExe | args: $GameArgs | cycles: $Cycles | TIMEOUT")
}

# screenshot of final screen for the record
try {
    [Win32b]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    $r = New-Object Win32b+RECT
    [Win32b]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    if ($w -gt 50 -and $ht -gt 50) {
        $bmp = New-Object System.Drawing.Bitmap($w, $ht)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $ht)))
        $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Write-Output "screenshot $Out"
    }
} catch { Write-Output "screenshot failed: $_" }

if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; Write-Output "dosbox stopped" }
