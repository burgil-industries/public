$APP_NAME      = "ALI"
$APP_NAME_LOW  = $APP_NAME.ToLower()
$APP_VERSION   = "1.0.0"
$ICON_URL      = "http://localhost:3000/favicon.ico"
$UPDATE_URL    = "http://localhost:3000/updates"
$AD_URL        = "http://localhost:3000/ads/softwisor.com.png"   # URL to a 480x82 banner image - leave empty to show placeholder
$AD_LINK       = "https://softwisor.com/"   # URL opened when the banner is clicked - leave empty to disable
$CONTACT_US    = "https://closed-ali.com/contact"              # shown in the ad placeholder "Contact us" line

$MIN_PYTHON = "3.8"
$MIN_NODE   = "20.0"

# --- Logging - always on, appends per launch, copied to data dir on success ---
$script:_logPath = "$env:TEMP\$($APP_NAME_LOW)_install.log"

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [$Level] $Msg" |
        Add-Content -Path $script:_logPath -Encoding UTF8
}

# Separator between runs
"" | Add-Content -Path $script:_logPath -Encoding UTF8
("=" * 60) | Add-Content -Path $script:_logPath -Encoding UTF8
Write-Log "$APP_NAME $APP_VERSION  launched"

# --- Hide the PowerShell console immediately -------
if (-not ([System.Management.Automation.PSTypeName]'ConsoleUtils.Window').Type) {
    Add-Type -Name Window -Namespace ConsoleUtils -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
"@
}
$null = [ConsoleUtils.Window]::ShowWindow([ConsoleUtils.Window]::GetConsoleWindow(), 0)

# Prevent Ctrl+C from firing a break signal into the WinForms message loop.
# The console is hidden so this has no user-visible effect, but without it a
# Ctrl+C in the launching terminal can interrupt timer callbacks mid-execution
# and crash with "You cannot call a method on a null-valued expression".
try { [Console]::TreatControlCAsInput = $true } catch {}

# --- Single-instance check (named mutex) -----------
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
# --- Icon: download to temp, shown in installer window, copied to install dir -
$script:iconTemp   = "$env:TEMP\$($APP_NAME_LOW)_setup.ico"
$script:iconObject = $null   # System.Drawing.Icon  - for the form title bar (requires real .ico)
$script:iconImage  = $null   # System.Drawing.Image - for PictureBox (accepts PNG, ICO, anything)

if ($ICON_URL) {
    try {
        if (Test-Path $script:iconTemp) { Remove-Item $script:iconTemp -Force -ErrorAction SilentlyContinue }
        (New-Object System.Net.WebClient).DownloadFile($ICON_URL, $script:iconTemp)
        $script:iconImage = [System.Drawing.Image]::FromFile($script:iconTemp)
        try { $script:iconObject = New-Object System.Drawing.Icon($script:iconTemp) } catch { }
    } catch {
        Write-Log "Icon download failed: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "Could not reach the $APP_NAME servers.`n`nPlease check your internet connection and try again later.",
            "$APP_NAME Setup",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        $script:_mutex.Dispose()
        exit
    }
}
# --- Custom controls: DarkButton + GlowProgressBar + DarkMode ----------------
$refs = @(
    [System.Reflection.Assembly]::GetAssembly([System.Windows.Forms.Control]).Location,
    [System.Reflection.Assembly]::GetAssembly([System.Drawing.Graphics]).Location
)
$_csButton = @"
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
pause
'@

$FILE_DATA_LIB_CHECK_UPDATE_PS1 = @'
# Check for Updates
$APP_NAME    = '__APP_NAME__'
$APP_VERSION = '__APP_VERSION__'
$UPDATE_URL  = '__UPDATE_URL__'

Add-Type -AssemblyName System.Windows.Forms
try {
    $wc   = New-Object System.Net.WebClient
    $json = $wc.DownloadString("$UPDATE_URL/latest.json") | ConvertFrom-Json
    $latest    = [System.Version]$json.version
    $installed = [System.Version]$APP_VERSION
    if ($latest -gt $installed) {
        [System.Windows.Forms.MessageBox]::Show(
            "$APP_NAME v$latest is available.`nYou have v$installed.`n`nDownload the update from the $APP_NAME website.",
            "Update Available",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
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
sh.Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "check-update.ps1""", 0, False
'@

$FILE_DATA_LIB_OK_TXT = @'
asdasdasd
'@

$FILE_DATA_LIB_ROUTER_PS1 = @'
param([string]$Uri)

$AppName = '__APP_NAME__'

Add-Type -AssemblyName System.Windows.Forms

try {
    $parsed = [System.Uri]$Uri
    $msg    = "URI    : $Uri`nScheme : $($parsed.Scheme)`nHost   : $($parsed.Host)`nPath   : $($parsed.AbsolutePath)`nQuery  : $($parsed.Query)"
} catch {
    $msg = "Received: $Uri"
}

[System.Windows.Forms.MessageBox]::Show(
    $msg, "$AppName Protocol Handler",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
)
'@

$FILE_DATA_LIB_ROUTER_VBS = @'
Dim scriptDir
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "router.ps1"" """ & WScript.Arguments(0) & """", 0, False
'@

$FILE_DATA_LIB_SENDTO_VBS = @'
If WScript.Arguments.Count > 0 Then
    Dim scriptDir, sh
    scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
    Set sh = CreateObject("WScript.Shell")
    sh.Run "wscript.exe """ & scriptDir & "router.vbs"" ""ali://open?path=" & WScript.Arguments(0) & """", 0, False
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
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tempScript`" `"$InstallDir`""
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

$frm.Controls.AddRange(@($icoLbl, $lbl1, $lbl2, $lbl3, $btnYes, $btnNo))

$btnNo.Add_Click({
    if ($script:uninstallDone -and (Test-Path $InstallDir)) {
        Start-Process cmd.exe -WorkingDirectory $env:TEMP -ArgumentList "/c for /l %i in (1,1,6) do (rd /s /q `"$InstallDir`" >nul 2>&1 & if not exist `"$InstallDir`" exit /b 0 & ping localhost -n 2 >nul)" -WindowStyle Hidden
    }
    $frm.Close()
})
$btnYes.Add_Click({
    $btnYes.Visible = $false; $btnNo.Visible = $false
    $lbl1.Text = "Removing..."
    [System.Windows.Forms.Application]::DoEvents()

    Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$AppNameLow\ShellNew"                  -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$AppNameLow"                           -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\$AppName.File"                          -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\SOFTWARE\Classes\$AppNameLow"                            -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $RegPath                                                         -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $AppName -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$AppName.lnk" -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "HKCU:\SOFTWARE\Classes\*\shell\$AppName"                -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\shell\$AppName"        -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\Background\shell\$AppName" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\SendTo\$AppName.lnk"                  -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$AppName.lnk"     -Force -ErrorAction SilentlyContinue
    $curPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = ($curPath -split ";" | Where-Object { $_ -and $_ -ne $InstallDir -and $_ -ne "$InstallDir\data" }) -join ";"
    if ($newPath -ne $curPath) { [Environment]::SetEnvironmentVariable("Path", $newPath, "User") }
    $sc = "$env:USERPROFILE\Desktop\$AppName.lnk"
    if (Test-Path $sc) { Remove-Item $sc -Force -ErrorAction SilentlyContinue }

    # Flush Explorer's icon/shell cache now that all registry associations are gone
    [UninstShell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800

    # Clear attributes on everything recursively so Remove-Item can delete cleanly
    Get-ChildItem $InstallDir -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {} }
    $dirItem = Get-Item $InstallDir -Force -ErrorAction SilentlyContinue
    if ($dirItem) { $dirItem.Attributes = [System.IO.FileAttributes]::Normal }

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

    $icoLbl.Text      = [char]0x2713
    $icoLbl.ForeColor = $C_SUCCESS
    $icoLbl.BackColor = [System.Drawing.Color]::FromArgb(15, 40, 20)
    $lbl1.Text        = "$AppName uninstalled."
    $lbl1.ForeColor   = $C_SUCCESS
    $lbl2.Text        = "All files and registry entries have been removed."
    $lbl3.Text        = ""
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
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
sh.Run cmd, 0, False
'@

$FILE_DATA_SRC_APP_JS = @'
console.log('Hello World - Node.js component!');
'@

$FILE_DATA_SRC_APP_PY = @'
print('Hello World - Python component!')
'@

$FILE_DATA_SRC_TEST_TXT = @'
hi
'@

$FILE_DATA_SRC_YTO_ASD_ASD = @'
בדיקה
'@

$FILE_DATA_TEST42 = @'
asd42
'@

$FILE_LICENSE_TXT = @'
ALI Source License 1.0
Copyright (c) 2026 ALI

TERMS AND CONDITIONS

1. DEFINITIONS

"Software" means ALI and all associated source code, documentation, and
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

3. RESTRICTIONS

a) You may not use, distribute, or incorporate this Software, in whole or
   in part, to build, market, or operate a Competing Product.

b) You may not redistribute the Software itself (not as a Plugin) without
   prior written permission from the copyright holder.

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

6. PLUGINS

Plugins you create are your own work. This license places no restrictions
on the license you choose for your Plugins, provided the Plugin does not
itself constitute a Competing Product.

7. DISCLAIMER - USE AT YOUR OWN RISK

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

$FILE_TEST_HERE_TXT = @'
csv
'@

$FILE_MANIFEST = [ordered]@{
    'data/__APP_NAME__.cmd' = $FILE_DATA___APP_NAME___CMD
    'data/lib/check-update.ps1' = $FILE_DATA_LIB_CHECK_UPDATE_PS1
    'data/lib/check-update.vbs' = $FILE_DATA_LIB_CHECK_UPDATE_VBS
    'data/lib/ok.txt' = $FILE_DATA_LIB_OK_TXT
    'data/lib/router.ps1' = $FILE_DATA_LIB_ROUTER_PS1
    'data/lib/router.vbs' = $FILE_DATA_LIB_ROUTER_VBS
    'data/lib/sendto.vbs' = $FILE_DATA_LIB_SENDTO_VBS
    'data/lib/startup.vbs' = $FILE_DATA_LIB_STARTUP_VBS
    'data/lib/uninstall.ps1' = $FILE_DATA_LIB_UNINSTALL_PS1
    'data/lib/uninstall.vbs' = $FILE_DATA_LIB_UNINSTALL_VBS
    'data/src/app.js' = $FILE_DATA_SRC_APP_JS
    'data/src/app.py' = $FILE_DATA_SRC_APP_PY
    'data/src/test.txt' = $FILE_DATA_SRC_TEST_TXT
    'data/src/yto/asd.asd' = $FILE_DATA_SRC_YTO_ASD_ASD
    'data/test42' = $FILE_DATA_TEST42
    'LICENSE.txt' = $FILE_LICENSE_TXT
    'test.here.txt' = $FILE_TEST_HERE_TXT
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
# --- Main form ------------
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "$APP_NAME $APP_VERSION Setup"
$form.ClientSize      = New-Object System.Drawing.Size(540, 475)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.BackColor       = $C_BG
if ($script:iconObject) { $form.Icon = $script:iconObject }

$form.Add_Load({ [DarkMode]::Enable($form.Handle) })

$form.Add_FormClosing({
    param($s, $e)
    if ($script:idx -eq 5) { $e.Cancel = $true; return }   # block close during installation
    if ($script:skipCloseConfirm) { return }               # after uninstall, allow closing
    if ($pgReinstall.Visible -or $pgUpdate.Visible) { return }  # maintenance pages - no confirmation
    if ($script:idx -lt 6) {
        $r = Show-Dialog "Cancel Setup" "Are you sure you want to cancel the installation?" @("Yes", "No")
        if ($r -ne "Yes") { $e.Cancel = $true }
    }
})

$form.Add_FormClosed({
    if ($script:iconObject) {
        $form.Icon = $null
        $script:iconObject.Dispose()
        $script:iconObject = $null
    }
    if ($script:iconImage) {
        $script:iconImage.Dispose()
        $script:iconImage = $null
    }
    if (Test-Path $script:iconTemp) {
        Remove-Item $script:iconTemp -Force -ErrorAction SilentlyContinue
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
    (New-Label "Creator"        30  218  68 18 9 Bold    $C_DIM),
    (New-Label "Wizard Burgil 42" 104 218 200 18 9 Regular $C_ACCENT),
    (New-Label "License"        312 218  52 18 9 Bold    $C_DIM),
    (New-Label "$APP_NAME Source License" 370 218 160 18 9 Regular $C_DIM)
))
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
$licBox.Font        = New-Object System.Drawing.Font("Consolas", 8)
$licBox.Text        = $FILE_LICENSE_TXT
$pgLicense.Controls.Add($licBox)

# --- 4-column summary grid ---
# Columns: [CAN 1 x=30] [CAN 2 x=152] | [CANT 1 x=276] [CANT 2 x=396]

$chk = [char]0x2713   # checkmark
$xmk = [char]0x2717   # ballot X

# Section headers
$pgLicense.Controls.Add((New-Label "$chk  YOU CAN"    30  162 238 15 8 Bold $C_SUCCESS))
$pgLicense.Controls.Add((New-Label "$xmk  YOU CANNOT" 276 162 238 15 8 Bold $C_DANGER))

# Vertical divider
$licDiv           = New-Object System.Windows.Forms.Panel
$licDiv.Location  = New-Object System.Drawing.Point(265, 160)
$licDiv.Size      = New-Object System.Drawing.Size(1, 82)
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
    (New-LicItem "$chk Personal use"      30  181 $C_SUCCESS "Use $APP_NAME freely for personal projects, learning, and experimentation"),
    (New-LicItem "$chk Build plugins"    152  181 $C_SUCCESS "Create extensions and integrations that work with and depend on $APP_NAME"),
    (New-LicItem "$chk Modify source"     30  198 $C_SUCCESS "Edit the source code to suit your personal or internal needs"),
    (New-LicItem "$chk Share plugins"    152  198 $C_SUCCESS "Distribute your plugins to others under any license you choose"),
    (New-LicItem "$chk Run internally"    30  215 $C_SUCCESS "Deploy $APP_NAME within your organization for internal business use"),
    (New-LicItem "$chk Use licensed code" 152 215 $C_SUCCESS "Incorporate third-party libraries in your plugins if their license permits")
))

# CANNOT - col 3 (x=276) and col 4 (x=396)
$pgLicense.Controls.AddRange(@(
    (New-LicItem "$xmk Compete with $APP_NAME"    276 181 $C_DANGER "Do not build a product whose primary purpose overlaps with $APP_NAME's core functionality"),
    (New-LicItem "$xmk Violate local laws"  396 181 $C_DANGER "You must verify that using $APP_NAME is legal in your country or region before installing"),
    (New-LicItem "$xmk Redistribute $APP_NAME"    276 198 $C_DANGER "Do not package or distribute $APP_NAME itself without prior written permission from the authors"),
    (New-LicItem "$xmk Illegal/harmful use" 396 198 $C_DANGER "Do not use $APP_NAME for fraud, malware, unauthorized system access, or any harmful activity"),
    (New-LicItem "$xmk Remove notices"      276 215 $C_DANGER "Do not remove or alter any copyright, license, or attribution notices in the source"),
    (New-LicItem "$xmk Hold liable"         396 215 $C_DANGER "Authors are not liable for any damages - you use this software entirely at your own risk")
))

# --- Disclaimer note ---
$warn = [char]0x26A0
$licWarn           = New-Object System.Windows.Forms.Label
$licWarn.Text      = "$warn  Used at your own risk - no warranty, no liability for any damages or losses. You are solely responsible for ensuring use is legal in your region."
$licWarn.Location  = New-Object System.Drawing.Point(30, 247)
$licWarn.Size      = New-Object System.Drawing.Size(480, 30)
$licWarn.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$licWarn.ForeColor = $C_DIM
$licWarn.BackColor = [System.Drawing.Color]::Transparent
$pgLicense.Controls.Add($licWarn)

# --- Accept checkbox ---
$chkLicense           = New-Object System.Windows.Forms.CheckBox
$chkLicense.Text      = "I accept the terms of the license agreement"
$chkLicense.Location  = New-Object System.Drawing.Point(30, 286)
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
# PAGE 2 - DEPENDENCIES
# =============================================================================
$pgDeps = New-Page
$pgDeps.Controls.Add((New-Label "Required Software" 30 18 480 26 13 Bold $C_TEXT))
$pgDeps.Controls.Add((New-Label "The following must be installed before $APP_NAME can run:" 30 48 480 20 10 Regular $C_DIM))

$lblPy       = New-Label "Python >= $MIN_PYTHON"  30  94 140 22 10 Regular $C_TEXT
$lblPyStatus = New-Label "..."                   178  94 192 22 10

$btnGetPy           = New-ActionButton "Get Python" 375 91
$btnGetPy.Add_Click({ Start-Process "https://www.python.org/downloads/" })

$lblNode       = New-Label "Node.js >= $MIN_NODE"  30 128 140 22 10 Regular $C_TEXT
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
    if ($script:idx -ne 2) { return }

    # - Python: existence -
    $hasPy = [bool]((Invoke-Async 'where.exe' 'python').Trim())
    if ($script:idx -ne 2) { return }
    if ($hasPy) { $lblPyStatus.Text = "Detected..."; $lblPyStatus.ForeColor = $C_SUCCESS }
    else        { $lblPyStatus.Text = "Not found";   $lblPyStatus.ForeColor = $C_DANGER; $btnGetPy.Visible = $true }

    # - Node: existence ---
    $hasNode = [bool]((Invoke-Async 'where.exe' 'node').Trim())
    if ($script:idx -ne 2) { return }
    if ($hasNode) { $lblNodeStatus.Text = "Detected..."; $lblNodeStatus.ForeColor = $C_SUCCESS }
    else          { $lblNodeStatus.Text = "Not found";   $lblNodeStatus.ForeColor = $C_DANGER; $btnGetNode.Visible = $true }

    # - Python version, then pip appended ----------
    if ($hasPy) {
        $raw   = Invoke-Async 'python' '--version'
        if ($script:idx -ne 2) { return }
        $pyVer = if ($raw -match 'Python\s+(\S+)') { $Matches[1] } else { $raw }
        $lblPyStatus.Text = if ($pyVer) { $pyVer } else { "Detected" }

        $raw    = Invoke-Async 'pip' '--version'
        if ($script:idx -ne 2) { return }
        $pipVer = if ($raw -match '^pip\s+(\S+)') { $Matches[1] } else { '' }
        if ($pipVer) { $lblPyStatus.Text = "$pyVer  /  pip $pipVer" }
    }

    # - Node version, then npm appended ------------
    if ($hasNode) {
        $raw     = Invoke-Async 'node' '--version'
        if ($script:idx -ne 2) { return }
        $nodeVer = if ($raw -match 'v?(\d[\d.]*)') { $Matches[1] } else { $raw }
        $lblNodeStatus.Text = if ($nodeVer) { "v$nodeVer" } else { "Detected" }

        $raw    = Invoke-Async 'npm' '--version'
        if ($script:idx -ne 2) { return }
        $npmVer = if ($raw -match '^\d') { ($raw -split '\r?\n')[0].Trim() } else { '' }
        if ($npmVer) { $lblNodeStatus.Text = "v$nodeVer  /  npm $npmVer" }
    }

    # - Enable Next only after ALL checks complete --
    Write-Log ("Dep check done - python={0} node={1}" -f $lblPyStatus.Text, $lblNodeStatus.Text)
    if (-not $hasPy)   { Write-Log "Python not found" "WARN" }
    if (-not $hasNode) { Write-Log "Node.js not found" "WARN" }
    if ($script:idx -eq 2) { $btnNext.Enabled = $hasPy -and $hasNode }
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
$txtDir.Text        = "$env:LOCALAPPDATA\Programs\$APP_NAME"
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

$lblConfAppL   = New-Label "Application :"  30  86 134 22 10 Bold    $C_DIM
$lblConfAppV   = New-Label "$APP_NAME $APP_VERSION" 172  86 326 22 10 Regular $C_TEXT
$lblConfDirL   = New-Label "Location :"     30 112 134 22 10 Bold    $C_DIM
$lblConfDirV   = New-Label ""              172 112 326 22 10 Regular $C_TEXT
$lblConfScL    = New-Label "Shortcut :"     30 138 134 22 10 Bold    $C_DIM
$lblConfScV    = New-Label ""              172 138 326 22 10 Regular $C_TEXT
$lblConfProtoL = New-Label "Protocol :"     30 164 134 22 10 Bold    $C_DIM
$lblConfProtoV = New-Label "$($APP_NAME_LOW)://"        172 164 326 22 10 Regular $C_ACCENT
$lblConfUninL  = New-Label "Uninstaller :"  30 190 134 22 10 Bold    $C_DIM
$lblConfUninV  = New-Label "Yes (Add/Remove Programs)" 172 190 326 22 10 Regular $C_SUCCESS

$confirmSep           = New-Object System.Windows.Forms.Panel
$confirmSep.Location  = New-Object System.Drawing.Point(30, 218)
$confirmSep.Size      = New-Object System.Drawing.Size(480, 1)
$confirmSep.BackColor = $C_BORDER

# Optional features - 2-column grid (col1 x=30, col2 x=285)
function New-OptChk([string]$text, [int]$x, [int]$y) {
    $c           = New-Object System.Windows.Forms.CheckBox
    $c.Text      = $text
    $c.Checked   = $true
    $c.Location  = New-Object System.Drawing.Point($x, $y)
    $c.Size      = New-Object System.Drawing.Size(240, 20)
    $c.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $c.ForeColor = $C_TEXT
    $c.BackColor = $C_BG
    return $c
}

$chkStartup   = New-OptChk "Run on Startup"          30  226
$chkSendTo    = New-OptChk "Add to Send To menu"     285 226
$chkAddPath   = New-OptChk "Add to Path"              30  250
$chkStartMenu = New-OptChk "Start Menu shortcut"     285 250
$chkOpenWith  = New-OptChk "Right-click menu"         30  274
$chkFileAssoc = New-OptChk "File type (.ali)"        285 274
$chkNewMenu   = New-OptChk "New menu (.ali)"         285 298

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

# Tooltips for all optional feature checkboxes
$optTip = New-Object System.Windows.Forms.ToolTip
$optTip.SetToolTip($chkStartup,   "Launch $APP_NAME automatically when Windows starts")
$optTip.SetToolTip($chkSendTo,    "Add 'Send to $APP_NAME' to the right-click Send To submenu")
$optTip.SetToolTip($chkAddPath,   "Add $APP_NAME to PATH so you can run '$APP_NAME_LOW' from any terminal")
$optTip.SetToolTip($chkStartMenu, "Create a $APP_NAME shortcut in the Windows Start Menu")
$optTip.SetToolTip($chkOpenWith,  "Add 'Open with $APP_NAME' to the right-click menu for files and folders")
$optTip.SetToolTip($chkFileAssoc, "Open .ali files with $APP_NAME on double-click")
$optTip.SetToolTip($chkNewMenu,   "Add 'New > $APP_NAME File (.ali)' to the right-click New submenu (requires File type)")

$pgConfirm.Controls.AddRange(@(
    $lblConfAppL, $lblConfAppV, $lblConfDirL, $lblConfDirV,
    $lblConfScL,  $lblConfScV,  $lblConfProtoL, $lblConfProtoV,
    $lblConfUninL, $lblConfUninV,
    $confirmSep,
    $chkStartup, $chkSendTo, $chkAddPath, $chkStartMenu, $chkOpenWith, $chkFileAssoc, $chkNewMenu
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
    if ($script:_recheckTimer) { $script:_recheckTimer.Stop() }
    $dir = $script:existingInstallDir
    $lblReinstTitle.Text      = "Uninstalling..."
    $lblReinstTitle.ForeColor = $C_DIM
    $lblUpdateStatus.Visible  = $false
    $btnRecheck.Visible       = $false
    $btnReinstOpen.Visible    = $false
    $btnRepair.Visible        = $false
    $btnUninstReinst.Visible  = $false
    $btnReinstClose.Visible   = $false
    [System.Windows.Forms.Application]::DoEvents()

    Remove-ExistingInstall $dir

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

$pgReinstall.Controls.AddRange(@(
    $lblReinstTitle, $lblReinstPath, $lblUpdateStatus, $btnRecheck,
    $btnReinstOpen, $btnRepair, $btnUninstReinst, $btnReinstClose
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
                            $wd = if ($act.workdir -eq '.') { $dir } else { Join-Path $dir $act.workdir }
                            Write-Log "  run: $($act.command)  (workdir: $wd)"
                            Start-Process cmd.exe -ArgumentList "/c $($act.command)" -WorkingDirectory $wd -Wait -WindowStyle Hidden
                        }
                    }
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }
            # Update license if this patch requires it
            if ($patch.requiresLicense -and $patch.newLicense) {
                Write-Log "  updating LICENSE.txt"
                $licPath = Join-Path $dir "LICENSE.txt"
                [System.IO.File]::WriteAllText($licPath, $patch.newLicense, (New-Object System.Text.UTF8Encoding($false)))
            }
            # Update registry after each patch so partial progress is saved
            Write-Log "  registry: $APP_NAME v$($patch.version)"
            Set-ItemProperty -Path $regPath -Name "DisplayVersion" -Value $patch.version -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $regPath -Name "DisplayName" -Value "$APP_NAME $($patch.version)" -ErrorAction SilentlyContinue
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
# --- Page list ------------
$allPages  = @($pgWelcome, $pgLicense, $pgDeps, $pgLocation, $pgConfirm, $pgInstall, $pgDone)
$pageNames = @("Welcome", "License Agreement", "Requirements", "Install Location", "Ready to Install", "Installing...", "Installation Complete")
$script:idx = 0
$script:skipCloseConfirm = $false
# --- Install helpers ------
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
    $uninstLink = Join-Path $Path "Uninstall.lnk"
    if (Test-Path $uninstLink) { Remove-Item $uninstLink -Force -ErrorAction SilentlyContinue }
    $updLink = Join-Path $Path "Check for Updates.lnk"
    if (Test-Path $updLink) { Remove-Item $updLink -Force -ErrorAction SilentlyContinue }

    # - 2. Flush Explorer shell cache AFTER registry keys are gone ------------
    #    This makes Explorer release icon handles for .ali files and the folder
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
# --- Installation ---------
function Start-Installation {
    $dir    = $txtDir.Text
    $data   = "$dir\data"
    $lib    = "$data\lib"
    $assets = "$data\assets"
    $logs   = "$data\logs"

    if (Test-Path $dir) { Clear-InstallAttributes $dir }

    $steps = @(
        @{ Pct =  7; Msg = "Creating directories...";
           Action = {
               New-Item -ItemType Directory -Force -Path $dir    | Out-Null
               New-Item -ItemType Directory -Force -Path $data   | Out-Null
               New-Item -ItemType Directory -Force -Path $assets | Out-Null
               New-Item -ItemType Directory -Force -Path $logs   | Out-Null
           }},

        @{ Pct = 15; Msg = "Copying icon...";
           Action = {
               if ($script:iconObject -and (Test-Path $script:iconTemp)) {
                   Copy-Item $script:iconTemp "$assets\$APP_NAME_LOW.ico" -Force
               }
           }},

        @{ Pct = 42; Msg = "Writing files...";
           Action = {
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

               # Main launcher: $dir\APP.lnk - targets APP.cmd directly so Open File Location shows data/
               $lnk = $wsh.CreateShortcut("$dir\$APP_NAME.lnk")
               $lnk.TargetPath       = "$data\$APP_NAME.cmd"
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

        @{ Pct = 87; Msg = "Registering $($APP_NAME_LOW):// protocol...";
           Action = {
               $protoKey = "HKCU:\SOFTWARE\Classes\$APP_NAME_LOW"
               New-Item -Path $protoKey -Value "URL:$APP_NAME Protocol" -Force | Out-Null
               New-ItemProperty -Path $protoKey -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null
               $cmd = "wscript.exe `"$lib\router.vbs`" `"%1`""
               New-Item -Path "$protoKey\shell\open\command" -Value $cmd -Force | Out-Null
           }},

        @{ Pct = 94; Msg = "Registering uninstaller...";
           Action = {
               $key = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$APP_NAME"
               New-Item -Path $key -Force | Out-Null
               $props = @{
                   DisplayName     = "$APP_NAME $APP_VERSION"
                   DisplayVersion  = $APP_VERSION
                   Publisher       = $APP_NAME
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

        @{ Pct = 96; Msg = "Applying optional features...";
           Action = {
               Write-Log ("Applying features: startup={0} path={1} context-menu={2} send-to={3} start-menu={4} file-assoc={5} new-menu={6}" -f
                   $chkStartup.Checked, $chkAddPath.Checked, $chkOpenWith.Checked,
                   $chkSendTo.Checked, $chkStartMenu.Checked, $chkFileAssoc.Checked, $chkNewMenu.Checked)

               # Run on Startup - Startup folder .lnk so Task Manager shows the app name + icon
               $startupLnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\$APP_NAME.lnk"
               Remove-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $APP_NAME -ErrorAction SilentlyContinue  # remove legacy Run key
               if ($chkStartup.Checked) {
                   Write-Log "Startup: creating $startupLnk"
                   $wsh = New-Object -ComObject WScript.Shell
                   $lnk = $wsh.CreateShortcut($startupLnk)
                   $lnk.TargetPath       = "$data\$APP_NAME.cmd"
                   $lnk.WorkingDirectory = $data
                   $lnk.IconLocation     = "$assets\$APP_NAME_LOW.ico,0"
                   $lnk.Description      = "Start $APP_NAME on login"
                   $lnk.Save()
               } else {
                   Write-Log "Startup: removing"
                   Remove-Item $startupLnk -Force -ErrorAction SilentlyContinue
               }

               # Add to Path
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

               # Right-click menu
               $ico    = "$assets\$APP_NAME_LOW.ico"
               $cmd    = "wscript.exe `"$lib\router.vbs`" `"$($APP_NAME_LOW)://open?path=%1`""
               $cmdDir = "wscript.exe `"$lib\router.vbs`" `"$($APP_NAME_LOW)://open?path=%V`""
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
                   Remove-Item -LiteralPath "HKCU:\SOFTWARE\Classes\*\shell\$APP_NAME"                   -Recurse -Force -ErrorAction SilentlyContinue
                   Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\shell\$APP_NAME"           -Recurse -Force -ErrorAction SilentlyContinue
                   Remove-Item -Path        "HKCU:\SOFTWARE\Classes\Directory\Background\shell\$APP_NAME" -Recurse -Force -ErrorAction SilentlyContinue
               }

               # Send To
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

               # Start Menu
               $startMenuLnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$APP_NAME.lnk"
               if ($chkStartMenu.Checked) {
                   Write-Log "Start Menu: creating $startMenuLnk"
                   $wsh = New-Object -ComObject WScript.Shell
                   $lnk = $wsh.CreateShortcut($startMenuLnk)
                   $lnk.TargetPath       = "$data\$APP_NAME.cmd"
                   $lnk.WorkingDirectory = $data
                   $lnk.IconLocation     = "$assets\$APP_NAME_LOW.ico,0"
                   $lnk.Save()
               } else {
                   Write-Log "Start Menu: removing"
                   Remove-Item $startMenuLnk -Force -ErrorAction SilentlyContinue
               }

               # File type association (.ali)
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
                   $k.SetValue("", "wscript.exe `"$lib\router.vbs`" `"$($APP_NAME_LOW)://open?path=%1`""); $k.Close()
               } else {
                   Write-Log "File assoc: removing .$APP_NAME_LOW"
                   Remove-Item -Path "HKCU:\SOFTWARE\Classes\.$APP_NAME_LOW" -Recurse -Force -ErrorAction SilentlyContinue
                   Remove-Item -Path "HKCU:\SOFTWARE\Classes\$APP_NAME.File" -Recurse -Force -ErrorAction SilentlyContinue
               }

               # New menu (.ali)
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

               # Flush Windows shell/icon cache
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
               Write-Log "Shell cache flushed (SHChangeNotify)"
           }},

        @{ Pct = 97; Msg = "Creating shortcut...";
           Action = {
               if ($chkShortcut.Checked) {
                   Write-Log "Desktop shortcut: creating"
                   $shell = New-Object -ComObject WScript.Shell
                   $sc    = $shell.CreateShortcut("$env:USERPROFILE\Desktop\$APP_NAME.lnk")
                   $sc.TargetPath       = "$data\$APP_NAME.cmd"
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
            $btnCancel.Enabled = $true
            return
        }
        Start-Sleep -Milliseconds 280
        [System.Windows.Forms.Application]::DoEvents()
    }
    Write-Log "Installation complete"

    Show-Page 6
}
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
        2 { Start-DepCheck }
        4 {
            $btnNext.Text     = "Install"
            $lblConfDirV.Text = $txtDir.Text
            $lblConfScV.Text  = if ($chkShortcut.Checked) { "Yes" } else { "No" }
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
        5 {
            $btnBack.Enabled   = $false
            $btnNext.Enabled   = $false
            $btnCancel.Enabled = $false
            Start-Installation
        }
        6 {
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
# --- Button handlers ------
$btnNext.Add_Click({
    if ($script:idx -eq 6) {
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
# --- Run ------------------
$form.Add_Load({
    $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$APP_NAME"
    $props   = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
    if ($props -and $props.InstallLocation -and (Test-Path $props.InstallLocation)) {
        $script:existingInstallDir = $props.InstallLocation
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
    [System.Windows.Forms.Application]::Run($form)
} finally {
    try { $script:_mutex.ReleaseMutex() } catch {}
    $script:_mutex.Dispose()
}