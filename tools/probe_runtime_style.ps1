# probe_runtime_style.ps1
# Captures window style bits, ex-style bits, and NC metrics at multiple
# points during the app's startup lifetime to catch any post-creation
# "borderless / full-client" adjustment that strips the native frame.
#
# Usage:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File tools\probe_runtime_style.ps1

param(
    [string]$ExePath       = "build\debug\bin\desktop_file_tool.exe",
    [int]   $PollIntervalMs = 50,   # how often to sample
    [int]   $TotalWindowMs  = 4000  # how long to probe
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# P/Invoke declarations
# ---------------------------------------------------------------------------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class WinApi {
    public const int GWL_STYLE   = -16;
    public const int GWL_EXSTYLE = -20;

    // Window styles we care about
    public const uint WS_OVERLAPPED   = 0x00000000;
    public const uint WS_CAPTION      = 0x00C00000;
    public const uint WS_BORDER       = 0x00800000;
    public const uint WS_DLGFRAME     = 0x00400000;
    public const uint WS_THICKFRAME   = 0x00040000;
    public const uint WS_SYSMENU      = 0x00080000;
    public const uint WS_MINIMIZEBOX  = 0x00020000;
    public const uint WS_MAXIMIZEBOX  = 0x00010000;
    public const uint WS_POPUP        = 0x80000000;
    public const uint WS_CLIPCHILDREN = 0x02000000;
    public const uint WS_CLIPSIBLINGS = 0x04000000;
    public const uint WS_VISIBLE      = 0x10000000;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindowW(string cls, string title);

    [DllImport("user32.dll")]
    public static extern uint GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(
        IntPtr hwnd, uint dwAttribute, out RECT pvAttribute, uint cbAttribute);

    public const uint DWMWA_EXTENDED_FRAME_BOUNDS = 9;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public static string StyleToFlags(uint s) {
        var flags = new System.Collections.Generic.List<string>();
        if ((s & WS_POPUP)        != 0) flags.Add("WS_POPUP");
        if ((s & WS_CAPTION)      != 0) flags.Add("WS_CAPTION");
        if ((s & WS_BORDER)       != 0) flags.Add("WS_BORDER");
        if ((s & WS_DLGFRAME)     != 0) flags.Add("WS_DLGFRAME");
        if ((s & WS_THICKFRAME)   != 0) flags.Add("WS_THICKFRAME");
        if ((s & WS_SYSMENU)      != 0) flags.Add("WS_SYSMENU");
        if ((s & WS_MINIMIZEBOX)  != 0) flags.Add("WS_MINIMIZEBOX");
        if ((s & WS_MAXIMIZEBOX)  != 0) flags.Add("WS_MAXIMIZEBOX");
        if ((s & WS_CLIPCHILDREN) != 0) flags.Add("WS_CLIPCHILDREN");
        if ((s & WS_CLIPSIBLINGS) != 0) flags.Add("WS_CLIPSIBLINGS");
        if ((s & WS_VISIBLE)      != 0) flags.Add("WS_VISIBLE");
        return string.Join(" | ", flags);
    }
}
"@ -PassThru | Out-Null

# ---------------------------------------------------------------------------
# Frame-critical flags that must always be present for native chrome
# ---------------------------------------------------------------------------
$REQUIRED_STYLE = [WinApi]::WS_CAPTION -bor [WinApi]::WS_THICKFRAME -bor [WinApi]::WS_SYSMENU
$FORBIDDEN_STYLE = [WinApi]::WS_POPUP

# ---------------------------------------------------------------------------
# Launch app
# ---------------------------------------------------------------------------
$exeAbs = Join-Path (Get-Location) $ExePath
if (-not (Test-Path $exeAbs)) {
    Write-Error "EXE not found: $exeAbs"
    exit 1
}

Write-Host "Launching: $exeAbs"
$appProc = Start-Process -FilePath $exeAbs -PassThru

Write-Host "PID: $($appProc.Id) — polling for window by title..."

# ---------------------------------------------------------------------------
# Wait for window to appear (up to 12s — app has extensive startup setup)
# Try both class name and title since class may differ across builds.
# ---------------------------------------------------------------------------
$hwnd = [IntPtr]::Zero
$waitStart = [System.Diagnostics.Stopwatch]::StartNew()
while ($waitStart.ElapsedMilliseconds -lt 12000) {
    # Must pass both class AND title — PowerShell $null maps to "" not null,
    # and FindWindowW(class, "") only matches windows with empty titles.
    $h = [WinApi]::FindWindowW("NGKsUIRuntimeWindowClass", "NGKsUI Runtime Desktop File Tool")
    if ($h -ne [IntPtr]::Zero) {
        $hwnd = $h
        break
    }
    Start-Sleep -Milliseconds 100
}

if ($hwnd -eq [IntPtr]::Zero) {
    Write-Warning "Window not found within 12 seconds. App may have crashed or title mismatch."
    $appProc | Stop-Process -Force -ErrorAction SilentlyContinue
    exit 2
}

$windowAge = $waitStart.ElapsedMilliseconds
Write-Host "Window found at T+${windowAge}ms  HWND=0x$('{0:X}' -f $hwnd.ToInt64())"
Write-Host ""
Write-Host "=== RUNTIME STYLE TIMELINE ==="
Write-Host ("  {0,-8}  {1,-10}  {2,-10}  {3,-6}  {4,-6}  {5,-6}  {6,-6}  {7,-6}  {8}" -f `
    "T+ms","GWL_STYLE","GWL_EXSTYLE","WND_W","WND_H","CLT_W","CLT_H","NC_TOP","STYLE_FLAGS")
Write-Host ("  {0}" -f ("-" * 120))

# ---------------------------------------------------------------------------
# Poll loop
# ---------------------------------------------------------------------------
$probe      = [System.Diagnostics.Stopwatch]::StartNew()
$prevStyle  = 0
$prevExStyle = 0
$mutations  = @()
$samples    = @()

while ($probe.ElapsedMilliseconds -lt $TotalWindowMs) {
    if (-not [WinApi]::IsWindow($hwnd)) {
        Write-Warning "Window closed at T+$($probe.ElapsedMilliseconds)ms"
        break
    }

    $style   = [WinApi]::GetWindowLong($hwnd, [WinApi]::GWL_STYLE)
    $exStyle = [WinApi]::GetWindowLong($hwnd, [WinApi]::GWL_EXSTYLE)

    $wndRect = New-Object WinApi+RECT
    $cltRect = New-Object WinApi+RECT
    [WinApi]::GetWindowRect($hwnd, [ref]$wndRect) | Out-Null
    [WinApi]::GetClientRect($hwnd, [ref]$cltRect)  | Out-Null

    $wndW = $wndRect.Right  - $wndRect.Left
    $wndH = $wndRect.Bottom - $wndRect.Top
    $cltW = $cltRect.Right  - $cltRect.Left
    $cltH = $cltRect.Bottom - $cltRect.Top
    $ncTop = $wndH - $cltH  # rough NC height (title bar + borders)

    $t = $probe.ElapsedMilliseconds
    $flags = [WinApi]::StyleToFlags([uint]$style)

    $row = [PSCustomObject]@{
        T        = $t
        Style    = ("0x{0:X8}" -f $style)
        ExStyle  = ("0x{0:X8}" -f $exStyle)
        WndW     = $wndW
        WndH     = $wndH
        CltW     = $cltW
        CltH     = $cltH
        NcTop    = $ncTop
        Flags    = $flags
    }
    $samples += $row

    # Detect style mutation
    if ($style -ne $prevStyle -or $exStyle -ne $prevExStyle) {
        if ($prevStyle -ne 0) {
            $mutations += [PSCustomObject]@{
                T       = $t
                OldStyle = ("0x{0:X8}" -f $prevStyle)
                NewStyle = ("0x{0:X8}" -f $style)
                OldFlags = [WinApi]::StyleToFlags([uint]$prevStyle)
                NewFlags = [WinApi]::StyleToFlags([uint]$style)
                WS_CAPTION_lost     = (($prevStyle -band [WinApi]::WS_CAPTION)    -ne 0) -and (($style -band [WinApi]::WS_CAPTION)    -eq 0)
                WS_THICKFRAME_lost  = (($prevStyle -band [WinApi]::WS_THICKFRAME) -ne 0) -and (($style -band [WinApi]::WS_THICKFRAME) -eq 0)
                WS_POPUP_gained     = (($prevStyle -band [WinApi]::WS_POPUP)      -eq 0) -and (($style -band [WinApi]::WS_POPUP)      -ne 0)
            }
        }
        $prevStyle   = $style
        $prevExStyle = $exStyle
    }

    Write-Host ("  {0,-8}  {1,-10}  {2,-10}  {3,-6}  {4,-6}  {5,-6}  {6,-6}  {7,-6}  {8}" -f `
        $t, ("0x{0:X8}" -f $style), ("0x{0:X8}" -f $exStyle), $wndW, $wndH, $cltW, $cltH, $ncTop, $flags)

    Start-Sleep -Milliseconds $PollIntervalMs
}

Write-Host ""
Write-Host "=== MUTATION SUMMARY ==="
if ($mutations.Count -eq 0) {
    Write-Host "  No style mutations detected during the probe window."
    Write-Host "  [Source-level styles are correct AND stable at runtime]"
    Write-Host "  => visual NC frame absence is NOT caused by a post-creation style strip."
    Write-Host "  => root cause is DWM NC composition deferral / DXGI swapchain timing."
} else {
    Write-Warning "  STYLE MUTATIONS FOUND ($($mutations.Count)):"
    foreach ($m in $mutations) {
        Write-Host ("  T+{0}ms  {1} => {2}" -f $m.T, $m.OldStyle, $m.NewStyle)
        if ($m.WS_CAPTION_lost)    { Write-Warning "    !! WS_CAPTION was STRIPPED" }
        if ($m.WS_THICKFRAME_lost) { Write-Warning "    !! WS_THICKFRAME was STRIPPED" }
        if ($m.WS_POPUP_gained)    { Write-Warning "    !! WS_POPUP was ADDED (borderless mode activated)" }
        Write-Host "    Before: $($m.OldFlags)"
        Write-Host "    After:  $($m.NewFlags)"
    }
}

Write-Host ""
Write-Host "=== NC HEIGHT ANALYSIS ==="
$firstSample = $samples | Select-Object -First 1
$lastSample  = $samples | Select-Object -Last 1
Write-Host ("  First sample (T+{0}ms): NC_TOP={1}px  [title bar + borders approx]" -f $firstSample.T, $firstSample.NcTop)
Write-Host ("  Last  sample (T+{0}ms): NC_TOP={1}px" -f $lastSample.T, $lastSample.NcTop)

$zeroNcSamples = $samples | Where-Object { $_.NcTop -le 0 }
if ($zeroNcSamples.Count -gt 0) {
    Write-Warning "  NC height was 0 or negative during $($zeroNcSamples.Count) sample(s)."
    Write-Warning "  => Window may briefly be in full-client/borderless state during startup."
} else {
    Write-Host "  NC height was consistently positive (native frame geometry intact)."
}

Write-Host ""
Write-Host "=== KEY DIAGNOSTICS ==="
$firstStyle = $samples[0].Style
$captionPresent   = ([uint]([Convert]::ToUInt32($firstStyle.Replace("0x",""), 16)) -band [WinApi]::WS_CAPTION)    -ne 0
$thickframePresent= ([uint]([Convert]::ToUInt32($firstStyle.Replace("0x",""), 16)) -band [WinApi]::WS_THICKFRAME)  -ne 0
$popupPresent     = ([uint]([Convert]::ToUInt32($firstStyle.Replace("0x",""), 16)) -band [WinApi]::WS_POPUP)       -ne 0
Write-Host "  first_sample_WS_CAPTION=$(    if ($captionPresent)    {'PRESENT'} else {'MISSING'} )"
Write-Host "  first_sample_WS_THICKFRAME=$( if ($thickframePresent) {'PRESENT'} else {'MISSING'} )"
Write-Host "  first_sample_WS_POPUP=$(      if ($popupPresent)      {'ABSENT' } else {'PRESENT'} )"
Write-Host "  style_mutations_count=$($mutations.Count)"
Write-Host "  borderless_strip_detected=$(  if (($mutations | Where-Object { $_.WS_CAPTION_lost -or $_.WS_POPUP_gained }).Count -gt 0) {'YES - FIX STYLE MUTATION'} else {'NO'} )"

Write-Host ""
Write-Host "Probe complete. Leaving app open for manual inspection."
Write-Host "Close the app window manually when done, or run: Stop-Process -Id $($appProc.Id) -Force"
