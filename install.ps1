# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# ==============================================================================
# Burgil Industries - C.O.M.P.U.T.E.R. Protocol Bootstrapper
# ==============================================================================
#
# SECURITY TRANSPARENCY NOTICE

# Hi, I'm Burgil, the author, this is the installer for C.O.M.P.U.T.E.R (Completely Open Modular Program Under Trusted Execution Rules),
# an open source modular AI hub / personal assistant platform built for windows.
# Full source: github.com/burgil-industries/computer
# Build instructions: github.com/burgil-industries/computer/blob/main/docs/building.md
#
# the installer is designed to be run via iex (piped from web with irm similar to a lot of open source software out there) e.g. irm localhost:3000/install.ps1 | iex
#
# Why it looks suspicious:
# 1) the hidden powershell window - the installer shows a loading screen in the console while the winforms wizard loads in a separate hidden process, once the gui is ready, the console closes. UX choice, not evasion.
# 2) kernel32.dll / user32.dll imports - used to draw a custom dark themed ui for the installer, custom buttons, custom title bar, standard winforms dark mode techniques, not process ibjection.
# 3) copies itself to %temp% - purely aesthetics, the installer is split into two phases: phase 1 runs in the console and shows an ASCII loading screen and phase 2 is the winforms GUI wizard, the launch phase 2 as a separate process powershell needs a file path, so the script copies itself to %temp% first, phase 1 then exists so you never see a console window sitting behind the GUI. Unless I do that I have 2 windows open during installation, the temp file is not used for anything else, it also cleans up after itself when you close it.
# 4) the logs in %temp% - the logs there will be needed to debug any issues that users will have, they don't contain any special data just literally install logs, once the installation is completed the logs are copied to the chosen app installation directory.
# 5) registry writes - all go to HKCU (current user, not all users) standard add/remove program entry for uninstallation support via windows native ui, optional URI scheme, optional file type association - all behind user visible checkboxes and terms.
# 6) vbs files launching powershell - thin launchers so shortcuts don't flash a console window, UX choice, the ps1 scripts they call are plain text in the install directory, it's all open source and modification is encouraged to fit your own needs and build it however you like, it's free and open source and modular that's the main goal and on top of that it's also gonna be a smart personal assistant, cool right?
# 7) update with command execution - I listened to the risk, and improved the updater, any software have an updater, this one is NOT automatic and has to be manually triggered by the user, the updater will now show an explicit allow / skip / cancel dialog before running any patch commands, there is no silent arbitrary execution, it all has to be manually invoked and approved by the user, especially in the new version.
#
# Why don't I just code sign? well I don't have a budget for an EV code signing certificates (really expensive) so I ship a powershell installer and make it open source instead of a signed exe. the entire installer is reproducible from source via the build.ps1 file in the repo, if you see anything that looks wrong, please open an issue on GitHub, Thanks!
# -----------------------------------------------------------------------------
# COMPUTER (Completely Open Modular Program Under Trusted Execution Rules) is
# a fully open-source modular AI hub.  Every line of this installer is public:
#   https://github.com/burgil-industries/computer
#
# This file may trigger heuristic warnings in antivirus products because it
# uses several techniques that are also found in malware.  Each is explained
# below so you can verify the intent yourself.
#
# WHY THIS SCRIPT LAUNCHES A HIDDEN POWERSHELL WINDOW
#   A graphical installer (WinForms) cannot coexist cleanly with a visible
#   console window.  The first run shows an ASCII progress bar in the console
#   while the WinForms wizard loads in a hidden process.  Once the wizard is
#   ready the console exits.  The hidden flag is for UX (no black terminal
#   behind the wizard), NOT to evade detection.  Source: lines below labelled
#   "Credits splash + relaunch as hidden process".
#
# WHY THIS SCRIPT COPIES ITSELF TO %TEMP%
#   The installer is split into two phases to avoid showing both a console
#   window and a GUI window at the same time.  Phase 1 (the original process)
#   shows an ASCII loading screen in the console.  It launches Phase 2 as a
#   hidden process (the WinForms wizard) and then exits - so the user only
#   ever sees one window.  To launch a new PowerShell process you need a file
#   path, so the script copies itself to %TEMP% first.  When already running
#   from a file on disk (PSCommandPath is set) it just copies that file;
#   when piped via `iex` it writes its own source text to the temp path.
#   The temp file is referenced by $script:setupTmp and only serves this
#   purpose - it is not used to persist anything after the installer exits.
#
# WHY THIS SCRIPT IMPORTS kernel32.dll / user32.dll
#   The installer draws a fully custom dark-themed UI (DarkButton,
#   DarkProgressBar, dark title bar).  These controls are compiled from C#
#   source (installer/controls/) and require P/Invoke calls to:
#     GetConsoleWindow / ShowWindow  - hide the console once the wizard opens
#     GetWindowLong / SetWindowLong  - enable dark-mode title bar (DWMWA)
#     SendMessage                    - send WM_DWMCOLORIZATIONCHANGED to apply
#   None of these calls are used for process injection, keylogging, or any
#   other malicious purpose.
#
# WHY THIS SCRIPT REGISTERS REGISTRY KEYS
#   All registry writes are in HKCU (current user only, no admin required).
#   They cover standard installer operations: Add/Remove Programs entry,
#   optional URI scheme (computer://), optional file type (.computer), and
#   optional right-click menu - all gated behind user-visible checkboxes on
#   the Confirm page and all reversible by the included Uninstaller.
#
# WHY VBS FILES LAUNCH POWERSHELL
#   check-update.vbs, repair.vbs, uninstall.vbs, router.vbs use WScript to
#   invoke PowerShell.  VBS is used as a thin launcher so double-clicking a
#   shortcut does not flash a console window.  The PowerShell scripts they
#   invoke are plain-text files written to the install directory that you can
#   read at any time.
#
# OPEN SOURCE AUDIT
#   Full source, build instructions, and change history are at:
#   https://github.com/burgil-industries/computer
#   The generated install.ps1 is reproducible from source via .\build.ps1.
# -----------------------------------------------------------------------------

$APP_NAME = "COMPUTER"
$PUBLISHER = "Burgil Industries"
$APP_NAME_LOW  = $APP_NAME.ToLower()
$APP_PROTO = $APP_NAME_LOW -replace '\.', ''
$APP_VERSION = "1.0.0"

# --- Credits splash + relaunch as hidden process ----------------------------
# First run: show credits for 3 s, then re-exec hidden so only the WinForms
# window appears in the taskbar.  Second run (HEADLESS=1): skip straight through.
if (-not $env:COMPUTER_SETUP_HEADLESS) {
    $env:COMPUTER_SETUP_HEADLESS = "1"

    # Phase 1 -> Phase 2 handoff.
    # Copy self to %TEMP% so we have a file path to pass to the new process,
    # then start it hidden.  The current (console) process shows the loading
    # screen while Phase 2 initialises, then exits - leaving only the GUI
    # window visible.  The hidden flag prevents a second terminal from
    # appearing behind the wizard; the process is still visible in Task Manager.
    $script:setupTmp = "$env:TEMP\computer_setup_launch.ps1"
    $tmp = $script:setupTmp
    if ($PSCommandPath) {
        Copy-Item $PSCommandPath $tmp -Force -ErrorAction SilentlyContinue
    } else {
        [System.IO.File]::WriteAllText($tmp,
            $MyInvocation.MyCommand.ScriptBlock.ToString(),
            [System.Text.Encoding]::UTF8)
    }
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NonInteractive -WindowStyle Hidden -File `"$tmp`""

    # --- ASCII art (visible in the console while installer loads) ------
    Clear-Host
    Write-Host "   ___ ___  __  __ ___ _   _ _____ ___ ___ " -ForegroundColor Cyan
    Write-Host "  / __/ _ \|  \/  | _ \ | | |_   _| __| _ \" -ForegroundColor Cyan
    Write-Host " | (_| (_) | |\/| |  _/ |_| | | | | _||   /" -ForegroundColor Cyan
    Write-Host "  \___\___/|_|  |_|_|  \___/  |_| |___|_|_\ " -ForegroundColor Cyan
    Write-Host ""
    Write-Host " COMPLETELY OPEN MODULAR PROGRAM UNDER TRUSTED EXECUTION RULES" -ForegroundColor Green
    Write-Host " (c) 2026 Burgil Industries | computer.burgil.dev" -ForegroundColor DarkGray
    $spin = @('/', '-', '\', '-')
    try { [Console]::CursorVisible = $false } catch {}
    for ($p = 0; $p -le 40; $p++) {
        $bar = ('=' * $p).PadRight(40)
        $pct = [int]($p / 40 * 100)
        Write-Host "`r  Setup Wizard Loading...  [$bar] $pct%  $($spin[$p % 4])" -NoNewline -ForegroundColor Green
        Start-Sleep -Milliseconds 75
    }
    Write-Host "`r  Setup Wizard Loading...  [$('=' * 40)] 100%   " -ForegroundColor Green
    Write-Host ""
    $env:COMPUTER_SETUP_HEADLESS = $null
    exit
}
Remove-Item Env:COMPUTER_SETUP_HEADLESS -ErrorAction SilentlyContinue
$script:setupTmp = "$env:TEMP\computer_setup_launch.ps1"
$ICON_URL      = "http://localhost:3000/favicon.ico"
$UPDATE_URL    = "http://localhost:3000/updates"
$AD_URL        = "http://localhost:3000/ads/softwisor.com.png"   # URL to a 480x82 banner image - leave empty to show placeholder
$AD_LINK       = "https://softwisor.com/"   # URL opened when the banner is clicked - leave empty to disable
$CONTACT_US    = "https://computer.burgil.dev/contact"              # shown in the ad placeholder "Contact us" line

$MIN_PYTHON = "3.8"
$MIN_NODE   = "20.0"

# --- Logging - always on, appends per launch, copied to data dir on success ---
$script:_logPath  = "$env:TEMP\$($APP_NAME_LOW)_install.log"
$script:_selfPath    = $PSCommandPath   # path of the running install.ps1 (empty if run via iex)
$script:_selfScript  = if (-not $PSCommandPath) { $MyInvocation.MyCommand.ScriptBlock.ToString() } else { $null }

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [$Level] $Msg" |
        Add-Content -Path $script:_logPath -Encoding UTF8
}

# Separator between runs
"" | Add-Content -Path $script:_logPath -Encoding UTF8
("=" * 60) | Add-Content -Path $script:_logPath -Encoding UTF8
Write-Log "$APP_NAME $APP_VERSION  launched"

# P/Invoke signatures used exclusively for UI purposes:
#   GetConsoleWindow + ShowWindow  -> hide the console once the WinForms wizard is visible
#   GetWindowLong + SetWindowLong  -> enable Windows 11 dark-mode title bar (DWMWA_USE_IMMERSIVE_DARK_MODE)
#   SendMessage                    -> broadcast WM_DWMCOLORIZATIONCHANGED so the dark title bar applies
# These are standard WinForms dark-mode techniques, not process injection or evasion.
if (-not ([System.Management.Automation.PSTypeName]'ConsoleUtils.Window').Type) {
    Add-Type -Name Window -Namespace ConsoleUtils -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool   ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")]   public static extern int    GetWindowLong(IntPtr hWnd, int nIndex);
[DllImport("user32.dll")]   public static extern int    SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
[DllImport("user32.dll", SetLastError=true)]
public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
"@
}
try { [Console]::TreatControlCAsInput = $true } catch {}

# (consent is handled by the wizard's License and Legal Notices pages)

# --- Single-instance check (named mutex) -----------
# Prevents two copies of the installer from running at the same time.
# Named mutex is the standard Windows mechanism for this; the name is
# scoped to this application and does not affect any other process.
$script:_mutex = New-Object System.Threading.Mutex($false, "Global\$($APP_NAME)_Setup_Mutex")
if (-not $script:_mutex.WaitOne(0, $false)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "$APP_NAME Setup is already running.", "$APP_NAME Setup",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    $script:_mutex.Dispose()
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Icon: download to temp, shown in installer window header PictureBox -----
$script:iconTemp  = "$env:TEMP\$($APP_NAME_LOW)_setup.ico"
$script:iconImage = $null   # System.Drawing.Image - for PictureBox (accepts PNG, ICO, anything)

if ($ICON_URL) {
    try {
        if (Test-Path $script:iconTemp) { Remove-Item $script:iconTemp -Force -ErrorAction SilentlyContinue }
        (New-Object System.Net.WebClient).DownloadFile($ICON_URL, $script:iconTemp)
        $script:iconImage = [System.Drawing.Image]::FromFile($script:iconTemp)
    } catch {
        Write-Log "Icon download failed (no internet?): $_" "WARN"
        $choice = [System.Windows.Forms.MessageBox]::Show(
            "Could not download the $APP_NAME icon (no internet connection?).`n`nA default system icon will be used instead.`n`nContinue with setup anyway?",
            "$APP_NAME Setup",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
            $script:_mutex.Dispose()
            exit
        }
        # Fall back to a built-in Windows shell icon (always available, no internet needed)
        try {
            $shell32 = [System.Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\System32\shell32.dll")
            $script:iconImage = $shell32.ToBitmap()
        } catch {
            Write-Log "Fallback icon also failed: $_" "WARN"
        }
    }
}
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Custom controls: DarkButton + GlowProgressBar + DarkMode ----------------
# Add-Type compiles C# source at runtime to create custom WinForms controls.
# This is standard PowerShell WinForms practice for controls that System.Windows.Forms
# does not provide natively (dark-themed button with hover/press states, animated
# progress bar, dark title bar helper).
# The compiled types exist only in the current PowerShell session and are not
# written to disk or injected into any other process.
$refs = @(
    [System.Reflection.Assembly]::GetAssembly([System.Windows.Forms.Control]).Location,
    [System.Reflection.Assembly]::GetAssembly([System.Drawing.Graphics]).Location
)
$_csButton = @"
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class DarkButton : Control {
    private bool _hov, _dn;
    public Color NormalColor { get; set; }
    public Color HoverColor  { get; set; }
    public Color PressColor  { get; set; }
    public Color BorderColor { get; set; }
    public int   Corner      { get; set; }

    public DarkButton() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                 ControlStyles.UserMouse | ControlStyles.SupportsTransparentBackColor, true);
        SetStyle(ControlStyles.Selectable, false);
        BackColor = Color.Transparent;
        TabStop = false;
        Cursor      = Cursors.Hand;
        NormalColor = Color.FromArgb(33, 38, 45);
        HoverColor  = Color.FromArgb(48, 54, 61);
        PressColor  = Color.FromArgb(22, 27, 34);
        BorderColor = Color.FromArgb(48, 54, 61);
        Corner      = 0;
        ForeColor   = Color.FromArgb(240, 246, 252);
        Font        = new Font("Segoe UI", 9.5f);
    }

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    private static extern int SetWindowTheme(IntPtr hwnd, string app, string idList);

    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        SetWindowTheme(Handle, "", "");  // disable all uxtheme styling on this control
        UpdateRegion();
    }

    protected override void OnParentChanged(EventArgs e) {
        base.OnParentChanged(e);
        if (Parent != null) BackColor = Parent.BackColor;
        Invalidate();
    }

    protected override void OnSizeChanged(EventArgs e) {
        base.OnSizeChanged(e);
        UpdateRegion();
    }

    protected override bool ShowFocusCues    { get { return false; } }
    protected override bool ShowKeyboardCues { get { return false; } }
    protected override void OnPaintBackground(PaintEventArgs e) {
        Color bg = Parent != null ? Parent.BackColor : BackColor;
        using (var b = new SolidBrush(bg)) e.Graphics.FillRectangle(b, ClientRectangle);
    }

    protected override void OnMouseEnter(EventArgs e)      { _hov = true;  Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e)      { _hov = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e)  {
        if (e.Button == MouseButtons.Left) { _dn = true; Invalidate(); }
        base.OnMouseDown(e);
    }
    // Intercept WM_LBUTTONUP directly so click fires exactly once,
    // bypassing Control.WmMouseUp whose auto-fire behaviour varies by .NET version.
    protected override void WndProc(ref Message m) {
        const int WM_LBUTTONUP = 0x0202;
        if (m.Msg == WM_LBUTTONUP && Enabled && _dn) {
            int lp = m.LParam.ToInt32();
            int x  = (short)(lp & 0xFFFF);
            int y  = (short)(lp >> 16);
            _dn = false; Invalidate();
            this.Capture = false;  // release OS mouse capture (set by base.WndProc on MouseDown)
            var me = new MouseEventArgs(MouseButtons.Left, 1, x, y, 0);
            if (ClientRectangle.Contains(x, y)) {
                OnClick(EventArgs.Empty);  // may close/destroy the form+controls
            }
            // Guard: OnClick may have destroyed this handle (e.g. form was closed)
            if (IsHandleCreated) {
                OnMouseClick(me);
                OnMouseUp(me);
                DefWndProc(ref m);
            }
            return;
        }
        base.WndProc(ref m);
    }
    protected override void OnEnabledChanged(EventArgs e)  { Invalidate(); base.OnEnabledChanged(e); }

    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics;
        g.SmoothingMode     = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        var rect = new Rectangle(0, 0, Width - 1, Height - 1);

        Color bg = !Enabled ? Color.FromArgb(22,27,34) : _dn ? PressColor : _hov ? HoverColor : NormalColor;
        using (var gp = Round(rect, Corner)) {
            using (var b = new SolidBrush(bg)) g.FillPath(b, gp);
            using (var p = new Pen(BorderColor, 1f)) g.DrawPath(p, gp);
        }

        Color fg = Enabled ? ForeColor : Color.FromArgb(80, ForeColor);
        using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
        using (var b  = new SolidBrush(fg))
            g.DrawString(Text, Font, b, new RectangleF(0, 0, Width, Height), sf);
    }

    void UpdateRegion() {
        if (Width <= 0 || Height <= 0) return;
        if (Corner <= 0) {
            Region = new Region(new Rectangle(0, 0, Width, Height));
            return;
        }
        using (var gp = Round(new Rectangle(0, 0, Width, Height), Corner)) {
            Region = new Region(gp);
        }
    }

    static GraphicsPath Round(Rectangle r, int rad) {
        int d = rad * 2; var p = new GraphicsPath();
        if (rad <= 0) { p.AddRectangle(r); return p; }
        p.AddArc(r.Left,      r.Top,       d, d, 180, 90);
        p.AddArc(r.Right - d, r.Top,       d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom- d, d, d,   0, 90);
        p.AddArc(r.Left,      r.Bottom- d, d, d,  90, 90);
        p.CloseFigure(); return p;
    }
}
"@
$_csProgress = @"
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class DarkProgressBar : Control {
    private int _val;
    public int Value {
        get { return _val; }
        set { _val = Math.Max(Minimum, Math.Min(Maximum, value)); Invalidate(); }
    }
    public int   Minimum  { get; set; }
    public int   Maximum  { get; set; }
    public Color BarStart { get; set; }
    public Color BarEnd   { get; set; }

    public DarkProgressBar() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer, true);
        SetStyle(ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        Minimum  = 0; Maximum = 100;
        BarStart = Color.FromArgb(31, 111, 235);
        BarEnd   = Color.FromArgb(88, 166, 255);
    }

    protected override void OnPaintBackground(PaintEventArgs e) {
        Color bg = Parent != null ? Parent.BackColor : BackColor;
        using (var b = new SolidBrush(bg)) e.Graphics.FillRectangle(b, ClientRectangle);
    }

    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int r = Height / 2;
        var trackRect = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var trackPath = Round(trackRect, r)) {
            using (var b = new SolidBrush(Color.FromArgb(33, 38, 45))) g.FillPath(b, trackPath);
            if (_val > Minimum && Maximum > Minimum) {
                float pct = (float)(_val - Minimum) / (Maximum - Minimum);
                int fw = (int)Math.Round(pct * (Width - 2));
                if (fw > 0) {
                    g.SetClip(trackPath);
                    var fill = new Rectangle(1, 1, Math.Min(fw, Width - 2), Height - 2);
                    using (var b = new LinearGradientBrush(fill, BarStart, BarEnd, LinearGradientMode.Horizontal))
                        g.FillRectangle(b, fill);
                    g.ResetClip();
                }
            }
            using (var p = new Pen(Color.FromArgb(48, 54, 61), 1f)) g.DrawPath(p, trackPath);
        }
    }

    static GraphicsPath Round(Rectangle rect, int rad) {
        int d = rad * 2; var p = new GraphicsPath();
        if (rad <= 0) { p.AddRectangle(rect); return p; }
        p.AddArc(rect.Left,          rect.Top,          d, d, 180, 90);
        p.AddArc(rect.Right - d,     rect.Top,          d, d, 270, 90);
        p.AddArc(rect.Right - d,     rect.Bottom - d,   d, d,   0, 90);
        p.AddArc(rect.Left,          rect.Bottom - d,   d, d,  90, 90);
        p.CloseFigure(); return p;
    }
}
"@
$_csDarkMode = @"
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
using System;
using System.Runtime.InteropServices;

// Dark title bar via DWM - makes Windows render the chrome in dark mode
public static class DarkMode {
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    public static void Enable(IntPtr hwnd) {
        int v = 1;
        DwmSetWindowAttribute(hwnd, 20, ref v, 4);  // DWMWA_USE_IMMERSIVE_DARK_MODE (Win10 20H1+)
        DwmSetWindowAttribute(hwnd, 19, ref v, 4);  // older Win10 fallback
        int noColor = unchecked((int)0xFFFFFFFE);   // DWMWA_COLOR_NONE
        DwmSetWindowAttribute(hwnd, 34, ref noColor, 4);  // DWMWA_BORDER_COLOR - remove blue accent border
    }
}
"@
if (-not ([System.Management.Automation.PSTypeName]'DarkButton').Type) {
    Add-Type -ReferencedAssemblies $refs -TypeDefinition $_csButton
}
if (-not ([System.Management.Automation.PSTypeName]'DarkProgressBar').Type) {
    Add-Type -ReferencedAssemblies $refs -TypeDefinition $_csProgress
}
if (-not ([System.Management.Automation.PSTypeName]'DarkMode').Type) {
    Add-Type -ReferencedAssemblies $refs -TypeDefinition $_csDarkMode
}
# --- Embedded file contents (auto-generated by build.ps1) ---
$FILE_DATA___APP_NAME___CMD = @'
@echo off
call python "%~dp0src\app.py"
call node   "%~dp0src\app.js"
PAUSE
'@

$FILE_DATA_LIB_CHECK_UPDATE_PS1 = @'
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# Check for Updates
$APP_NAME    = '__APP_NAME__'
$APP_VERSION = '__APP_VERSION__'
$UPDATE_URL  = '__UPDATE_URL__'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class UpdDark {
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    public static void Enable(IntPtr hwnd) {
        int v = 1;
        DwmSetWindowAttribute(hwnd, 20, ref v, 4);
        DwmSetWindowAttribute(hwnd, 19, ref v, 4);
    }
}
"@

$C_BG     = [System.Drawing.Color]::FromArgb(13,  17,  23)
$C_CARD   = [System.Drawing.Color]::FromArgb(22,  27,  34)
$C_TEXT   = [System.Drawing.Color]::FromArgb(240, 246, 252)
$C_DIM    = [System.Drawing.Color]::FromArgb(139, 148, 158)
$C_ACCENT = [System.Drawing.Color]::FromArgb(121, 192, 255)
$C_BORDER = [System.Drawing.Color]::FromArgb(48,  54,  61)

function New-UpdBtn {
    param([string]$T, [int]$X, [int]$W,
          [System.Drawing.Color]$Bg, [System.Drawing.Color]$Fg,
          [System.Drawing.Color]$Border)
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $T
    $b.Location  = New-Object System.Drawing.Point($X, 108)
    $b.Size      = New-Object System.Drawing.Size($W, 32)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderColor            = $Border
    $b.FlatAppearance.BorderSize             = 1
    $b.FlatAppearance.MouseOverBackColor     = [System.Drawing.Color]::FromArgb(38, 44, 52)
    $b.FlatAppearance.MouseDownBackColor     = [System.Drawing.Color]::FromArgb(24, 28, 34)
    $b.BackColor = $Bg
    $b.ForeColor = $Fg
    $b.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $b.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $b.TabStop   = $false
    return $b
}

try {
    $wc      = New-Object System.Net.WebClient
    $json    = $wc.DownloadString("$UPDATE_URL/latest.json") | ConvertFrom-Json
    $latest    = [System.Version]$json.version
    $installed = [System.Version]$APP_VERSION

    if ($latest -gt $installed) {
        $frm = New-Object System.Windows.Forms.Form
        $frm.Text            = "$APP_NAME - Update Available"
        $frm.ClientSize      = New-Object System.Drawing.Size(400, 152)
        $frm.StartPosition   = "CenterScreen"
        $frm.FormBorderStyle = "FixedDialog"
        $frm.MaximizeBox     = $false
        $frm.MinimizeBox     = $false
        $frm.BackColor       = $C_BG
        $frm.Add_Load({ [UpdDark]::Enable($frm.Handle) })

        $icoLbl           = New-Object System.Windows.Forms.Label
        $icoLbl.Text      = [char]0x2191   # up arrow
        $icoLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
        $icoLbl.ForeColor = $C_ACCENT
        $icoLbl.BackColor = [System.Drawing.Color]::FromArgb(15, 30, 50)
        $icoLbl.Size      = New-Object System.Drawing.Size(48, 48)
        $icoLbl.Location  = New-Object System.Drawing.Point(20, 20)
        $icoLbl.TextAlign = "MiddleCenter"

        $lbl1           = New-Object System.Windows.Forms.Label
        $lbl1.Text      = "$APP_NAME v$latest is available"
        $lbl1.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $lbl1.ForeColor = $C_TEXT
        $lbl1.BackColor = [System.Drawing.Color]::Transparent
        $lbl1.Location  = New-Object System.Drawing.Point(82, 22)
        $lbl1.Size      = New-Object System.Drawing.Size(300, 26)

        $lbl2           = New-Object System.Windows.Forms.Label
        $lbl2.Text      = "You have v$installed. How would you like to update?"
        $lbl2.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
        $lbl2.ForeColor = $C_DIM
        $lbl2.BackColor = [System.Drawing.Color]::Transparent
        $lbl2.Location  = New-Object System.Drawing.Point(82, 54)
        $lbl2.Size      = New-Object System.Drawing.Size(300, 18)

        $btnInstall = New-UpdBtn "Run Installer" 20  155 `
            ([System.Drawing.Color]::FromArgb(17, 36, 64)) $C_ACCENT `
            ([System.Drawing.Color]::FromArgb(56, 112, 200))
        $btnWeb     = New-UpdBtn "Open Website"  183 130 $C_CARD $C_TEXT $C_BORDER
        $btnCancel  = New-UpdBtn "Cancel"        321  59 $C_BG   $C_DIM  $C_BG

        $siteBase = $UPDATE_URL -replace '/updates.*$', ''
        $ps1Path  = Join-Path $PSScriptRoot "install.ps1"

        $btnInstall.Add_Click({
            $frm.Close()
            if (Test-Path $ps1Path) {
                Start-Process powershell.exe -ArgumentList "-NoProfile -File `"$ps1Path`""
            }
        })
        $btnWeb.Add_Click({
            $frm.Close()
            Start-Process $siteBase
        })
        $btnCancel.Add_Click({ $frm.Close() })

        $frm.Controls.AddRange(@($icoLbl, $lbl1, $lbl2, $btnInstall, $btnWeb, $btnCancel))
        $frm.ShowDialog() | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "$APP_NAME is up to date (v$APP_VERSION).",
            "No Updates",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Unable to check for updates.`n`n$_",
        "Update Check Failed",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}
'@

$FILE_DATA_LIB_CHECK_UPDATE_VBS = @'
Dim sh, scriptDir
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -File """ & scriptDir & "check-update.ps1""", 0, False
'@

$FILE_DATA_LIB_REPAIR_VBS = @'
Set sh = CreateObject("WScript.Shell")
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
ps1 = scriptDir & "install.ps1"
cmd = "powershell.exe -NoProfile -File """ & ps1 & """"
sh.Run cmd, 1, False
'@

$FILE_DATA_LIB_ROUTER_PS1 = @'
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
param([string]$Uri)

$AppName = '__APP_NAME__'

Add-Type -AssemblyName System.Windows.Forms

# Permission descriptions for human-readable display
$PermDescriptions = @{
    'fs.read'        = 'Read files from your computer'
    'fs.write'       = 'Write files to your computer'
    'net.listen'     = 'Start a local server'
    'net.connect'    = 'Connect to the internet'
    'system.exec'    = 'Run system commands'
    'ctx.provide'    = 'Provide services to other plugins'
    'ctx.broadcast'  = 'Send messages to all connected clients'
}

function Get-PermissionDescription([string]$perm) {
    $base = ($perm -split ':')[0]
    $scope = if ($perm.Contains(':')) { ($perm -split ':', 2)[1] } else { $null }
    $desc = $PermDescriptions[$base]
    if (-not $desc) { $desc = $perm }
    if ($scope -and $scope -ne '${dataDir}') {
        $desc += " ($scope)"
    }
    return $desc
}

function Format-PermissionList([string[]]$permissions) {
    if (-not $permissions -or $permissions.Count -eq 0) {
        return "  (none)"
    }
    $lines = @()
    foreach ($p in $permissions) {
        $lines += "  - $(Get-PermissionDescription $p)"
    }
    return ($lines -join "`n")
}

try {
    $parsed = [System.Uri]$Uri
    $host_  = $parsed.Host.ToLower()
    $path_  = $parsed.AbsolutePath.TrimStart('/')
    $queryString = $parsed.Query.TrimStart('?')
    $query = @{}
    if ($queryString) {
        foreach ($part in $queryString.Split('&')) {
            $kv = $part.Split('=', 2)
            $key = [System.Uri]::UnescapeDataString($kv[0])
            $val = if ($kv.Count -gt 1) { [System.Uri]::UnescapeDataString($kv[1]) } else { '' }
            $query[$key] = $val
        }
    }

    switch ($host_) {

        'install' {
            # computer://install/PLUGIN_ID?version=1.0.0&deps=dep1,dep2&permissions=fs.read,net.connect
            $pluginId = $path_
            $version  = $query['version']
            $deps     = $query['deps']
            $perms    = $query['permissions']

            if (-not $pluginId) {
                [System.Windows.Forms.MessageBox]::Show(
                    'No plugin ID specified.',
                    "$AppName - Install",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                break
            }

            $msg = "Plugin: $pluginId"
            if ($version) { $msg += "`nVersion: $version" }
            if ($deps)    { $msg += "`nRequires: $($deps -replace ',', ', ')" }

            # Show permissions if provided
            if ($perms) {
                $permList = $perms -split ','
                $msg += "`n`nPermissions requested:`n$(Format-PermissionList $permList)"
            }

            $msg += "`n`nInstall this plugin?"

            $result = [System.Windows.Forms.MessageBox]::Show(
                $msg,
                "$AppName - Install Plugin",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question)

            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                # Placeholder: actual plugin installation logic goes here
                [System.Windows.Forms.MessageBox]::Show(
                    "Plugin '$pluginId' installed successfully.",
                    "$AppName - Install Plugin",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
        }

        'install-package' {
            # computer://install-package/PACKAGE_ID?plugins=core,ui,settings
            $packageId = $path_
            $pluginsList = $query['plugins']

            if (-not $packageId) {
                [System.Windows.Forms.MessageBox]::Show(
                    'No package ID specified.',
                    "$AppName - Install Package",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                break
            }

            $plugins = if ($pluginsList) { $pluginsList -split ',' } else { @() }

            $msg = "Package: $packageId"
            $msg += "`nPlugins: $($plugins -join ', ')"
            $msg += "`n`nInstall all $($plugins.Count) plugins in this package?"

            $result = [System.Windows.Forms.MessageBox]::Show(
                $msg,
                "$AppName - Install Package",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question)

            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                $installed = @()
                foreach ($p in $plugins) {
                    # Placeholder: actual plugin installation logic goes here
                    $installed += $p
                }
                [System.Windows.Forms.MessageBox]::Show(
                    "Package '$packageId' installed successfully.`n`nPlugins installed: $($installed -join ', ')",
                    "$AppName - Install Package",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
        }

        'open' {
            $path = $query['path']
            $msg = "URI    : $Uri`nScheme : $($parsed.Scheme)`nHost   : $($parsed.Host)`nPath   : $($parsed.AbsolutePath)`nQuery  : $($parsed.Query)"
            if ($path) { $msg += "`nFile   : $path" }
            [System.Windows.Forms.MessageBox]::Show(
                $msg, "$AppName Protocol Handler",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }

        default {
            # Show raw URI info for unrecognised commands
            $msg = "URI    : $Uri`nScheme : $($parsed.Scheme)`nHost   : $($parsed.Host)`nPath   : $($parsed.AbsolutePath)`nQuery  : $($parsed.Query)"
            [System.Windows.Forms.MessageBox]::Show(
                $msg, "$AppName Protocol Handler",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    }
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Failed to handle URI: $Uri`n$_",
        "$AppName Protocol Handler",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}
'@

$FILE_DATA_LIB_ROUTER_VBS = @'
Dim scriptDir
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -File """ & scriptDir & "router.ps1"" """ & WScript.Arguments(0) & """", 0, False
'@

$FILE_DATA_LIB_SENDTO_VBS = @'
If WScript.Arguments.Count > 0 Then
    Dim scriptDir, sh
    scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
    Set sh = CreateObject("WScript.Shell")
    sh.Run "wscript.exe """ & scriptDir & "router.vbs"" ""computer://open?path=" & WScript.Arguments(0) & """", 0, False
End If
'@

$FILE_DATA_LIB_STARTUP_VBS = @'
' Silently launches APP.cmd from the same data directory
Dim scriptDir, sh
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
Set sh = CreateObject("WScript.Shell")
sh.Run Chr(34) & scriptDir & "..\__APP_NAME__.cmd" & Chr(34), 0, False
'@

$FILE_DATA_LIB_UNINSTALL_PS1 = @'
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
param([string]$PresetInstallDir = "")

$AppName    = '__APP_NAME__'
$AppNameLow = $AppName.ToLower()
$RegPath    = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$AppName"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Single-instance guard
$_mutex = New-Object System.Threading.Mutex($false, "Global\$($AppName)_Uninstall_Mutex")
if (-not $_mutex.WaitOne(0, $false)) {
    [System.Windows.Forms.MessageBox]::Show(
        "$AppName Uninstaller is already running.", "$AppName Uninstaller",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    $_mutex.Dispose()
    exit
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class UninstDark {
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    public static void Enable(IntPtr hwnd) {
        int v = 1;
        DwmSetWindowAttribute(hwnd, 20, ref v, 4);
        DwmSetWindowAttribute(hwnd, 19, ref v, 4);
    }
}
public static class UninstShell {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
"@

$props      = Get-ItemProperty $RegPath -ErrorAction SilentlyContinue
$InstallDir = if ($PresetInstallDir) { $PresetInstallDir } `
              elseif ($props)        { $props.InstallLocation } `
              else                   { Split-Path $PSScriptRoot -Parent }

# Self-relaunch from %TEMP%: releases CMD's working-directory handle on the
# install folder so Remove-Item can delete it cleanly.
if (-not $PresetInstallDir) {
    $src        = if ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $PSCommandPath }
    $tempScript = "$env:TEMP\$($AppNameLow)_uninstall_run.ps1"
    Copy-Item $src $tempScript -Force
    $vbs = "$env:TEMP\$($AppNameLow)_uninstall_run.vbs"
    $cmd = "powershell.exe -NoProfile -WindowStyle Hidden -File `"$tempScript`" `"$InstallDir`""
    $cmdVbs = $cmd.Replace('"', '""')
    $vbsContent = @"
Set sh = CreateObject("WScript.Shell")
temp = sh.ExpandEnvironmentStrings("%TEMP%")
sh.CurrentDirectory = temp
sh.Run "$cmdVbs", 0, False
"@
    [System.IO.File]::WriteAllText($vbs, $vbsContent, [System.Text.Encoding]::ASCII)
    Start-Process wscript.exe -WorkingDirectory $env:TEMP -ArgumentList "`"$vbs`""
    exit
}

# Wait for the parent CMD process to fully exit before we attempt deletion
Start-Sleep -Milliseconds 600
try { Set-Location -Path (Split-Path $InstallDir -Parent) } catch { Set-Location -Path $env:TEMP }

$C_BG      = [System.Drawing.Color]::FromArgb(13,  17,  23)
$C_CARD    = [System.Drawing.Color]::FromArgb(22,  27,  34)
$C_TEXT    = [System.Drawing.Color]::FromArgb(240, 246, 252)
$C_DIM     = [System.Drawing.Color]::FromArgb(139, 148, 158)
$C_DANGER  = [System.Drawing.Color]::FromArgb(248, 81,  73)
$C_SUCCESS = [System.Drawing.Color]::FromArgb(63,  185, 80)
$C_BORDER  = [System.Drawing.Color]::FromArgb(48,  54,  61)
$script:uninstallDone = $false

$frm                 = New-Object System.Windows.Forms.Form
$frm.Text            = "Uninstall $AppName"
$frm.ClientSize      = New-Object System.Drawing.Size(420, 210)
$frm.StartPosition   = "CenterScreen"
$frm.FormBorderStyle = "FixedDialog"
$frm.MaximizeBox     = $false
$frm.MinimizeBox     = $false
$frm.BackColor       = $C_BG
$frm.Icon            = [System.Drawing.SystemIcons]::Shield

$frm.Add_Load({ [UninstDark]::Enable($frm.Handle) })

$icoLbl           = New-Object System.Windows.Forms.Label
$icoLbl.Text      = "!"
$icoLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
$icoLbl.ForeColor = $C_DANGER
$icoLbl.BackColor = [System.Drawing.Color]::FromArgb(60, 15, 10)
$icoLbl.Size      = New-Object System.Drawing.Size(48, 48)
$icoLbl.Location  = New-Object System.Drawing.Point(24, 24)
$icoLbl.TextAlign = "MiddleCenter"

$lbl1           = New-Object System.Windows.Forms.Label
$lbl1.Text      = "Uninstall $AppName?"
$lbl1.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$lbl1.ForeColor = $C_TEXT
$lbl1.BackColor = [System.Drawing.Color]::Transparent
$lbl1.Location  = New-Object System.Drawing.Point(84, 24)
$lbl1.Size      = New-Object System.Drawing.Size(310, 28)

$lbl2           = New-Object System.Windows.Forms.Label
$lbl2.Text      = $InstallDir
$lbl2.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lbl2.ForeColor = $C_DIM
$lbl2.BackColor = [System.Drawing.Color]::Transparent
$lbl2.Location  = New-Object System.Drawing.Point(84, 58)
$lbl2.Size      = New-Object System.Drawing.Size(310, 18)

$lbl3           = New-Object System.Windows.Forms.Label
$lbl3.Text      = "All files and registry entries will be removed. This cannot be undone."
$lbl3.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lbl3.ForeColor = $C_DIM
$lbl3.BackColor = [System.Drawing.Color]::Transparent
$lbl3.Location  = New-Object System.Drawing.Point(24, 92)
$lbl3.Size      = New-Object System.Drawing.Size(372, 36)

function New-FlatBtn {
    param([string]$T, [int]$X, [System.Drawing.Color]$Bg, [System.Drawing.Color]$Fg)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $T; $b.Location = New-Object System.Drawing.Point($X, 158)
    $b.Size = New-Object System.Drawing.Size(116, 34)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderColor = $C_BORDER
    $b.FlatAppearance.BorderSize  = 1
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38, 44, 52)
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(24, 28, 34)
    $b.BackColor = $Bg; $b.ForeColor = $Fg
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.TabStop = $false
    return $b
}

$btnYes = New-FlatBtn "Uninstall" 164 ([System.Drawing.Color]::FromArgb(58,15,12)) $C_DANGER
$btnNo  = New-FlatBtn "Cancel"    286 $C_CARD $C_TEXT

$pb           = New-Object System.Windows.Forms.ProgressBar
$pb.Location  = New-Object System.Drawing.Point(24, 134)
$pb.Size      = New-Object System.Drawing.Size(372, 14)
$pb.Minimum   = 0
$pb.Maximum   = 100
$pb.Visible   = $false

$frm.Controls.AddRange(@($icoLbl, $lbl1, $lbl2, $lbl3, $pb, $btnYes, $btnNo))

$btnNo.Add_Click({
    if ($script:uninstallDone -and (Test-Path $InstallDir)) {
        Start-Process cmd.exe -WorkingDirectory $env:TEMP -ArgumentList "/c for /l %i in (1,1,6) do (rd /s /q `"$InstallDir`" >nul 2>&1 & if not exist `"$InstallDir`" exit /b 0 & ping localhost -n 2 >nul)" -WindowStyle Hidden
    }
    $frm.Close()
})
$btnYes.Add_Click({
    $btnYes.Visible = $false; $btnNo.Visible = $false
    $lbl1.Text  = "Uninstalling $AppName..."
    $lbl3.Text  = "Removing registry entries..."
    $pb.Value   = 0
    $pb.Visible = $true
    [System.Windows.Forms.Application]::DoEvents()

    # Step 1 - registry entries
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$AppNameLow\ShellNew"                      -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$AppNameLow"                               -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\$AppName.File"                              -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\$AppNameLow"                                -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $RegPath                                                             -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $AppName -ErrorAction SilentlyContinue
    $pb.Value = 20
    [System.Windows.Forms.Application]::DoEvents()

    # Step 2 - shortcuts & PATH
    $lbl3.Text = "Removing shortcuts..."
    $pb.Value  = 25
    [System.Windows.Forms.Application]::DoEvents()
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$AppName.lnk" -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "HKCU:\SOFTWARE\Classes\*\shell\$AppName"                    -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\shell\$AppName"            -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\Background\shell\$AppName" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\SendTo\$AppName.lnk"                      -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$AppName.lnk"         -Force -ErrorAction SilentlyContinue
    $curPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = ($curPath -split ";" | Where-Object { $_ -and $_ -ne $InstallDir -and $_ -ne "$InstallDir\data" }) -join ";"
    if ($newPath -ne $curPath) { [Environment]::SetEnvironmentVariable("Path", $newPath, "User") }
    $sc = "$env:USERPROFILE\Desktop\$AppName.lnk"
    if (Test-Path $sc) { Remove-Item $sc -Force -ErrorAction SilentlyContinue }
    foreach ($lnkName in @("Repair.lnk", "Uninstall.lnk", "Check for Updates.lnk")) {
        $lnkPath = Join-Path $InstallDir $lnkName
        if (Test-Path $lnkPath) { Remove-Item $lnkPath -Force -ErrorAction SilentlyContinue }
    }
    $pb.Value = 45
    [System.Windows.Forms.Application]::DoEvents()

    # Step 3 - flush shell cache
    $lbl3.Text = "Flushing shell cache..."
    $pb.Value  = 50
    [System.Windows.Forms.Application]::DoEvents()
    [UninstShell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800

    # Step 4 - delete files
    $lbl3.Text = "Deleting files..."
    $pb.Value  = 65
    [System.Windows.Forms.Application]::DoEvents()
    Get-ChildItem $InstallDir -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {} }
    $dirItem = Get-Item $InstallDir -Force -ErrorAction SilentlyContinue
    if ($dirItem) { $dirItem.Attributes = [System.IO.FileAttributes]::Normal }
    $pb.Value = 75
    [System.Windows.Forms.Application]::DoEvents()

    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $InstallDir) {
        try { [System.IO.Directory]::Delete($InstallDir, $true) } catch {}
    }
    if (Test-Path $InstallDir) {
        Start-Process cmd.exe -WorkingDirectory $env:TEMP -ArgumentList "/c rd /s /q `"$InstallDir`"" -Wait -WindowStyle Hidden
    }
    if (Test-Path $InstallDir) {
        Start-Process cmd.exe -WorkingDirectory $env:TEMP -ArgumentList "/c for /l %i in (1,1,6) do (rd /s /q `"$InstallDir`" >nul 2>&1 & if not exist `"$InstallDir`" exit /b 0 & ping localhost -n 2 >nul)" -Wait -WindowStyle Hidden
    }
    $pb.Value = 100
    [System.Windows.Forms.Application]::DoEvents()

    $icoLbl.Text      = [char]0x2713
    $icoLbl.ForeColor = $C_SUCCESS
    $icoLbl.BackColor = [System.Drawing.Color]::FromArgb(15, 40, 20)
    $lbl1.Text        = "$AppName uninstalled."
    $lbl1.ForeColor   = $C_SUCCESS
    $lbl2.Text        = "All files and registry entries have been removed."
    $lbl3.Text        = ""
    $pb.Visible       = $false
    $btnNo.Text       = "Close"
    $btnNo.Visible    = $true
    $script:uninstallDone = $true
})
$frm.ShowDialog() | Out-Null
'@

$FILE_DATA_LIB_UNINSTALL_VBS = @'
Set sh = CreateObject("WScript.Shell")
temp = sh.ExpandEnvironmentStrings("%TEMP%")
sh.CurrentDirectory = temp
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
ps1 = scriptDir & "uninstall.ps1"
cmd = "powershell.exe -NoProfile -WindowStyle Hidden -File """ & ps1 & """"
sh.Run cmd, 0, False
'@

$FILE_DATA_SRC_APP_JS = @'
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
'use strict';
const path = require('path');
const http = require('http');
const { PluginVM } = require('./vm');

// __dirname = <install_dir>/data/src/
// go up twice to reach the install root: data/src -> data -> install root
const installDir = path.join(__dirname, '..', '..');

const vm = new PluginVM({
    pluginsDir : path.join(installDir, 'plugins'),
    dataDir    : path.join(installDir, 'data'),
    appName    : 'Computer',
    appVersion : '1.0.0',
});

// Heartbeat server on port 53420 - lets the installer/updater detect that
// the app is running via Test-ComputerRunning (checks TCP listeners on 53420).
http.createServer((_req, res) => { res.writeHead(200); res.end('ok'); })
    .listen(53420, '127.0.0.1', () => console.log('[app] heartbeat on 127.0.0.1:53420'))
    .on('error', err => {
        if (err.code === 'EADDRINUSE') {
            console.warn('[app] port 53420 already in use - another instance may be running');
        }
    });

vm.loadAll().catch(err => {
    console.error('[app] fatal:', err.message);
    console.error(err);
    process.exit(1);
});
'@

$FILE_DATA_SRC_APP_PY = @'
print('Hello World - Python component!')
'@

$FILE_DATA_SRC_DIALOG_HTML = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Plugin Permissions</title>
<link rel="icon" href="/favicon.ico">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --bg:          #0b0b10;
    --surface:     #111118;
    --surface-2:   #17171f;
    --surface-3:   #1e1e28;
    --border:      #252530;
    --text:        #e2e8f0;
    --text-muted:  #64748b;
    --text-dim:    #94a3b8;
    --green:       #10b981;
    --mono:        'Cascadia Code', 'Consolas', monospace;
  }

  html, body {
    height: 100%;
    background: var(--bg);
    color: var(--text);
    font-family: 'Segoe UI', system-ui, sans-serif;
    font-size: 14px;
    -webkit-font-smoothing: antialiased;
    user-select: none;
  }

  body { display: flex; flex-direction: column; overflow: hidden; }

  /* -- Header ----------------------------------------------------------- */
  .header {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    padding: 13px 18px 11px;
    flex-shrink: 0;
  }

  .app-tag {
    font-size: 10px;
    font-weight: 600;
    letter-spacing: .06em;
    text-transform: uppercase;
    color: var(--text-muted);
    margin-bottom: 8px;
  }

  .plugin-row {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .plugin-avatar {
    width: 38px;
    height: 38px;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 17px;
    font-weight: 700;
    flex-shrink: 0;
    border: 1px solid var(--border);
  }

  .plugin-info { flex: 1; min-width: 0; }

  .plugin-name-line {
    display: flex;
    align-items: baseline;
    gap: 7px;
    flex-wrap: wrap;
  }

  .plugin-name {
    font-size: 16px;
    font-weight: 700;
    color: var(--text);
    white-space: nowrap;
  }

  .plugin-version {
    font-size: 11px;
    color: var(--text-muted);
    background: var(--surface-3);
    border: 1px solid var(--border);
    border-radius: 4px;
    padding: 1px 5px;
    flex-shrink: 0;
  }

  .plugin-desc {
    font-size: 11px;
    color: var(--text-muted);
    margin-top: 3px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* -- Bundle plugin pills ----------------------------------------------- */
  .plugin-pills {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin-top: 6px;
  }

  .pill {
    font-size: 10px;
    font-weight: 600;
    padding: 2px 7px;
    border-radius: 10px;
    border: 1px solid var(--border);
    color: var(--text-dim);
    background: var(--surface-3);
  }

  /* -- Permission list --------------------------------------------------- */
  .body::-webkit-scrollbar { width: 5px; }
  .body::-webkit-scrollbar-track { background: transparent; }
  .body::-webkit-scrollbar-thumb { background: var(--surface-3); border-radius: 3px; }

  .section-label {
    font-size: 10px;
    font-weight: 700;
    letter-spacing: .08em;
    text-transform: uppercase;
    color: var(--text-muted);
    margin-bottom: 7px;
  }

  .group-label {
    font-size: 10px;
    font-weight: 700;
    letter-spacing: .06em;
    text-transform: uppercase;
    color: var(--text-muted);
    margin: 8px 0 2px;
    padding: 0 2px;
    opacity: .75;
  }

  .group-desc {
    font-size: 11px;
    color: var(--text-muted);
    margin-bottom: 5px;
    padding: 0 2px;
    line-height: 1.4;
  }

  .perm-list {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .perm-item {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    background: var(--surface-2);
    border: 1px solid var(--border);
    border-radius: 9px;
    padding: 9px 12px;
    transition: border-color .15s;
    position: relative;
  }

  .perm-item:hover { border-color: #333344; }

  /* -- Hover tooltip ---------------------------------------------------- */
  .perm-tooltip {
    display: none;
    position: absolute;
    bottom: calc(100% + 6px);
    left: 0;
    right: 0;
    background: var(--surface-3);
    border: 1px solid #333348;
    border-radius: 7px;
    padding: 8px 10px;
    z-index: 10;
    pointer-events: none;
    box-shadow: 0 4px 16px rgba(0,0,0,.5);
  }

  .perm-item:hover .perm-tooltip { display: block; }

  .perm-tooltip-raw {
    font-family: var(--mono);
    font-size: 10px;
    color: #79c0ff;
    word-break: break-all;
    margin-bottom: 4px;
  }

  .perm-tooltip-line {
    font-size: 10.5px;
    color: var(--text-dim);
    line-height: 1.5;
  }

  .perm-tooltip-line + .perm-tooltip-line { margin-top: 2px; }

  .perm-icon {
    width: 20px;
    height: 20px;
    flex-shrink: 0;
    margin-top: 1px;
    color: var(--text-dim);
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .perm-icon svg { width: 16px; height: 16px; }

  .perm-text { flex: 1; min-width: 0; }

  .perm-label {
    font-size: 12px;
    font-weight: 500;
    color: var(--text);
  }

  .perm-scope {
    font-family: var(--mono);
    font-size: 10px;
    color: var(--text-muted);
    margin-top: 3px;
    word-break: break-all;
    line-height: 1.5;
    background: var(--surface-3);
    border-radius: 4px;
    padding: 2px 5px;
    display: inline-block;
    max-width: 100%;
  }

  .perm-reason {
    font-size: 11px;
    color: var(--text-dim);
    margin-top: 5px;
    line-height: 1.45;
    opacity: .85;
  }

  /* -- Scroll hint ------------------------------------------------------- */
  .body-wrap {
    flex: 1;
    position: relative;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  .body {
    flex: 1;
    overflow-y: auto;
    padding: 11px 18px 8px;
    scrollbar-width: thin;
    scrollbar-color: var(--surface-3) transparent;
  }

  .scroll-hint {
    position: absolute;
    bottom: 0;
    left: 0;
    right: 0;
    height: 52px;
    background: linear-gradient(to bottom, transparent, var(--bg));
    display: flex;
    align-items: flex-end;
    justify-content: center;
    padding-bottom: 6px;
    pointer-events: none;
    transition: opacity .25s;
  }

  .scroll-hint svg {
    opacity: .55;
    animation: bounce 1.4s ease-in-out infinite;
  }

  @keyframes bounce {
    0%, 100% { transform: translateY(0); }
    50%       { transform: translateY(4px); }
  }

  /* -- Footer ------------------------------------------------------------ */
  .footer {
    border-top: 1px solid var(--border);
    padding: 10px 18px 12px;
    display: flex;
    gap: 8px;
    justify-content: flex-end;
    flex-shrink: 0;
    background: var(--surface);
  }

  button {
    border: none;
    border-radius: 7px;
    padding: 8px 20px;
    font-size: 12px;
    font-weight: 600;
    font-family: inherit;
    cursor: pointer;
    transition: opacity .15s, transform .1s;
    letter-spacing: .01em;
  }

  button:active { transform: scale(.97); }
  button:disabled { opacity: .45; cursor: default; transform: none; }

  .btn-deny {
    background: var(--surface-3);
    color: var(--text-dim);
    border: 1px solid var(--border);
  }
  .btn-deny:hover:not(:disabled) { background: #232333; }

  .btn-allow {
    background: var(--green);
    color: #fff;
  }
  .btn-allow:hover:not(:disabled) { opacity: .88; }

  /* -- Done state -------------------------------------------------------- */
  .done-overlay {
    display: none;
    position: fixed;
    inset: 0;
    background: var(--bg);
    align-items: center;
    justify-content: center;
    flex-direction: column;
    gap: 10px;
    animation: fadein .2s ease;
  }

  .done-overlay.show { display: flex; }

  .done-icon { display: flex; align-items: center; justify-content: center; }
  .done-text { font-size: 13px; color: var(--text-muted); }

  @keyframes fadein {
    from { opacity: 0; }
    to   { opacity: 1; }
  }
</style>
</head>
<body>

<!-- Plugin / bundle data injected by the vm.js HTTP server -->
<script id="d" type="application/json">__PLUGIN_DATA__</script>

<div class="header">
  <div class="app-tag" id="app-tag"></div>
  <div class="plugin-row">
    <div class="plugin-avatar" id="avatar"></div>
    <div class="plugin-info">
      <div class="plugin-name-line">
        <span class="plugin-name" id="pname"></span>
        <span class="plugin-version" id="pver"></span>
      </div>
      <div class="plugin-desc" id="pdesc"></div>
      <div class="plugin-pills" id="ppills" style="display:none"></div>
    </div>
  </div>
</div>

<div class="body-wrap">
  <div class="body" id="body-scroll">
    <div class="section-label">Requests access to</div>
    <div class="perm-list" id="perm-list"></div>
  </div>
  <div class="scroll-hint" id="scroll-hint">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="18" height="18"><polyline points="6 9 12 15 18 9"/></svg>
  </div>
</div>

<div class="footer">
  <button class="btn-deny"  id="btn-deny"  onclick="answer(false)">Deny</button>
  <button class="btn-allow" id="btn-allow" onclick="answer(true)" disabled>Scroll Down</button>
</div>

<div class="done-overlay" id="done"></div>

<script>
// Inline SVG icons - pure ASCII, no encoding issues
const SVG = (d, extra) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"${extra ? ' ' + extra : ''}>${d}</svg>`;

const ICONS = {
  'fs.read':
    SVG('<path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/>'),
  'fs.write':
    SVG('<path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 013 3L7 19l-4 1 1-4L16.5 3.5z"/>'),
  'net.listen':
    SVG('<rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><line x1="6" y1="6" x2="6.01" y2="6"/><line x1="6" y1="18" x2="6.01" y2="18"/>'),
  'net.connect':
    SVG('<circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/>'),
  'system.exec':
    SVG('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/>'),
  'ctx.provide':
    SVG('<path d="M10 13a5 5 0 007.54.54l3-3a5 5 0 00-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 00-7.54-.54l-3 3a5 5 0 007.07 7.07l1.71-1.71"/>'),
  'ctx.broadcast':
    SVG('<path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z" opacity=".15" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="3" fill="currentColor" stroke="none"/><path d="M6.34 6.34a8 8 0 000 11.32M17.66 6.34a8 8 0 010 11.32M3.52 3.52a12 12 0 000 16.96M20.48 3.52a12 12 0 010 16.96"/>'),
};

const DEFAULT_ICON =
  SVG('<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0110 0v4"/>');

// Extra technical detail shown in the hover tooltip per permission type
const PERM_DETAILS = {
  'fs.read'      : 'ctx.readFile(path) - ctx.readDir(path) - ctx.existsSync(path)',
  'fs.write'     : 'ctx.writeFile(path, data)',
  'net.listen'   : 'ctx.listen(port, handler) -> http.Server',
  'net.connect'  : 'ctx.fetch(url, options) -> Promise<Response>',
  'system.exec'  : 'ctx.exec(cmd, args) - ctx.execAsync(cmd) - ctx.spawnDetached(cmd, args)',
  'ctx.provide'  : 'ctx.provide(name, value)  -  exposes a service other plugins can ctx.use()',
  'ctx.broadcast': 'ctx.broadcast(msg)  -  fires vm:broadcast on the shared event bus',
  'vm.manage'    : 'ctx.use("vm")  -  getAll - disable - enable - resetPerms - getDependents',
};

const AVATAR_COLORS = [
  ['#1e3a5f','#60a5fa'], ['#1a3a2a','#34d399'], ['#3b1f4a','#c084fc'],
  ['#3b2a10','#fbbf24'], ['#3b1a1a','#f87171'], ['#1a2f3b','#38bdf8'],
];

// Shorten long paths to last 3 segments, e.g. C:\...\data\plugins\example
function truncateScope(scope) {
  if (scope.length <= 44) return scope;
  const hasBs = scope.includes('\\');
  const sep = hasBs ? '\\' : (scope.includes('/') ? '/' : null);
  if (!sep) return scope;
  const parts = scope.split(sep).filter(Boolean);
  if (parts.length <= 3) return scope;
  return '...' + sep + parts.slice(-3).join(sep);
}

function renderPerm(perm, container, reasons) {
  const colon = perm.indexOf(':');
  const base  = colon === -1 ? perm : perm.slice(0, colon);
  const scope = colon === -1 ? null  : perm.slice(colon + 1);

  const icon    = ICONS[base] || DEFAULT_ICON;
  const desc    = PERM_DESCRIPTIONS[base] || base;
  const reason  = reasons && (reasons[perm] || reasons[base]) || null;
  const detail  = PERM_DETAILS[base] || null;

  // Tooltip lines
  const tooltipLines = [];
  if (scope) tooltipLines.push(`Scope: ${scope}`);
  if (detail) tooltipLines.push(`API: ${detail}`);

  const tooltip =
    `<div class="perm-tooltip">` +
      `<div class="perm-tooltip-raw">${perm}</div>` +
      tooltipLines.map(l => `<div class="perm-tooltip-line">${l}</div>`).join('') +
    `</div>`;

  const item = document.createElement('div');
  item.className = 'perm-item';
  item.innerHTML =
    tooltip +
    `<span class="perm-icon">${icon}</span>` +
    `<div class="perm-text">` +
      `<div class="perm-label">${desc}</div>` +
      (scope  ? `<div class="perm-scope">${truncateScope(scope)}</div>` : '') +
      (reason ? `<div class="perm-reason">${reason}</div>` : '') +
    `</div>`;
  container.appendChild(item);
}

const data = JSON.parse(document.getElementById('d').textContent);
const PERM_DESCRIPTIONS = data.permDescriptions;

// Enforce intended window dimensions regardless of what the OS/browser opened.
// window.resizeTo works in Edge/Chrome --app mode.
if (data.winW && data.winH) {
  try { window.resizeTo(data.winW, data.winH); } catch (_) {}
}

// Header
document.getElementById('app-tag').textContent = data.appName;
document.getElementById('pname').textContent   = data.name;
document.getElementById('pver').textContent    = 'v' + data.version;
document.getElementById('pdesc').textContent   = data.description || '';

// Avatar: coloured square with first letter
const av = document.getElementById('avatar');
const ci = (data.name.charCodeAt(0) || 0) % AVATAR_COLORS.length;
av.style.background = AVATAR_COLORS[ci][0];
av.style.color      = AVATAR_COLORS[ci][1];
av.textContent      = (data.name[0] || '?').toUpperCase();

const list = document.getElementById('perm-list');

if (data.type === 'bundle') {
  // Show member plugin pills under the bundle name
  const pillsEl = document.getElementById('ppills');
  pillsEl.style.display = '';
  for (const p of data.plugins) {
    const pill = document.createElement('span');
    pill.className = 'pill';
    pill.textContent = p.name;
    pillsEl.appendChild(pill);
  }

  // Render permissions grouped by member plugin
  for (const plugin of data.plugins) {
    if (!plugin.permissions || plugin.permissions.length === 0) continue;
    const grp = document.createElement('div');
    grp.className = 'group-label';
    grp.textContent = plugin.name;
    list.appendChild(grp);
    if (plugin.description) {
      const desc = document.createElement('div');
      desc.className = 'group-desc';
      desc.textContent = plugin.description;
      list.appendChild(desc);
    }
    for (const perm of plugin.permissions) {
      renderPerm(perm, list, plugin.permReasons);
    }
  }
} else {
  // Single plugin - flat list
  for (const perm of data.permissions) {
    renderPerm(perm, list, data.permReasons);
  }
}

// -- Scroll gate: Allow button unlocks once the user reaches the bottom --------
const bodyEl     = document.getElementById('body-scroll');
const hintEl     = document.getElementById('scroll-hint');
const allowBtn   = document.getElementById('btn-allow');

function checkScrolled() {
  // scrollHeight - scrollTop - clientHeight <= threshold (2px tolerance)
  const atBottom = bodyEl.scrollHeight - bodyEl.scrollTop - bodyEl.clientHeight <= 2;
  const canScroll = bodyEl.scrollHeight > bodyEl.clientHeight + 2;

  if (!canScroll || atBottom) {
    allowBtn.disabled   = false;
    allowBtn.textContent = 'Allow';
    hintEl.style.opacity = '0';
    hintEl.style.pointerEvents = 'none';
  } else {
    hintEl.style.opacity = '1';
  }
}

bodyEl.addEventListener('scroll', checkScrolled, { passive: true });
// Check after a frame so layout is complete and scrollHeight is accurate
requestAnimationFrame(checkScrolled);

// Keep an SSE connection alive so the server knows when this window closes.
// Edge closes the normal HTTP keep-alive connection right after page load,
// so the old req.socket 'close' trick fires immediately (before you click).
// An SSE stream stays open for the entire lifetime of the page.
new EventSource('/sse');

async function answer(granted) {
  document.getElementById('btn-deny').disabled  = true;
  document.getElementById('btn-allow').disabled = true;

  const overlay = document.getElementById('done');
  const doneColor = granted ? '#10b981' : '#ef4444';
  const doneSvg = granted
    ? `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="${doneColor}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="48" height="48"><polyline points="20 6 9 17 4 12"/></svg>`
    : `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="${doneColor}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="48" height="48"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>`;
  overlay.innerHTML =
    `<div class="done-icon">${doneSvg}</div>` +
    `<div class="done-text" style="color:${doneColor}">${granted ? 'Permission granted' : 'Permission denied'}</div>`;
  overlay.classList.add('show');

  try {
    await fetch('/result', {
      method  : 'POST',
      headers : { 'Content-Type': 'application/json' },
      body    : JSON.stringify({ granted }),
    });
  } catch (_) {}

  window.close();
}
</script>
</body>
</html>
'@

$FILE_DATA_SRC_VM_JS = @'
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
'use strict';
const vm     = require('vm');
const fs     = require('fs');
const path   = require('path');
const http   = require('http');
const { exec, execFileSync, spawn } = require('child_process');

// -- Feature flags: broad (unscoped) permissions that require an explicit opt-in
// Maps permission prefix -> config key that must be true to allow it.
const FEATURE_GATED_PERMS = {
    'system.exec'  : 'features.unrestricted_exec',
    'net.connect'  : 'features.unrestricted_network',
};

// Safe defaults shipped with the app - all advanced features disabled.
const FEATURE_FLAG_DEFAULTS = {
    'features.experimental'       : false,
    'features.unrestricted_exec'  : false,
    'features.unrestricted_network': false,
};

// -- Permission metadata -------------------------------------------------------
const PERM_DESCRIPTIONS = {
    'fs.read'        : 'Read files from your computer',
    'fs.write'       : 'Write files to your computer',
    'net.listen'     : 'Start a local server on your machine',
    'net.connect'    : 'Connect to the internet',
    'system.exec'    : 'Run system commands',
    'ctx.provide'    : 'Provide services to other plugins',
    'ctx.broadcast'  : 'Send messages to all connected clients',
    'vm.manage'      : 'Manage plugins (enable, disable, reload)',
};

// -- Plugin VM -----------------------------------------------------------------
class PluginVM {
    /**
     * @param {{
     *   pluginsDir : string,
     *   dataDir    : string,
     *   appName    : string,
     *   appVersion : string,
     * }} options
     */
    constructor(options) {
        this.pluginsDir   = options.pluginsDir;
        this.dataDir      = options.dataDir;
        this.appName      = options.appName    || 'Computer';
        this.appVersion   = options.appVersion || '1.0.0';
        this._services         = new Map();   // name -> value (provided by plugins)
        this._serviceProviders = new Map();   // service name -> pluginId that provided it
        this._loaded      = [];          // plugin/bundle IDs loaded in this session
        this._pluginMetas = new Map();   // pluginId -> plugin.json contents
        this._syncing     = false;       // mutex: prevents concurrent _syncPlugins calls
    }

    // -- Feature flags (read from data/config.json, same file as core's Config) -

    _readFeatureFlags() {
        const cfgFile = path.join(this.dataDir, 'config.json');
        let stored = {};
        try { stored = JSON.parse(fs.readFileSync(cfgFile, 'utf8')); } catch (_) {}
        const flags = {};
        for (const [k, def] of Object.entries(FEATURE_FLAG_DEFAULTS)) {
            flags[k] = k in stored ? stored[k] : def;
        }
        return flags;
    }

    // -- Plugin cache (data/plugins-cache.json) --------------------------------
    // Schema: { [id]: { status: "loaded"|"denied"|"error"|"removed"|"disabled", folder?, type? } }

    _cacheFile() { return path.join(this.dataDir, 'plugins-cache.json'); }

    _loadCache() {
        try { return JSON.parse(fs.readFileSync(this._cacheFile(), 'utf8')); }
        catch (_) { return {}; }
    }

    _saveCache(cache) {
        fs.mkdirSync(this.dataDir, { recursive: true });
        fs.writeFileSync(this._cacheFile(), JSON.stringify(cache, null, 2));
    }

    // -- Permission persistence ------------------------------------------------

    _permsFile(pluginId) {
        return path.join(this.dataDir, 'permissions', `${pluginId}.json`);
    }

    _loadSavedPerms(pluginId) {
        try {
            return new Set(JSON.parse(fs.readFileSync(this._permsFile(pluginId), 'utf8')));
        } catch (_) {
            return null; // not yet granted
        }
    }

    _savePerms(pluginId, perms) {
        const dir = path.join(this.dataDir, 'permissions');
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(this._permsFile(pluginId), JSON.stringify([...perms], null, 2));
    }

    // -- Permission dialog (Edge --app + local HTTP server) --------------------

    _findEdge() {
        const candidates = [
            path.join(process.env['ProgramFiles(x86)'] || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
            path.join(process.env['ProgramFiles']       || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
            path.join(process.env['LOCALAPPDATA']       || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        ];
        return candidates.find(p => { try { fs.accessSync(p); return true; } catch (_) { return false; } }) || null;
    }

    _openBrowser(url, w = 420, h = 380) {
        const edge = this._findEdge();
        if (edge) {
            // A dedicated profile dir forces Edge to open a fresh window that
            // actually respects --window-size (ignored when a profile is already open).
            const profileDir = path.join(this.dataDir, 'edge-dialog-profile');
            spawn(edge, [
                `--app=${url}`,
                `--window-size=${w},${h}`,
                `--user-data-dir=${profileDir}`,
                '--no-first-run',
                '--disable-extensions',
                '--disable-default-apps',
                '--disable-sync',
                '--no-default-browser-check',
            ], { detached: true, stdio: 'ignore' }).unref();
        } else {
            exec(`cmd /c start "" "${url}"`);
        }
    }

    /**
     * Show the permission dialog and resolve when the user responds or closes.
     *
     * Window-close detection uses a persistent SSE connection (/sse) instead of
     * the socket close event on the GET / request.  Edge closes the keep-alive
     * HTTP connection right after loading the page, which caused the old
     * req.socket 'close' handler to fire immediately (before the user clicked
     * anything).  The SSE stream stays alive for the entire lifetime of the page.
     *
     * @param {object} dialogData  Fully-formed data object injected into dialog.html
     * @param {number} [winW=420]
     * @param {number} [winH=380]
     * @returns {Promise<boolean>} true = granted, false = denied/closed
     */
    _showPermDialog(dialogData, winW = 420, winH = 380) {
        const iconPath = path.join(this.dataDir, 'assets', `${this.appName.toLowerCase()}.ico`);

        return new Promise((resolve) => {
            const htmlTemplate = fs.readFileSync(path.join(__dirname, 'dialog.html'), 'utf8');
            const html = htmlTemplate.replace('__PLUGIN_DATA__', JSON.stringify(dialogData));

            let settled = false;
            const settle = (granted) => {
                if (settled) return;
                settled = true;
                clearTimeout(timeout);
                server.close();
                resolve(granted);
            };

            const timeout = setTimeout(() => {
                console.warn(`[vm] permission dialog timed out for "${dialogData.name}" - denying`);
                settle(false);
            }, 2 * 60 * 1000);

            const server = http.createServer((req, res) => {
                // -- Favicon ----------------------------------------------------
                if (req.url === '/favicon.ico') {
                    try {
                        res.writeHead(200, { 'Content-Type': 'image/x-icon', 'Cache-Control': 'no-cache' });
                        res.end(fs.readFileSync(iconPath));
                    } catch (_) { res.writeHead(204); res.end(); }
                    return;
                }

                // -- SSE endpoint - stays open while the dialog window is open --
                // When the window closes, this connection drops -> settle(false).
                if (req.method === 'GET' && req.url === '/sse') {
                    res.writeHead(200, {
                        'Content-Type' : 'text/event-stream',
                        'Cache-Control': 'no-cache',
                        'Connection'   : 'keep-alive',
                    });
                    res.write('data: connected\n\n');

                    const hb = setInterval(() => {
                        try { res.write(':ping\n\n'); }
                        catch (_) { clearInterval(hb); }
                    }, 25000);

                    req.socket.once('close', () => {
                        clearInterval(hb);
                        // Small delay so any in-flight POST /result still wins
                        setTimeout(() => settle(false), 500);
                    });
                    return;
                }

                // -- Serve the dialog HTML --------------------------------------
                if (req.method === 'GET' && req.url === '/') {
                    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
                    res.end(html);
                    return;
                }

                // -- Receive the Allow / Deny click -----------------------------
                if (req.method === 'POST' && req.url === '/result') {
                    let body = '';
                    req.on('data', chunk => { body += chunk; });
                    req.on('end', () => {
                        try {
                            const { granted } = JSON.parse(body);
                            res.writeHead(200); res.end();
                            settle(!!granted);
                        } catch (_) { res.writeHead(400); res.end(); }
                    });
                    return;
                }

                res.writeHead(404); res.end();
            });

            server.listen(0, '127.0.0.1', () => {
                const { port } = server.address();
                this._openBrowser(`http://127.0.0.1:${port}/`, winW, winH);
            });

            server.on('error', (err) => {
                console.error(`[vm] dialog server error: ${err.message}`);
                settle(false);
            });
        });
    }

    // -- Permission check for a single plugin (load saved or prompt) -----------

    async _checkPermissions(pluginId, meta, requested) {
        if (!requested || requested.length === 0) return new Set();

        // -- Feature-flag gate: check opt-in flags before prompting the user ---
        const flags = this._readFeatureFlags();

        // Block experimental plugins unless the experimental flag is enabled
        if (meta.experimental === true && !flags['features.experimental']) {
            throw new Error(
                `[vm] Plugin "${pluginId}" is marked experimental. ` +
                `Enable "features.experimental" in Settings to load it.`
            );
        }

        // Block broad (unscoped) sensitive permissions unless the flag is on.
        // Scoped variants like "system.exec:powershell" are allowed without a flag.
        for (const perm of requested) {
            const blocked = FEATURE_GATED_PERMS[perm]; // exact match = unscoped
            if (blocked && !flags[blocked]) {
                throw new Error(
                    `[vm] Plugin "${pluginId}" requests "${perm}" (unrestricted). ` +
                    `Enable "${blocked}" in Settings -> Feature Flags to allow it.`
                );
            }
        }

        const saved = this._loadSavedPerms(pluginId);
        if (saved !== null) return saved;

        const winH = Math.min(Math.max(206 + requested.length * 54, 290), 500);

        // Expand ${dataDir} and ${pluginDataDir} in reason keys so they match expanded perms
        const pluginDataDir = path.join(this.dataDir, 'plugins', pluginId);
        const expandedReasons = {};
        for (const [k, v] of Object.entries(meta.permissionReasons || {})) {
            expandedReasons[k
                .replace('${dataDir}', this.dataDir)
                .replace('${pluginDataDir}', pluginDataDir)] = v;
        }

        const dialogData = {
            type            : 'plugin',
            appName         : this.appName,
            name            : meta.name    || meta.id,
            version         : meta.version || '',
            description     : meta.description || '',
            permissions     : requested,
            permDescriptions: PERM_DESCRIPTIONS,
            permReasons     : expandedReasons,
            winW            : 420,
            winH,
        };

        const granted = await this._showPermDialog(dialogData, 420, winH);
        if (!granted) {
            throw new Error(`[vm] Permission denied by user for plugin "${pluginId}"`);
        }

        const perms = new Set(requested);
        this._savePerms(pluginId, perms);
        return perms;
    }

    // -- Bundle permission check (merged dialog for all members) ---------------

    async _checkBundlePermissions(bundleMeta, memberMetas) {
        const anyMissing = memberMetas.some(meta => {
            const requested = (meta.permissions || []).map(p =>
                p.replace('${dataDir}', this.dataDir)
            );
            return requested.length > 0 && this._loadSavedPerms(meta.id) === null;
        });

        if (!anyMissing) return true;

        const groups = memberMetas
            .map(meta => {
                const pluginDataDir = path.join(this.dataDir, 'plugins', meta.id);
                const expandedReasons = {};
                for (const [k, v] of Object.entries(meta.permissionReasons || {})) {
                    expandedReasons[k
                        .replace('${dataDir}', this.dataDir)
                        .replace('${pluginDataDir}', pluginDataDir)] = v;
                }
                return {
                    id          : meta.id,
                    name        : meta.name || meta.id,
                    description : meta.description || '',
                    permissions : (meta.permissions || []).map(p =>
                        p.replace('${dataDir}', this.dataDir)
                         .replace('${pluginDataDir}', pluginDataDir)
                    ),
                    permReasons : expandedReasons,
                };
            })
            .filter(g => g.permissions.length > 0);

        const totalPerms   = groups.reduce((n, g) => n + g.permissions.length, 0);
        const groupHeaders = groups.length;
        const winH = Math.min(Math.max(216 + totalPerms * 58 + groupHeaders * 26, 290), 520);

        const dialogData = {
            type            : 'bundle',
            appName         : this.appName,
            name            : bundleMeta.name    || bundleMeta.id,
            version         : bundleMeta.version || '',
            description     : bundleMeta.description || '',
            plugins         : groups,
            permDescriptions: PERM_DESCRIPTIONS,
            winW            : 440,
            winH,
        };

        const granted = await this._showPermDialog(dialogData, 440, winH);
        if (!granted) return false;

        for (const meta of memberMetas) {
            const requested = (meta.permissions || []).map(p =>
                p.replace('${dataDir}', this.dataDir)
            );
            this._savePerms(meta.id, new Set(requested));
        }
        return true;
    }

    // -- Load a bundle (show merged dialog, then load each member) -------------

    async _loadBundle(bundleMeta, allPluginManifests, cache) {
        const memberIds = bundleMeta.plugins || [];
        const memberMetas = [];

        for (const id of memberIds) {
            const meta = allPluginManifests[id];
            if (!meta) {
                console.warn(`[vm] bundle "${bundleMeta.id}" member "${id}" not found in plugins folder`);
                continue;
            }
            memberMetas.push(meta);
        }

        if (memberMetas.length === 0) {
            console.warn(`[vm] bundle "${bundleMeta.id}" has no loadable members`);
            return;
        }

        console.log(`[vm] loading bundle "${bundleMeta.id}" (${memberMetas.map(m => m.id).join(', ')})`);

        const granted = await this._checkBundlePermissions(bundleMeta, memberMetas);
        if (!granted) {
            for (const meta of memberMetas) {
                cache[meta.id] = { status: 'denied', folder: meta._folder };
            }
            throw new Error(`[vm] Bundle "${bundleMeta.id}" denied by user`);
        }

        for (const meta of memberMetas) {
            if (this._loaded.includes(meta.id)) continue;
            try {
                await this.loadPlugin(meta._dir);
                cache[meta.id] = { status: 'loaded', folder: meta._folder };
            } catch (e) {
                console.error(`[vm] bundle member "${meta.id}" failed: ${e.message}`);
                cache[meta.id] = { status: 'error', folder: meta._folder, error: e.message };
            }
        }
    }

    // -- Management API (exposed as the 'vm' service) --------------------------

    /**
     * Returns the full plugin/bundle list from disk, annotated with live status.
     */
    getAllPlugins() {
        const cache = this._loadCache();
        const result = [];

        if (!fs.existsSync(this.pluginsDir)) return result;

        const folders = fs.readdirSync(this.pluginsDir).filter(e => {
            try { return fs.statSync(path.join(this.pluginsDir, e)).isDirectory(); }
            catch (_) { return false; }
        });

        for (const folder of folders) {
            const dir        = path.join(this.pluginsDir, folder);
            const bundleFile = path.join(dir, 'bundle.json');
            const pluginFile = path.join(dir, 'plugin.json');

            if (fs.existsSync(bundleFile)) {
                try {
                    const meta  = JSON.parse(fs.readFileSync(bundleFile, 'utf8'));
                    const entry = cache[meta.id] || {};
                    result.push({
                        id: meta.id, name: meta.name || meta.id,
                        version: meta.version || '', description: meta.description || '',
                        type: 'bundle', members: meta.plugins || [],
                        dependencies: [], permissions: [], dependents: [],
                        status: entry.status || 'new',
                        loaded: this._loaded.includes(meta.id),
                    });
                } catch (_) {}
            } else if (fs.existsSync(pluginFile)) {
                try {
                    const meta  = JSON.parse(fs.readFileSync(pluginFile, 'utf8'));
                    const entry = cache[meta.id] || {};
                    result.push({
                        id: meta.id, name: meta.name || meta.id,
                        version: meta.version || '', description: meta.description || '',
                        type: 'plugin',
                        dependencies: Object.keys(meta.dependencies || {}),
                        permissions: meta.permissions || [], dependents: [],
                        status: entry.status || 'new',
                        loaded: this._loaded.includes(meta.id),
                    });
                } catch (_) {}
            }
        }

        // Fill in dependents: which other plugins list this one as a dependency
        for (const p of result) {
            p.dependents = result
                .filter(q => q.dependencies.includes(p.id))
                .map(q => q.id);
        }

        return result;
    }

    /**
     * Returns a deep list of all plugin IDs that (transitively) depend on `id`.
     */
    getAllDependents(id) {
        const plugins = this.getAllPlugins();
        const direct = (x) => plugins.filter(p => p.dependencies.includes(x)).map(p => p.id);
        const visited = new Set();
        const walk = (x) => {
            if (visited.has(x)) return;
            visited.add(x);
            for (const d of direct(x)) walk(d);
        };
        walk(id);
        visited.delete(id);
        return [...visited];
    }

    /**
     * Mark a plugin as disabled. Effect is permanent but only fully takes effect
     * on next restart (we can't unload running plugin code).
     */
    disablePlugin(id) {
        const cache = this._loadCache();
        cache[id] = { ...(cache[id] || {}), status: 'disabled' };
        this._saveCache(cache);
        return { ok: true, restart_required: this._loaded.includes(id) };
    }

    /**
     * Re-enable a disabled/denied/errored plugin and immediately try to load it.
     */
    async enablePlugin(id) {
        const cache = this._loadCache();
        const existing = cache[id] || {};
        cache[id] = { status: 'loaded', ...(existing.folder ? { folder: existing.folder } : {}) };
        this._saveCache(cache);
        if (!this._loaded.includes(id)) {
            await this._syncPlugins();
        }
        return { ok: true, loaded: this._loaded.includes(id) };
    }

    /**
     * Delete saved permissions and re-prompt on next load attempt.
     */
    async resetPluginPerms(id) {
        try { fs.unlinkSync(this._permsFile(id)); } catch (_) {}
        const cache = this._loadCache();
        const existing = cache[id] || {};
        // If it was loaded before, mark as 'loaded' but without saved perms it will re-prompt
        cache[id] = { status: 'loaded', ...(existing.folder ? { folder: existing.folder } : {}) };
        this._saveCache(cache);
        // Remove from _loaded so the sync will attempt to re-run it (and re-prompt)
        this._loaded = this._loaded.filter(x => x !== id);
        await this._syncPlugins();
        return { ok: true };
    }

    // -- Sandbox context builder -----------------------------------------------

    _buildCtx(pluginId, grantedPerms, pluginDir, meta) {
        const self = this;

        const scopeRoots = (base) => {
            const roots = [];
            for (const p of grantedPerms) {
                if (!p.startsWith(base + ':')) continue;
                const scope = p.slice(base.length + 1).replace('${dataDir}', self.dataDir);
                roots.push(path.resolve(scope));
            }
            if (grantedPerms.has(base)) roots.push(path.resolve(path.join(__dirname, '..')));
            return roots;
        };

        const assertPath = (base, filePath) => {
            // Unscoped permission (e.g. "fs.read" with no path) = unrestricted access
            if (grantedPerms.has(base)) return;
            const roots = scopeRoots(base);
            if (roots.length === 0) throw new Error(`Permission denied: ${base} not granted`);
            const resolved = path.resolve(filePath);
            const ok = roots.some(r => resolved === r || resolved.startsWith(r + path.sep));
            if (!ok) throw new Error(`Permission denied: ${base} access outside allowed paths`);
        };

        const has = (perm) => grantedPerms.has(perm) ||
            [...grantedPerms].some(p => p === perm || p.startsWith(perm + ':'));

        return {
            pluginId,
            pluginDir,
            dataDir    : path.join(self.dataDir, 'plugins', pluginId),
            appName    : self.appName,
            appVersion : self.appVersion,
            loadedPlugins: () => [...self._loaded],

            readFile(filePath) {
                assertPath('fs.read', filePath);
                return fs.readFileSync(filePath, 'utf8');
            },
            readFileBuffer(filePath) {
                assertPath('fs.read', filePath);
                return fs.readFileSync(filePath);
            },
            writeFile(filePath, data) {
                assertPath('fs.write', filePath);
                fs.mkdirSync(path.dirname(filePath), { recursive: true });
                fs.writeFileSync(filePath, data, 'utf8');
            },
            existsSync(filePath) {
                assertPath('fs.read', filePath);
                return fs.existsSync(filePath);
            },
            readDir(dirPath) {
                assertPath('fs.read', dirPath);
                return fs.readdirSync(dirPath);
            },

            listen(port, handler) {
                if (!has('net.listen')) throw new Error('Permission denied: net.listen not granted');
                const allowed = [...grantedPerms]
                    .filter(p => p.startsWith('net.listen:'))
                    .map(p => parseInt(p.split(':')[1], 10));
                if (allowed.length > 0 && !allowed.includes(port)) {
                    throw new Error(`Permission denied: net.listen on port ${port} not granted`);
                }
                const server = http.createServer(handler);
                server.listen(port);
                return server;
            },

            fetch(url, options) {
                if (!has('net.connect')) throw new Error('Permission denied: net.connect not granted');
                const allowed = [...grantedPerms]
                    .filter(p => p.startsWith('net.connect:'))
                    .map(p => p.split(':')[1]);
                if (allowed.length > 0) {
                    try {
                        const host = new URL(url).hostname;
                        if (!allowed.includes(host)) {
                            throw new Error(`Permission denied: net.connect to "${host}" not granted`);
                        }
                    } catch (e) {
                        if (e.message.startsWith('Permission denied')) throw e;
                    }
                }
                return global.fetch
                    ? global.fetch(url, options)
                    : Promise.reject(new Error('fetch not available - upgrade Node.js to v18+'));
            },

            exec(cmd, args = []) {
                if (!has('system.exec')) throw new Error('Permission denied: system.exec not granted');
                const allowed = [...grantedPerms]
                    .filter(p => p.startsWith('system.exec:'))
                    .map(p => p.split(':')[1]);
                const cmdBase = path.basename(cmd).replace(/\.exe$/i, '').toLowerCase();
                if (allowed.length > 0 && !allowed.includes(cmdBase)) {
                    throw new Error(`Permission denied: system.exec for "${cmdBase}" not granted`);
                }
                return execFileSync(cmd, args, { encoding: 'utf8' });
            },

            execAsync(cmd) {
                if (!has('system.exec')) throw new Error('Permission denied: system.exec not granted');
                const allowed = [...grantedPerms]
                    .filter(p => p.startsWith('system.exec:'))
                    .map(p => p.split(':')[1]);
                if (allowed.length > 0) {
                    const cmdBase = cmd.trim().split(/\s+/)[0].toLowerCase();
                    if (!allowed.includes(cmdBase)) {
                        throw new Error(`Permission denied: system.exec for "${cmdBase}" not granted`);
                    }
                }
                return new Promise((res, rej) =>
                    exec(cmd, (err, stdout) => err ? rej(err) : res(stdout))
                );
            },

            /**
             * Launch a detached background process (fire-and-forget).
             * Requires system.exec permission for the target command.
             */
            spawnDetached(cmd, args = [], opts = {}) {
                if (!has('system.exec')) throw new Error('Permission denied: system.exec not granted');
                const allowed = [...grantedPerms]
                    .filter(p => p.startsWith('system.exec:'))
                    .map(p => p.split(':')[1]);
                const cmdBase = path.basename(cmd).replace(/\.exe$/i, '').toLowerCase();
                if (allowed.length > 0 && !allowed.includes(cmdBase)) {
                    throw new Error(`Permission denied: system.exec for "${cmdBase}" not granted`);
                }
                const child = spawn(cmd, args, {
                    detached   : true,
                    stdio      : 'ignore',
                    windowsHide: true,
                    ...opts,
                });
                child.unref();
                return child.pid;
            },

            provide(name, value) {
                if (!has('ctx.provide')) throw new Error('Permission denied: ctx.provide not granted');
                self._services.set(name, value);
                self._serviceProviders.set(name, pluginId);
            },

            use(name) {
                // The built-in 'vm' service is gated by the vm.manage permission
                if (name === 'vm') {
                    if (!has('vm.manage')) {
                        throw new Error('Permission denied: vm.manage not granted - declare it in plugin.json to access VM control');
                    }
                } else {
                    // Access gate: caller must declare the providing plugin as a dependency
                    const providerId = self._serviceProviders.get(name);
                    if (providerId) {
                        const deps = Object.keys(meta.dependencies || {});
                        if (!deps.includes(providerId)) {
                            throw new Error(
                                `Plugin "${pluginId}" used service "${name}" (from "${providerId}") ` +
                                `without declaring "${providerId}" as a dependency in plugin.json`
                            );
                        }
                    }
                }
                if (!self._services.has(name)) {
                    throw new Error(`Service "${name}" not found - is the plugin that provides it loaded?`);
                }
                const service = self._services.get(name);
                // Function filtering: "uses": { "log": ["info", "warn"] } in plugin.json
                const allowed = (meta.uses || {})[name];
                if (Array.isArray(allowed) && allowed.length > 0 &&
                    typeof service === 'object' && service !== null) {
                    return Object.fromEntries(
                        allowed
                            .filter(fn => typeof service[fn] === 'function')
                            .map(fn => [fn, service[fn].bind(service)])
                    );
                }
                return service;
            },

            broadcast(msg) {
                if (!has('ctx.broadcast')) throw new Error('Permission denied: ctx.broadcast not granted');
                const events = self._services.get('events');
                if (events) events.emit('vm:broadcast', msg);
            },
            onMessage(_type, _handler) {},
            reply(_socket, _msg) {},
        };
    }

    // -- Run plugin code in a Node vm sandbox ----------------------------------

    _runPlugin(pluginDir, meta, ctx) {
        const mainFile = path.join(pluginDir, meta.main || 'index.js');
        const code = fs.readFileSync(mainFile, 'utf8');

        const ALLOWED_BUILTINS = new Set([
            'path', 'events', 'util', 'url', 'querystring',
            'stream', 'crypto', 'buffer', 'string_decoder',
        ]);

        const moduleObj = { exports: {} };
        const sandbox = vm.createContext({
            module     : moduleObj,
            exports    : moduleObj.exports,
            __dirname  : pluginDir,
            __filename : mainFile,
            console,
            Buffer,
            setTimeout, clearTimeout, setInterval, clearInterval,
            Promise,
            require(id) {
                if (ALLOWED_BUILTINS.has(id)) return require(id);
                throw new Error(
                    `[vm] Plugin "${meta.id}" tried to require("${id}") - ` +
                    `use the ctx API instead or request the appropriate permission.`
                );
            },
        });

        vm.runInContext(code, sandbox, { filename: mainFile });

        const plugin = sandbox.module.exports;
        if (typeof plugin.install !== 'function') {
            throw new Error(`[vm] Plugin "${meta.id}" does not export an install() function`);
        }
        plugin.install(ctx);
    }

    // -- loadPlugin (single plugin, no cache management) ----------------------

    async loadPlugin(pluginDir) {
        const metaPath = path.join(pluginDir, 'plugin.json');
        const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));

        const pluginDataDir = path.join(this.dataDir, 'plugins', meta.id);
        const requested = (meta.permissions || []).map(p =>
            p.replace('${dataDir}', this.dataDir)
             .replace('${pluginDataDir}', pluginDataDir)
        );

        console.log(`[vm] loading "${meta.id}" (${meta.name || meta.id})`);

        const grantedPerms = await this._checkPermissions(meta.id, meta, requested);
        const ctx = this._buildCtx(meta.id, grantedPerms, pluginDir, meta);

        fs.mkdirSync(ctx.dataDir, { recursive: true });
        this._runPlugin(pluginDir, meta, ctx);

        this._loaded.push(meta.id);
        this._pluginMetas.set(meta.id, meta);   // track for dependency graph
        console.log(`[vm] "${meta.id}" loaded`);
    }

    // -- _syncPlugins: scan folder, update cache, load new plugins/bundles -----

    async _syncPlugins() {
        if (this._syncing) return;
        this._syncing = true;
        try { await this.__doSync(); }
        finally { this._syncing = false; }
    }

    async __doSync() {
        const cache = this._loadCache();

        if (!fs.existsSync(this.pluginsDir)) {
            console.warn(`[vm] plugins directory not found: ${this.pluginsDir}`);
            return;
        }

        // -- Snapshot current folders ------------------------------------------
        const presentFolders = new Set(
            fs.readdirSync(this.pluginsDir).filter(e => {
                try { return fs.statSync(path.join(this.pluginsDir, e)).isDirectory(); }
                catch (_) { return false; }
            })
        );

        // -- Mark removed items ------------------------------------------------
        for (const [id, entry] of Object.entries(cache)) {
            if (entry.status !== 'removed' && entry.folder && !presentFolders.has(entry.folder)) {
                console.log(`[vm] "${id}" folder removed - will re-try if added back`);
                cache[id] = { ...entry, status: 'removed' };
            }
        }

        // -- Separate bundles from plugins -------------------------------------
        const bundleManifests = {};
        const pluginManifests = {};

        for (const folder of presentFolders) {
            const dir        = path.join(this.pluginsDir, folder);
            const bundleFile = path.join(dir, 'bundle.json');
            const pluginFile = path.join(dir, 'plugin.json');

            if (fs.existsSync(bundleFile)) {
                try {
                    const meta   = JSON.parse(fs.readFileSync(bundleFile, 'utf8'));
                    meta._dir    = dir;
                    meta._folder = folder;
                    bundleManifests[meta.id] = meta;
                } catch (e) { console.error(`[vm] skipping bundle "${folder}": ${e.message}`); }
            } else if (fs.existsSync(pluginFile)) {
                try {
                    const meta   = JSON.parse(fs.readFileSync(pluginFile, 'utf8'));
                    meta._dir    = dir;
                    meta._folder = folder;
                    pluginManifests[meta.id] = meta;
                } catch (e) { console.error(`[vm] skipping plugin "${folder}": ${e.message}`); }
            }
        }

        // shouldLoad: returns true if this id should be loaded in this sync pass
        const shouldLoad = (id) => {
            if (this._loaded.includes(id)) return false;
            const entry = cache[id];
            if (!entry) return true;
            if (entry.status === 'removed')  return true;
            if (entry.status === 'loaded')   return true;   // new session
            if (entry.status === 'disabled') return false;  // explicitly disabled
            return false;                                   // denied / error - wait for drag cycle
        };

        // -- Load bundles first ------------------------------------------------
        for (const bundleId of Object.keys(bundleManifests)) {
            if (!shouldLoad(bundleId)) continue;
            const bundleMeta = bundleManifests[bundleId];
            try {
                await this._loadBundle(bundleMeta, pluginManifests, cache);
                this._loaded.push(bundleId);
                cache[bundleId] = { status: 'loaded', folder: bundleMeta._folder, type: 'bundle' };
            } catch (e) {
                const denied = e.message.includes('denied by user');
                console.log(`[vm] bundle "${bundleId}" ${denied ? 'denied by user' : 'failed: ' + e.message}`);
                cache[bundleId] = {
                    status: denied ? 'denied' : 'error',
                    folder: bundleMeta._folder, type: 'bundle',
                    ...(denied ? {} : { error: e.message }),
                };
            }
        }

        // -- Topological async load of standalone plugins ----------------------
        const visited = new Set();
        const load = async (id) => {
            if (visited.has(id)) return;
            visited.add(id);
            if (!shouldLoad(id)) return;

            const meta = pluginManifests[id];
            if (!meta) {
                console.warn(`[vm] dependency "${id}" not found in plugins folder`);
                return;
            }

            for (const dep of Object.keys(meta.dependencies || {})) await load(dep);

            try {
                await this.loadPlugin(meta._dir);
                cache[id] = { status: 'loaded', folder: meta._folder };
            } catch (e) {
                const denied = e.message.includes('Permission denied by user');
                console.log(`[vm] "${id}" ${denied ? 'denied by user' : 'failed: ' + e.message}`);
                cache[id] = { status: denied ? 'denied' : 'error', folder: meta._folder,
                    ...(denied ? {} : { error: e.message }) };
            }
        };

        for (const id of Object.keys(pluginManifests)) await load(id);

        this._saveCache(cache);
    }

    // -- Folder watcher --------------------------------------------------------

    watchPlugins() {
        if (!fs.existsSync(this.pluginsDir)) return;

        let debounce = null;
        fs.watch(this.pluginsDir, { persistent: true }, () => {
            clearTimeout(debounce);
            debounce = setTimeout(() => {
                this._syncPlugins().catch(e =>
                    console.error('[vm] watch sync error:', e.message)
                );
            }, 600);
        });

        console.log(`[vm] watching ${this.pluginsDir}`);
    }

    // -- Public API ------------------------------------------------------------

    async loadAll() {
        // Register the built-in VM control service before plugins load,
        // so plugins declared with vm.manage permission can use it immediately.
        this._serviceProviders.set('vm', '__builtin__');
        this._services.set('vm', {
            getAll         : ()     => this.getAllPlugins(),
            getDependents  : (id)   => this.getAllDependents(id),
            disable        : (id)   => this.disablePlugin(id),
            enable         : (id)   => this.enablePlugin(id),
            resetPerms     : (id)   => this.resetPluginPerms(id),
            getLoaded      : ()     => [...this._loaded],
        });

        await this._syncPlugins();
        this.watchPlugins();
    }
}

module.exports = { PluginVM };
'@

$FILE_LICENSE = @'
COMPUTER Source License 1.0
Copyright (c) 2026 COMPUTER

TERMS AND CONDITIONS

1. DEFINITIONS

"Software" means COMPUTER and all associated source code, documentation, and
configuration files distributed under this license.

"Plugin" means a separate work designed to extend or integrate with the
Software, which does not replicate the Software's core functionality and
depends on the Software to operate.

"Competing Product" means any product, service, or software whose primary
purpose substantially replicates or replaces the core functionality of the
Software, regardless of whether it is based on this source code.

2. GRANT OF RIGHTS

Subject to the conditions below, you are granted a worldwide, royalty-free,
non-exclusive license to:

a) Use, run, and inspect the Software for any personal or internal purpose.
b) Modify the Software for personal or internal use.
c) Create, use, modify, and distribute Plugins for the Software.
d) Incorporate third-party code into Plugins, provided the license of that
   third-party code permits such use.
e) Share and distribute the Software to others, provided this license
   accompanies any distribution and no source files are altered to misrepresent
   the origin of the Software.

3. RESTRICTIONS

a) You may not use, distribute, or incorporate this Software, in whole or
   in part, to build, market, or operate a Competing Product.

b) You may not redistribute a modified version of the Software itself (not
   as a Plugin) without prior written permission from the copyright holder.
   Unmodified redistribution is permitted under section 2(e).

c) You may not remove or alter any copyright, license, or attribution
   notices present in the Software.

4. PROHIBITED USES

You may not use the Software:

a) For any purpose that is unlawful, harmful, abusive, threatening,
   harassing, defamatory, or otherwise objectionable.

b) To facilitate or participate in any illegal activity, including but not
   limited to fraud, malware distribution, unauthorized access to systems,
   or violation of any applicable law or regulation.

c) In any manner that could damage, disable, overburden, or impair the
   Software or its associated infrastructure.

5. REGIONAL COMPLIANCE

You are solely responsible for determining whether your use of the Software
is lawful in your jurisdiction. The authors make no representation that the
Software is appropriate or available for use in any specific location. If
access to or use of the Software is prohibited by the laws of your region,
you must not use it. Proceeding with installation or use constitutes your
confirmation that such use is permitted under the laws applicable to you.

6. PLUGINS AND OPEN SOURCE REQUIREMENT

The COMPUTER ecosystem is built on the principle that users should always be
able to inspect, audit, and trust what runs on their machines. To uphold this
principle, the following requirements apply to all publicly distributed Plugins:

a) Any Plugin distributed publicly (released outside of personal or internal
   use) MUST be licensed under the GNU Affero General Public License v3.0
   (AGPLv3) or a compatible license approved in writing by the copyright
   holder.

   Full license text: https://www.gnu.org/licenses/agpl-3.0
   Plain-language summary: https://www.tldrlegal.com/license/gnu-affero-general-public-license-v3-agpl-3-0

b) Any publicly distributed Plugin MUST make its complete source code freely
   available. Closed-source plugins distributed to others are not permitted
   in the COMPUTER ecosystem.

c) Plugins you create for personal or internal use are not subject to these
   distribution requirements and may be kept private.

d) The AGPLv3 requirement exists because COMPUTER connects to networks and
   AI providers. The AGPLv3 closes the "network use" loophole - if you modify
   a plugin and offer it to others over a network, you must provide the source.
   This ensures the entire ecosystem remains open and auditable.

e) Third-party libraries incorporated into Plugins must be compatible with
   AGPLv3. The plugin author is responsible for ensuring compatibility.

f) A Plugin does not constitute a Competing Product solely by implementing
   features that interact with or extend the Software's functionality.

7. OPEN SOURCE COMMITMENT

The authors commit that the Software itself will remain open source and freely
available under these terms. The source code for the Software, including the
installer, runtime, and all core components, will always be publicly accessible
for inspection and audit before running on any machine.

8. DISCLAIMER - USE AT YOUR OWN RISK

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED. YOU USE THIS SOFTWARE ENTIRELY AT YOUR OWN RISK.

THE AUTHORS AND COPYRIGHT HOLDERS EXPRESSLY DISCLAIM ALL WARRANTIES,
INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE, ACCURACY, AND NONINFRINGEMENT.

IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING BUT NOT LIMITED TO LOSS OF DATA, LOSS OF PROFITS, BUSINESS
INTERRUPTION, OR ANY OTHER LOSS) ARISING OUT OF OR IN CONNECTION WITH THE
USE OR INABILITY TO USE THE SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
OF SUCH DAMAGES.
'@

$FILE_README_MD = @'
# app

> **Part of [burgil-industries/computer](https://github.com/burgil-industries/computer)**
> [`computer`](https://github.com/burgil-industries/computer) -> **`app`** | [`installer`](https://github.com/burgil-industries/installer) | [`public`](https://github.com/burgil-industries/public) | [`plugins`](https://github.com/burgil-industries/plugins)

---

This repository contains the files that are **written to the user's machine** at install time. Nothing here runs during installation - these files are the application that gets installed.

## How it works

[`build.ps1`](https://github.com/burgil-industries/computer/blob/main/build.ps1) (in the root repo) processes [`installer/main.ps1`](https://github.com/burgil-industries/installer/blob/main/main.ps1), which contains:

```
{{EMBED_DIR:app}}
```

This directive reads every file under `app/` and encodes each one as a PowerShell here-string variable inside `public/install.ps1`. At install time, the installer script extracts those variables back to disk.

### File -> variable -> disk path

| Source file | Variable in install.ps1 | Written to |
|---|---|---|
| `data/lib/router.ps1` | `$FILE_DATA_LIB_ROUTER_PS1` | `<install_dir>/data/lib/router.ps1` |
| `data/src/app.js` | `$FILE_DATA_SRC_APP_JS` | `<install_dir>/data/src/app.js` |
| `__APP_NAME__.cmd` | `$FILE___APP_NAME___CMD` | `<install_dir>/__APP_NAME__.cmd` |

Variable naming rule: `FILE_` + relative path with `/`, `\`, `.`, `-` replaced by `_`, uppercased.

## What to edit

Edit files here to change what ends up on the user's machine. Then run [`build.ps1`](https://github.com/burgil-industries/computer/blob/main/build.ps1) from the root repo to regenerate [`public/install.ps1`](https://github.com/burgil-industries/public/blob/main/install.ps1).

```powershell
# From the computer/ root:
.\build.ps1
```

Do **not** edit [`public/install.ps1`](https://github.com/burgil-industries/public/blob/main/install.ps1) directly - it is a generated file and will be overwritten.

## Layout

```
data/
  lib/          Runtime scripts (router, updater, uninstaller, startup hooks)
  src/          Application source (app.js, app.py, permissions.js)
__APP_NAME__.cmd  Launcher stub (name filled in at install time)
LICENSE
```
'@

$FILE_MANIFEST = [ordered]@{
    'data/__APP_NAME__.cmd' = $FILE_DATA___APP_NAME___CMD
    'data/lib/check-update.ps1' = $FILE_DATA_LIB_CHECK_UPDATE_PS1
    'data/lib/check-update.vbs' = $FILE_DATA_LIB_CHECK_UPDATE_VBS
    'data/lib/repair.vbs' = $FILE_DATA_LIB_REPAIR_VBS
    'data/lib/router.ps1' = $FILE_DATA_LIB_ROUTER_PS1
    'data/lib/router.vbs' = $FILE_DATA_LIB_ROUTER_VBS
    'data/lib/sendto.vbs' = $FILE_DATA_LIB_SENDTO_VBS
    'data/lib/startup.vbs' = $FILE_DATA_LIB_STARTUP_VBS
    'data/lib/uninstall.ps1' = $FILE_DATA_LIB_UNINSTALL_PS1
    'data/lib/uninstall.vbs' = $FILE_DATA_LIB_UNINSTALL_VBS
    'data/src/app.js' = $FILE_DATA_SRC_APP_JS
    'data/src/app.py' = $FILE_DATA_SRC_APP_PY
    'data/src/dialog.html' = $FILE_DATA_SRC_DIALOG_HTML
    'data/src/vm.js' = $FILE_DATA_SRC_VM_JS
    'LICENSE' = $FILE_LICENSE
    'README.md' = $FILE_README_MD
}

# --- Plugin files (auto-embedded from plugins/ by build.ps1) ---
$FILE_PLUGINS_CORE_INDEX_JS = @'
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
'use strict';
const EventEmitter = require('events');
const path         = require('path');

// Feature flags: safe defaults shipped with the app.
// Only written on first run (if the key is absent); user values are never overwritten.
const FEATURE_DEFAULTS = {
    'features.experimental'        : false,
    'features.unrestricted_exec'   : false,
    'features.unrestricted_network': false,
};

// -- EventBus ------------------------------------------------------------------
class EventBus extends EventEmitter {}

// -- Config --------------------------------------------------------------------
class Config {
    constructor(ctx) {
        this._ctx  = ctx;
        this._file = path.join(ctx.dataDir, 'config.json');
        this._data = {};
        this._load();
    }

    _load() {
        try { this._data = JSON.parse(this._ctx.readFile(this._file)); }
        catch (_) { this._data = {}; }
    }

    get(key, def = undefined) {
        return key in this._data ? this._data[key] : def;
    }

    set(key, val) {
        this._data[key] = val;
        try { this._ctx.writeFile(this._file, JSON.stringify(this._data, null, 2)); }
        catch (e) { console.error(`[core] config write failed: ${e.message}`); }
    }

    all() { return Object.assign({}, this._data); }
}

// -- Logger --------------------------------------------------------------------
function makeLogger(events) {
    return function log(msg, level = 'INFO') {
        const line = `[${new Date().toISOString()}] [${level}] ${msg}`;
        console.log(line);
        events.emit('core:log', { level, msg, line });
    };
}

// -- Plugin install ------------------------------------------------------------
module.exports = {
    install(ctx) {
        const bus    = new EventBus();
        const config = new Config(ctx);
        const log    = makeLogger(bus);

        ctx.provide('events', bus);
        ctx.provide('config', config);
        ctx.provide('log',    log);

        // Seed feature flags with safe defaults on first run
        for (const [key, def] of Object.entries(FEATURE_DEFAULTS)) {
            if (config.get(key) === undefined) config.set(key, def);
        }

        log(`core plugin loaded`);
    }
};
'@

$FILE_PLUGINS_CORE_LICENSE_AGPL3 = @'

                    GNU AFFERO GENERAL PUBLIC LICENSE
                       Version 3, 19 November 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU Affero General Public License is a free, copyleft license for
software and other kinds of works, specifically designed to ensure
cooperation with the community in the case of network server software.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
our General Public Licenses are intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  Developers that use our General Public Licenses protect your rights
with two steps: (1) assert copyright on the software, and (2) offer
you this License which gives you legal permission to copy, distribute
and/or modify the software.

  A secondary benefit of defending all users' freedom is that
improvements made in alternate versions of the program, if they
receive widespread use, become available for other developers to
incorporate.  Many developers of free software are heartened and
encouraged by the resulting cooperation.  However, in the case of
software used on network servers, this result may fail to come about.
The GNU General Public License permits making a modified version and
letting the public access it on a server without ever releasing its
source code to the public.

  The GNU Affero General Public License is designed specifically to
ensure that, in such cases, the modified source code becomes available
to the community.  It requires the operator of a network server to
provide the source code of the modified version running there to the
users of that server.  Therefore, public use of a modified version, on
a publicly accessible server, gives the public access to the source
code of the modified version.

  An older license, called the Affero General Public License and
published by Affero, was designed to accomplish similar goals.  This is
a different license, not a version of the Affero GPL, but Affero has
released a new version of the Affero GPL which permits relicensing under
this license.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU Affero General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Remote Network Interaction; Use with the GNU General Public License.

  Notwithstanding any other provision of this License, if you modify the
Program, your modified version must prominently offer all users
interacting with it remotely through a computer network (if your version
supports such interaction) an opportunity to receive the Corresponding
Source of your version by providing access to the Corresponding Source
from a network server at no charge, through some standard or customary
means of facilitating copying of software.  This Corresponding Source
shall include the Corresponding Source for any work covered by version 3
of the GNU General Public License that is incorporated pursuant to the
following paragraph.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the work with which it is combined will remain governed by version
3 of the GNU General Public License.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU Affero General Public License from time to time.  Such new versions
will be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU Affero General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU Affero General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU Affero General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If your software can interact with users remotely through a computer
network, you should also make sure that it provides a way for users to
get its source.  For example, if your program is a web application, its
interface could display a "Source" link that leads users to an archive
of the code.  There are many ways you could offer source, and different
solutions will be better for different programs; see section 13 for the
specific requirements.

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU AGPL, see
<https://www.gnu.org/licenses/>.
'@

$FILE_PLUGINS_CORE_PLUGIN_JSON = @'
{
  "id": "core",
  "name": "Core",
  "version": "1.0.0",
  "description": "Core plugin - event bus, persistent config, logger",
  "main": "index.js",
  "dependencies": {},
  "permissions": [
    "fs.read:${dataDir}",
    "fs.write:${dataDir}",
    "ctx.provide"
  ]
}
'@

$FILE_PLUGINS_ESSENTIALS_BUNDLE_JSON = @'
{
  "id": "essentials",
  "name": "COMPUTER Essentials",
  "version": "1.0.0",
  "description": "The core foundation every COMPUTER installation needs.",
  "plugins": ["core", "ui", "settings", "manager", "tray"]
}
'@

$FILE_PLUGINS_ESSENTIALS_LICENSE_AGPL3 = @'

                    GNU AFFERO GENERAL PUBLIC LICENSE
                       Version 3, 19 November 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU Affero General Public License is a free, copyleft license for
software and other kinds of works, specifically designed to ensure
cooperation with the community in the case of network server software.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
our General Public Licenses are intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  Developers that use our General Public Licenses protect your rights
with two steps: (1) assert copyright on the software, and (2) offer
you this License which gives you legal permission to copy, distribute
and/or modify the software.

  A secondary benefit of defending all users' freedom is that
improvements made in alternate versions of the program, if they
receive widespread use, become available for other developers to
incorporate.  Many developers of free software are heartened and
encouraged by the resulting cooperation.  However, in the case of
software used on network servers, this result may fail to come about.
The GNU General Public License permits making a modified version and
letting the public access it on a server without ever releasing its
source code to the public.

  The GNU Affero General Public License is designed specifically to
ensure that, in such cases, the modified source code becomes available
to the community.  It requires the operator of a network server to
provide the source code of the modified version running there to the
users of that server.  Therefore, public use of a modified version, on
a publicly accessible server, gives the public access to the source
code of the modified version.

  An older license, called the Affero General Public License and
published by Affero, was designed to accomplish similar goals.  This is
a different license, not a version of the Affero GPL, but Affero has
released a new version of the Affero GPL which permits relicensing under
this license.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU Affero General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Remote Network Interaction; Use with the GNU General Public License.

  Notwithstanding any other provision of this License, if you modify the
Program, your modified version must prominently offer all users
interacting with it remotely through a computer network (if your version
supports such interaction) an opportunity to receive the Corresponding
Source of your version by providing access to the Corresponding Source
from a network server at no charge, through some standard or customary
means of facilitating copying of software.  This Corresponding Source
shall include the Corresponding Source for any work covered by version 3
of the GNU General Public License that is incorporated pursuant to the
following paragraph.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the work with which it is combined will remain governed by version
3 of the GNU General Public License.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU Affero General Public License from time to time.  Such new versions
will be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU Affero General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU Affero General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU Affero General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If your software can interact with users remotely through a computer
network, you should also make sure that it provides a way for users to
get its source.  For example, if your program is a web application, its
interface could display a "Source" link that leads users to an archive
of the code.  There are many ways you could offer source, and different
solutions will be better for different programs; see section 13 for the
specific requirements.

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU AGPL, see
<https://www.gnu.org/licenses/>.
'@

$FILE_PLUGINS_EXAMPLE_INDEX_JS = @'
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
'use strict';
const path = require('path');

module.exports = {
    install(ctx) {
        const log = ctx.use('log');

        log(`example: data dir -> ${ctx.dataDir}`);

        // Write a greeting to the plugin's data directory
        const greetFile = path.join(ctx.dataDir, 'hello.txt');
        ctx.writeFile(greetFile, `Hello from ${ctx.pluginId} at ${new Date().toISOString()}\n`);
        log(`example: wrote -> ${greetFile}`);

        // Read it back and log it
        const content = ctx.readFile(greetFile);
        log(`example: ${content.trim()}`);

        log('example plugin loaded');
    }
};
'@

$FILE_PLUGINS_EXAMPLE_LICENSE_AGPL3 = @'

                    GNU AFFERO GENERAL PUBLIC LICENSE
                       Version 3, 19 November 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU Affero General Public License is a free, copyleft license for
software and other kinds of works, specifically designed to ensure
cooperation with the community in the case of network server software.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
our General Public Licenses are intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  Developers that use our General Public Licenses protect your rights
with two steps: (1) assert copyright on the software, and (2) offer
you this License which gives you legal permission to copy, distribute
and/or modify the software.

  A secondary benefit of defending all users' freedom is that
improvements made in alternate versions of the program, if they
receive widespread use, become available for other developers to
incorporate.  Many developers of free software are heartened and
encouraged by the resulting cooperation.  However, in the case of
software used on network servers, this result may fail to come about.
The GNU General Public License permits making a modified version and
letting the public access it on a server without ever releasing its
source code to the public.

  The GNU Affero General Public License is designed specifically to
ensure that, in such cases, the modified source code becomes available
to the community.  It requires the operator of a network server to
provide the source code of the modified version running there to the
users of that server.  Therefore, public use of a modified version, on
a publicly accessible server, gives the public access to the source
code of the modified version.

  An older license, called the Affero General Public License and
published by Affero, was designed to accomplish similar goals.  This is
a different license, not a version of the Affero GPL, but Affero has
released a new version of the Affero GPL which permits relicensing under
this license.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU Affero General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Remote Network Interaction; Use with the GNU General Public License.

  Notwithstanding any other provision of this License, if you modify the
Program, your modified version must prominently offer all users
interacting with it remotely through a computer network (if your version
supports such interaction) an opportunity to receive the Corresponding
Source of your version by providing access to the Corresponding Source
from a network server at no charge, through some standard or customary
means of facilitating copying of software.  This Corresponding Source
shall include the Corresponding Source for any work covered by version 3
of the GNU General Public License that is incorporated pursuant to the
following paragraph.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the work with which it is combined will remain governed by version
3 of the GNU General Public License.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU Affero General Public License from time to time.  Such new versions
will be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU Affero General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU Affero General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU Affero General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If your software can interact with users remotely through a computer
network, you should also make sure that it provides a way for users to
get its source.  For example, if your program is a web application, its
interface could display a "Source" link that leads users to an archive
of the code.  There are many ways you could offer source, and different
solutions will be better for different programs; see section 13 for the
specific requirements.

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU AGPL, see
<https://www.gnu.org/licenses/>.
'@

$FILE_PLUGINS_EXAMPLE_PLUGIN_JSON = @'
{
  "id": "example",
  "name": "Example",
  "version": "1.0.0",
  "description": "Minimal example plugin - reads a file and logs it via the core logger",
  "main": "index.js",
  "dependencies": {
    "core": "*"
  },
  "permissions": [
    "fs.read:${dataDir}",
    "fs.write:${dataDir}"
  ]
}
'@

$FILE_PLUGINS_EXAMPLE_TODO_TXT = @'
Under construction
'@

$FILE_PLUGINS_MANAGER_INDEX_JS = @'
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
'use strict';
const path = require('path');

const PORT = 53422;

module.exports = {
    install(ctx) {
        const log    = ctx.use('log');
        const vmCtrl = ctx.use('vm');

        // Read panel HTML once at install time (avoids require('fs') in handlers)
        const panelHtml = ctx.readFile(path.join(__dirname, 'panel.html'));

        // -- REST API + panel server --------------------------------------------
        const server = ctx.listen(PORT, (req, res) => {
            res.setHeader('Access-Control-Allow-Origin', '*');
            res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
            res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

            if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

            const url = req.url || '/';

            // -- Panel HTML (served directly from this plugin's directory) ------
            if (req.method === 'GET' && (url === '/' || url === '/index.html')) {
                res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
                res.end(panelHtml);
                return;
            }

            // -- GET /api/plugins -----------------------------------------------
            if (req.method === 'GET' && url === '/api/plugins') {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(vmCtrl.getAll()));
                return;
            }

            // -- POST /api/plugins/:id/disable ----------------------------------
            if (req.method === 'POST' && /^\/api\/plugins\/[^/]+\/disable$/.test(url)) {
                const id = url.split('/')[3];
                const dependents = vmCtrl.getDependents(id);
                if (dependents.length > 0) {
                    // Return dependents list so the UI can confirm
                    res.writeHead(409, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ conflict: true, dependents }));
                    return;
                }
                const result = vmCtrl.disable(id);
                log(`manager: disabled "${id}" (restart_required=${result.restart_required})`);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(result));
                return;
            }

            // -- POST /api/plugins/:id/disable-force ----------------------------
            // Disables the plugin AND all dependents in one shot.
            if (req.method === 'POST' && /^\/api\/plugins\/[^/]+\/disable-force$/.test(url)) {
                const id = url.split('/')[3];
                const dependents = vmCtrl.getDependents(id);
                for (const dep of dependents) vmCtrl.disable(dep);
                const result = vmCtrl.disable(id);
                log(`manager: force-disabled "${id}" + dependents [${dependents.join(', ')}]`);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ ...result, also_disabled: dependents }));
                return;
            }

            // -- POST /api/plugins/:id/enable -----------------------------------
            if (req.method === 'POST' && /^\/api\/plugins\/[^/]+\/enable$/.test(url)) {
                const id = url.split('/')[3];
                vmCtrl.enable(id).then(result => {
                    log(`manager: enabled "${id}" (loaded=${result.loaded})`);
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify(result));
                }).catch(err => {
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ ok: false, error: err.message }));
                });
                return;
            }

            // -- POST /api/plugins/:id/reset-perms -----------------------------
            if (req.method === 'POST' && /^\/api\/plugins\/[^/]+\/reset-perms$/.test(url)) {
                const id = url.split('/')[3];
                vmCtrl.resetPerms(id).then(result => {
                    log(`manager: reset permissions for "${id}"`);
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify(result));
                }).catch(err => {
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ ok: false, error: err.message }));
                });
                return;
            }

            res.writeHead(404); res.end('Not found');
        });

        server.on('error', err => log(`manager: server error - ${err.message}`, 'ERROR'));

        // Register as a redirect panel in the UI plugin
        const registerPanel = ctx.use('ui.registerPanel');
        registerPanel('manager', `http://127.0.0.1:${PORT}/`, 'Plugin Manager');

        log(`manager: panel server -> http://127.0.0.1:${PORT}`);
        log('manager plugin loaded');
    },
};
'@

$FILE_PLUGINS_MANAGER_LICENSE_AGPL3 = @'

                    GNU AFFERO GENERAL PUBLIC LICENSE
                       Version 3, 19 November 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU Affero General Public License is a free, copyleft license for
software and other kinds of works, specifically designed to ensure
cooperation with the community in the case of network server software.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
our General Public Licenses are intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  Developers that use our General Public Licenses protect your rights
with two steps: (1) assert copyright on the software, and (2) offer
you this License which gives you legal permission to copy, distribute
and/or modify the software.

  A secondary benefit of defending all users' freedom is that
improvements made in alternate versions of the program, if they
receive widespread use, become available for other developers to
incorporate.  Many developers of free software are heartened and
encouraged by the resulting cooperation.  However, in the case of
software used on network servers, this result may fail to come about.
The GNU General Public License permits making a modified version and
letting the public access it on a server without ever releasing its
source code to the public.

  The GNU Affero General Public License is designed specifically to
ensure that, in such cases, the modified source code becomes available
to the community.  It requires the operator of a network server to
provide the source code of the modified version running there to the
users of that server.  Therefore, public use of a modified version, on
a publicly accessible server, gives the public access to the source
code of the modified version.

  An older license, called the Affero General Public License and
published by Affero, was designed to accomplish similar goals.  This is
a different license, not a version of the Affero GPL, but Affero has
released a new version of the Affero GPL which permits relicensing under
this license.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU Affero General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Remote Network Interaction; Use with the GNU General Public License.

  Notwithstanding any other provision of this License, if you modify the
Program, your modified version must prominently offer all users
interacting with it remotely through a computer network (if your version
supports such interaction) an opportunity to receive the Corresponding
Source of your version by providing access to the Corresponding Source
from a network server at no charge, through some standard or customary
means of facilitating copying of software.  This Corresponding Source
shall include the Corresponding Source for any work covered by version 3
of the GNU General Public License that is incorporated pursuant to the
following paragraph.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the work with which it is combined will remain governed by version
3 of the GNU General Public License.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU Affero General Public License from time to time.  Such new versions
will be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU Affero General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU Affero General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU Affero General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If your software can interact with users remotely through a computer
network, you should also make sure that it provides a way for users to
get its source.  For example, if your program is a web application, its
interface could display a "Source" link that leads users to an archive
of the code.  There are many ways you could offer source, and different
solutions will be better for different programs; see section 13 for the
specific requirements.

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU AGPL, see
<https://www.gnu.org/licenses/>.
'@

$FILE_PLUGINS_MANAGER_PANEL_HTML = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Plugin Manager</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --bg:        #08080d;
  --surface:   #0f0f17;
  --surface-2: #161620;
  --surface-3: #1c1c28;
  --border:    #22222e;
  --text:      #e2e8f0;
  --muted:     #64748b;
  --dim:       #94a3b8;
  --green:     #10b981;
  --red:       #ef4444;
  --orange:    #f97316;
  --blue:      #3b82f6;
  --yellow:    #eab308;
  --mono:      'Cascadia Code', 'Consolas', monospace;
}

html, body { height: 100%; background: var(--bg); color: var(--text);
  font-family: 'Segoe UI', system-ui, sans-serif; font-size: 14px;
  -webkit-font-smoothing: antialiased; }

/* -- Layout -- */
body { display: flex; flex-direction: column; }

.topbar {
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  padding: 14px 24px;
  display: flex;
  align-items: center;
  gap: 16px;
  flex-shrink: 0;
}

.topbar-title { font-size: 16px; font-weight: 700; letter-spacing: -.3px; flex-shrink: 0; }
.topbar-sub   { font-size: 11px; color: var(--muted); flex-shrink: 0; }

.search-wrap { flex: 1; max-width: 300px; position: relative; }
.search-wrap svg { position: absolute; left: 10px; top: 50%; transform: translateY(-50%);
  width: 14px; height: 14px; color: var(--muted); pointer-events: none; }
#search { width: 100%; background: var(--surface-3); border: 1px solid var(--border);
  border-radius: 7px; padding: 7px 10px 7px 32px; color: var(--text); font-size: 12px;
  font-family: inherit; outline: none; }
#search:focus { border-color: #3b3b55; }

.filters { display: flex; gap: 6px; }
.filter-btn { background: var(--surface-3); border: 1px solid var(--border);
  border-radius: 6px; padding: 5px 12px; font-size: 11px; font-weight: 600;
  color: var(--dim); cursor: pointer; transition: all .15s; }
.filter-btn:hover { border-color: #3b3b55; color: var(--text); }
.filter-btn.active { background: var(--surface-2); border-color: #4b4b66; color: var(--text); }

.refresh-btn { background: none; border: 1px solid var(--border); border-radius: 6px;
  padding: 5px 10px; color: var(--dim); cursor: pointer; display: flex;
  align-items: center; gap: 5px; font-size: 11px; font-family: inherit; transition: all .15s; }
.refresh-btn:hover { border-color: #3b3b55; color: var(--text); }
.refresh-btn svg { width: 12px; height: 12px; }

.content { flex: 1; overflow-y: auto; padding: 20px 24px;
  scrollbar-width: thin; scrollbar-color: var(--surface-3) transparent; }
.content::-webkit-scrollbar { width: 5px; }
.content::-webkit-scrollbar-thumb { background: var(--surface-3); border-radius: 3px; }

/* -- Plugin cards -- */
.plugin-grid { display: flex; flex-direction: column; gap: 8px; }

.plugin-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 14px 16px;
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 8px 16px;
  transition: border-color .15s;
}
.plugin-card:hover { border-color: #2e2e3e; }
.plugin-card.loaded  { border-left: 3px solid var(--green); }
.plugin-card.denied  { border-left: 3px solid var(--red); }
.plugin-card.error   { border-left: 3px solid var(--orange); }
.plugin-card.disabled{ border-left: 3px solid var(--muted); }
.plugin-card.bundle  { border-left: 3px solid var(--blue); }
.plugin-card.new     { border-left: 3px solid var(--yellow); }

.card-main { display: flex; align-items: flex-start; gap: 12px; }

.card-avatar {
  width: 36px; height: 36px; border-radius: 9px; flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
  font-size: 15px; font-weight: 700; border: 1px solid var(--border);
}

.card-info { flex: 1; min-width: 0; }

.card-name-row { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-bottom: 3px; }
.card-name  { font-size: 14px; font-weight: 600; }
.card-ver   { font-size: 10px; color: var(--muted); background: var(--surface-3);
  border: 1px solid var(--border); border-radius: 4px; padding: 1px 5px; }
.card-badge { font-size: 10px; font-weight: 700; padding: 1px 7px; border-radius: 10px;
  text-transform: uppercase; letter-spacing: .04em; }
.badge-loaded   { background: #0d2e1f; color: var(--green); }
.badge-denied   { background: #2d1212; color: var(--red); }
.badge-error    { background: #2d1a0d; color: var(--orange); }
.badge-disabled { background: var(--surface-3); color: var(--muted); }
.badge-bundle   { background: #0d1a35; color: var(--blue); }
.badge-new      { background: #2d2700; color: var(--yellow); }

.card-desc { font-size: 12px; color: var(--muted); margin-bottom: 5px;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

.card-meta { display: flex; gap: 12px; flex-wrap: wrap; }
.card-meta-item { font-size: 10px; color: var(--muted); display: flex; align-items: center; gap: 4px; }
.card-meta-item strong { color: var(--dim); }
.dep-link { color: var(--dim); text-decoration: none; cursor: default; }
.dep-link:hover { color: var(--text); text-decoration: underline; cursor: pointer; }

.card-actions { display: flex; flex-direction: column; align-items: flex-end;
  gap: 8px; justify-content: flex-start; }

/* -- Toggle switch -- */
.toggle-wrap { display: flex; align-items: center; gap: 6px; }
.toggle-label { font-size: 10px; color: var(--muted); }

.toggle { position: relative; display: inline-block; width: 38px; height: 22px; }
.toggle input { opacity: 0; width: 0; height: 0; }
.toggle-track {
  position: absolute; inset: 0; cursor: pointer;
  background: var(--surface-3); border: 1px solid var(--border);
  border-radius: 22px; transition: background .2s, border-color .2s;
}
.toggle-thumb {
  position: absolute; left: 3px; top: 3px;
  width: 14px; height: 14px; border-radius: 50%;
  background: var(--muted); transition: transform .2s, background .2s;
}
.toggle input:checked + .toggle-track { background: #0d2e1f; border-color: var(--green); }
.toggle input:checked + .toggle-track .toggle-thumb { background: var(--green); transform: translateX(16px); }
.toggle input:disabled + .toggle-track { opacity: .4; cursor: default; }

.action-btn {
  background: none; border: 1px solid var(--border); border-radius: 6px;
  padding: 4px 9px; font-size: 10px; font-weight: 600; color: var(--muted);
  cursor: pointer; font-family: inherit; transition: all .15s; white-space: nowrap;
}
.action-btn:hover { border-color: #3b3b55; color: var(--text); }

.error-msg { font-size: 10px; color: var(--orange); font-family: var(--mono);
  background: #2d1a0d; border-radius: 4px; padding: 3px 6px; max-width: 180px;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

/* -- Empty / loading -- */
.empty { text-align: center; color: var(--muted); padding: 60px 0; font-size: 13px; }

/* -- Confirm modal -- */
.modal-backdrop {
  display: none; position: fixed; inset: 0;
  background: rgba(0,0,0,.65); z-index: 100;
  align-items: center; justify-content: center;
}
.modal-backdrop.show { display: flex; }
.modal {
  background: var(--surface); border: 1px solid var(--border);
  border-radius: 12px; padding: 24px; max-width: 360px; width: 100%; margin: 16px;
  animation: pop .18s ease;
}
@keyframes pop { from { opacity: 0; transform: scale(.94); } to { opacity: 1; transform: none; } }
.modal h3 { font-size: 15px; font-weight: 700; margin-bottom: 10px; }
.modal p  { font-size: 12px; color: var(--dim); line-height: 1.6; margin-bottom: 14px; }
.dep-list { font-size: 11px; font-family: var(--mono); color: var(--orange);
  background: #2d1a0d; border-radius: 6px; padding: 8px 10px; margin-bottom: 16px;
  list-style: none; display: flex; flex-direction: column; gap: 3px; }
.modal-actions { display: flex; gap: 8px; justify-content: flex-end; }
.modal-actions button { border: none; border-radius: 7px; padding: 8px 18px;
  font-size: 12px; font-weight: 600; font-family: inherit; cursor: pointer; }
.btn-cancel { background: var(--surface-3); color: var(--dim);
  border: 1px solid var(--border); }
.btn-cancel:hover { background: var(--surface-2); }
.btn-confirm { background: var(--red); color: #fff; }
.btn-confirm:hover { opacity: .88; }

/* -- Toast -- */
.toast {
  position: fixed; bottom: 20px; right: 20px;
  background: var(--surface); border: 1px solid var(--border); border-radius: 8px;
  padding: 10px 16px; font-size: 12px; color: var(--text); z-index: 200;
  animation: slidein .2s ease; pointer-events: none;
}
@keyframes slidein { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: none; } }
</style>
</head>
<body>

<div class="topbar">
  <div>
    <div class="topbar-title">Plugin Manager</div>
    <div class="topbar-sub" id="topbar-sub">Loading...</div>
  </div>

  <div class="search-wrap">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
    </svg>
    <input id="search" type="text" placeholder="Search plugins..." oninput="render()">
  </div>

  <div class="filters">
    <button class="filter-btn active" onclick="setFilter('all',this)">All</button>
    <button class="filter-btn" onclick="setFilter('loaded',this)">Loaded</button>
    <button class="filter-btn" onclick="setFilter('disabled',this)">Disabled</button>
    <button class="filter-btn" onclick="setFilter('problem',this)">Problems</button>
  </div>

  <button class="refresh-btn" onclick="load()">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="23 4 23 10 17 10"/>
      <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
    </svg>
    Refresh
  </button>
</div>

<div class="content">
  <div class="plugin-grid" id="grid"><div class="empty">Loading...</div></div>
</div>

<!-- Dependency confirmation modal -->
<div class="modal-backdrop" id="modal-backdrop">
  <div class="modal">
    <h3 id="modal-title">Disable Plugin</h3>
    <p id="modal-body"></p>
    <ul class="dep-list" id="dep-list"></ul>
    <div class="modal-actions">
      <button class="btn-cancel" onclick="closeModal()">Cancel</button>
      <button class="btn-confirm" id="modal-confirm">Disable All</button>
    </div>
  </div>
</div>

<script>
const API = 'http://127.0.0.1:53422';

const AVATAR_COLORS = [
  ['#1e3a5f','#60a5fa'], ['#1a3a2a','#34d399'], ['#3b1f4a','#c084fc'],
  ['#3b2a10','#fbbf24'], ['#3b1a1a','#f87171'], ['#1a2f3b','#38bdf8'],
];

let plugins = [];
let activeFilter = 'all';

async function load() {
  try {
    const res = await fetch(`${API}/api/plugins`);
    plugins = await res.json();
    render();
  } catch (e) {
    document.getElementById('grid').innerHTML =
      `<div class="empty">Could not reach manager API (${e.message})</div>`;
  }
}

function setFilter(f, btn) {
  activeFilter = f;
  document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  render();
}

function render() {
  const q = document.getElementById('search').value.toLowerCase();
  let list = plugins;

  if (q) list = list.filter(p =>
    p.name.toLowerCase().includes(q) ||
    p.id.toLowerCase().includes(q) ||
    (p.description || '').toLowerCase().includes(q)
  );

  if (activeFilter === 'loaded')   list = list.filter(p => p.loaded);
  if (activeFilter === 'disabled') list = list.filter(p => p.status === 'disabled');
  if (activeFilter === 'problem')  list = list.filter(p =>
    p.status === 'error' || p.status === 'denied'
  );

  // Update subtitle
  const loaded = plugins.filter(p => p.loaded).length;
  document.getElementById('topbar-sub').textContent =
    `${plugins.length} plugins - ${loaded} loaded`;

  const grid = document.getElementById('grid');
  if (list.length === 0) {
    grid.innerHTML = '<div class="empty">No plugins match.</div>';
    return;
  }
  grid.innerHTML = list.map(p => cardHTML(p)).join('');
}

function cardHTML(p) {
  const ci = (p.name.charCodeAt(0) || 0) % AVATAR_COLORS.length;
  const [bg, fg] = AVATAR_COLORS[ci];
  const letter = (p.name[0] || '?').toUpperCase();

  const statusClass = p.type === 'bundle' ? 'bundle' : (p.status || 'new');
  const badgeLabel  = p.type === 'bundle' ? 'bundle' : (p.status || 'new');

  const isEnabled = p.loaded || p.status === 'loaded' || p.status === 'new';
  const canToggle = p.status !== 'error'; // errors need reset-perms first

  const depsHtml = p.dependencies && p.dependencies.length
    ? `<span class="card-meta-item">deps: ${
        p.dependencies.map(d => `<a class="dep-link" onclick="scrollTo('${d}')">${d}</a>`).join(', ')
      }</span>`
    : '';

  const usedByHtml = p.dependents && p.dependents.length
    ? `<span class="card-meta-item">used by: ${
        p.dependents.map(d => `<a class="dep-link" onclick="scrollTo('${d}')">${d}</a>`).join(', ')
      }</span>`
    : '';

  const membersHtml = p.type === 'bundle' && p.members && p.members.length
    ? `<span class="card-meta-item">includes: <strong>${p.members.join(', ')}</strong></span>`
    : '';

  const errorHtml = p.status === 'error' && p.error
    ? `<div class="error-msg" title="${esc(p.error)}">${esc(p.error.slice(0,60))}</div>`
    : '';

  const restartNote = p.status === 'disabled' && p.loaded
    ? `<div class="action-btn" style="color:var(--yellow);border-color:var(--yellow);cursor:default">restart needed</div>`
    : '';

  return `
<div class="plugin-card ${statusClass}" id="card-${p.id}">
  <div class="card-main">
    <div class="card-avatar" style="background:${bg};color:${fg}">${letter}</div>
    <div class="card-info">
      <div class="card-name-row">
        <span class="card-name">${esc(p.name)}</span>
        <span class="card-ver">v${esc(p.version)}</span>
        <span class="card-badge badge-${statusClass}">${badgeLabel}</span>
      </div>
      <div class="card-desc">${esc(p.description || '')}</div>
      <div class="card-meta">
        ${depsHtml}${usedByHtml}${membersHtml}
      </div>
      ${errorHtml}
    </div>
  </div>
  <div class="card-actions">
    <div class="toggle-wrap">
      <label class="toggle" title="${isEnabled ? 'Disable' : 'Enable'} ${esc(p.name)}">
        <input type="checkbox" ${isEnabled ? 'checked' : ''} ${!canToggle ? 'disabled' : ''}
          onchange="togglePlugin('${p.id}', this.checked, this)">
        <div class="toggle-track"><div class="toggle-thumb"></div></div>
      </label>
    </div>
    ${restartNote}
    <button class="action-btn" onclick="resetPerms('${p.id}')" title="Re-show permission dialog">
      Reset perms
    </button>
  </div>
</div>`;
}

function esc(s) {
  return String(s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function scrollTo(id) {
  const el = document.getElementById(`card-${id}`);
  if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

// -- Toggle (enable / disable) -----------------------------------------------
async function togglePlugin(id, enable, checkbox) {
  checkbox.disabled = true;
  try {
    if (enable) {
      const res = await fetch(`${API}/api/plugins/${id}/enable`, { method: 'POST' });
      const data = await res.json();
      toast(`${id}: ${data.loaded ? 'loaded' : 'enabled (restart may be needed)'}`);
    } else {
      await disablePlugin(id, checkbox);
      return; // disablePlugin handles re-enable on cancel
    }
    await load();
  } catch (e) {
    toast(`Error: ${e.message}`, true);
    checkbox.checked = !checkbox.checked;
    checkbox.disabled = false;
  }
}

async function disablePlugin(id, checkbox) {
  const res = await fetch(`${API}/api/plugins/${id}/disable`, { method: 'POST' });

  if (res.status === 409) {
    const data = await res.json();
    // Show confirmation modal
    showModal(
      `Disable "${id}"`,
      `This plugin has dependents that will also be disabled:`,
      data.dependents,
      async () => {
        const r2 = await fetch(`${API}/api/plugins/${id}/disable-force`, { method: 'POST' });
        const d2 = await r2.json();
        toast(`Disabled "${id}" + ${d2.also_disabled.length} dependent(s). Restart to take full effect.`);
        await load();
      },
      () => { checkbox.checked = true; checkbox.disabled = false; }
    );
  } else {
    const data = await res.json();
    toast(`Disabled "${id}"${data.restart_required ? ' - restart to take full effect' : ''}`);
    await load();
  }
}

async function resetPerms(id) {
  if (!confirm(`Reset saved permissions for "${id}"? It will re-ask for permissions on next load.`)) return;
  try {
    await fetch(`${API}/api/plugins/${id}/reset-perms`, { method: 'POST' });
    toast(`Permissions reset for "${id}"`);
    await load();
  } catch (e) {
    toast(`Error: ${e.message}`, true);
  }
}

// -- Modal --------------------------------------------------------------------
let _modalOnConfirm = null;
let _modalOnCancel  = null;

function showModal(title, body, deps, onConfirm, onCancel) {
  document.getElementById('modal-title').textContent = title;
  document.getElementById('modal-body').textContent  = body;
  document.getElementById('dep-list').innerHTML = deps.map(d =>
    `<li>• ${esc(d)}</li>`).join('');
  _modalOnConfirm = onConfirm;
  _modalOnCancel  = onCancel;
  document.getElementById('modal-confirm').onclick = () => {
    closeModal();
    if (_modalOnConfirm) _modalOnConfirm();
  };
  document.getElementById('modal-backdrop').classList.add('show');
}

function closeModal() {
  document.getElementById('modal-backdrop').classList.remove('show');
  if (_modalOnCancel) { _modalOnCancel(); _modalOnCancel = null; }
  _modalOnConfirm = null;
}

document.getElementById('modal-backdrop').addEventListener('click', e => {
  if (e.target === e.currentTarget) closeModal();
});

// -- Toast --------------------------------------------------------------------
let _toastTimer = null;
function toast(msg, isError = false) {
  let el = document.querySelector('.toast');
  if (el) el.remove();
  clearTimeout(_toastTimer);
  el = document.createElement('div');
  el.className = 'toast';
  el.style.borderColor = isError ? 'var(--red)' : 'var(--border)';
  el.textContent = msg;
  document.body.appendChild(el);
  _toastTimer = setTimeout(() => el.remove(), 3500);
}

load();
</script>
</body>
</html>
'@

$FILE_PLUGINS_MANAGER_PLUGIN_JSON = @'
{
  "id": "manager",
  "name": "Plugin Manager",
  "version": "1.0.0",
  "description": "Web-based plugin manager - enable, disable, inspect and manage all plugins.",
  "main": "index.js",
  "dependencies": {
    "core": "*",
    "ui": "*"
  },
  "permissions": [
    "net.listen:53422",
    "fs.read",
    "ctx.provide",
    "vm.manage"
  ]
}
'@

$FILE_PLUGINS_PHONE_LICENSE_AGPL3 = @'

                    GNU AFFERO GENERAL PUBLIC LICENSE
                       Version 3, 19 November 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU Affero General Public License is a free, copyleft license for
software and other kinds of works, specifically designed to ensure
cooperation with the community in the case of network server software.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
our General Public Licenses are intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  Developers that use our General Public Licenses protect your rights
with two steps: (1) assert copyright on the software, and (2) offer
you this License which gives you legal permission to copy, distribute
and/or modify the software.

  A secondary benefit of defending all users' freedom is that
improvements made in alternate versions of the program, if they
receive widespread use, become available for other developers to
incorporate.  Many developers of free software are heartened and
encouraged by the resulting cooperation.  However, in the case of
software used on network servers, this result may fail to come about.
The GNU General Public License permits making a modified version and
letting the public access it on a server without ever releasing its
source code to the public.

  The GNU Affero General Public License is designed specifically to
ensure that, in such cases, the modified source code becomes available
to the community.  It requires the operator of a network server to
provide the source code of the modified version running there to the
users of that server.  Therefore, public use of a modified version, on
a publicly accessible server, gives the public access to the source
code of the modified version.

  An older license, called the Affero General Public License and
published by Affero, was designed to accomplish similar goals.  This is
a different license, not a version of the Affero GPL, but Affero has
released a new version of the Affero GPL which permits relicensing under
this license.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU Affero General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Remote Network Interaction; Use with the GNU General Public License.

  Notwithstanding any other provision of this License, if you modify the
Program, your modified version must prominently offer all users
interacting with it remotely through a computer network (if your version
supports such interaction) an opportunity to receive the Corresponding
Source of your version by providing access to the Corresponding Source
from a network server at no charge, through some standard or customary
means of facilitating copying of software.  This Corresponding Source
shall include the Corresponding Source for any work covered by version 3
of the GNU General Public License that is incorporated pursuant to the
following paragraph.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the work with which it is combined will remain governed by version
3 of the GNU General Public License.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU Affero General Public License from time to time.  Such new versions
will be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU Affero General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU Affero General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU Affero General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If your software can interact with users remotely through a computer
network, you should also make sure that it provides a way for users to
get its source.  For example, if your program is a web application, its
interface could display a "Source" link that leads users to an archive
of the code.  There are many ways you could offer source, and different
solutions will be better for different programs; see section 13 for the
specific requirements.

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU AGPL, see
<https://www.gnu.org/licenses/>.
'@

$FILE_PLUGINS_PHONE_TODO_TXT = @'
Under construction
'@

$FILE_PLUGINS_SETTINGS_INDEX_JS = @'
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
'use strict';
const path = require('path');

module.exports = {
    install(ctx) {
        const log           = ctx.use('log');
        const config        = ctx.use('config');
        const registerPanel = ctx.use('ui.registerPanel');

        // Register the settings panel with the UI plugin
        registerPanel('settings', path.join(__dirname, 'panel.html'), 'Settings');

        // WS: settings:get_all -> send all config entries + app/plugin info
        ctx.onMessage('settings:get_all', (socket, _msg) => {
            ctx.reply(socket, {
                type:    'settings:state',
                config:  config.all(),
                app:     ctx.appName,
                version: ctx.appVersion,
                plugins: ctx.loadedPlugins(),
            });
        });

        // WS: settings:set { key, value }
        ctx.onMessage('settings:set', (socket, msg) => {
            if (typeof msg.key !== 'string' || msg.key.trim() === '') {
                ctx.reply(socket, { type: 'error', message: 'settings:set requires a key string' });
                return;
            }
            config.set(msg.key, msg.value);
            log(`settings: config["${msg.key}"] = ${JSON.stringify(msg.value)}`);
            ctx.broadcast({ type: 'settings:changed', key: msg.key, value: msg.value });
        });

        log(`settings plugin loaded`);
    }
};
'@

$FILE_PLUGINS_SETTINGS_LICENSE_AGPL3 = @'

                    GNU AFFERO GENERAL PUBLIC LICENSE
                       Version 3, 19 November 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU Affero General Public License is a free, copyleft license for
software and other kinds of works, specifically designed to ensure
cooperation with the community in the case of network server software.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
our General Public Licenses are intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  Developers that use our General Public Licenses protect your rights
with two steps: (1) assert copyright on the software, and (2) offer
you this License which gives you legal permission to copy, distribute
and/or modify the software.

  A secondary benefit of defending all users' freedom is that
improvements made in alternate versions of the program, if they
receive widespread use, become available for other developers to
incorporate.  Many developers of free software are heartened and
encouraged by the resulting cooperation.  However, in the case of
software used on network servers, this result may fail to come about.
The GNU General Public License permits making a modified version and
letting the public access it on a server without ever releasing its
source code to the public.

  The GNU Affero General Public License is designed specifically to
ensure that, in such cases, the modified source code becomes available
to the community.  It requires the operator of a network server to
provide the source code of the modified version running there to the
users of that server.  Therefore, public use of a modified version, on
a publicly accessible server, gives the public access to the source
code of the modified version.

  An older license, called the Affero General Public License and
published by Affero, was designed to accomplish similar goals.  This is
a different license, not a version of the Affero GPL, but Affero has
released a new version of the Affero GPL which permits relicensing under
this license.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU Affero General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Remote Network Interaction; Use with the GNU General Public License.

  Notwithstanding any other provision of this License, if you modify the
Program, your modified version must prominently offer all users
interacting with it remotely through a computer network (if your version
supports such interaction) an opportunity to receive the Corresponding
Source of your version by providing access to the Corresponding Source
from a network server at no charge, through some standard or customary
means of facilitating copying of software.  This Corresponding Source
shall include the Corresponding Source for any work covered by version 3
of the GNU General Public License that is incorporated pursuant to the
following paragraph.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the work with which it is combined will remain governed by version
3 of the GNU General Public License.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU Affero General Public License from time to time.  Such new versions
will be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU Affero General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU Affero General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU Affero General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If your software can interact with users remotely through a computer
network, you should also make sure that it provides a way for users to
get its source.  For example, if your program is a web application, its
interface could display a "Source" link that leads users to an archive
of the code.  There are many ways you could offer source, and different
solutions will be better for different programs; see section 13 for the
specific requirements.

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU AGPL, see
<https://www.gnu.org/licenses/>.
'@

$FILE_PLUGINS_SETTINGS_PANEL_HTML = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Settings</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: system-ui, -apple-system, sans-serif;
    background: #0a0a0f;
    color: #e2e8f0;
    min-height: 100vh;
    padding: 32px 24px;
  }

  header {
    display: flex;
    align-items: baseline;
    gap: 12px;
    margin-bottom: 32px;
    border-bottom: 1px solid #1e293b;
    padding-bottom: 20px;
  }

  header h1   { font-size: 1.4rem; font-weight: 600; letter-spacing: -.3px; }
  header span { font-size: 0.8rem; color: #64748b; font-family: monospace; }

  .status {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 0.75rem;
    color: #64748b;
    margin-left: auto;
  }
  .dot {
    width: 8px; height: 8px;
    border-radius: 50%;
    background: #ef4444;
    transition: background .3s;
  }
  .dot.connected { background: #22c55e; }

  section {
    background: #0f172a;
    border: 1px solid #1e293b;
    border-radius: 10px;
    padding: 20px 24px;
    margin-bottom: 20px;
  }

  section h2 {
    font-size: 0.7rem;
    font-weight: 600;
    letter-spacing: .08em;
    text-transform: uppercase;
    color: #475569;
    margin-bottom: 16px;
  }

  .info-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 0;
    border-bottom: 1px solid #1e293b;
    font-size: 0.875rem;
  }
  .info-row:last-child { border-bottom: none; }
  .info-row .label  { color: #94a3b8; }
  .info-row .value  { font-family: monospace; color: #e2e8f0; }

  .plugin-badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 20px;
    padding: 3px 10px;
    font-size: 0.75rem;
    color: #94a3b8;
    margin: 3px;
  }
  .plugin-badge .ver { color: #475569; font-family: monospace; }

  /* Feature flag toggles */
  .flag-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 0;
    border-bottom: 1px solid #1e293b;
  }
  .flag-row:last-child { border-bottom: none; }
  .flag-label { font-size: 0.875rem; }
  .flag-label small { display: block; color: #64748b; font-size: 0.75rem; margin-top: 2px; }

  .toggle { position: relative; display: inline-block; width: 36px; height: 20px; flex-shrink: 0; }
  .toggle input { opacity: 0; width: 0; height: 0; }
  .slider {
    position: absolute; inset: 0;
    background: #334155; border-radius: 20px; cursor: pointer;
    transition: background .2s;
  }
  .slider::before {
    content: ''; position: absolute;
    width: 14px; height: 14px; left: 3px; bottom: 3px;
    background: #fff; border-radius: 50%;
    transition: transform .2s;
  }
  .toggle input:checked + .slider { background: #6366f1; }
  .toggle input:checked + .slider::before { transform: translateX(16px); }

  .warn-badge {
    display: inline-block;
    background: #7c2d12;
    color: #fca5a5;
    font-size: 0.65rem;
    font-weight: 600;
    letter-spacing: .05em;
    text-transform: uppercase;
    padding: 2px 6px;
    border-radius: 4px;
    margin-left: 8px;
    vertical-align: middle;
  }

  .field-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
    margin-bottom: 12px;
  }
  @media (max-width: 520px) { .field-row { grid-template-columns: 1fr; } }

  label { font-size: 0.8rem; color: #94a3b8; display: block; margin-bottom: 5px; }

  input[type="text"], input[type="number"] {
    width: 100%;
    background: #020617;
    border: 1px solid #334155;
    border-radius: 6px;
    color: #e2e8f0;
    padding: 8px 12px;
    font-size: 0.875rem;
    font-family: monospace;
    outline: none;
    transition: border-color .15s;
  }
  input:focus { border-color: #6366f1; }

  .actions { display: flex; gap: 10px; margin-top: 16px; }

  button {
    padding: 8px 20px;
    border-radius: 6px;
    border: none;
    font-size: 0.875rem;
    font-weight: 500;
    cursor: pointer;
    transition: opacity .15s;
  }
  button:hover { opacity: .85; }
  button.primary { background: #6366f1; color: #fff; }
  button.secondary { background: #1e293b; color: #94a3b8; border: 1px solid #334155; }

  .toast {
    position: fixed;
    bottom: 24px; right: 24px;
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 8px;
    padding: 12px 18px;
    font-size: 0.85rem;
    opacity: 0;
    transform: translateY(6px);
    transition: opacity .2s, transform .2s;
    pointer-events: none;
  }
  .toast.show { opacity: 1; transform: translateY(0); }

  #plugins-list { display: flex; flex-wrap: wrap; gap: 4px; }
  #no-conn { color: #ef4444; font-size: 0.8rem; padding: 8px 0; }
</style>
</head>
<body>

<header>
  <h1 id="app-title">Settings</h1>
  <span id="app-version"></span>
  <div class="status">
    <div class="dot" id="dot"></div>
    <span id="conn-label">Connecting...</span>
  </div>
</header>

<section>
  <h2>App Info</h2>
  <div class="info-row"><span class="label">Name</span>    <span class="value" id="info-name">-</span></div>
  <div class="info-row"><span class="label">Version</span> <span class="value" id="info-version">-</span></div>
  <div class="info-row"><span class="label">WS Port</span> <span class="value">53420</span></div>
  <div class="info-row"><span class="label">UI Port</span> <span class="value">53421</span></div>
</section>

<section>
  <h2>Loaded Plugins</h2>
  <div id="plugins-list"><span id="no-conn">Not connected</span></div>
</section>

<section id="section-flags">
  <h2>Feature Flags</h2>

  <div class="flag-row" id="flag-experimental">
    <div class="flag-label">
      Experimental plugins
      <span class="warn-badge">risky</span>
      <small>Allow loading plugins tagged <code>experimental: true</code> in their manifest</small>
    </div>
    <label class="toggle">
      <input type="checkbox" data-flag="features.experimental">
      <span class="slider"></span>
    </label>
  </div>

  <div class="flag-row" id="flag-exec">
    <div class="flag-label">
      Unrestricted system.exec
      <span class="warn-badge">risky</span>
      <small>Allow plugins to run any system command (not scoped to a specific binary)</small>
    </div>
    <label class="toggle">
      <input type="checkbox" data-flag="features.unrestricted_exec">
      <span class="slider"></span>
    </label>
  </div>

  <div class="flag-row" id="flag-net">
    <div class="flag-label">
      Unrestricted outbound network
      <span class="warn-badge">risky</span>
      <small>Allow plugins to connect to any host (not scoped to a specific domain)</small>
    </div>
    <label class="toggle">
      <input type="checkbox" data-flag="features.unrestricted_network">
      <span class="slider"></span>
    </label>
  </div>
</section>

<section>
  <h2>Config</h2>
  <div class="field-row">
    <div>
      <label for="cfg-key">Key</label>
      <input type="text" id="cfg-key" placeholder="e.g. ui.port">
    </div>
    <div>
      <label for="cfg-value">Value</label>
      <input type="text" id="cfg-value" placeholder="value">
    </div>
  </div>
  <div class="actions">
    <button class="primary"    id="btn-set">Set</button>
    <button class="secondary"  id="btn-get">Get</button>
    <button class="secondary"  id="btn-refresh">Refresh</button>
  </div>
</section>

<div class="toast" id="toast"></div>

<script>
const WS_URL = 'ws://127.0.0.1:53420';
let ws = null;
let reconnectTimer = null;

const dot        = document.getElementById('dot');
const connLabel  = document.getElementById('conn-label');
const appTitle   = document.getElementById('app-title');
const appVersion = document.getElementById('app-version');
const infoName   = document.getElementById('info-name');
const infoVer    = document.getElementById('info-version');
const plugsList  = document.getElementById('plugins-list');
const noConn     = document.getElementById('no-conn');
const cfgKey     = document.getElementById('cfg-key');
const cfgValue   = document.getElementById('cfg-value');
const toast      = document.getElementById('toast');

let toastTimer = null;
function showToast(msg) {
    clearTimeout(toastTimer);
    toast.textContent = msg;
    toast.classList.add('show');
    toastTimer = setTimeout(() => toast.classList.remove('show'), 2800);
}

function send(obj) {
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
}

function setConnected(ok) {
    dot.className = 'dot' + (ok ? ' connected' : '');
    connLabel.textContent = ok ? 'Connected' : 'Disconnected';
    if (!ok) {
        noConn.style.display = '';
        plugsList.querySelectorAll('.plugin-badge').forEach(el => el.remove());
    }
}

function renderPlugins(plugins) {
    noConn.style.display = 'none';
    plugsList.querySelectorAll('.plugin-badge').forEach(el => el.remove());
    if (!plugins || !Object.keys(plugins).length) {
        noConn.style.display = '';
        noConn.textContent = 'No plugins registered';
        return;
    }
    for (const [id, info] of Object.entries(plugins)) {
        const b = document.createElement('span');
        b.className = 'plugin-badge';
        b.innerHTML = `${id} <span class="ver">v${info.version || '?'}</span>`;
        plugsList.appendChild(b);
    }
}

function onMessage(data) {
    let msg;
    try { msg = JSON.parse(data); } catch (_) { return; }

    if (msg.type === 'settings:state') {
        infoName.textContent    = msg.app     || '-';
        infoVer.textContent     = msg.version || '-';
        appTitle.textContent    = (msg.app || 'Settings') + ' - Settings';
        appVersion.textContent  = msg.version ? `v${msg.version}` : '';
        renderPlugins(msg.plugins);

        const cfg = msg.config || {};
        if (cfgKey.value && cfgKey.value in cfg) {
            cfgValue.value = String(cfg[cfgKey.value]);
        }

        // Sync feature flag toggles
        document.querySelectorAll('[data-flag]').forEach(cb => {
            const key = cb.getAttribute('data-flag');
            if (key in cfg) cb.checked = !!cfg[key];
        });
    }

    if (msg.type === 'settings:changed') {
        showToast(`Saved: ${msg.key} = ${JSON.stringify(msg.value)}`);
        if (cfgKey.value === msg.key) cfgValue.value = String(msg.value);
    }

    if (msg.type === 'error') {
        showToast('Error: ' + msg.message);
    }
}

function connect() {
    ws = new WebSocket(WS_URL);

    ws.addEventListener('open', () => {
        setConnected(true);
        send({ type: 'settings:get_all' });
    });

    ws.addEventListener('message', e => onMessage(e.data));

    ws.addEventListener('close', () => {
        setConnected(false);
        reconnectTimer = setTimeout(connect, 3000);
    });

    ws.addEventListener('error', () => {
        ws.close();
    });
}

document.getElementById('btn-set').addEventListener('click', () => {
    const k = cfgKey.value.trim();
    const v = cfgValue.value;
    if (!k) { showToast('Enter a key first'); return; }
    // Try to parse value as JSON, fall back to string
    let val;
    try { val = JSON.parse(v); } catch (_) { val = v; }
    send({ type: 'settings:set', key: k, value: val });
});

document.getElementById('btn-get').addEventListener('click', () => {
    send({ type: 'settings:get_all' });
});

document.getElementById('btn-refresh').addEventListener('click', () => {
    send({ type: 'settings:get_all' });
    showToast('Refreshed');
});

// Feature flag toggles -> settings:set
document.querySelectorAll('[data-flag]').forEach(cb => {
    cb.addEventListener('change', () => {
        const key = cb.getAttribute('data-flag');
        send({ type: 'settings:set', key, value: cb.checked });
        showToast(`${key} = ${cb.checked}`);
    });
});

connect();
</script>
</body>
</html>
'@

$FILE_PLUGINS_SETTINGS_PLUGIN_JSON = @'
{
  "id": "settings",
  "name": "Settings",
  "version": "1.0.0",
  "description": "Settings panel - demonstrates the UI plugin; exposes config read/write over WebSocket",
  "main": "index.js",
  "dependencies": {
    "core": "*",
    "ui": "*"
  },
  "permissions": [
    "ctx.broadcast"
  ]
}
'@

$FILE_PLUGINS_TRAY_INDEX_JS = @'
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
'use strict';
const path = require('path');

module.exports = {
    install(ctx) {
        const log  = ctx.use('log');
        const port = ctx.use('ui.port');   // guaranteed available - ui is a dependency

        // Path to the bundled PowerShell tray script
        const ps1 = path.join(ctx.pluginDir, 'tray.ps1');

        // App icon - falls back gracefully in the PS script if not present
        const iconPath = path.join(ctx.dataDir, '..', '..', 'assets',
            ctx.appName.toLowerCase() + '.ico');

        try {
            ctx.spawnDetached('powershell.exe', [
                '-STA',
                '-NonInteractive',
                '-WindowStyle', 'Hidden',
                '-ExecutionPolicy', 'Bypass',
                '-File', ps1,
                '-Port', String(port),
                '-AppName', ctx.appName,
                '-IconPath', iconPath,
            ]);
            log(`tray: icon started (UI -> http://127.0.0.1:${port})`);
        } catch (e) {
            log(`tray: failed to start icon - ${e.message}`, 'WARN');
        }

        log('tray plugin loaded');
    },
};
'@

$FILE_PLUGINS_TRAY_LICENSE_AGPL3 = @'

                    GNU AFFERO GENERAL PUBLIC LICENSE
                       Version 3, 19 November 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU Affero General Public License is a free, copyleft license for
software and other kinds of works, specifically designed to ensure
cooperation with the community in the case of network server software.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
our General Public Licenses are intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  Developers that use our General Public Licenses protect your rights
with two steps: (1) assert copyright on the software, and (2) offer
you this License which gives you legal permission to copy, distribute
and/or modify the software.

  A secondary benefit of defending all users' freedom is that
improvements made in alternate versions of the program, if they
receive widespread use, become available for other developers to
incorporate.  Many developers of free software are heartened and
encouraged by the resulting cooperation.  However, in the case of
software used on network servers, this result may fail to come about.
The GNU General Public License permits making a modified version and
letting the public access it on a server without ever releasing its
source code to the public.

  The GNU Affero General Public License is designed specifically to
ensure that, in such cases, the modified source code becomes available
to the community.  It requires the operator of a network server to
provide the source code of the modified version running there to the
users of that server.  Therefore, public use of a modified version, on
a publicly accessible server, gives the public access to the source
code of the modified version.

  An older license, called the Affero General Public License and
published by Affero, was designed to accomplish similar goals.  This is
a different license, not a version of the Affero GPL, but Affero has
released a new version of the Affero GPL which permits relicensing under
this license.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU Affero General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Remote Network Interaction; Use with the GNU General Public License.

  Notwithstanding any other provision of this License, if you modify the
Program, your modified version must prominently offer all users
interacting with it remotely through a computer network (if your version
supports such interaction) an opportunity to receive the Corresponding
Source of your version by providing access to the Corresponding Source
from a network server at no charge, through some standard or customary
means of facilitating copying of software.  This Corresponding Source
shall include the Corresponding Source for any work covered by version 3
of the GNU General Public License that is incorporated pursuant to the
following paragraph.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the work with which it is combined will remain governed by version
3 of the GNU General Public License.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU Affero General Public License from time to time.  Such new versions
will be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU Affero General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU Affero General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU Affero General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If your software can interact with users remotely through a computer
network, you should also make sure that it provides a way for users to
get its source.  For example, if your program is a web application, its
interface could display a "Source" link that leads users to an archive
of the code.  There are many ways you could offer source, and different
solutions will be better for different programs; see section 13 for the
specific requirements.

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU AGPL, see
<https://www.gnu.org/licenses/>.
'@

$FILE_PLUGINS_TRAY_PLUGIN_JSON = @'
{
  "id": "tray",
  "name": "System Tray",
  "version": "1.0.0",
  "description": "Windows system tray icon. Left-click or 'Open' to launch the panel UI; 'Exit' to shut down.",
  "main": "index.js",
  "dependencies": {
    "core": "*",
    "ui": "*"
  },
  "permissions": [
    "system.exec:powershell",
    "fs.read:${dataDir}",
    "fs.write:${dataDir}"
  ]
}
'@

$FILE_PLUGINS_TRAY_TRAY_PS1 = @'
<#
.SYNOPSIS
    COMPUTER system tray icon.
    Runs in STA mode so WinForms works. Launched as a detached background
    process by the tray plugin (plugins/tray/index.js).

.PARAMETER Port
    Port of the UI panel server (default 53421).

.PARAMETER AppName
    Display name shown in the tray tooltip and menu header.

.PARAMETER IconPath
    Full path to a .ico file. Falls back to a built-in system icon if not found.
#>
param(
    [int]    $Port     = 53421,
    [string] $AppName  = 'COMPUTER',
    [string] $IconPath = ''
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$url = "http://127.0.0.1:$Port"

# -- Tray icon image ------------------------------------------------------------
if ($IconPath -and (Test-Path $IconPath)) {
    $icon = [System.Drawing.Icon]::new($IconPath)
} else {
    # Fall back to the generic application icon from the shell
    $icon = [System.Drawing.SystemIcons]::Application
}

# -- NotifyIcon -----------------------------------------------------------------
$tray          = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon     = $icon
$tray.Text     = $AppName
$tray.Visible  = $true

# -- Context menu --------------------------------------------------------------
$menu = New-Object System.Windows.Forms.ContextMenuStrip

# Header item (non-clickable label)
$header           = New-Object System.Windows.Forms.ToolStripMenuItem
$header.Text      = $AppName
$header.Font      = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$header.Enabled   = $false
[void]$menu.Items.Add($header)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# Open panels
$open           = New-Object System.Windows.Forms.ToolStripMenuItem
$open.Text      = 'Open Panels'
$open.Add_Click({ Start-Process $url })
[void]$menu.Items.Add($open)

# Open settings
$settings           = New-Object System.Windows.Forms.ToolStripMenuItem
$settings.Text      = 'Settings'
$settings.Add_Click({ Start-Process "$url/settings" })
[void]$menu.Items.Add($settings)

# Open plugin manager directly
$mgr           = New-Object System.Windows.Forms.ToolStripMenuItem
$mgr.Text      = 'Plugin Manager'
$mgr.Add_Click({ Start-Process "$url/manager" })
[void]$menu.Items.Add($mgr)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# Exit (removes icon and stops the PS process; Node.js keeps running)
$exit           = New-Object System.Windows.Forms.ToolStripMenuItem
$exit.Text      = 'Hide Tray Icon'
$exit.Add_Click({
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
[void]$menu.Items.Add($exit)

$tray.ContextMenuStrip = $menu

# Left-click opens the panels URL
$tray.Add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Start-Process $url
    }
})

# -- Message loop (keeps icon alive until Exit is chosen) ---------------------
[System.Windows.Forms.Application]::Run()

# Cleanup
$tray.Visible = $false
$tray.Dispose()
'@

$FILE_PLUGINS_UI_INDEX_JS = @'
// Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
'use strict';
const path = require('path');

// Panels registered by other plugins: id -> { htmlPath, title }
const panels = new Map();

// Serve a file by extension with correct content-type
const MIME = {
    '.html': 'text/html',
    '.css':  'text/css',
    '.js':   'application/javascript',
    '.json': 'application/json',
    '.png':  'image/png',
    '.svg':  'image/svg+xml',
};

function serveFile(ctx, res, filePath) {
    try {
        const ext  = path.extname(filePath).toLowerCase();
        const mime = MIME[ext] || 'text/plain';
        const data = ctx.readFileBuffer(filePath);
        res.writeHead(200, { 'Content-Type': mime });
        res.end(data);
    } catch (_) {
        res.writeHead(404);
        res.end('Not found');
    }
}

function buildIndex(appName, appVersion) {
    const rows = [...panels.entries()].map(([id, p]) =>
        `<li><a href="/${id}">${p.title || id}</a></li>`
    ).join('');
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${appName} - Panels</title>
<style>
  body { font-family: system-ui, sans-serif; background: #0f0f0f; color: #e2e8f0;
         display: flex; flex-direction: column; align-items: center; padding: 48px 24px; margin: 0; }
  h1   { font-size: 1.5rem; margin-bottom: 8px; }
  p    { color: #64748b; margin-bottom: 32px; }
  ul   { list-style: none; padding: 0; display: flex; flex-direction: column; gap: 12px; }
  a    { display: block; padding: 14px 28px; background: #1e293b; border: 1px solid #334155;
         border-radius: 8px; color: #e2e8f0; text-decoration: none; font-size: 1rem;
         transition: background .15s; }
  a:hover { background: #334155; }
</style>
</head>
<body>
  <h1>${appName}</h1>
  <p>v${appVersion}</p>
  ${rows.length ? `<ul>${rows}</ul>` : '<p>No panels registered yet.</p>'}
</body>
</html>`;
}

module.exports = {
    install(ctx) {
        const log     = ctx.use('log');
        const config  = ctx.use('config');
        const events  = ctx.use('events');
        const port    = config.get('ui.port', 53421);

        // Service: register a panel.
        // source can be a file path (served statically) or an http:// URL (redirected).
        ctx.provide('ui.registerPanel', (id, source, title = id) => {
            const isUrl = typeof source === 'string' && /^https?:\/\//.test(source);
            panels.set(id, isUrl
                ? { redirect: source, title }
                : { htmlPath: path.resolve(source), title }
            );
            log(`ui: registered panel "${id}" (${title})`);
            events.emit('ui:panel:registered', { id, title });
        });

        // Service: open a panel in the default browser
        ctx.provide('ui.openPanel', (id = '') => {
            const target = `http://127.0.0.1:${port}/${id}`;
            ctx.execAsync(`start "" "${target}"`);
            log(`ui: opened panel "${id}" -> ${target}`);
        });

        const server = ctx.listen(port, (req, res) => {
            res.setHeader('Access-Control-Allow-Origin', '*');

            const parsedUrl = new URL(req.url || '/', 'http://localhost');
            const panelId = (parsedUrl.pathname || '/').replace(/^\//, '').split('/')[0];

            // Root -> panel index
            if (!panelId) {
                res.writeHead(200, { 'Content-Type': 'text/html' });
                res.end(buildIndex(ctx.appName, ctx.appVersion));
                return;
            }

            if (panels.has(panelId)) {
                const panel = panels.get(panelId);

                // URL-based panel: redirect the browser to the external server
                if (panel.redirect) {
                    const suffix = (parsedUrl.pathname || '/').replace(/^\/[^/]+/, '') || '';
                    const search = parsedUrl.search || '';
                    res.writeHead(302, { Location: panel.redirect + suffix + search });
                    res.end();
                    return;
                }

                // Static asset within a panel dir: /<panelId>/sub/path.ext
                const subPath = (parsedUrl.pathname || '/').replace(/^\/[^/]+/, '');
                if (subPath && subPath !== '/') {
                    const asset = path.join(path.dirname(panel.htmlPath), subPath);
                    serveFile(ctx, res, asset);
                    return;
                }

                // Panel HTML
                serveFile(ctx, res, panel.htmlPath);
                return;
            }

            res.writeHead(404);
            res.end('Panel not found');
        });

        server.on('error', err => log(`ui: server error - ${err.message}`, 'ERROR'));

        // Service: get the port the UI server is listening on
        ctx.provide('ui.port', port);

        log(`ui: panel server -> http://127.0.0.1:${port}`);
        events.emit('ui:ready', { port });

        log(`ui plugin loaded`);
    }
};
'@

$FILE_PLUGINS_UI_LICENSE_AGPL3 = @'

                    GNU AFFERO GENERAL PUBLIC LICENSE
                       Version 3, 19 November 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU Affero General Public License is a free, copyleft license for
software and other kinds of works, specifically designed to ensure
cooperation with the community in the case of network server software.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
our General Public Licenses are intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  Developers that use our General Public Licenses protect your rights
with two steps: (1) assert copyright on the software, and (2) offer
you this License which gives you legal permission to copy, distribute
and/or modify the software.

  A secondary benefit of defending all users' freedom is that
improvements made in alternate versions of the program, if they
receive widespread use, become available for other developers to
incorporate.  Many developers of free software are heartened and
encouraged by the resulting cooperation.  However, in the case of
software used on network servers, this result may fail to come about.
The GNU General Public License permits making a modified version and
letting the public access it on a server without ever releasing its
source code to the public.

  The GNU Affero General Public License is designed specifically to
ensure that, in such cases, the modified source code becomes available
to the community.  It requires the operator of a network server to
provide the source code of the modified version running there to the
users of that server.  Therefore, public use of a modified version, on
a publicly accessible server, gives the public access to the source
code of the modified version.

  An older license, called the Affero General Public License and
published by Affero, was designed to accomplish similar goals.  This is
a different license, not a version of the Affero GPL, but Affero has
released a new version of the Affero GPL which permits relicensing under
this license.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU Affero General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Remote Network Interaction; Use with the GNU General Public License.

  Notwithstanding any other provision of this License, if you modify the
Program, your modified version must prominently offer all users
interacting with it remotely through a computer network (if your version
supports such interaction) an opportunity to receive the Corresponding
Source of your version by providing access to the Corresponding Source
from a network server at no charge, through some standard or customary
means of facilitating copying of software.  This Corresponding Source
shall include the Corresponding Source for any work covered by version 3
of the GNU General Public License that is incorporated pursuant to the
following paragraph.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the work with which it is combined will remain governed by version
3 of the GNU General Public License.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU Affero General Public License from time to time.  Such new versions
will be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU Affero General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU Affero General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU Affero General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If your software can interact with users remotely through a computer
network, you should also make sure that it provides a way for users to
get its source.  For example, if your program is a web application, its
interface could display a "Source" link that leads users to an archive
of the code.  There are many ways you could offer source, and different
solutions will be better for different programs; see section 13 for the
specific requirements.

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU AGPL, see
<https://www.gnu.org/licenses/>.
'@

$FILE_PLUGINS_UI_PLUGIN_JSON = @'
{
  "id": "ui",
  "name": "UI",
  "version": "1.0.0",
  "description": "UI plugin - serves HTML panels via local HTTP; provides panel registration API",
  "main": "index.js",
  "dependencies": {
    "core": "*"
  },
  "permissions": [
    "net.listen:53421",
    "fs.read",
    "ctx.provide",
    "system.exec:start"
  ]
}
'@

$FILE_MANIFEST['plugins/core/index.js'] = $FILE_PLUGINS_CORE_INDEX_JS
$FILE_MANIFEST['plugins/core/LICENSE-AGPL3'] = $FILE_PLUGINS_CORE_LICENSE_AGPL3
$FILE_MANIFEST['plugins/core/plugin.json'] = $FILE_PLUGINS_CORE_PLUGIN_JSON
$FILE_MANIFEST['plugins/essentials/bundle.json'] = $FILE_PLUGINS_ESSENTIALS_BUNDLE_JSON
$FILE_MANIFEST['plugins/essentials/LICENSE-AGPL3'] = $FILE_PLUGINS_ESSENTIALS_LICENSE_AGPL3
$FILE_MANIFEST['plugins/example/index.js'] = $FILE_PLUGINS_EXAMPLE_INDEX_JS
$FILE_MANIFEST['plugins/example/LICENSE-AGPL3'] = $FILE_PLUGINS_EXAMPLE_LICENSE_AGPL3
$FILE_MANIFEST['plugins/example/plugin.json'] = $FILE_PLUGINS_EXAMPLE_PLUGIN_JSON
$FILE_MANIFEST['plugins/example/todo.txt'] = $FILE_PLUGINS_EXAMPLE_TODO_TXT
$FILE_MANIFEST['plugins/manager/index.js'] = $FILE_PLUGINS_MANAGER_INDEX_JS
$FILE_MANIFEST['plugins/manager/LICENSE-AGPL3'] = $FILE_PLUGINS_MANAGER_LICENSE_AGPL3
$FILE_MANIFEST['plugins/manager/panel.html'] = $FILE_PLUGINS_MANAGER_PANEL_HTML
$FILE_MANIFEST['plugins/manager/plugin.json'] = $FILE_PLUGINS_MANAGER_PLUGIN_JSON
$FILE_MANIFEST['plugins/phone/LICENSE-AGPL3'] = $FILE_PLUGINS_PHONE_LICENSE_AGPL3
$FILE_MANIFEST['plugins/phone/todo.txt'] = $FILE_PLUGINS_PHONE_TODO_TXT
$FILE_MANIFEST['plugins/settings/index.js'] = $FILE_PLUGINS_SETTINGS_INDEX_JS
$FILE_MANIFEST['plugins/settings/LICENSE-AGPL3'] = $FILE_PLUGINS_SETTINGS_LICENSE_AGPL3
$FILE_MANIFEST['plugins/settings/panel.html'] = $FILE_PLUGINS_SETTINGS_PANEL_HTML
$FILE_MANIFEST['plugins/settings/plugin.json'] = $FILE_PLUGINS_SETTINGS_PLUGIN_JSON
$FILE_MANIFEST['plugins/tray/index.js'] = $FILE_PLUGINS_TRAY_INDEX_JS
$FILE_MANIFEST['plugins/tray/LICENSE-AGPL3'] = $FILE_PLUGINS_TRAY_LICENSE_AGPL3
$FILE_MANIFEST['plugins/tray/plugin.json'] = $FILE_PLUGINS_TRAY_PLUGIN_JSON
$FILE_MANIFEST['plugins/tray/tray.ps1'] = $FILE_PLUGINS_TRAY_TRAY_PS1
$FILE_MANIFEST['plugins/ui/index.js'] = $FILE_PLUGINS_UI_INDEX_JS
$FILE_MANIFEST['plugins/ui/LICENSE-AGPL3'] = $FILE_PLUGINS_UI_LICENSE_AGPL3
$FILE_MANIFEST['plugins/ui/plugin.json'] = $FILE_PLUGINS_UI_PLUGIN_JSON

# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- RichTextBox styled append ----------------------
function RTB-Write {
    param(
        [System.Windows.Forms.RichTextBox]$RTB,
        [string]$Text,
        [System.Drawing.Color]$Color,
        [switch]$Bold,
        [float]$Size = 8.5
    )
    $RTB.SelectionFont  = New-Object System.Drawing.Font("Segoe UI", $Size,
        $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
    $RTB.SelectionColor = $Color
    $RTB.AppendText($Text)
}

# --- Encoding-safe file writer ----------------------
function Write-File {
    param([string]$Path, [string]$Content, [switch]$Ascii)
    $enc = if ($Ascii) { [System.Text.Encoding]::ASCII } else { New-Object System.Text.UTF8Encoding($false) }
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

# --- Non-blocking subprocess helper ----------------
# Runs a process and pumps DoEvents every 50 ms while waiting, so the UI stays
# responsive. Returns combined stdout+stderr trimmed - use for version commands
# (python --version writes to stderr on Python 2).
function Invoke-Async {
    param([string]$Command, [string]$Arguments = '')
    # Always run through cmd.exe so .cmd/.bat scripts (npm, pip, etc.) resolve
    # correctly via PATHEXT without needing the full path or extension.
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo('cmd.exe', "/c $Command $Arguments")
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow         = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        while (-not $p.WaitForExit(50)) {
            [System.Windows.Forms.Application]::DoEvents()
        }
        return ($p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd()).Trim()
    } catch { return '' }
}

# --- Modern dark dialog (replaces MessageBox::Show) 
function Show-Dialog {
    param([string]$Title, [string]$Message, [string[]]$Buttons = @("OK"))
    # Use a single-element array as a captured-by-reference result box.
    # Avoids $script: scope issues inside nested ShowDialog message loops.
    # Default = last button (what X / no-choice means).
    $res = @($Buttons[$Buttons.Count - 1])

    $d = New-Object System.Windows.Forms.Form
    $d.Text            = $Title
    $d.ClientSize      = New-Object System.Drawing.Size(420, 100)
    $d.StartPosition   = "CenterScreen"
    $d.FormBorderStyle = "FixedDialog"
    $d.MaximizeBox     = $false
    $d.MinimizeBox     = $false
    $d.BackColor       = $C_CARD
    $d.Add_Load({ [DarkMode]::Enable($d.Handle) }.GetNewClosure())

    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Text      = $Message
    $lbl.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
    $lbl.ForeColor = $C_TEXT
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $maxW = 380
    $size = [System.Windows.Forms.TextRenderer]::MeasureText(
        $Message, $lbl.Font,
        (New-Object System.Drawing.Size($maxW, 0)),
        [System.Windows.Forms.TextFormatFlags]::WordBreak)
    $lbl.Location  = New-Object System.Drawing.Point(20, 12)
    $lbl.Size      = New-Object System.Drawing.Size($maxW, $size.Height)
    $d.Controls.Add($lbl)

    $minH    = 84
    $dialogH = [Math]::Max($minH, $lbl.Bottom + 50)
    $d.ClientSize = New-Object System.Drawing.Size(420, $dialogH)

    $btnW   = 90
    $gap    = 10
    $total  = ($btnW * $Buttons.Count) + ($gap * ($Buttons.Count - 1))
    $startX = (420 - $total) / 2
    $btnY   = $d.ClientSize.Height - 42

    for ($i = 0; $i -lt $Buttons.Count; $i++) {
        $label = $Buttons[$i]
        $btn   = New-Object System.Windows.Forms.Button
        $btn.Text     = $label
        $btn.FlatStyle = "Flat"
        $btn.FlatAppearance.BorderColor = $C_BORDER
        $btn.FlatAppearance.BorderSize  = 1
        $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38, 44, 52)
        $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(24, 28, 34)
        $btn.BackColor = $C_CARD
        $btn.ForeColor = $C_TEXT
        $btn.UseVisualStyleBackColor = $false
        $btn.Font   = New-Object System.Drawing.Font("Segoe UI", 9.5)
        $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btn.TabStop = $false
        $btn.Location = New-Object System.Drawing.Point(($startX + $i * ($btnW + $gap)), $btnY)
        $btn.Size     = New-Object System.Drawing.Size($btnW, 30)
        $btn.Add_Click({
            $res[0] = $label   # write into the shared reference box
            $d.Close()         # close dialog; ShowDialog returns
        }.GetNewClosure())
        $d.Controls.Add($btn)
    }

    $d.ShowDialog() | Out-Null
    return $res[0]
}
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Color palette --------

$C_BG      = [System.Drawing.Color]::FromArgb(13,  17,  23)
$C_CARD    = [System.Drawing.Color]::FromArgb(22,  27,  34)
$C_INPUT   = [System.Drawing.Color]::FromArgb(33,  38,  45)
$C_BORDER  = [System.Drawing.Color]::FromArgb(48,  54,  61)
$C_ACCENT  = [System.Drawing.Color]::FromArgb(88,  166, 255)
$C_PRIMARY = [System.Drawing.Color]::FromArgb(31,  111, 235)
$C_TEXT    = [System.Drawing.Color]::FromArgb(240, 246, 252)
$C_DIM     = [System.Drawing.Color]::FromArgb(139, 148, 158)
$C_SUCCESS = [System.Drawing.Color]::FromArgb(63,  185, 80)
$C_DANGER  = [System.Drawing.Color]::FromArgb(248, 81,  73)
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Control factories ----
function New-Label {
    param(
        [string]$Text,
        [int]$X, [int]$Y,
        [int]$W = 480, [int]$H = 22,
        [float]$FontSize = 10,
        [System.Drawing.FontStyle]$FontStyle = "Regular",
        [System.Drawing.Color]$Color = [System.Drawing.Color]::FromArgb(240, 246, 252)
    )
    $l           = New-Object System.Windows.Forms.Label
    $l.Text      = $Text
    $l.Location  = New-Object System.Drawing.Point($X, $Y)
    $l.Size      = New-Object System.Drawing.Size($W, $H)
    $l.Font      = New-Object System.Drawing.Font("Segoe UI", $FontSize, $FontStyle)
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    return $l
}

function New-NavButton {
    param([string]$Text, [int]$X)
    $b          = New-Object DarkButton
    $b.Text     = $Text
    $b.Location = New-Object System.Drawing.Point($X, 12)
    $b.Size     = New-Object System.Drawing.Size(90, 30)
    return $b
}

function New-ActionButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 115, [int]$H = 28)
    $b          = New-Object DarkButton
    $b.Text     = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size     = New-Object System.Drawing.Size($W, $H)
    $b.Corner   = 0
    return $b
}
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Main form ------------
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "$APP_NAME $APP_VERSION Setup"
$form.ClientSize      = New-Object System.Drawing.Size(540, 475)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.BackColor       = $C_BG

$form.Add_Load({
    # Remove WS_EX_APPWINDOW (0x40000) from the console and hide it - this strips
    # the taskbar entry and hides the window at the exact moment the form appears.
    $hCon = [ConsoleUtils.Window]::GetConsoleWindow()
    if ($hCon -ne [IntPtr]::Zero) {
        $ex = [ConsoleUtils.Window]::GetWindowLong($hCon, -20)           # GWL_EXSTYLE
        [ConsoleUtils.Window]::SetWindowLong($hCon, -20,
            ($ex -band (-bnot 0x40000)) -bor 0x80) | Out-Null            # remove APPWINDOW, add TOOLWINDOW
        [ConsoleUtils.Window]::ShowWindow($hCon, 0) | Out-Null           # SW_HIDE
    }

    [DarkMode]::Enable($form.Handle)
})

$form.Add_FormClosing({
    param($s, $e)
    if ($script:idx -eq 6) { $e.Cancel = $true; return }   # block close during installation
    if ($script:skipCloseConfirm) { return }               # after uninstall, allow closing
    if ($pgReinstall.Visible -or $pgUpdate.Visible) { return }  # maintenance pages - no confirmation
    if ($script:idx -lt 7) {
        $r = Show-Dialog "Cancel Setup" "Are you sure you want to cancel the installation?" @("Yes", "No")
        if ($r -ne "Yes") { $e.Cancel = $true }
    }
})

$form.Add_FormClosed({
    if ($script:iconImage) {
        $script:iconImage.Dispose()
        $script:iconImage = $null
    }
    if (Test-Path $script:iconTemp) {
        Remove-Item $script:iconTemp -Force -ErrorAction SilentlyContinue
    }
    if ($script:setupTmp -and (Test-Path $script:setupTmp)) {
        Remove-Item $script:setupTmp -Force -ErrorAction SilentlyContinue
    }
})

# --- Header: y=0, h=80 ----
$header           = New-Object System.Windows.Forms.Panel
$header.Location  = New-Object System.Drawing.Point(0, 0)
$header.Size      = New-Object System.Drawing.Size(540, 80)
$header.BackColor = $C_CARD

$picIcon           = New-Object System.Windows.Forms.PictureBox
$picIcon.Location  = New-Object System.Drawing.Point(16, 12)
$picIcon.Size      = New-Object System.Drawing.Size(56, 56)
$picIcon.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picIcon.BackColor = $C_CARD

if ($script:iconImage) {
    $_bmp = New-Object System.Drawing.Bitmap(56, 56)
    $_gfx = [System.Drawing.Graphics]::FromImage($_bmp)
    $_gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $_gfx.Clear($C_CARD)
    $_gfx.DrawImage($script:iconImage, 0, 0, 56, 56)
    $_gfx.Dispose()
    $picIcon.Image   = $_bmp
    $lblTitle        = New-Label $APP_NAME  82 10 260 38 22 Bold    $C_TEXT
    $lblSubtitle     = New-Label "Welcome"  85 52 430 22 10 Regular $C_DIM
} else {
    $lblTitle        = New-Label $APP_NAME  20 10 300 38 22 Bold    $C_TEXT
    $lblSubtitle     = New-Label "Welcome"  23 52 490 22 10 Regular $C_DIM
}

$header.Controls.AddRange(@($picIcon, $lblTitle, $lblSubtitle))
$form.Controls.Add($header)

# --- Accent separator: y=80, h=2 --------------------
$hdrLine           = New-Object System.Windows.Forms.Panel
$hdrLine.Location  = New-Object System.Drawing.Point(0, 80)
$hdrLine.Size      = New-Object System.Drawing.Size(540, 2)
$hdrLine.BackColor = $C_PRIMARY
$form.Controls.Add($hdrLine)

# --- Content: y=82, h=263 -
$body           = New-Object System.Windows.Forms.Panel
$body.Location  = New-Object System.Drawing.Point(0, 82)
$body.Size      = New-Object System.Drawing.Size(540, 338)
$body.BackColor = $C_BG
$form.Controls.Add($body)

# --- Footer: y=345, h=55 --
$footer           = New-Object System.Windows.Forms.Panel
$footer.Location  = New-Object System.Drawing.Point(0, 420)
$footer.Size      = New-Object System.Drawing.Size(540, 55)
$footer.BackColor = $C_CARD
$footer.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen($C_BORDER, 1)
    $e.Graphics.DrawLine($pen, 0, 0, $footer.Width, 0)
    $pen.Dispose()
})

$btnBack   = New-NavButton "< Back"  250
$btnNext   = New-NavButton "Next >"  345
$btnCancel = New-NavButton "Cancel"  440

$btnNext.NormalColor = $C_PRIMARY
$btnNext.HoverColor  = [System.Drawing.Color]::FromArgb(56, 139, 253)
$btnNext.PressColor  = [System.Drawing.Color]::FromArgb(17,  88, 199)

$footer.Controls.AddRange(@($btnBack, $btnNext, $btnCancel))
$form.Controls.Add($footer)

# --- Page factory ---------
function New-Page {
    $p           = New-Object System.Windows.Forms.Panel
    $p.Location  = New-Object System.Drawing.Point(0, 0)
    $p.Size      = New-Object System.Drawing.Size(540, 338)
    $p.BackColor = $C_BG
    $p.Visible   = $false
    $body.Controls.Add($p)
    return $p
}
# =============================================================================
# PAGE 0 - WELCOME
# =============================================================================
$pgWelcome = New-Page
$pgWelcome.Controls.AddRange(@(
    (New-Label "Welcome to $APP_NAME Setup" 30 28 480 34 16 Bold   $C_TEXT),
    (New-Label "Version $APP_VERSION  -  $APP_NAME Source License  -  Open Source" 33 70 480 20 9 Regular $C_DIM),
    (New-Label "This wizard will guide you through installing $APP_NAME" 30 112 480 20 10 Regular $C_TEXT),
    (New-Label "on your computer." 30 134 480 20 10 Regular $C_TEXT),
    (New-Label "Click Next to begin." 30 172 480 20 10 Regular $C_DIM),
    (New-Label "Creator" 30  218  68 18 9 Bold $C_DIM),
    (New-Label "GitHub"  312 218  52 18 9 Bold $C_DIM)
))

function New-WelcomeLink($text, $url, $x, $y, $w) {
    $lnk                  = New-Object System.Windows.Forms.LinkLabel
    $lnk.Text             = $text
    $lnk.Location         = New-Object System.Drawing.Point($x, $y)
    $lnk.Size             = New-Object System.Drawing.Size($w, 18)
    $lnk.Font             = New-Object System.Drawing.Font("Segoe UI", 9)
    $lnk.LinkColor        = $C_ACCENT
    $lnk.ActiveLinkColor  = [System.Drawing.Color]::White
    $lnk.VisitedLinkColor = $C_ACCENT
    $lnk.BackColor        = [System.Drawing.Color]::Transparent
    $lnk.Cursor           = [System.Windows.Forms.Cursors]::Hand
    $lnk.Add_LinkClicked({ Start-Process $url }.GetNewClosure())
    return $lnk
}

$pgWelcome.Controls.Add((New-WelcomeLink "Wizard Burgil 42" "https://github.com/burgil"            104 218 200))
$pgWelcome.Controls.Add((New-WelcomeLink "Burgil Industries"   "https://github.com/burgil-industries"  370 218 160))
# =============================================================================
# PAGE 1 - LICENSE
# =============================================================================
$pgLicense = New-Page
$pgLicense.Controls.Add((New-Label "License Agreement" 30 18 480 22 13 Bold $C_TEXT))

$licBox             = New-Object System.Windows.Forms.RichTextBox
$licBox.Location    = New-Object System.Drawing.Point(30, 44)
$licBox.Size        = New-Object System.Drawing.Size(480, 108)
$licBox.ReadOnly    = $true
$licBox.BackColor   = $C_INPUT
$licBox.ForeColor   = $C_TEXT
$licBox.BorderStyle = "FixedSingle"
$licBox.Font        = New-Object System.Drawing.Font("Segoe UI", 8.5)
$licBox.ScrollBars  = "Vertical"
$licBox.DetectUrls  = $false

RTB-Write $licBox "COMPUTER Source License 1.0`n"   $C_ACCENT -Bold -Size 9
RTB-Write $licBox "Copyright (c) 2026 COMPUTER`n`n" $C_DIM   -Size 8

RTB-Write $licBox "TERMS AND CONDITIONS`n`n" $C_TEXT -Bold

RTB-Write $licBox "1. DEFINITIONS`n" $C_ACCENT -Bold
RTB-Write $licBox "`"Software`" means COMPUTER and all associated source code, documentation, and`nconfiguration files distributed under this license.`n`n" $C_TEXT
RTB-Write $licBox "`"Plugin`" means a separate work designed to extend or integrate with the`nSoftware, which does not replicate the Software's core functionality and`ndepends on the Software to operate.`n`n" $C_TEXT
RTB-Write $licBox "`"Competing Product`" means any product, service, or software whose primary`npurpose substantially replicates or replaces the core functionality of the`nSoftware, regardless of whether it is based on this source code.`n`n" $C_TEXT

RTB-Write $licBox "2. GRANT OF RIGHTS`n" $C_SUCCESS -Bold
RTB-Write $licBox "Subject to the conditions below, you are granted a worldwide, royalty-free,`nnon-exclusive license to:`n`n" $C_TEXT
RTB-Write $licBox "a) Use, run, and inspect the Software for any personal or internal purpose.`n" $C_TEXT
RTB-Write $licBox "b) Modify the Software for personal or internal use.`n" $C_TEXT
RTB-Write $licBox "c) Create, use, modify, and distribute Plugins for the Software.`n" $C_TEXT
RTB-Write $licBox "d) Incorporate third-party code into Plugins, provided the license of that`n   third-party code permits such use.`n" $C_TEXT
RTB-Write $licBox "e) Share and distribute the Software to others, provided this license`n   accompanies any distribution and no files are altered to misrepresent origin.`n`n" $C_TEXT

RTB-Write $licBox "3. RESTRICTIONS`n" $C_DANGER -Bold
RTB-Write $licBox "a) You may not use, distribute, or incorporate this Software, in whole or`n   in part, to build, market, or operate a Competing Product.`n`n" $C_TEXT
RTB-Write $licBox "b) You may not redistribute the Software itself (not as a Plugin) without`n   prior written permission from the copyright holder.`n`n" $C_TEXT
RTB-Write $licBox "c) You may not remove or alter any copyright, license, or attribution`n   notices present in the Software.`n`n" $C_TEXT

RTB-Write $licBox "4. PROHIBITED USES`n" $C_DANGER -Bold
RTB-Write $licBox "You may not use the Software:`n`n" $C_TEXT
RTB-Write $licBox "a) For any purpose that is unlawful, harmful, abusive, threatening,`n   harassing, defamatory, or otherwise objectionable.`n`n" $C_TEXT
RTB-Write $licBox "b) To facilitate or participate in any illegal activity, including but not`n   limited to fraud, malware distribution, unauthorized access to systems,`n   or violation of any applicable law or regulation.`n`n" $C_TEXT
RTB-Write $licBox "c) In any manner that could damage, disable, overburden, or impair the`n   Software or its associated infrastructure.`n`n" $C_TEXT

RTB-Write $licBox "5. REGIONAL COMPLIANCE`n" ([System.Drawing.Color]::FromArgb(255, 200, 60)) -Bold
RTB-Write $licBox "You are solely responsible for determining whether your use of the Software`nis lawful in your jurisdiction. The authors make no representation that the`nSoftware is appropriate or available for use in any specific location. If`naccess to or use of the Software is prohibited by the laws of your region,`nyou must not use it. Proceeding with installation or use constitutes your`nconfirmation that such use is permitted under the laws applicable to you.`n`n" $C_TEXT

RTB-Write $licBox "6. PLUGINS AND OPEN SOURCE REQUIREMENT`n" $C_ACCENT -Bold
RTB-Write $licBox "The COMPUTER ecosystem is built on transparency. Any Plugin distributed`npublicly MUST be licensed under the " $C_TEXT
RTB-Write $licBox "GNU Affero General Public License v3.0 (AGPLv3)" $C_ACCENT -Bold
RTB-Write $licBox "`nand its source code must be freely available. Plugins kept for personal`nor internal use only are not subject to this requirement.`n`n" $C_TEXT

RTB-Write $licBox "7. DISCLAIMER - USE AT YOUR OWN RISK`n" ([System.Drawing.Color]::FromArgb(255, 200, 60)) -Bold
RTB-Write $licBox "THE SOFTWARE IS PROVIDED " $C_DIM
RTB-Write $licBox "`"AS IS`""                 $C_DANGER -Bold
RTB-Write $licBox ", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR`nIMPLIED. YOU USE THIS SOFTWARE ENTIRELY AT YOUR OWN RISK.`n`n" $C_DIM
RTB-Write $licBox "THE AUTHORS AND COPYRIGHT HOLDERS EXPRESSLY DISCLAIM ALL WARRANTIES,`nINCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A`nPARTICULAR PURPOSE, ACCURACY, AND NONINFRINGEMENT.`n`n" $C_DIM
RTB-Write $licBox "IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY DIRECT,`nINDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES`n(INCLUDING BUT NOT LIMITED TO LOSS OF DATA, LOSS OF PROFITS, BUSINESS`nINTERRUPTION, OR ANY OTHER LOSS) ARISING OUT OF OR IN CONNECTION WITH THE`nUSE OR INABILITY TO USE THE SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY`nOF SUCH DAMAGES.`n" $C_DIM

$pgLicense.Controls.Add($licBox)

# --- 4-column summary grid ---
# Columns: [CAN 1 x=30] [CAN 2 x=152] | [CANT 1 x=276] [CANT 2 x=396]

# Section headers
$pgLicense.Controls.Add((New-Label "[+]  YOU CAN"    30  162 238 15 8 Bold $C_SUCCESS))
$pgLicense.Controls.Add((New-Label "[x]  YOU CANNOT" 276 162 238 15 8 Bold $C_DANGER))

# Vertical divider
$licDiv           = New-Object System.Windows.Forms.Panel
$licDiv.Location  = New-Object System.Drawing.Point(265, 160)
$licDiv.Size      = New-Object System.Drawing.Size(1, 90)
$licDiv.BackColor = $C_BORDER
$pgLicense.Controls.Add($licDiv)

# Tooltip for all summary items
$licTip = New-Object System.Windows.Forms.ToolTip

function New-LicItem([string]$t, [int]$x, [int]$y, [System.Drawing.Color]$c, [string]$tip) {
    $lbl = New-Label $t $x $y 118 14 8 Regular $c
    $licTip.SetToolTip($lbl, $tip)
    return $lbl
}

# CAN DO - col 1 (x=30) and col 2 (x=152)
$pgLicense.Controls.AddRange(@(
    (New-LicItem "[+] Personal use"      30  181 $C_SUCCESS "Use $APP_NAME freely for personal projects, learning, and experimentation"),
    (New-LicItem "[+] Build plugins"    152  181 $C_SUCCESS "Create extensions and integrations that work with and depend on $APP_NAME"),
    (New-LicItem "[+] Modify source"     30  198 $C_SUCCESS "Edit the source code to suit your personal or internal needs"),
    (New-LicItem "[+] Share freely"     152  198 $C_SUCCESS "Share and distribute $APP_NAME to others - unmodified, with this license included"),
    (New-LicItem "[+] Run internally"    30  215 $C_SUCCESS "Deploy $APP_NAME within your organization for internal business use"),
    (New-LicItem "[+] Use licensed code" 152 215 $C_SUCCESS "Incorporate third-party libraries in your plugins if their AGPLv3-compatible license permits"),
    (New-LicItem "[+] Share plugins"     30  232 $C_SUCCESS "Distribute your plugins to others - must be open source under AGPLv3 when distributed publicly")
))

# CANNOT - col 3 (x=276) and col 4 (x=396)
$pgLicense.Controls.AddRange(@(
    (New-LicItem "[x] Compete with us"     276 181 $C_DANGER "Do not build a product whose primary purpose overlaps with $APP_NAME's core functionality"),
    (New-LicItem "[x] Violate local laws"  396 181 $C_DANGER "You must verify that using $APP_NAME is legal in your country or region before installing"),
    (New-LicItem "[x] Redistribute it"    276 198 $C_DANGER "Do not distribute a modified version of $APP_NAME itself without prior written permission"),
    (New-LicItem "[x] Illegal/harmful use" 396 198 $C_DANGER "Do not use $APP_NAME for fraud, malware, unauthorized system access, or any harmful activity"),
    (New-LicItem "[x] Remove notices"      276 215 $C_DANGER "Do not remove or alter any copyright, license, or attribution notices in the source"),
    (New-LicItem "[x] Hold liable"         396 215 $C_DANGER "Authors are not liable for any damages - you use this software entirely at your own risk"),
    (New-LicItem "[x] Closed plugins"      276 232 ([System.Drawing.Color]::FromArgb(255,140,0)) "Public plugins MUST be open source under AGPLv3 - closed-source plugin distribution is not permitted")
))

# --- Disclaimer note ---
$licWarn           = New-Object System.Windows.Forms.Label
$licWarn.Text      = "[!]  Used at your own risk - no warranty, no liability for any damages or losses. You are solely responsible for ensuring use is legal in your region."
$licWarn.Location  = New-Object System.Drawing.Point(30, 254)
$licWarn.Size      = New-Object System.Drawing.Size(480, 30)
$licWarn.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$licWarn.ForeColor = $C_DIM
$licWarn.BackColor = [System.Drawing.Color]::Transparent
$pgLicense.Controls.Add($licWarn)

# --- Accept checkbox ---
$chkLicense           = New-Object System.Windows.Forms.CheckBox
$chkLicense.Text      = "I accept the terms of the license agreement"
$chkLicense.Location  = New-Object System.Drawing.Point(30, 293)
$chkLicense.Size      = New-Object System.Drawing.Size(480, 24)
$chkLicense.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$chkLicense.ForeColor = $C_TEXT
$chkLicense.BackColor = $C_BG
$chkLicense.Add_CheckedChanged({
    $btnNext.Enabled = $chkLicense.Checked
    if ($chkLicense.Checked) { Write-Log "License accepted" }
})
$pgLicense.Controls.Add($chkLicense)
# =============================================================================
# PAGE 2 - LEGAL NOTICES
# =============================================================================
$pgLegal = New-Page
$pgLegal.Controls.Add((New-Label "Legal Notices" 30 18 480 22 13 Bold $C_TEXT))

$legalBox             = New-Object System.Windows.Forms.RichTextBox
$legalBox.Location    = New-Object System.Drawing.Point(30, 44)
$legalBox.Size        = New-Object System.Drawing.Size(480, 210)
$legalBox.ReadOnly    = $true
$legalBox.BackColor   = $C_INPUT
$legalBox.ForeColor   = $C_TEXT
$legalBox.BorderStyle = "FixedSingle"
$legalBox.Font        = New-Object System.Drawing.Font("Segoe UI", 8.5)
$legalBox.ScrollBars  = "Vertical"
$legalBox.DetectUrls  = $false
$pgLegal.Controls.Add($legalBox)

$C_AMBER  = [System.Drawing.Color]::FromArgb(255, 200, 60)
$C_ORANGE = [System.Drawing.Color]::FromArgb(255, 140, 0)
$C_VIOLET = [System.Drawing.Color]::FromArgb(188, 140, 255)

# --- Quick-reference summary (mirrors bootstrap terminal) ---
RTB-Write $legalBox "  WARNING: EXPERIMENTAL ALPHA SOFTWARE`n"  $C_DANGER -Bold -Size 10
RTB-Write $legalBox "  By continuing you enter a legally binding agreement:`n`n" $C_DIM

RTB-Write $legalBox "  1. " $C_ACCENT -Bold
RTB-Write $legalBox "AGE REQUIREMENT         " $C_AMBER -Bold
RTB-Write $legalBox "You must be 18 or older to use this software.`n" $C_TEXT

RTB-Write $legalBox "  2. " $C_ACCENT -Bold
RTB-Write $legalBox "LIMITATION OF LIABILITY " $C_DANGER -Bold
RTB-Write $legalBox "No liability for damage, data loss, or harm.`n" $C_TEXT

RTB-Write $legalBox "  3. " $C_ACCENT -Bold
RTB-Write $legalBox "NO WARRANTIES           " $C_DANGER -Bold
RTB-Write $legalBox "Provided AS IS. No guarantees of any kind.`n" $C_TEXT

RTB-Write $legalBox "  4. " $C_ACCENT -Bold
RTB-Write $legalBox "BINDING ARBITRATION     " $C_DANGER -Bold
RTB-Write $legalBox "No jury trial or class-action. Individual arbitration.`n" $C_TEXT

RTB-Write $legalBox "  5. " $C_ACCENT -Bold
RTB-Write $legalBox "THIRD-PARTY MODULES     " $C_ORANGE -Bold
RTB-Write $legalBox "Third-party plugins are not reviewed by the author.`n" $C_TEXT

RTB-Write $legalBox "  6. " $C_ACCENT -Bold
RTB-Write $legalBox "DATA TRANSPARENCY       " $C_ACCENT -Bold
RTB-Write $legalBox "COMPUTER itself does not collect or transmit your data.`n" $C_TEXT

RTB-Write $legalBox "  7. " $C_ACCENT -Bold
RTB-Write $legalBox "AI TRANSPARENCY         " $C_VIOLET -Bold
RTB-Write $legalBox "AI providers you configure are governed by their own terms of service.`n" $C_TEXT

RTB-Write $legalBox "  8. " $C_ACCENT -Bold
RTB-Write $legalBox "GRACE PERIOD            " $C_SUCCESS -Bold
RTB-Write $legalBox "Contact legal@burgil.dev before taking legal action.`n" $C_TEXT

RTB-Write $legalBox "`n  --------------------------------------------------------`n`n" $C_BORDER

# --- Open Source & Fully Auditable ---
RTB-Write $legalBox "  Open Source and Fully Auditable`n"       $C_SUCCESS -Bold -Size 9.5
RTB-Write $legalBox "  This installer and "                     $C_TEXT
RTB-Write $legalBox "every component"                           $C_SUCCESS -Bold
RTB-Write $legalBox " is fully open source. You can read, audit,`n  and verify " $C_TEXT
RTB-Write $legalBox "every single line"                         $C_SUCCESS -Bold
RTB-Write $legalBox " before anything runs on your machine.`n"  $C_TEXT
RTB-Write $legalBox "  Source: "                                $C_DIM
RTB-Write $legalBox "computer.burgil.dev`n`n"                   $C_ACCENT -Bold

# --- Age Requirement ---
RTB-Write $legalBox "  Age Requirement`n"                       $C_AMBER -Bold -Size 9.5
RTB-Write $legalBox "  You must be "                            $C_TEXT
RTB-Write $legalBox "18 years of age or older"                  $C_AMBER -Bold
RTB-Write $legalBox " to use this software.`n"                  $C_TEXT
RTB-Write $legalBox "  Minors must not proceed.`n`n"            $C_DIM

# --- No Warranties / Liability ---
RTB-Write $legalBox "  No Warranties / Limitation of Liability`n" $C_DANGER -Bold -Size 9.5
RTB-Write $legalBox "  Provided "                               $C_TEXT
RTB-Write $legalBox "`"AS IS`""                                 $C_DANGER -Bold
RTB-Write $legalBox " without warranty of any kind. The author accepts "  $C_TEXT
RTB-Write $legalBox "no liability`n  "                          $C_DANGER -Bold
RTB-Write $legalBox "for damage, data loss, system failure, or harm. "    $C_TEXT
RTB-Write $legalBox "You assume all risk.`n`n"                  $C_DIM

# --- Binding Arbitration ---
RTB-Write $legalBox "  Binding Arbitration`n"                   $C_DANGER -Bold -Size 9.5
RTB-Write $legalBox "  By continuing, you waive your right to a " $C_TEXT
RTB-Write $legalBox "jury trial"                                $C_DANGER -Bold
RTB-Write $legalBox " and "                                     $C_TEXT
RTB-Write $legalBox "class-action lawsuits`n"                   $C_DANGER -Bold
RTB-Write $legalBox "  Disputes are resolved by "               $C_TEXT
RTB-Write $legalBox "individual arbitration at your expense`n`n" $C_DANGER -Bold

# --- Third-Party Plugins ---
RTB-Write $legalBox "  Third-Party Plugins`n"                   $C_ORANGE -Bold -Size 9.5
RTB-Write $legalBox "  Plugins from third parties are "         $C_TEXT
RTB-Write $legalBox "not reviewed"                              $C_ORANGE -Bold
RTB-Write $legalBox " by the author.`n"                         $C_TEXT
RTB-Write $legalBox "  Install them at your own risk. Report violations: " $C_TEXT
RTB-Write $legalBox "legal@burgil.dev`n`n"                      $C_ACCENT

# --- Privacy ---
RTB-Write $legalBox "  Data Transparency`n"                     $C_ACCENT -Bold -Size 9.5
RTB-Write $legalBox "  COMPUTER itself does "                   $C_TEXT
RTB-Write $legalBox "not"                                       $C_ACCENT -Bold
RTB-Write $legalBox " collect or transmit your data.`n"         $C_TEXT
RTB-Write $legalBox "  "                                        $C_TEXT
RTB-Write $legalBox "Plugins"                                   $C_ORANGE -Bold
RTB-Write $legalBox " and "                                     $C_TEXT
RTB-Write $legalBox "AI providers"                              $C_VIOLET -Bold
RTB-Write $legalBox " you configure operate under their own terms.`n`n" $C_TEXT

# --- AI Components ---
RTB-Write $legalBox "  AI Components`n"                         $C_VIOLET -Bold -Size 9.5
RTB-Write $legalBox "  You choose your AI provider - local model, cloud API, or anything OpenAI-compatible.`n" $C_TEXT
RTB-Write $legalBox "  AI providers "                           $C_TEXT
RTB-Write $legalBox "(e.g. NVIDIA NIM, any OpenAI-compatible API)" $C_DIM
RTB-Write $legalBox " are`n  user-configured and governed by "  $C_TEXT
RTB-Write $legalBox "their own terms of service`n`n"            $C_VIOLET -Bold

# --- Grace Period ---
RTB-Write $legalBox "  Grace Period`n"                          $C_SUCCESS -Bold -Size 9.5
RTB-Write $legalBox "  Contact "                                $C_TEXT
RTB-Write $legalBox "legal@burgil.dev"                          $C_ACCENT -Bold
RTB-Write $legalBox " before initiating any legal proceedings.`n" $C_TEXT
RTB-Write $legalBox "  The author commits to acting in "        $C_TEXT
RTB-Write $legalBox "good faith"                                $C_SUCCESS -Bold
RTB-Write $legalBox " to resolve valid concerns within 72 hours.`n" $C_TEXT

$legalBox.SelectionStart = 0

# --- Age confirmation checkbox ---
$chkAge           = New-Object System.Windows.Forms.CheckBox
$chkAge.Text      = "I confirm I am 18 years of age or older"
$chkAge.Location  = New-Object System.Drawing.Point(30, 262)
$chkAge.Size      = New-Object System.Drawing.Size(480, 20)
$chkAge.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$chkAge.ForeColor = $C_TEXT
$chkAge.BackColor = $C_BG
$chkAge.Add_CheckedChanged({
    $btnNext.Enabled = $chkAge.Checked -and $chkLegal.Checked
    if ($chkAge.Checked) { Write-Log "Age requirement confirmed" }
})
$pgLegal.Controls.Add($chkAge)

# --- Legal acceptance checkbox ---
$chkLegal           = New-Object System.Windows.Forms.CheckBox
$chkLegal.Text      = "I acknowledge and accept the above legal terms"
$chkLegal.Location  = New-Object System.Drawing.Point(30, 284)
$chkLegal.Size      = New-Object System.Drawing.Size(480, 20)
$chkLegal.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$chkLegal.ForeColor = $C_TEXT
$chkLegal.BackColor = $C_BG
$chkLegal.Add_CheckedChanged({
    $btnNext.Enabled = $chkAge.Checked -and $chkLegal.Checked
    if ($chkLegal.Checked) { Write-Log "Legal terms accepted" }
})
$pgLegal.Controls.Add($chkLegal)
# =============================================================================
# PAGE 2 - DEPENDENCIES
# =============================================================================
$pgDeps = New-Page
$pgDeps.Controls.Add((New-Label "Required Software" 30 18 480 26 13 Bold $C_TEXT))
$pgDeps.Controls.Add((New-Label "The following must be installed before $APP_NAME can run:" 30 48 480 20 10 Regular $C_DIM))

$lblPy       = New-Label "Python $([char]62)= $MIN_PYTHON"  30  94 140 22 10 Regular $C_TEXT
$lblPyStatus = New-Label "..."                   178  94 192 22 10

$btnGetPy           = New-ActionButton "Get Python" 375 91
$btnGetPy.Add_Click({ Start-Process "https://www.python.org/downloads/" })

$lblNode       = New-Label "Node.js $([char]62)= $MIN_NODE"  30 128 140 22 10 Regular $C_TEXT
$lblNodeStatus = New-Label "..."                  178 128 192 22 10

$btnGetNode           = New-ActionButton "Get Node.js" 375 125
$btnGetNode.Add_Click({ Start-Process "https://nodejs.org/en/download/" })

$btnRecheck = New-ActionButton "Recheck" 30 167 90 28

function Start-DepCheck {
    Write-Log "Dep check started"
    # Resets labels to "Checking..." and queues Update-DepStatus via a timer.
    # Using a timer means the dep check runs AFTER the current WndProc chain
    # (including DefWndProc / mouse-capture release) has fully unwound - so
    # DoEvents calls inside the check never see a captured button.
    $lblPyStatus.Text        = "Checking..."
    $lblPyStatus.ForeColor   = $C_DIM
    $lblNodeStatus.Text      = "Checking..."
    $lblNodeStatus.ForeColor = $C_DIM
    $btnGetPy.Visible        = $false
    $btnGetNode.Visible      = $false
    $btnNext.Enabled         = $false
    if ($script:_depTimer) { $script:_depTimer.Stop() }
    $script:_depTimer = New-Object System.Windows.Forms.Timer
    $script:_depTimer.Interval = 50
    $script:_depTimer.Add_Tick({
        try { $script:_depTimer.Stop(); Update-DepStatus } catch {}
    })
    $script:_depTimer.Start()
}

function Update-DepStatus {
    # Each Invoke-Async call pumps DoEvents - a Back/Next click can fire mid-run.
    # Guard every state change so navigating away doesn't corrupt the new page.
    if ($script:idx -ne 3) { return }

    # - Python: existence -
    $hasPy = [bool]((Invoke-Async 'where.exe' 'python').Trim())
    if ($script:idx -ne 3) { return }
    if ($hasPy) { $lblPyStatus.Text = "Detected..."; $lblPyStatus.ForeColor = $C_SUCCESS }
    else        { $lblPyStatus.Text = "Not found";   $lblPyStatus.ForeColor = $C_DANGER; $btnGetPy.Visible = $true }

    # - Node: existence ---
    $hasNode = [bool]((Invoke-Async 'where.exe' 'node').Trim())
    if ($script:idx -ne 3) { return }
    if ($hasNode) { $lblNodeStatus.Text = "Detected..."; $lblNodeStatus.ForeColor = $C_SUCCESS }
    else          { $lblNodeStatus.Text = "Not found";   $lblNodeStatus.ForeColor = $C_DANGER; $btnGetNode.Visible = $true }

    # - Python version, then pip appended ----------
    if ($hasPy) {
        $raw   = Invoke-Async 'python' '--version'
        if ($script:idx -ne 3) { return }
        $pyVer = if ($raw -match 'Python\s+(\S+)') { $Matches[1] } else { $raw }
        $lblPyStatus.Text = if ($pyVer) { $pyVer } else { "Detected" }

        $raw    = Invoke-Async 'pip' '--version'
        if ($script:idx -ne 3) { return }
        $pipVer = if ($raw -match '^pip\s+(\S+)') { $Matches[1] } else { '' }
        if ($pipVer) { $lblPyStatus.Text = "$pyVer  /  pip $pipVer" }
    }

    # - Node version, then npm appended ------------
    if ($hasNode) {
        $raw     = Invoke-Async 'node' '--version'
        if ($script:idx -ne 3) { return }
        $nodeVer = if ($raw -match 'v?(\d[\d.]*)') { $Matches[1] } else { $raw }
        $lblNodeStatus.Text = if ($nodeVer) { "v$nodeVer" } else { "Detected" }

        $raw    = Invoke-Async 'npm' '--version'
        if ($script:idx -ne 3) { return }
        $npmVer = if ($raw -match '^\d') { ($raw -split '\r?\n')[0].Trim() } else { '' }
        if ($npmVer) { $lblNodeStatus.Text = "v$nodeVer  /  npm $npmVer" }
    }

    # - Enable Next only after ALL checks complete --
    Write-Log ("Dep check done - python={0} node={1}" -f $lblPyStatus.Text, $lblNodeStatus.Text)
    if (-not $hasPy)   { Write-Log "Python not found" "WARN" }
    if (-not $hasNode) { Write-Log "Node.js not found" "WARN" }
    if ($script:idx -eq 3) { $btnNext.Enabled = $hasPy -and $hasNode }
}

$btnRecheck.Add_Click({ Write-Log "Dep recheck requested"; Start-DepCheck })
$pgDeps.Controls.AddRange(@($lblPy, $lblPyStatus, $btnGetPy, $lblNode, $lblNodeStatus, $btnGetNode, $btnRecheck))
# =============================================================================
# PAGE 3 - INSTALL LOCATION
# =============================================================================
$pgLocation = New-Page
$pgLocation.Controls.Add((New-Label "Install Location" 30 18 480 26 13 Bold $C_TEXT))
$pgLocation.Controls.Add((New-Label "Choose where to install $APP_NAME :" 30 48 480 20 10 Regular $C_DIM))

$txtDir             = New-Object System.Windows.Forms.TextBox
$txtDir.Location    = New-Object System.Drawing.Point(30, 82)
$txtDir.Size        = New-Object System.Drawing.Size(368, 26)
$txtDir.Font        = New-Object System.Drawing.Font("Segoe UI", 10)
$txtDir.Text        = "$env:LOCALAPPDATA\Programs\$APP_NAME".TrimEnd('.')
$txtDir.BackColor   = $C_INPUT
$txtDir.ForeColor   = $C_TEXT
$txtDir.BorderStyle = "FixedSingle"

$btnBrowse = New-ActionButton "Browse..." 406 80 102 28
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $txtDir.Text
    if ($dlg.ShowDialog() -eq "OK") {
        $txtDir.Text = $dlg.SelectedPath
        Write-Log "Install dir changed via browse: $($dlg.SelectedPath)"
    }
})

$chkShortcut           = New-Object System.Windows.Forms.CheckBox
$chkShortcut.Text      = "Create a desktop shortcut"
$chkShortcut.Checked   = $true
$chkShortcut.Location  = New-Object System.Drawing.Point(30, 124)
$chkShortcut.Size      = New-Object System.Drawing.Size(480, 24)
$chkShortcut.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$chkShortcut.ForeColor = $C_TEXT
$chkShortcut.BackColor = $C_BG

$pgLocation.Controls.AddRange(@($txtDir, $btnBrowse, $chkShortcut))
# =============================================================================
# PAGE 4 - CONFIRM
# =============================================================================
$pgConfirm = New-Page
$pgConfirm.Controls.Add((New-Label "Ready to Install" 30 18 480 26 13 Bold $C_TEXT))
$pgConfirm.Controls.Add((New-Label "Review your choices, then click Install:" 30 48 480 20 10 Regular $C_DIM))

# Summary rows: font=9, height=18, 22px row spacing (frees vertical space for the toggle)
$lblConfAppL   = New-Label "Application :"  30  84 134 18 9 Bold    $C_DIM
$lblConfAppV   = New-Label "$APP_NAME $APP_VERSION" 172  84 326 18 9 Regular $C_TEXT
$lblConfDirL   = New-Label "Location :"     30 106 134 18 9 Bold    $C_DIM
$lblConfDirV   = New-Label ""              172 106 326 18 9 Regular $C_TEXT
$lblConfScL    = New-Label "Shortcut :"     30 128 134 18 9 Bold    $C_DIM
$lblConfScV    = New-Label ""              172 128 326 18 9 Regular $C_TEXT
$lblConfProtoL = New-Label "Protocol :"     30 150 134 18 9 Bold    $C_DIM
$lblConfProtoV = New-Label "$($APP_PROTO)://"        172 150 326 18 9 Regular $C_ACCENT
$lblConfUninL  = New-Label "Uninstaller :"  30 172 134 18 9 Bold    $C_DIM
$lblConfUninV  = New-Label "Yes (Add/Remove Programs)" 172 172 326 18 9 Regular $C_SUCCESS

$confirmSep           = New-Object System.Windows.Forms.Panel
$confirmSep.Location  = New-Object System.Drawing.Point(30, 198)
$confirmSep.Size      = New-Object System.Drawing.Size(480, 1)
$confirmSep.BackColor = $C_BORDER

# "Advanced settings" collapsible toggle - DarkButton for proper hover/press feedback
$btnAdvToggle             = New-ActionButton "[+]  Advanced settings" 30 208 480 28
$btnAdvToggle.Font        = New-Object System.Drawing.Font("Segoe UI", 10)
$btnAdvToggle.ForeColor   = $C_TEXT
$btnAdvToggle.NormalColor = $C_INPUT
$btnAdvToggle.HoverColor  = $C_BORDER
$btnAdvToggle.PressColor  = $C_CARD
$btnAdvToggle.BorderColor = $C_BORDER
$btnAdvToggle.Corner      = 4

# Collapsible panel - hidden by default (2-column grid, rows at 22px spacing)
$pnlAdvanced           = New-Object System.Windows.Forms.Panel
$pnlAdvanced.Location  = New-Object System.Drawing.Point(30, 240)
$pnlAdvanced.Size      = New-Object System.Drawing.Size(480, 90)
$pnlAdvanced.BackColor = $C_BG
$pnlAdvanced.Visible   = $false

function New-OptChk([string]$text, [int]$x, [int]$y) {
    $c           = New-Object System.Windows.Forms.CheckBox
    $c.Text      = $text
    $c.Checked   = $true
    $c.Location  = New-Object System.Drawing.Point($x, $y)
    $c.Size      = New-Object System.Drawing.Size(235, 20)
    $c.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $c.ForeColor = $C_TEXT
    $c.BackColor = $C_BG
    return $c
}

# col1 x=0, col2 x=240; rows at y=2,24,46,68
$chkStartup   = New-OptChk "Run on Startup"          0   2
$chkSendTo    = New-OptChk "Add to Send To menu"     240  2
$chkAddPath   = New-OptChk "Add to Path"             0   24
$chkStartMenu = New-OptChk "Start Menu shortcut"     240 24
$chkOpenWith  = New-OptChk "Right-click menu"        0   46
$chkFileAssoc = New-OptChk "File type (.computer)"        240 46
$chkProto     = New-OptChk "App protocol ($($APP_PROTO)://)" 0   68
$chkNewMenu   = New-OptChk "New menu (.computer)"         240 68

$pnlAdvanced.Controls.AddRange(@($chkStartup, $chkSendTo, $chkAddPath, $chkStartMenu, $chkOpenWith, $chkFileAssoc, $chkProto, $chkNewMenu))

# New menu requires file type - disable it when file type is unchecked
$chkFileAssoc.Add_CheckedChanged({
    if (-not $chkFileAssoc.Checked) {
        $chkNewMenu.Checked = $false
        $chkNewMenu.Enabled = $false
    } else {
        $chkNewMenu.Enabled  = $true
        $chkNewMenu.Checked  = $true
    }
})

# Toggle expand/collapse on click
$btnAdvToggle.Add_Click({
    $pnlAdvanced.Visible = -not $pnlAdvanced.Visible
    $btnAdvToggle.Text   = if ($pnlAdvanced.Visible) { "[-]  Advanced settings" } else { "[+]  Advanced settings" }
})

# Tooltips for all optional feature checkboxes
$optTip = New-Object System.Windows.Forms.ToolTip
$optTip.SetToolTip($chkStartup,   "Launch $APP_NAME automatically when Windows starts")
$optTip.SetToolTip($chkSendTo,    "Add 'Send to $APP_NAME' to the right-click Send To submenu")
$optTip.SetToolTip($chkAddPath,   "Add $APP_NAME to PATH so you can run '$APP_NAME_LOW' from any terminal")
$optTip.SetToolTip($chkStartMenu, "Create a $APP_NAME shortcut in the Windows Start Menu")
$optTip.SetToolTip($chkOpenWith,  "Add 'Open with $APP_NAME' to the right-click menu for files and folders")
$optTip.SetToolTip($chkProto,     "Register the $($APP_PROTO):// URI scheme so links and scripts can open $APP_NAME")
$optTip.SetToolTip($chkFileAssoc, "Open .computer files with $APP_NAME on double-click")
$optTip.SetToolTip($chkNewMenu,   "Add 'New > $APP_NAME File (.computer)' to the right-click New submenu (requires File type)")

# Warning strip shown when COMPUTER is already running
$pnlComputerRunning           = New-Object System.Windows.Forms.Panel
$pnlComputerRunning.Location  = New-Object System.Drawing.Point(30, 342)
$pnlComputerRunning.Size      = New-Object System.Drawing.Size(480, 26)
$pnlComputerRunning.BackColor = [System.Drawing.Color]::FromArgb(60, 40, 0)
$pnlComputerRunning.Visible   = $false

$lblComputerRunningTxt           = New-Object System.Windows.Forms.Label
$lblComputerRunningTxt.Text      = "[!]  $APP_NAME is currently running - click Install to close it automatically"
$lblComputerRunningTxt.Location  = New-Object System.Drawing.Point(8, 4)
$lblComputerRunningTxt.Size      = New-Object System.Drawing.Size(464, 18)
$lblComputerRunningTxt.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblComputerRunningTxt.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 60)
$lblComputerRunningTxt.BackColor = [System.Drawing.Color]::Transparent
$pnlComputerRunning.Controls.Add($lblComputerRunningTxt)

$pgConfirm.Controls.AddRange(@(
    $lblConfAppL, $lblConfAppV, $lblConfDirL, $lblConfDirV,
    $lblConfScL,  $lblConfScV,  $lblConfProtoL, $lblConfProtoV,
    $lblConfUninL, $lblConfUninV,
    $confirmSep,
    $btnAdvToggle, $pnlAdvanced,
    $pnlComputerRunning
))
# =============================================================================
# PAGE 5 - INSTALLING
# =============================================================================
$pgInstall = New-Page
$pgInstall.Controls.Add((New-Label "Installing $APP_NAME..." 30 18 480 26 13 Bold $C_TEXT))

$progressBar          = New-Object DarkProgressBar
$progressBar.Location = New-Object System.Drawing.Point(30, 60)
$progressBar.Size     = New-Object System.Drawing.Size(480, 20)
$progressBar.Minimum  = 0
$progressBar.Maximum  = 100

$lblStep = New-Label "Preparing..." 30 90 480 20 10 Regular $C_DIM
$pgInstall.Controls.AddRange(@($progressBar, $lblStep))
# =============================================================================
# PAGE 6 - DONE  (setup complete + credits + ad, combined)
# =============================================================================
$pgDone = New-Page

$lblDoneTitle = New-Label "Setup complete!" 30  8 480 30 16 Bold    $C_SUCCESS
$lblDonePath  = New-Label ""               30 38 390 18  9 Regular $C_DIM

$btnOpenDir = New-ActionButton "Open folder" 420 38 90 22
$btnOpenDir.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($txtDir.Text)`"" })

$doneSep           = New-Object System.Windows.Forms.Panel
$doneSep.Location  = New-Object System.Drawing.Point(30, 64)
$doneSep.Size      = New-Object System.Drawing.Size(480, 1)
$doneSep.BackColor = $C_BORDER

# Ad strip - try to load banner image from $AD_URL, fall back to placeholder text
# $script:adStream kept alive at script scope so GC doesn't corrupt the image
$script:adImage  = $null
$script:adStream = $null
if ($AD_URL) {
    try {
        $adBytes         = (New-Object System.Net.WebClient).DownloadData($AD_URL)
        $script:adStream = New-Object System.IO.MemoryStream(,$adBytes)
        $script:adImage  = [System.Drawing.Image]::FromStream($script:adStream)
        Write-Log "Ad loaded: $AD_URL"
    } catch {
        Write-Log "Ad load failed: $_" "WARN"
    }
} else {
    Write-Log "Ad URL not set - showing placeholder"
}

$adBox           = New-Object System.Windows.Forms.Panel
$adBox.Location  = New-Object System.Drawing.Point(30, 74)
$adBox.Size      = New-Object System.Drawing.Size(480, 100)
$adBox.BackColor = $C_CARD

if ($script:adImage) {
    # Image fills full 480x82, contact text sits below it at y=83
    $adPic           = New-Object System.Windows.Forms.PictureBox
    $adPic.Location  = New-Object System.Drawing.Point(0, 0)
    $adPic.Size      = New-Object System.Drawing.Size(480, 82)
    $adPic.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
    $adPic.BackColor = $C_CARD
    $adPic.Image     = $script:adImage
    if ($AD_LINK) {
        $adPic.Cursor = [System.Windows.Forms.Cursors]::Hand
        $adPic.Add_Click({ Write-Log "Ad clicked: $AD_LINK"; Start-Process $AD_LINK })
    }
    $adBox.Controls.Add($adPic)

    $adSub                = New-Object System.Windows.Forms.LinkLabel
    $adSub.Text           = "Reach  people  installing  $APP_NAME  -  Contact us to advertise"
    $adSub.Location       = New-Object System.Drawing.Point(0, 83)
    $adSub.Size           = New-Object System.Drawing.Size(480, 16)
    $adSub.Font           = New-Object System.Drawing.Font("Segoe UI", 8)
    $adSub.TextAlign      = "MiddleCenter"
    $adSub.ForeColor      = $C_DIM
    $adSub.BackColor      = $C_CARD
    $adSub.LinkColor      = $C_ACCENT
    $adSub.ActiveLinkColor = $C_ACCENT
    $adSub.Links.Clear()
    $linkOffset = "Reach  people  installing  $APP_NAME  -  ".Length
    $adSub.Links.Add($linkOffset, "Contact us to advertise".Length, $CONTACT_US) | Out-Null
    $adSub.Add_LinkClicked({ param($s,$e) Start-Process $e.Link.LinkData })
    $adBox.Controls.Add($adSub)
} else {
    # Dashed border placeholder - "Your Ad Here" + contact line both inside the box
    $adBox.Add_Paint({
        param($s, $e)
        $dash = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 88, 166, 255), 1)
        $dash.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        $e.Graphics.DrawRectangle($dash, 2, 2, $s.Width - 5, 79)
        $dash.Dispose()
    })
    $adTitle           = New-Label "Your Ad Here" 0 16 480 24 14 Bold $C_DIM
    $adTitle.TextAlign = "MiddleCenter"
    $adSub                = New-Object System.Windows.Forms.LinkLabel
    $adSub.Text           = "Reach  people  installing  $APP_NAME  -  Contact us to advertise"
    $adSub.Location       = New-Object System.Drawing.Point(0, 48)
    $adSub.Size           = New-Object System.Drawing.Size(480, 16)
    $adSub.Font           = New-Object System.Drawing.Font("Segoe UI", 8)
    $adSub.TextAlign      = "MiddleCenter"
    $adSub.ForeColor      = $C_DIM
    $adSub.BackColor      = $C_CARD
    $adSub.LinkColor      = $C_ACCENT
    $adSub.ActiveLinkColor = $C_ACCENT
    $adSub.Links.Clear()
    $linkOffset = "Reach  people  installing  $APP_NAME  -  ".Length
    $adSub.Links.Add($linkOffset, "Contact us to advertise".Length, $CONTACT_US) | Out-Null
    $adSub.Add_LinkClicked({ param($s,$e) Start-Process $e.Link.LinkData })
    $adBox.Controls.Add($adTitle)
    $adBox.Controls.Add($adSub)
}

# Checkboxes
$chkLaunch           = New-Object System.Windows.Forms.CheckBox
$chkLaunch.Text      = "Launch $APP_NAME now"
$chkLaunch.Checked   = $true
$chkLaunch.Location  = New-Object System.Drawing.Point(30, 186)
$chkLaunch.Size      = New-Object System.Drawing.Size(480, 22)
$chkLaunch.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$chkLaunch.ForeColor = $C_TEXT
$chkLaunch.BackColor = $C_BG

$pgDone.Controls.AddRange(@($lblDoneTitle, $lblDonePath, $btnOpenDir, $doneSep, $adBox, $chkLaunch))
# =============================================================================
# REINSTALL DETECTION PAGE (shown instead of wizard when already installed)
# =============================================================================
$pgReinstall = New-Page
$script:existingInstallDir = $null
$script:existingVersion    = $null
$script:patchChain         = @()         # ordered array of patch objects to apply

$lblReinstTitle  = New-Label "$APP_NAME is already installed" 30 18 480 26 13 Bold $C_TEXT
$lblReinstPath   = New-Label "" 30 48 480 20 10 Regular $C_DIM
$lblUpdateStatus = New-Label "Checking for updates..." 30 78 340 22 10 Regular $C_DIM
$btnRecheck      = New-ActionButton "Recheck" 380 76 90 24

$btnReinstOpen   = New-ActionButton "Open folder" 30 118 100 28
$btnReinstOpen.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($script:existingInstallDir)`"" })

$btnRepair       = New-ActionButton "Repair / Reinstall" 30 158 160 32
$btnUninstReinst = New-ActionButton "Uninstall" 200 158 120 32
$btnReinstClose  = New-ActionButton "Cancel" 330 158 90 32

$btnUninstReinst.NormalColor = [System.Drawing.Color]::FromArgb(58, 15, 12)
$btnUninstReinst.ForeColor   = $C_DANGER

# - Update check logic ---
$script:_recheckTimer = $null

function Check-ForUpdate {
    Write-Log "Check-ForUpdate: $UPDATE_URL/latest.json  (installed: $script:existingVersion)"
    $pnlReinstComputerRunning.Visible = Test-ComputerRunning
    $lblUpdateStatus.Text      = "Checking for updates..."
    $lblUpdateStatus.ForeColor = $C_DIM
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $wc   = New-Object System.Net.WebClient
        $json = $wc.DownloadString("$UPDATE_URL/latest.json") | ConvertFrom-Json
        if (-not $json.version) { throw "bad json" }
        $latest    = [System.Version]$json.version
        $installed = [System.Version]$script:existingVersion
        if ($latest -gt $installed) {
            Write-Log "Update found: $installed -> $latest"
            if ($script:_recheckTimer) { $script:_recheckTimer.Stop() }
            # Build patch chain - filter patches newer than installed version
            $chain = @()
            if ($json.patches) {
                $patchVersions = $json.patches | Where-Object {
                    [System.Version]$_.version -gt $installed
                } | Sort-Object { [System.Version]$_.version }
                foreach ($pv in $patchVersions) {
                    try {
                        $p = $wc.DownloadString("$UPDATE_URL/patches/$($pv.version)/patch.json") | ConvertFrom-Json
                        $chain += $p
                    } catch {}
                }
            }
            # Fallback: if no patches array or chain is empty, use latest.json as single patch
            if ($chain.Count -eq 0) {
                try {
                    $p = $wc.DownloadString("$UPDATE_URL/patches/$($json.version)/patch.json") | ConvertFrom-Json
                    $chain = @($p)
                } catch {
                    $chain = @($json)
                }
            }
            $script:patchChain = $chain
            Show-UpdatePage
            return
        }
        Write-Log "Up to date: $script:existingVersion"
        $lblUpdateStatus.Text      = "You have the latest version ($($script:existingVersion))"
        $lblUpdateStatus.ForeColor = $C_SUCCESS
    } catch {
        Write-Log "Update check failed: $_" "ERROR"
        $lblUpdateStatus.Text      = "Unable to check for updates"
        $lblUpdateStatus.ForeColor = $C_DANGER
    }
}

$btnRecheck.Add_Click({
    if ($script:_recheckTimer -and $script:_recheckTimer.Enabled) {
        Write-Log "Update auto-recheck stopped"
        $script:_recheckTimer.Stop()
        $btnRecheck.Text = "Recheck"
    } else {
        Write-Log "Update recheck requested"
        Check-ForUpdate
        if ($pgUpdate.Visible) { return }   # update was found, already on update page
        # Start auto-recheck every 3s
        if ($script:_recheckTimer) { $script:_recheckTimer.Stop() }
        $script:_recheckTimer = New-Object System.Windows.Forms.Timer
        $script:_recheckTimer.Interval = 3000
        $script:_recheckTimer.Add_Tick({
            Check-ForUpdate
        })
        $script:_recheckTimer.Start()
        $btnRecheck.Text = "Stop"
    }
})

$btnRepair.Add_Click({
    Write-Log "Repair/reinstall selected"
    if (Test-ComputerRunning) {
        $choice = Show-Dialog "$APP_NAME is Running" "$APP_NAME is currently running in the background.`nPlease close it before repairing." @("Close $APP_NAME", "Cancel")
        if ($choice -eq "Close $APP_NAME") {
            Stop-ComputerProcess
            Start-Sleep -Milliseconds 800
            if (Test-ComputerRunning) {
                Show-Dialog "Could Not Close $APP_NAME" "$APP_NAME is still running. Please close it manually and try again." @("OK")
                return
            }
        } else { return }
    }
    if ($script:_recheckTimer) { $script:_recheckTimer.Stop() }
    if ($script:existingInstallDir -and (Test-Path $script:existingInstallDir)) {
        Clear-InstallAttributes $script:existingInstallDir
    }
    $pgReinstall.Visible = $false
    $footer.Visible      = $true
    $form.ClientSize     = New-Object System.Drawing.Size(540, 475)
    Show-Page 0
})

$btnUninstReinst.Add_Click({
    Write-Log "Uninstall selected from maintenance page"
    if (Test-ComputerRunning) {
        $choice = Show-Dialog "$APP_NAME is Running" "$APP_NAME is currently running in the background.`nPlease close it before uninstalling." @("Close $APP_NAME", "Cancel")
        if ($choice -eq "Close $APP_NAME") {
            Stop-ComputerProcess
            Start-Sleep -Milliseconds 800
            if (Test-ComputerRunning) {
                Show-Dialog "Could Not Close $APP_NAME" "$APP_NAME is still running. Please close it manually and try again." @("OK")
                return
            }
        } else { return }
    }
    if ($script:_recheckTimer) { $script:_recheckTimer.Stop() }
    $dir = $script:existingInstallDir
    $lblReinstTitle.Text      = "Uninstalling $APP_NAME..."
    $lblReinstTitle.ForeColor = $C_DIM
    $lblUpdateStatus.Visible  = $false
    $btnRecheck.Visible       = $false
    $btnReinstOpen.Visible    = $false
    $btnRepair.Visible        = $false
    $btnUninstReinst.Visible  = $false
    $btnReinstClose.Visible   = $false
    $pnlReinstComputerRunning.Visible = $false
    $pbUninst.Value   = 0
    $pbUninst.Visible = $true
    [System.Windows.Forms.Application]::DoEvents()

    # Step 1 - registry entries
    $lblReinstPath.Text = "Removing registry entries..."
    $pbUninst.Value = 10
    [System.Windows.Forms.Application]::DoEvents()
    try { [System.IO.Directory]::SetCurrentDirectory($env:TEMP) } catch {}
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$APP_NAME_LOW\ShellNew" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$APP_NAME_LOW"          -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\$APP_NAME.File"          -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\$APP_NAME_LOW"           -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$APP_NAME" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $APP_NAME -ErrorAction SilentlyContinue

    # Step 2 - shortcuts & PATH
    $lblReinstPath.Text = "Removing shortcuts..."
    $pbUninst.Value = 30
    [System.Windows.Forms.Application]::DoEvents()
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$APP_NAME.lnk" -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "HKCU:\SOFTWARE\Classes\*\shell\$APP_NAME"                    -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\shell\$APP_NAME"            -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\Background\shell\$APP_NAME" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\SendTo\$APP_NAME.lnk"                      -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$APP_NAME.lnk"         -Force -ErrorAction SilentlyContinue
    $sc = "$env:USERPROFILE\Desktop\$APP_NAME.lnk"
    if (Test-Path $sc) { Remove-Item $sc -Force -ErrorAction SilentlyContinue }
    foreach ($lnkName in @("Repair.lnk", "Uninstall.lnk", "Check for Updates.lnk")) {
        $lnkPath = Join-Path $dir $lnkName
        if (Test-Path $lnkPath) { Remove-Item $lnkPath -Force -ErrorAction SilentlyContinue }
    }
    $curPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = ($curPath -split ";" | Where-Object { $_ -ne "$dir\data" -and $_ -ne $dir }) -join ";"
    if ($newPath -ne $curPath) { [Environment]::SetEnvironmentVariable("Path", $newPath, "User") }

    # Step 3 - flush shell cache
    $lblReinstPath.Text = "Flushing shell cache..."
    $pbUninst.Value = 55
    [System.Windows.Forms.Application]::DoEvents()
    if (-not ([System.Management.Automation.PSTypeName]'ShellNotify').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ShellNotify {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
"@
    }
    [ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800

    # Step 4 - delete files
    $lblReinstPath.Text = "Deleting files..."
    $pbUninst.Value = 72
    [System.Windows.Forms.Application]::DoEvents()
    $desktopIni = Join-Path $dir "desktop.ini"
    if (Test-Path $desktopIni -ErrorAction SilentlyContinue) {
        try { (Get-Item $desktopIni -Force).Attributes = [System.IO.FileAttributes]::Normal } catch {}
        Remove-Item $desktopIni -Force -ErrorAction SilentlyContinue
    }
    Clear-InstallAttributes $dir
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $dir) {
        Start-Sleep -Milliseconds 500
        try { [System.IO.Directory]::Delete($dir, $true) } catch {}
    }
    if (Test-Path $dir) {
        Start-Sleep -Milliseconds 500
        Start-Process cmd.exe -WorkingDirectory $env:TEMP -ArgumentList "/c rd /s /q `"$dir`"" -Wait -WindowStyle Hidden
    }
    $pbUninst.Value = 100
    [System.Windows.Forms.Application]::DoEvents()

    if (Test-Path $dir) {
        Write-Log "Uninstall failed - dir still exists: $dir" "ERROR"
        $lblReinstTitle.Text      = "Unable to uninstall"
        $lblReinstTitle.ForeColor = $C_DANGER
        $lblReinstPath.Text       = "The folder may be in use. Close any open windows inside it, or restart your PC and try again."
    } else {
        Write-Log "Uninstall complete"
        $lblReinstTitle.Text      = "$APP_NAME has been uninstalled"
        $lblReinstTitle.ForeColor = $C_SUCCESS
        $lblReinstPath.Text       = "All files and registry entries have been removed."
    }
    $btnReinstClose.Text    = "Close"
    $btnReinstClose.Visible = $true
    $script:skipCloseConfirm = $true
})

$btnReinstClose.Add_Click({
    if ($script:_recheckTimer) { $script:_recheckTimer.Stop() }
    $script:skipCloseConfirm = $true
    $form.Close()
})

# Progress bar for uninstall (shares y=200 with warning panel - they are mutually exclusive)
$pbUninst          = New-Object System.Windows.Forms.ProgressBar
$pbUninst.Location = New-Object System.Drawing.Point(30, 200)
$pbUninst.Size     = New-Object System.Drawing.Size(480, 14)
$pbUninst.Minimum  = 0
$pbUninst.Maximum  = 100
$pbUninst.Visible  = $false

# Warning strip shown when COMPUTER is already running
$pnlReinstComputerRunning           = New-Object System.Windows.Forms.Panel
$pnlReinstComputerRunning.Location  = New-Object System.Drawing.Point(30, 200)
$pnlReinstComputerRunning.Size      = New-Object System.Drawing.Size(390, 26)
$pnlReinstComputerRunning.BackColor = [System.Drawing.Color]::FromArgb(60, 40, 0)
$pnlReinstComputerRunning.Visible   = $false

$lblReinstComputerRunningTxt           = New-Object System.Windows.Forms.Label
$lblReinstComputerRunningTxt.Text      = "[!]  $APP_NAME is currently running - close it before continuing"
$lblReinstComputerRunningTxt.Location  = New-Object System.Drawing.Point(8, 4)
$lblReinstComputerRunningTxt.Size      = New-Object System.Drawing.Size(374, 18)
$lblReinstComputerRunningTxt.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblReinstComputerRunningTxt.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 60)
$lblReinstComputerRunningTxt.BackColor = [System.Drawing.Color]::Transparent
$pnlReinstComputerRunning.Controls.Add($lblReinstComputerRunningTxt)

$pgReinstall.Controls.AddRange(@(
    $lblReinstTitle, $lblReinstPath, $lblUpdateStatus, $btnRecheck,
    $btnReinstOpen, $btnRepair, $btnUninstReinst, $btnReinstClose,
    $pbUninst, $pnlReinstComputerRunning
))
# =============================================================================
# UPDATE PAGE (shown when a newer version is found)
# =============================================================================
$pgUpdate = New-Page
$pgUpdate.Visible = $false

$lblUpdateTitle = New-Label "Update Available" 30 14 480 28 14 Bold $C_ACCENT
$lblUpdateVer   = New-Label "" 30 44 480 20 10 Regular $C_DIM
$lblUpdateDesc  = New-Label "" 30 68 480 20 10 Regular $C_TEXT

$lblChangelogH  = New-Label "What's new:" 30 92 480 20 10 Bold $C_TEXT

$txtChangelog             = New-Object System.Windows.Forms.RichTextBox
$txtChangelog.Location    = New-Object System.Drawing.Point(30, 114)
$txtChangelog.Size        = New-Object System.Drawing.Size(480, 82)
$txtChangelog.ReadOnly    = $true
$txtChangelog.BackColor   = $C_INPUT
$txtChangelog.ForeColor   = $C_TEXT
$txtChangelog.BorderStyle = "FixedSingle"
$txtChangelog.Font        = New-Object System.Drawing.Font("Segoe UI", 9)

$chkUpdateLicense           = New-Object System.Windows.Forms.CheckBox
$chkUpdateLicense.Text      = "I accept the updated license agreement"
$chkUpdateLicense.Location  = New-Object System.Drawing.Point(30, 200)
$chkUpdateLicense.Size      = New-Object System.Drawing.Size(480, 24)
$chkUpdateLicense.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$chkUpdateLicense.ForeColor = $C_TEXT
$chkUpdateLicense.BackColor = $C_BG
$chkUpdateLicense.Visible   = $false
$chkUpdateLicense.Add_CheckedChanged({ $btnApplyUpdate.Enabled = $chkUpdateLicense.Checked })

$btnApplyUpdate = New-ActionButton "Update" 30 230 100 28
$btnApplyUpdate.NormalColor = $C_SUCCESS
$btnApplyUpdate.HoverColor  = [System.Drawing.Color]::FromArgb(90, 210, 110)
$btnApplyUpdate.PressColor  = [System.Drawing.Color]::FromArgb(40, 150, 60)

$btnSkipUpdate  = New-ActionButton "Skip" 140 230 80 28
$btnUpdateClose = New-ActionButton "Close" 420 230 90 28

function Show-UpdatePage {
    $chain   = $script:patchChain
    $final   = $chain[$chain.Count - 1]
    $count   = $chain.Count

    $lblUpdateTitle.Text      = "Update Available"
    $lblUpdateTitle.ForeColor = $C_ACCENT
    $lblUpdateVer.Text = "v$($script:existingVersion) -> v$($final.version)  ($count $(if ($count -eq 1) {'update'} else {'updates'}))"
    $lblUpdateDesc.Text  = if ($final.description) { $final.description } else { "" }
    $lblUpdateDesc.ForeColor = $C_TEXT

    # Build combined changelog grouped by version
    $log = @()
    foreach ($p in $chain) {
        $log += "v$($p.version)  ($($p.date))"
        if ($p.changelog) {
            foreach ($c in $p.changelog) { $log += "  - $c" }
        }
        $log += ""
    }
    $txtChangelog.Text = ($log -join "`r`n").TrimEnd()

    # License: required if ANY patch in chain requires it
    $needsLicense = $chain | Where-Object { $_.requiresLicense } | Select-Object -First 1
    if ($needsLicense) {
        $chkUpdateLicense.Visible = $true
        $chkUpdateLicense.Checked = $false
        $btnApplyUpdate.Enabled   = $false
        $txtChangelog.Size    = New-Object System.Drawing.Size(480, 56)
        $lblChangelogH.Text  = "What's new:  (includes updated license)"
    } else {
        $chkUpdateLicense.Visible = $false
        $btnApplyUpdate.Enabled   = $true
        $txtChangelog.Size    = New-Object System.Drawing.Size(480, 82)
        $lblChangelogH.Text  = "What's new:"
    }

    $btnApplyUpdate.Visible = $true
    $btnSkipUpdate.Visible  = $true
    $btnUpdateClose.Visible = $false
    $pgReinstall.Visible    = $false
    $pgUpdate.Visible       = $true
    $lblSubtitle.Text       = "Update"
    $form.ClientSize        = New-Object System.Drawing.Size(540, 370)
}

$btnApplyUpdate.Add_Click({
    if (Test-ComputerRunning) {
        $choice = Show-Dialog "$APP_NAME is Running" "$APP_NAME is currently running in the background.`nPlease close it before updating." @("Close $APP_NAME", "Cancel")
        if ($choice -eq "Close $APP_NAME") {
            Stop-ComputerProcess
            Start-Sleep -Milliseconds 800
            if (Test-ComputerRunning) {
                Show-Dialog "Could Not Close $APP_NAME" "$APP_NAME is still running. Please close it manually and try again." @("OK")
                return
            }
        } else { return }
    }
    $chain = $script:patchChain
    $dir   = $script:existingInstallDir
    $final = $chain[$chain.Count - 1]
    Write-Log "Update: applying $($chain.Count) patch(es) -> v$($final.version)  dir: $dir"
    $btnApplyUpdate.Enabled  = $false
    $btnSkipUpdate.Visible   = $false
    $chkUpdateLicense.Visible = $false
    [System.Windows.Forms.Application]::DoEvents()

    $ok        = $true
    $lastApplied = $null
    $regPath   = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$APP_NAME"
    $wc        = New-Object System.Net.WebClient
    try {
        for ($pi = 0; $pi -lt $chain.Count; $pi++) {
            $patch = $chain[$pi]
            Write-Log "Update: patch $($pi+1)/$($chain.Count) - v$($patch.version)"
            $lblUpdateDesc.Text      = "Applying v$($patch.version)... ($($pi+1)/$($chain.Count))"
            $lblUpdateDesc.ForeColor = $C_DIM
            [System.Windows.Forms.Application]::DoEvents()

            if ($patch.actions) {
                foreach ($act in $patch.actions) {
                    $target = Join-Path $dir $act.path
                    Write-Log "  action: $($act.type) -> $($act.path)"
                    switch ($act.type) {
                        'write' {
                            $parent = Split-Path $target -Parent
                            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
                            $url = "$UPDATE_URL/patches/$($patch.version)/$($act.source)"
                            Write-Log "  downloading: $url"
                            $wc.DownloadFile($url, $target)
                        }
                        'delete' {
                            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
                        }
                        'mkdir' {
                            if (-not (Test-Path $target)) { New-Item -ItemType Directory -Force -Path $target | Out-Null }
                        }
                        'rmdir' {
                            if (Test-Path $target) { Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue }
                        }
                        'run' {
                            # 'run' executes a shell command from the patch manifest.
                            # Intended for post-patch migration steps (e.g. database
                            # schema upgrades, one-time data conversions).
                            # The user must explicitly approve each command before it runs.
                            $wd = if ($act.workdir -eq '.') { $dir } else { Join-Path $dir $act.workdir }
                            $label = if ($act.label) { $act.label } else { $act.command }
                            $choice = Show-Dialog "Run Update Step" (
                                "Patch v$($patch.version) wants to run a command:`n`n" +
                                "  $label`n`n" +
                                "Working directory: $wd`n`n" +
                                "Allow this step?") @("Allow", "Skip", "Cancel")
                            if ($choice -eq "Cancel") { throw "Update cancelled by user at 'run' step: $($act.command)" }
                            if ($choice -eq "Allow") {
                                Write-Log "  run (approved): $($act.command)  (workdir: $wd)"
                                Start-Process cmd.exe -ArgumentList "/c $($act.command)" -WorkingDirectory $wd -Wait -WindowStyle Hidden
                            } else {
                                Write-Log "  run (skipped by user): $($act.command)"
                            }
                        }
                    }
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }
            # Update license if this patch requires it
            if ($patch.requiresLicense -and $patch.newLicense) {
                Write-Log "  updating LICENSE"
                $licPath = Join-Path $dir "LICENSE"
                [System.IO.File]::WriteAllText($licPath, $patch.newLicense, (New-Object System.Text.UTF8Encoding($false)))
            }
            # Update registry after each patch so partial progress is saved
            Write-Log "  registry: $APP_NAME v$($patch.version)"
            Set-ItemProperty -Path $regPath -Name "DisplayVersion" -Value $patch.version -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $regPath -Name "DisplayName" -Value $APP_NAME -ErrorAction SilentlyContinue
            $lastApplied = $patch.version
        }
    } catch {
        $ok = $false
        $script:_updateError = $_.ToString()
        Write-Log "Update exception: $script:_updateError" "ERROR"
    }

    if ($ok) {
        Write-Log "Update complete: v$($final.version)"
        $lblUpdateTitle.Text      = "Update Complete"
        $lblUpdateTitle.ForeColor = $C_SUCCESS
        $lblUpdateDesc.Text       = "$APP_NAME has been updated to v$($final.version)"
        $lblUpdateDesc.ForeColor  = $C_TEXT
        $script:existingVersion   = $final.version
    } else {
        Write-Log "Update failed: $script:_updateError" "ERROR"
        $lblUpdateTitle.Text      = "Update Failed"
        $lblUpdateTitle.ForeColor = $C_DANGER
        $partial = if ($lastApplied) { "Partially applied up to v$lastApplied." } else { "No changes were applied." }
        $lblUpdateDesc.Text       = $partial
        $lblUpdateDesc.ForeColor  = $C_DANGER
        $txtChangelog.Text        = $script:_updateError
        $txtChangelog.ForeColor   = $C_DANGER
        $lblChangelogH.Text       = "Error details:"
        if ($lastApplied) { $script:existingVersion = $lastApplied }
    }
    $btnApplyUpdate.Visible = $false
    $btnUpdateClose.Visible = $true
})

$btnSkipUpdate.Add_Click({
    Write-Log "Update skipped by user"
    $pgUpdate.Visible    = $false
    $pgReinstall.Visible = $true
    $pnlReinstComputerRunning.Visible = Test-ComputerRunning
    $lblSubtitle.Text    = "Maintenance"
    $form.ClientSize     = New-Object System.Drawing.Size(540, 320)
    $lblUpdateStatus.Text      = "Update skipped"
    $lblUpdateStatus.ForeColor = $C_DIM
    if ($script:_recheckTimer) { $script:_recheckTimer.Stop() }
    $btnRecheck.Text = "Recheck"
})

$btnUpdateClose.Add_Click({
    $script:skipCloseConfirm = $true
    $form.Close()
})

$pgUpdate.Controls.AddRange(@(
    $lblUpdateTitle, $lblUpdateVer, $lblUpdateDesc, $lblChangelogH,
    $txtChangelog, $chkUpdateLicense,
    $btnApplyUpdate, $btnSkipUpdate, $btnUpdateClose
))
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Page list ------------
$allPages  = @($pgWelcome, $pgLicense, $pgLegal, $pgDeps, $pgLocation, $pgConfirm, $pgInstall, $pgDone)
$pageNames = @("Welcome", "License Agreement", "Legal Notices", "Requirements", "Install Location", "Ready to Install", "Installing...", "Installation Complete")
$script:idx = 0
$script:skipCloseConfirm = $false
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Install helpers ------

function Test-ComputerRunning {
    # IPGlobalProperties is pure .NET - no module load, runs in <5ms
    try {
        $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        return [bool]($listeners | Where-Object { $_.Port -eq 53420 })
    } catch { return $false }
}

$script:_safeProcNames = @('explorer','svchost','services','lsass','winlogon','csrss','smss','wininit','System','wscript','powershell','pwsh')

function Stop-ComputerProcess {
    # Collect all unique PIDs that own any TCP connection on port 53420
    $pids = @(Get-NetTCPConnection -LocalPort 53420 -ErrorAction SilentlyContinue |
              Select-Object -ExpandProperty OwningProcess -Unique)
    if ($pids.Count -eq 0) { return }
    foreach ($pid1 in $pids) {
        $wmi = Get-CimInstance Win32_Process -Filter "ProcessId=$pid1" -ErrorAction SilentlyContinue
        # Kill the node/python process holding the port
        Stop-Process -Id $pid1 -Force -ErrorAction SilentlyContinue
        Write-Log "Stop-ComputerProcess: killed PID $pid1 ($($wmi.Name))"
        # Kill its parent (the cmd.exe hosting __APP_NAME__.cmd) if it is safe to do so
        if ($wmi -and $wmi.ParentProcessId -gt 0) {
            $parentProc = Get-Process -Id $wmi.ParentProcessId -ErrorAction SilentlyContinue
            if ($parentProc -and $parentProc.ProcessName -notin $script:_safeProcNames) {
                Stop-Process -Id $wmi.ParentProcessId -Force -ErrorAction SilentlyContinue
                Write-Log "Stop-ComputerProcess: killed parent PID $($wmi.ParentProcessId) ($($parentProc.ProcessName))"
            }
        }
    }
}
function Clear-InstallAttributes {
    param([string]$Path)
    Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {} }
    $dirItem = Get-Item $Path -Force -ErrorAction SilentlyContinue
    if ($dirItem) { $dirItem.Attributes = [System.IO.FileAttributes]::Normal }
}

function Remove-ExistingInstall {
    param([string]$Path)
    Write-Log "Remove-ExistingInstall: $Path"

    # Move Win32 CWD away so this process doesn't hold a handle on $Path
    try { [System.IO.Directory]::SetCurrentDirectory($env:TEMP) } catch {}

    # - 1. Registry and shortcut cleanup first ------
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$APP_NAME_LOW\ShellNew" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$APP_NAME_LOW"          -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\$APP_NAME.File"          -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\$APP_NAME_LOW"           -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$APP_NAME" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $APP_NAME -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$APP_NAME.lnk" -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "HKCU:\SOFTWARE\Classes\*\shell\$APP_NAME"                    -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\shell\$APP_NAME"            -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\Background\shell\$APP_NAME" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\SendTo\$APP_NAME.lnk"                      -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$APP_NAME.lnk"         -Force -ErrorAction SilentlyContinue
    $curPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = ($curPath -split ";" | Where-Object { $_ -ne "$Path\data" -and $_ -ne $Path }) -join ";"
    if ($newPath -ne $curPath) { [Environment]::SetEnvironmentVariable("Path", $newPath, "User") }
    $sc = "$env:USERPROFILE\Desktop\$APP_NAME.lnk"
    if (Test-Path $sc) { Remove-Item $sc -Force -ErrorAction SilentlyContinue }
    $uninstLink  = Join-Path $Path "Uninstall.lnk"
    if (Test-Path $uninstLink)  { Remove-Item $uninstLink  -Force -ErrorAction SilentlyContinue }
    $repairLink  = Join-Path $Path "Repair.lnk"
    if (Test-Path $repairLink)  { Remove-Item $repairLink  -Force -ErrorAction SilentlyContinue }
    $updLink     = Join-Path $Path "Check for Updates.lnk"
    if (Test-Path $updLink)     { Remove-Item $updLink     -Force -ErrorAction SilentlyContinue }

    # - 2. Flush Explorer shell cache AFTER registry keys are gone ------------
    #    This makes Explorer release icon handles for .computer files and the folder
    if (-not ([System.Management.Automation.PSTypeName]'ShellNotify').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ShellNotify {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
"@
    }
    [ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800

    # - 3. Clear file attributes then delete --------
    $desktopIni = Join-Path $Path "desktop.ini"
    if (Test-Path $desktopIni -ErrorAction SilentlyContinue) {
        try { (Get-Item $desktopIni -Force).Attributes = [System.IO.FileAttributes]::Normal } catch {}
        Remove-Item $desktopIni -Force -ErrorAction SilentlyContinue
    }
    Clear-InstallAttributes $Path
    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $Path) {
        Start-Sleep -Milliseconds 500
        try { [System.IO.Directory]::Delete($Path, $true) } catch {}
    }
    if (Test-Path $Path) {
        Start-Sleep -Milliseconds 500
        Start-Process cmd.exe -WorkingDirectory $env:TEMP -ArgumentList "/c rd /s /q `"$Path`"" -Wait -WindowStyle Hidden
    }
}
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Installation ---------
# This function performs all install steps sequentially.  Every step that
# touches the registry, file system, or shell integration is explained inline.
# All registry writes go to HKCU (current user) - no admin rights required.
# All optional features (startup, PATH, right-click, etc.) are gated behind
# checkboxes the user sees and controls on the Confirm page (04-confirm.ps1).
function Start-Installation {
    $dir    = $txtDir.Text.TrimEnd('.')
    $data   = "$dir\data"
    $lib    = "$data\lib"
    $assets = "$data\assets"
    $logs   = "$data\logs"

    if (Test-Path $dir) { Clear-InstallAttributes $dir }

    # Pre-compile the shell-notify type so Add-Type doesn't stall mid-install.
    # SHChangeNotify (shell32.dll) is the documented Windows API for telling
    # Explorer that file type or icon associations have changed.  Without it
    # the user must log off and back on before new icons/context menus appear.
    if (-not ([System.Management.Automation.PSTypeName]'ShellNotify').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ShellNotify {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
"@
    }

    $steps = @(
        @{ Pct =  7; Msg = "Creating directories...";
           Action = {
               New-Item -ItemType Directory -Force -Path $dir    | Out-Null
               New-Item -ItemType Directory -Force -Path $data   | Out-Null
               New-Item -ItemType Directory -Force -Path $lib    | Out-Null
               New-Item -ItemType Directory -Force -Path $assets | Out-Null
               New-Item -ItemType Directory -Force -Path $logs   | Out-Null
           }},

        @{ Pct = 15; Msg = "Copying icon...";
           Action = {
               if (Test-Path $script:iconTemp) {
                   Copy-Item $script:iconTemp "$assets\$APP_NAME_LOW.ico" -Force
               }
           }},

        @{ Pct = 20; Msg = "Saving installer...";
           Action = {
               # A copy of install.ps1 is saved to the install directory so the
               # Repair and Check-for-Updates shortcuts can re-run the installer
               # without requiring the user to re-download it.  This is the same
               # practice used by traditional Windows installers (e.g. setup.exe
               # saved to %ProgramFiles%\AppName\).
               if ($script:_selfPath -and (Test-Path $script:_selfPath)) {
                   Write-Log "Installer: copying from file $script:_selfPath"
                   Copy-Item $script:_selfPath "$lib\install.ps1" -Force
               } elseif ($script:_selfScript) {
                   Write-Log "Installer: writing from memory (iex mode)"
                   Set-Content "$lib\install.ps1" $script:_selfScript -Encoding UTF8
               } else {
                   Write-Log "Installer: skipped (source unavailable)" "WARN"
               }
           }},

        @{ Pct = 42; Msg = "Writing files...";
           Action = {
               # $FILE_MANIFEST is populated at build time by {{EMBED_DIR:app/}} -
               # every file under app/ is embedded as a here-string variable and
               # extracted here.  .vbs and .cmd files are written as ASCII because
               # WScript / cmd.exe do not handle UTF-8 BOM gracefully.
               # Placeholders __APP_NAME__, __APP_VERSION__, __UPDATE_URL__ are
               # substituted so embedded scripts know which app they belong to.
               foreach ($entry in $FILE_MANIFEST.GetEnumerator()) {
                   $relDest  = $entry.Key -replace '__APP_NAME__', $APP_NAME
                   $destPath = Join-Path $dir ($relDest.Replace('/', '\'))
                   $destDir  = Split-Path $destPath -Parent
                   if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
                   $content  = $entry.Value `
                       -replace '__APP_NAME__',    $APP_NAME `
                       -replace '__APP_VERSION__', $APP_VERSION `
                       -replace '__UPDATE_URL__',  $UPDATE_URL
                   $ext = [System.IO.Path]::GetExtension($destPath).ToLower()
                   if ($ext -in @('.vbs', '.cmd', '.bat')) {
                       Write-File $destPath $content -Ascii
                   } else {
                       Write-File $destPath $content
                   }
               }
           }},

        @{ Pct = 58; Msg = "Creating shortcuts...";
           Action = {
               $wsh = New-Object -ComObject WScript.Shell

               # Main launcher
               $lnk = $wsh.CreateShortcut("$dir\$APP_NAME.lnk")
               $lnk.TargetPath       = "$data\$APP_NAME.cmd"
               $lnk.Arguments        = ""
               $lnk.WorkingDirectory = $data
               $lnk.IconLocation     = "$assets\$APP_NAME_LOW.ico,0"
               $lnk.Description      = "Launch $APP_NAME"
               $lnk.Save()

               # Check for Updates shortcut
               $upd = $wsh.CreateShortcut("$dir\Check for Updates.lnk")
               $upd.TargetPath       = "wscript.exe"
               $upd.Arguments        = "`"$lib\check-update.vbs`""
               $upd.WorkingDirectory = $lib
               $upd.IconLocation     = "$env:SystemRoot\system32\shell32.dll,238"
               $upd.Description      = "Check for $APP_NAME updates"
               $upd.Save()

               # Repair shortcut
               $repair = $wsh.CreateShortcut("$dir\Repair.lnk")
               $repair.TargetPath       = "wscript.exe"
               $repair.Arguments        = "`"$lib\repair.vbs`""
               $repair.WorkingDirectory = $env:TEMP
               $repair.Description      = "Repair or reinstall $APP_NAME"
               $repair.IconLocation     = "$env:SystemRoot\system32\imageres.dll,109"
               $repair.Save()

               # Uninstall shortcut
               $uninst = $wsh.CreateShortcut("$dir\Uninstall.lnk")
               $uninst.TargetPath        = "wscript.exe"
               $uninst.Arguments         = "`"$lib\uninstall.vbs`""
               $uninst.WorkingDirectory  = $env:TEMP
               $uninst.WindowStyle       = 7
               $uninst.Description       = "Uninstall $APP_NAME"
               $uninst.IconLocation      = "shell32.dll,32"
               $uninst.Save()
           }},


        @{ Pct = 79; Msg = "Setting folder icon...";
           Action = {
               if (Test-Path "$assets\$APP_NAME_LOW.ico") {
                   Clear-InstallAttributes $dir
                   $ini = "[.ShellClassInfo]`r`nIconResource=$assets\$APP_NAME_LOW.ico,0`r`n[ViewState]`r`nMode=`r`nVid=`r`nFolderType=Generic`r`n"
                   Write-File "$dir\desktop.ini" $ini -Ascii
                   $f = Get-Item $dir
                   $f.Attributes = $f.Attributes -bor [System.IO.FileAttributes]::ReadOnly
                   $i = Get-Item "$dir\desktop.ini" -Force
                   $i.Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
               }
           }},

        @{ Pct = 87; Msg = "Registering $($APP_PROTO):// protocol...";
           Action = {
               # URI scheme registration (e.g. computer://) lets links in browsers
               # and scripts open COMPUTER directly.  Written to HKCU\SOFTWARE\Classes
               # (current-user scope, no admin required).  Only registered when the
               # user checks "App protocol" on the Confirm page.
               if ($chkProto.Checked) {
                   $protoKey = "HKCU:\SOFTWARE\Classes\$APP_PROTO"
                   New-Item -Path $protoKey -Value "URL:$APP_NAME Protocol" -Force | Out-Null
                   New-ItemProperty -Path $protoKey -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null
                   # Friendly name shown in protocol confirmation dialogs (when respected by the browser)
                   New-Item -Path "$protoKey\Application" -Force | Out-Null
                   New-ItemProperty -Path "$protoKey\Application" -Name "ApplicationName" -Value $APP_NAME -PropertyType String -Force | Out-Null
                   New-ItemProperty -Path "$protoKey\Application" -Name "ApplicationDescription" -Value "$APP_NAME Protocol Handler" -PropertyType String -Force | Out-Null
                   $cmd = "wscript.exe `"$lib\router.vbs`" `"%1`""
                   New-Item -Path "$protoKey\shell\open\command" -Value $cmd -Force | Out-Null
               } else {
                   Write-Log "Protocol: skipping ($($APP_PROTO)://)"
               }
           }},

        @{ Pct = 94; Msg = "Registering uninstaller...";
           Action = {
               # Adds COMPUTER to Add/Remove Programs (HKCU uninstall key).
               # Uses HKCU so no admin rights are needed.  The UninstallString
               # points to uninstall.vbs in the install directory - a plain-text
               # script the user can read and audit at any time.
               $key = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$APP_NAME"
               New-Item -Path $key -Force | Out-Null
               $props = @{
                   DisplayName     = $APP_NAME
                   DisplayVersion  = $APP_VERSION
                   Publisher       = $PUBLISHER
                   InstallLocation = $dir
                   UninstallString = "wscript.exe `"$lib\uninstall.vbs`""
               }
               foreach ($p in $props.GetEnumerator()) {
                   New-ItemProperty -Path $key -Name $p.Key -Value $p.Value -PropertyType String -Force | Out-Null
               }
               if (Test-Path "$assets\$APP_NAME_LOW.ico") {
                   New-ItemProperty -Path $key -Name "DisplayIcon" -Value "$assets\$APP_NAME_LOW.ico" -PropertyType String -Force | Out-Null
               }
               New-ItemProperty -Path $key -Name "NoModify" -Value 1 -PropertyType DWord -Force | Out-Null
               New-ItemProperty -Path $key -Name "NoRepair" -Value 1 -PropertyType DWord -Force | Out-Null
           }},

        @{ Pct = 88; Msg = "Applying optional features (1/7): Run on startup...";
           Action = {
               # Startup shortcut - only created when $chkStartup.Checked is true
               # (user explicitly opted in on the Confirm page).  Uses the standard
               # Startup folder (%APPDATA%\...\Startup), not the Run registry key,
               # so it is visible and removable via Task Manager > Startup tab.
               $startupLnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$APP_NAME.lnk"
               Remove-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $APP_NAME -ErrorAction SilentlyContinue
               if ($chkStartup.Checked) {
                   Write-Log "Startup: creating $startupLnk"
                   $wsh = New-Object -ComObject WScript.Shell
                   $lnk = $wsh.CreateShortcut($startupLnk)
                   $lnk.TargetPath       = "$data\$APP_NAME.cmd"
                   $lnk.Arguments        = ""
                   $lnk.WorkingDirectory = $data
                   $lnk.IconLocation     = "$assets\$APP_NAME_LOW.ico,0"
                   $lnk.Description      = "Start $APP_NAME on login"
                   $lnk.Save()
               } else {
                   Write-Log "Startup: removing"
                   Remove-Item $startupLnk -Force -ErrorAction SilentlyContinue
               }
           }},

        @{ Pct = 89; Msg = "Applying optional features (2/7): Add to PATH...";
           Action = {
               $curPath = [Environment]::GetEnvironmentVariable("Path", "User")
               if ($chkAddPath.Checked) {
                   if ($curPath -notlike "*$data*") {
                       Write-Log "Path: adding $data"
                       [Environment]::SetEnvironmentVariable("Path", "$curPath;$data", "User")
                   } else {
                       Write-Log "Path: already present"
                   }
               } else {
                   Write-Log "Path: removing $data"
                   $newPath = ($curPath -split ";" | Where-Object { $_ -ne $data }) -join ";"
                   [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
               }
           }},

        @{ Pct = 91; Msg = "Applying optional features (3/7): Right-click menu...";
           Action = {
               $ico    = "$assets\$APP_NAME_LOW.ico"
               $cmd    = "wscript.exe `"$lib\router.vbs`" `"$($APP_PROTO)://open?path=%1`""
               $cmdDir = "wscript.exe `"$lib\router.vbs`" `"$($APP_PROTO)://open?path=%V`""
               if ($chkOpenWith.Checked) {
                   Write-Log "Right-click menu: registering"
                   $hkcu = [Microsoft.Win32.Registry]::CurrentUser
                   foreach ($base in @("SOFTWARE\Classes\*\shell\$APP_NAME", "SOFTWARE\Classes\Directory\shell\$APP_NAME", "SOFTWARE\Classes\Directory\Background\shell\$APP_NAME")) {
                       $k = $hkcu.CreateSubKey($base)
                       $k.SetValue("", "Open with $APP_NAME")
                       $k.SetValue("Icon", $ico)
                       $k.Close()
                       $ck = $hkcu.CreateSubKey("$base\command")
                       $ck.SetValue("", $(if ($base -like "*Background*") { $cmdDir } else { $cmd }))
                       $ck.Close()
                   }
               } else {
                   Write-Log "Right-click menu: removing"
                   Remove-Item -LiteralPath "HKCU:\SOFTWARE\Classes\*\shell\$APP_NAME"                    -Recurse -Force -ErrorAction SilentlyContinue
                   Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\shell\$APP_NAME"            -Recurse -Force -ErrorAction SilentlyContinue
                   Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\Background\shell\$APP_NAME" -Recurse -Force -ErrorAction SilentlyContinue
               }
           }},

        @{ Pct = 92; Msg = "Applying optional features (4/7): Send To...";
           Action = {
               $sendToLnk = "$env:APPDATA\Microsoft\Windows\SendTo\$APP_NAME.lnk"
               if ($chkSendTo.Checked) {
                   Write-Log "Send To: creating $sendToLnk"
                   $wsh = New-Object -ComObject WScript.Shell
                   $lnk = $wsh.CreateShortcut($sendToLnk)
                   $lnk.TargetPath   = "wscript.exe"
                   $lnk.Arguments    = "`"$lib\sendto.vbs`""
                   $lnk.Description  = "Open with $APP_NAME"
                   $lnk.IconLocation = "$assets\$APP_NAME_LOW.ico,0"
                   $lnk.Save()
               } else {
                   Write-Log "Send To: removing"
                   Remove-Item $sendToLnk -Force -ErrorAction SilentlyContinue
               }
           }},

        @{ Pct = 93; Msg = "Applying optional features (5/7): Start Menu...";
           Action = {
               $startMenuLnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$APP_NAME.lnk"
               if ($chkStartMenu.Checked) {
                   Write-Log "Start Menu: creating $startMenuLnk"
                   $wsh = New-Object -ComObject WScript.Shell
                   $lnk = $wsh.CreateShortcut($startMenuLnk)
                   $lnk.TargetPath       = "$data\$APP_NAME.cmd"
                   $lnk.Arguments        = ""
                   $lnk.WorkingDirectory = $data
                   $lnk.IconLocation     = "$assets\$APP_NAME_LOW.ico,0"
                   $lnk.Save()
               } else {
                   Write-Log "Start Menu: removing"
                   Remove-Item $startMenuLnk -Force -ErrorAction SilentlyContinue
               }
           }},

        @{ Pct = 94; Msg = "Applying optional features (6/7): File association...";
           Action = {
               if ($chkFileAssoc.Checked) {
                   Write-Log "File assoc: registering .$APP_NAME_LOW"
                   $hkcu = [Microsoft.Win32.Registry]::CurrentUser
                   $k = $hkcu.CreateSubKey("SOFTWARE\Classes\.$APP_NAME_LOW")
                   $k.SetValue("", "$APP_NAME.File"); $k.Close()
                   $k = $hkcu.CreateSubKey("SOFTWARE\Classes\$APP_NAME.File")
                   $k.SetValue("", "$APP_NAME File"); $k.Close()
                   $k = $hkcu.CreateSubKey("SOFTWARE\Classes\$APP_NAME.File\DefaultIcon")
                   $k.SetValue("", "$assets\$APP_NAME_LOW.ico,0"); $k.Close()
                   $k = $hkcu.CreateSubKey("SOFTWARE\Classes\$APP_NAME.File\shell\open\command")
                   $k.SetValue("", "wscript.exe `"$lib\router.vbs`" `"$($APP_PROTO)://open?path=%1`""); $k.Close()
               } else {
                   Write-Log "File assoc: removing .$APP_NAME_LOW"
                   Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$APP_NAME_LOW" -Recurse -Force -ErrorAction SilentlyContinue
                   Remove-Item -Path "HKCU:\SOFTWARE\Classes\$APP_NAME.File" -Recurse -Force -ErrorAction SilentlyContinue
               }
           }},

        @{ Pct = 95; Msg = "Applying optional features (7/7): New menu...";
           Action = {
               if ($chkNewMenu.Checked) {
                   Write-Log "New menu: registering .$APP_NAME_LOW ShellNew"
                   $hkcu = [Microsoft.Win32.Registry]::CurrentUser
                   $k = $hkcu.CreateSubKey("SOFTWARE\Classes\.$APP_NAME_LOW")
                   $k.SetValue("", "$APP_NAME.File"); $k.Close()
                   $k = $hkcu.CreateSubKey("SOFTWARE\Classes\.$APP_NAME_LOW\ShellNew")
                   $k.SetValue("NullFile", ""); $k.Close()
               } else {
                   Write-Log "New menu: removing .$APP_NAME_LOW ShellNew"
                   Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$APP_NAME_LOW\ShellNew" -Recurse -Force -ErrorAction SilentlyContinue
               }
           }},

        @{ Pct = 96; Msg = "Refreshing shell...";
           Action = {
               # SHCNE_ASSOCCHANGED (0x08000000) tells Explorer to refresh its
               # file-type icon and context-menu cache.  This is the documented,
               # recommended way to apply file-association changes without a reboot.
               [ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
               Write-Log "Shell cache flushed (SHChangeNotify)"
           }},

        @{ Pct = 97; Msg = "Creating shortcut...";
           Action = {
               if ($chkShortcut.Checked) {
                   Write-Log "Desktop shortcut: creating"
                   $shell = New-Object -ComObject WScript.Shell
                   $sc    = $shell.CreateShortcut("$env:USERPROFILE\Desktop\$APP_NAME.lnk")
                   $sc.TargetPath       = "$data\$APP_NAME.cmd"
                   $sc.Arguments        = ""
                   $sc.WorkingDirectory = $data
                   $sc.IconLocation     = "$assets\$APP_NAME_LOW.ico,0"
                   $sc.Save()
               } else {
                   Write-Log "Desktop shortcut: skipped (unchecked)"
               }
           }},

        @{ Pct = 100; Msg = "Done!"; Action = {
               $dest = "$logs\install.log"
               Move-Item $script:_logPath $dest -Force -ErrorAction SilentlyContinue
               $script:_logPath = $dest
           }}
    )

    Write-Log "Installation started - dir: $dir"
    Write-Log ("Features: shortcut={0} startup={1} path={2} context-menu={3} send-to={4} start-menu={5} file-assoc={6} new-menu={7}" -f
        $chkShortcut.Checked, $chkStartup.Checked, $chkAddPath.Checked,
        $chkOpenWith.Checked, $chkSendTo.Checked, $chkStartMenu.Checked, $chkFileAssoc.Checked, $chkNewMenu.Checked)
    foreach ($step in $steps) {
        $lblStep.Text      = $step.Msg
        $progressBar.Value = $step.Pct
        Write-Log ("[{0}pct] {1}" -f $step.Pct, $step.Msg)
        [System.Windows.Forms.Application]::DoEvents()
        try {
            & $step.Action
            Write-Log ("[{0}pct] OK" -f $step.Pct)
        } catch {
            Write-Log ("[{0}pct] FAILED: {1}" -f $step.Pct, $_) "ERROR"
            Show-Dialog "$APP_NAME Setup" "An error occurred:`n$_" @("OK")
            $script:idx        = 5   # leave install page visible but unblock FormClosing
            $btnBack.Enabled   = $true
            $btnCancel.Enabled = $true
            $btnNext.Enabled   = $false
            return
        }
        Start-Sleep -Milliseconds 280
        [System.Windows.Forms.Application]::DoEvents()
    }
    Write-Log "Installation complete"

    Show-Page 7
}
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Navigation -----------
function Show-Page([int]$n) {
    if ($script:_depTimer) { $script:_depTimer.Stop() }  # cancel any pending dep check
    Write-Log "Show-Page $n ($($pageNames[$n]))"
    $script:idx = $n
    foreach ($pg in $allPages) { $pg.Visible = $false }
    $allPages[$n].Visible = $true
    $lblSubtitle.Text = $pageNames[$n]

    $btnBack.Enabled   = $true
    $btnNext.Enabled   = $true
    $btnCancel.Enabled = $true
    $btnCancel.Visible = $true
    $btnNext.Text      = "Next >"
    $btnNext.NormalColor = $C_PRIMARY
    $btnNext.HoverColor  = [System.Drawing.Color]::FromArgb(56, 139, 253)
    $btnNext.PressColor  = [System.Drawing.Color]::FromArgb(17, 88, 199)

    switch ($n) {
        0 { $btnBack.Enabled = ($null -ne $script:existingInstallDir) }
        1 { $btnNext.Enabled = $chkLicense.Checked }
        2 { $btnNext.Enabled = $chkAge.Checked -and $chkLegal.Checked }
        3 { Start-DepCheck }
        5 {
            $btnNext.Text     = "Install"
            $lblConfDirV.Text = $txtDir.Text
            $lblConfScV.Text  = if ($chkShortcut.Checked) { "Yes" } else { "No" }
            $pnlComputerRunning.Visible = $false
            # Defer the port check so the page paints before we query the network stack
            if ($script:_computerCheckTimer) { $script:_computerCheckTimer.Stop() }
            $script:_computerCheckTimer = New-Object System.Windows.Forms.Timer
            $script:_computerCheckTimer.Interval = 80
            $script:_computerCheckTimer.Add_Tick({
                $script:_computerCheckTimer.Stop()
                $pnlComputerRunning.Visible = Test-ComputerRunning
            })
            $script:_computerCheckTimer.Start()
            # Fresh install: all checked by default; repair: reflect current registered state
            if ($script:existingInstallDir) {
                $chkStartup.Checked   = Test-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$APP_NAME.lnk"
                $curPath = [Environment]::GetEnvironmentVariable("Path", "User")
                $chkAddPath.Checked   = $curPath -like "*$($txtDir.Text)\data*"
                $chkOpenWith.Checked  = (Test-Path -LiteralPath "HKCU:\SOFTWARE\Classes\*\shell\$APP_NAME" -ErrorAction SilentlyContinue) -or
                                        (Test-Path "HKCU:\SOFTWARE\Classes\Directory\shell\$APP_NAME" -ErrorAction SilentlyContinue)
                $chkSendTo.Checked    = Test-Path "$env:APPDATA\Microsoft\Windows\SendTo\$APP_NAME.lnk"
                $chkStartMenu.Checked = Test-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$APP_NAME.lnk"
                $chkFileAssoc.Checked = Test-Path "HKCU:\SOFTWARE\Classes\$APP_NAME.File"
                $chkNewMenu.Checked   = Test-Path "HKCU:\SOFTWARE\Classes\.$APP_NAME_LOW\ShellNew"
                $chkNewMenu.Enabled   = $chkFileAssoc.Checked
            } else {
                $chkStartup.Checked   = $true
                $chkAddPath.Checked   = $true
                $chkOpenWith.Checked  = $true
                $chkSendTo.Checked    = $true
                $chkStartMenu.Checked = $true
                $chkFileAssoc.Checked = $true
                $chkNewMenu.Checked   = $true
                $chkNewMenu.Enabled   = $true
            }
        }
        6 {
            if (Test-ComputerRunning) {
                $choice = Show-Dialog "$APP_NAME is Running" "$APP_NAME is currently running in the background.`nPlease close it before installing." @("Close $APP_NAME", "Cancel")
                if ($choice -eq "Close $APP_NAME") {
                    Stop-ComputerProcess
                    Start-Sleep -Milliseconds 800
                    if (Test-ComputerRunning) {
                        Show-Dialog "Could Not Close $APP_NAME" "$APP_NAME is still running. Please close it manually and try again." @("OK")
                        Show-Page 5
                        return
                    }
                    # Successfully closed - fall through to install
                } else {
                    Show-Page 5
                    return
                }
            }
            $btnBack.Enabled   = $false
            $btnNext.Enabled   = $false
            $btnCancel.Enabled = $false
            Start-Installation
        }
        7 {
            $btnBack.Enabled     = $false
            $btnCancel.Text      = "Close"
            $btnNext.Text        = "Finish"
            $btnNext.NormalColor = $C_SUCCESS
            $btnNext.HoverColor  = [System.Drawing.Color]::FromArgb(90, 210, 110)
            $btnNext.PressColor  = [System.Drawing.Color]::FromArgb(40, 150, 60)
            $lblDonePath.Text    = "Installed to: $($txtDir.Text)"
            $footer.Refresh()   # force-repaint so new button text shows immediately
        }
    }
}
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Button handlers ------
$btnNext.Add_Click({
    if ($script:idx -eq 7) {
        Write-Log "Finish clicked"
        if ($chkLaunch.Checked) {
            Write-Log "Launching $APP_NAME"
            Start-Process "$($txtDir.Text)\$APP_NAME.lnk"
        }
        $form.Close()
    } else {
        Show-Page ($script:idx + 1)
    }
})

$btnBack.Add_Click({
    if ($script:idx -eq 0 -and $script:existingInstallDir) {
        # Came from maintenance page during repair - go back there
        foreach ($pg in $allPages) { $pg.Visible = $false }
        $footer.Visible      = $false
        $pgReinstall.Visible = $true
        $lblSubtitle.Text    = "Maintenance"
        $form.ClientSize     = New-Object System.Drawing.Size(540, 320)
    } else {
        Show-Page ($script:idx - 1)
    }
})

$btnCancel.Add_Click({ $form.Close() })
# Copyright (c) 2026 COMPUTER. Provided "AS IS" without warranty. See LICENSE for full terms.
# --- Run ------------------
$form.Add_Load({
    $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$APP_NAME"
    $props   = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
    if ($props -and $props.InstallLocation -and (Test-Path $props.InstallLocation.TrimEnd('.'))) {
        $script:existingInstallDir = $props.InstallLocation.TrimEnd('.')
        $script:existingVersion    = if ($props.DisplayVersion) { $props.DisplayVersion } else { "0.0.0" }
        Write-Log "Existing install detected: v$($script:existingVersion) at $($props.InstallLocation)"
        $lblReinstPath.Text  = "Installed in: $($props.InstallLocation)  (v$($script:existingVersion))"
        $txtDir.Text         = $props.InstallLocation
        $pgReinstall.Visible = $true
        $footer.Visible      = $false
        $lblSubtitle.Text    = "Maintenance"
        $form.ClientSize     = New-Object System.Drawing.Size(540, 320)
        # Trigger update check after form is fully rendered
        $script:_loadTimer = New-Object System.Windows.Forms.Timer
        $script:_loadTimer.Interval = 100
        $script:_loadTimer.Add_Tick({ $script:_loadTimer.Stop(); $script:_loadTimer.Dispose(); Check-ForUpdate })
        $script:_loadTimer.Start()
    } else {
        Write-Log "Fresh install - no existing registry entry found"
        Show-Page 0
    }
})
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
        [System.Windows.Forms.UnhandledExceptionMode]::CatchException)
} catch {}
[System.Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    Write-Log "Unhandled exception: $($e.Exception)" "ERROR"
    try { Show-Dialog "$APP_NAME Setup" "An error occurred:`n$($e.Exception.Message)" @("OK") } catch {}
})

try {
    [System.Windows.Forms.Application]::Run($form)
} finally {
    try { $script:_mutex.ReleaseMutex() } catch {}
    $script:_mutex.Dispose()
}