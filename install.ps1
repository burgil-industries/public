# ==============================================================================
# Burgil Industries - C.O.M.P.U.T.E.R. Protocol Bootstrapper
# ==============================================================================

$APP_NAME      = "C.O.M.P.U.T.E.R."
$APP_NAME_LOW  = $APP_NAME.ToLower()
$APP_VERSION   = "1.0.0"

# --- Credits splash + relaunch as hidden process ----------------------------
# First run: show credits for 3 s, then re-exec hidden so only the WinForms
# window appears in the taskbar.  Second run (HEADLESS=1): skip straight through.
if (-not $env:COMPUTER_SETUP_HEADLESS) {
    $env:COMPUTER_SETUP_HEADLESS = "1"

    # Launch the hidden installer immediately so it loads while credits are shown
    $tmp = "$env:TEMP\computer_setup_launch.ps1"
    if ($PSCommandPath) {
        Copy-Item $PSCommandPath $tmp -Force -ErrorAction SilentlyContinue
    } else {
        [System.IO.File]::WriteAllText($tmp,
            $MyInvocation.MyCommand.ScriptBlock.ToString(),
            [System.Text.Encoding]::UTF8)
    }
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tmp`""

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
    exit
}
$env:COMPUTER_SETUP_HEADLESS = ""   # reset for future runs in this session
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
# --- Icon: download to temp, shown in installer window header PictureBox -----
$script:iconTemp  = "$env:TEMP\$($APP_NAME_LOW)_setup.ico"
$script:iconImage = $null   # System.Drawing.Image - for PictureBox (accepts PNG, ICO, anything)

if ($ICON_URL) {
    try {
        if (Test-Path $script:iconTemp) { Remove-Item $script:iconTemp -Force -ErrorAction SilentlyContinue }
        (New-Object System.Net.WebClient).DownloadFile($ICON_URL, $script:iconTemp)
        $script:iconImage = [System.Drawing.Image]::FromFile($script:iconTemp)
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
'@

$FILE_DATA_LIB_CHECK_UPDATE_PS1 = @'
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
                Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ps1Path`""
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
sh.Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "check-update.ps1""", 0, False
'@

$FILE_DATA_LIB_REPAIR_VBS = @'
Set sh = CreateObject("WScript.Shell")
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
ps1 = scriptDir & "install.ps1"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """"
sh.Run cmd, 1, False
'@

$FILE_DATA_LIB_ROUTER_PS1 = @'
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
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "router.ps1"" """ & WScript.Arguments(0) & """", 0, False
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
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
sh.Run cmd, 0, False
'@

$FILE_DATA_PLUGINS_JSON = @'
{}
'@

$FILE_DATA_SRC_APP_JS = @'
'use strict';
const http   = require('http');
const crypto = require('crypto');
const fs     = require('fs');
const path   = require('path');
const { PermissionError, checkPermission, validatePermissions, expandPermissions } = require('./permissions');

const APP_NAME    = '__APP_NAME__';
const APP_VERSION = '__APP_VERSION__';
const PORT        = 53420;
const WS_MAGIC    = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

// Rate limit: max 20 messages per 10-second window per remote address
const RATE_WINDOW = 10_000;
const RATE_MAX    = 20;
const rateLimits  = new Map();

function checkRate(ip) {
    const now = Date.now();
    let rl = rateLimits.get(ip);
    if (!rl || now > rl.reset) rl = { count: 0, reset: now + RATE_WINDOW };
    rl.count++;
    rateLimits.set(ip, rl);
    return rl.count <= RATE_MAX;
}

// Clean up stale rate-limit entries every minute
setInterval(() => {
    const now = Date.now();
    for (const [ip, rl] of rateLimits) if (now > rl.reset) rateLimits.delete(ip);
}, 60_000).unref();

// ── WebSocket frame codec ──────────────────────────────────────────────────────

function wsAccept(key) {
    return crypto.createHash('sha1').update(key + WS_MAGIC).digest('base64');
}

function parseFrame(buf) {
    if (buf.length < 2) return null;
    const opcode    = buf[0] & 0x0f;
    if (opcode === 8) return null;              // connection close frame
    const isMasked   = !!(buf[1] & 0x80);
    let   payloadLen = buf[1] & 0x7f;
    let   offset     = 2;
    if      (payloadLen === 126) { payloadLen = buf.readUInt16BE(2);             offset = 4;  }
    else if (payloadLen === 127) { payloadLen = Number(buf.readBigUInt64BE(2));  offset = 10; }
    const maskStart = offset;
    const dataStart = offset + (isMasked ? 4 : 0);
    const data      = Buffer.from(buf.slice(dataStart, dataStart + payloadLen));
    if (isMasked) {
        const mask = buf.slice(maskStart, maskStart + 4);
        for (let i = 0; i < data.length; i++) data[i] ^= mask[i % 4];
    }
    return data.toString('utf8');
}

function makeFrame(msg) {
    const payload = Buffer.from(msg, 'utf8');
    const len     = payload.length;
    let   header;
    if (len < 126) {
        header = Buffer.alloc(2);
        header[0] = 0x81;
        header[1] = len;
    } else if (len < 65536) {
        header = Buffer.alloc(4);
        header[0] = 0x81; header[1] = 126;
        header.writeUInt16BE(len, 2);
    } else {
        header = Buffer.alloc(10);
        header[0] = 0x81; header[1] = 127;
        header.writeBigUInt64BE(BigInt(len), 2);
    }
    return Buffer.concat([header, payload]);
}

function send(socket, obj) {
    try { socket.write(makeFrame(JSON.stringify(obj))); } catch (_) {}
}

// ── Plugin system ─────────────────────────────────────────────────────────────

const pluginsFile = path.join(__dirname, '..', 'plugins.json');
const pluginsDir  = path.join(__dirname, '..', 'plugins');
const dataDir     = path.join(__dirname, '..');

// All active WS sockets
const sockets     = new Set();
// Plugin-registered WS message handlers: type -> handler(socket, msg)
const wsHandlers  = new Map();
// Loaded plugin manifests: id -> { id, name, version, ... }
const loadedPlugins = {};
// Shared services map (cross-plugin)
const services = new Map();

function broadcast(obj) {
    for (const s of sockets) send(s, obj);
}

function readPluginsJson() {
    try { return JSON.parse(fs.readFileSync(pluginsFile, 'utf8')); }
    catch (_) { return {}; }
}

// ── Per-plugin context with permission enforcement ───────────────────────────

function createContext(pluginId, grantedPermissions) {
    function requirePermission(needed) {
        if (!checkPermission(grantedPermissions, needed)) {
            throw new PermissionError(pluginId, needed);
        }
    }

    return {
        // Identity
        appName:    APP_NAME,
        appVersion: APP_VERSION,
        dataDir,

        // Service provider/consumer
        provide(key, val) {
            requirePermission('ctx.provide');
            services.set(key, val);
        },
        use(key) {
            if (!services.has(key)) {
                throw new Error(
                    `[plugin:${pluginId}] Service "${key}" not found. ` +
                    `Is the providing plugin listed as a dependency and loaded first?`
                );
            }
            return services.get(key);
        },

        // WS integration (always allowed)
        onMessage(type, handler) { wsHandlers.set(type, handler); },
        reply: send,

        // Broadcast (permission-gated)
        broadcast(obj) {
            requirePermission('ctx.broadcast');
            broadcast(obj);
        },

        // Introspection (always allowed)
        loadedPlugins() { return Object.assign({}, loadedPlugins); },

        // ── Permission-gated file system ─────────────────────────────────
        readFile(filePath) {
            const resolved = path.resolve(filePath);
            requirePermission(`fs.read:${resolved}`);
            return fs.readFileSync(resolved, 'utf8');
        },

        readFileBuffer(filePath) {
            const resolved = path.resolve(filePath);
            requirePermission(`fs.read:${resolved}`);
            return fs.readFileSync(resolved);
        },

        writeFile(filePath, data) {
            const resolved = path.resolve(filePath);
            requirePermission(`fs.write:${resolved}`);
            fs.writeFileSync(resolved, data);
        },

        existsSync(filePath) {
            const resolved = path.resolve(filePath);
            requirePermission(`fs.read:${resolved}`);
            return fs.existsSync(resolved);
        },

        readDir(dirPath) {
            const resolved = path.resolve(dirPath);
            requirePermission(`fs.read:${resolved}`);
            return fs.readdirSync(resolved);
        },

        // ── Permission-gated network ─────────────────────────────────────
        listen(port, handler) {
            requirePermission(`net.listen:${port}`);
            const srv = http.createServer(handler);
            srv.listen(port, '127.0.0.1');
            return srv;
        },

        fetch(url, options) {
            const parsed = new URL(url);
            requirePermission(`net.connect:${parsed.hostname}`);
            // Use Node.js built-in fetch if available, otherwise http/https
            if (typeof globalThis.fetch === 'function') {
                return globalThis.fetch(url, options);
            }
            const mod = parsed.protocol === 'https:' ? require('https') : require('http');
            return new Promise((resolve, reject) => {
                mod.get(url, options || {}, res => {
                    let data = '';
                    res.on('data', chunk => data += chunk);
                    res.on('end', () => resolve({ ok: res.statusCode < 400, status: res.statusCode, text: () => Promise.resolve(data), json: () => Promise.resolve(JSON.parse(data)) }));
                }).on('error', reject);
            });
        },

        // ── Permission-gated system exec ─────────────────────────────────
        exec(command, args) {
            const cmd = typeof command === 'string' ? command.split(/\s+/)[0] : command;
            requirePermission(`system.exec:${cmd}`);
            const { execSync } = require('child_process');
            const fullCmd = args ? `${command} ${args.join(' ')}` : command;
            return execSync(fullCmd, { encoding: 'utf8' });
        },

        execAsync(command, args) {
            const cmd = typeof command === 'string' ? command.split(/\s+/)[0] : command;
            requirePermission(`system.exec:${cmd}`);
            const { exec } = require('child_process');
            const fullCmd = args ? `${command} ${args.join(' ')}` : command;
            return new Promise((resolve, reject) => {
                exec(fullCmd, (err, stdout, stderr) => {
                    if (err) reject(err);
                    else resolve({ stdout, stderr });
                });
            });
        },
    };
}

// ── Plugin loader ────────────────────────────────────────────────────────────

function loadPlugins() {
    if (!fs.existsSync(pluginsDir)) {
        console.log(`[plugin] no plugins directory at ${pluginsDir}`);
        return;
    }

    const entries = fs.readdirSync(pluginsDir);

    // Dependency sort: core first, then ui, then everything else
    entries.sort((a, b) => {
        if (a === 'core') return -1;
        if (b === 'core') return 1;
        if (a === 'ui')   return -1;
        if (b === 'ui')   return 1;
        return a.localeCompare(b);
    });

    for (const name of entries) {
        const dir          = path.join(pluginsDir, name);
        const manifestPath = path.join(dir, 'plugin.json');

        if (!fs.existsSync(manifestPath)) continue;

        let manifest;
        try { manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')); }
        catch (e) {
            console.error(`[plugin] bad manifest for ${name}: ${e.message}`);
            continue;
        }

        // Read and validate permissions
        const rawPerms = manifest.permissions || [];
        const expanded = expandPermissions(rawPerms, dataDir);
        const invalid  = validatePermissions(expanded);
        if (invalid.length > 0) {
            console.warn(`[plugin] "${name}" has unrecognized permissions: ${invalid.join(', ')}`);
        }

        const pluginId = manifest.id || name;

        try {
            const ctx    = createContext(pluginId, expanded);
            const plugin = require(path.join(dir, manifest.main || 'index.js'));
            if (typeof plugin.install === 'function') plugin.install(ctx);
            loadedPlugins[pluginId] = {
                name:    manifest.name    || name,
                version: manifest.version || '0.0.0',
            };
            console.log(`[plugin] loaded "${pluginId}" with permissions: [${expanded.join(', ')}]`);
        } catch (e) {
            if (e instanceof PermissionError) {
                console.error(`[plugin] permission denied for "${name}": ${e.message}`);
            } else {
                console.error(`[plugin] failed to load "${name}": ${e.message}`);
            }
        }
    }

    const count = Object.keys(loadedPlugins).length;
    console.log(`[plugin] ${count} plugin(s) loaded: ${Object.keys(loadedPlugins).join(', ') || 'none'}`);
}

// ── Message handler ───────────────────────────────────────────────────────────

function handleMessage(socket, ip, raw) {
    if (!checkRate(ip)) {
        send(socket, { type: 'error', message: 'rate limited' });
        return;
    }
    let msg;
    try { msg = JSON.parse(raw); } catch (_) {
        send(socket, { type: 'error', message: 'invalid json' });
        return;
    }

    switch (msg.type) {
        case 'ping':
            send(socket, { type: 'pong', app: APP_NAME, version: APP_VERSION });
            break;
        case 'versions':
            send(socket, {
                type:    'versions',
                app:     APP_NAME,
                version: APP_VERSION,
                plugins: readPluginsJson(),
            });
            break;
        case 'install-package': {
            // Package install request from the web UI
            const plugins = msg.plugins || [];
            const packageId = msg.packageId || 'unknown';
            console.log(`[ws] install-package request: ${packageId} -> [${plugins.join(', ')}]`);
            // Placeholder: actual package installation logic would go here
            send(socket, { type: 'install-package:ack', packageId, plugins, status: 'received' });
            break;
        }
        default: {
            const handler = wsHandlers.get(msg.type);
            if (handler) handler(socket, msg);
            else send(socket, { type: 'error', message: `unknown type: ${msg.type}` });
        }
    }
}

// ── HTTP + WebSocket server ───────────────────────────────────────────────────

const server = http.createServer((req, res) => {
    res.writeHead(200, {
        'Content-Type': 'text/plain',
        'Access-Control-Allow-Origin': '*'
    });
    res.end(`${APP_NAME} ${APP_VERSION}`);
});

server.on('upgrade', (req, socket) => {
    const key    = req.headers['sec-websocket-key'];
    const accept = wsAccept(key);
    const ip     = socket.remoteAddress || 'unknown';

    socket.write(
        'HTTP/1.1 101 Switching Protocols\r\n' +
        'Upgrade: websocket\r\n' +
        'Connection: Upgrade\r\n' +
        `Sec-WebSocket-Accept: ${accept}\r\n` +
        'Access-Control-Allow-Origin: *\r\n' +
        '\r\n'
    );

    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => sockets.delete(socket));

    let buf = Buffer.alloc(0);
    socket.on('data', chunk => {
        buf = Buffer.concat([buf, chunk]);
        const msg = parseFrame(buf);
        if (msg !== null) {
            buf = Buffer.alloc(0);
            handleMessage(socket, ip, msg);
        }
    });
});

server.on('error', err => {
    if (err.code === 'EADDRINUSE') {
        console.log(`${APP_NAME}: port ${PORT} already in use - another instance may be running`);
    } else {
        console.error(`${APP_NAME}: server error: ${err.message}`);
    }
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`${APP_NAME} ${APP_VERSION} - WS server listening on ws://127.0.0.1:${PORT}`);
    loadPlugins();
});
'@

$FILE_DATA_SRC_APP_PY = @'
print('Hello World - Python component!')
'@

$FILE_DATA_SRC_PERMISSIONS_JS = @'
'use strict';

// ── Permission Taxonomy ──────────────────────────────────────────────────────
//
// Format: category.action           (wildcard - grants all scopes)
//         category.action:scope     (scoped - grants only matching scope)
//
// Categories:
//   fs.read            Read any file
//   fs.read:<path>     Read files under a specific path
//   fs.write           Write any file
//   fs.write:<path>    Write files under a specific path
//   net.listen         Listen on any port
//   net.listen:<port>  Listen on a specific port
//   net.connect        Make outbound connections to any host
//   net.connect:<host> Connect to a specific host
//   system.exec        Execute any child process
//   system.exec:<cmd>  Execute a specific command
//   ctx.provide        Register services for other plugins
//   ctx.broadcast      Broadcast messages to all WS clients

const PERMISSION_CATEGORIES = [
    'fs.read',
    'fs.write',
    'net.listen',
    'net.connect',
    'system.exec',
    'ctx.provide',
    'ctx.broadcast',
];

const PERMISSION_DESCRIPTIONS = {
    'fs.read':        'Read files from your computer',
    'fs.write':       'Write files to your computer',
    'net.listen':     'Start a local server',
    'net.connect':    'Connect to the internet',
    'system.exec':    'Run system commands',
    'ctx.provide':    'Provide services to other plugins',
    'ctx.broadcast':  'Send messages to all connected clients',
};

class PermissionError extends Error {
    constructor(pluginId, needed) {
        super(`Plugin "${pluginId}" requires permission "${needed}" but was not granted it.`);
        this.name = 'PermissionError';
        this.pluginId = pluginId;
        this.permission = needed;
    }
}

/**
 * Parse a permission string into its components.
 * "fs.read:/some/path" -> { base: "fs.read", scope: "/some/path" }
 * "ctx.provide"        -> { base: "ctx.provide", scope: null }
 */
function parsePermission(str) {
    const colonIdx = str.indexOf(':');
    // Check if colon is after the category.action part (not within it)
    // e.g. "fs.read" has no colon, "fs.read:/path" has colon as scope separator
    // but "ctx.provide" should not split on any colon
    const parts = str.split(':');
    const base = parts[0];
    const scope = parts.length > 1 ? parts.slice(1).join(':') : null;
    return { base, scope };
}

/**
 * Check if a specific permission is granted by the granted list.
 * Supports wildcard: "fs.read" (no scope) grants "fs.read:/any/path".
 * Supports path matching: "fs.write:/data" grants "fs.write:/data/config.json".
 */
function checkPermission(grantedList, needed) {
    const { base: neededBase, scope: neededScope } = parsePermission(needed);

    for (const granted of grantedList) {
        const { base: grantedBase, scope: grantedScope } = parsePermission(granted);

        if (grantedBase !== neededBase) continue;

        // Wildcard: granted has no scope -> grants everything under this category
        if (grantedScope === null) return true;

        // Exact match
        if (neededScope === null) continue; // needed is wildcard but granted is scoped -> no match
        if (neededScope === grantedScope) return true;

        // Path prefix match: granted "/data" matches needed "/data/config.json"
        if (neededScope.startsWith(grantedScope + '/')) return true;
        if (neededScope.startsWith(grantedScope + '\\')) return true;
    }

    return false;
}

/**
 * Validate that all permissions in a list are recognized categories.
 * Returns array of unrecognized permissions (empty if all valid).
 */
function validatePermissions(permissions) {
    const invalid = [];
    for (const perm of permissions) {
        const { base } = parsePermission(perm);
        if (!PERMISSION_CATEGORIES.includes(base)) {
            invalid.push(perm);
        }
    }
    return invalid;
}

/**
 * Expand ${dataDir} tokens in permission scopes.
 */
function expandPermissions(permissions, dataDir) {
    return permissions.map(p => p.replace(/\$\{dataDir\}/g, dataDir));
}

module.exports = {
    PERMISSION_CATEGORIES,
    PERMISSION_DESCRIPTIONS,
    PermissionError,
    parsePermission,
    checkPermission,
    validatePermissions,
    expandPermissions,
};
'@

$FILE_LICENSE_TXT = @'
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
    'data/plugins.json' = $FILE_DATA_PLUGINS_JSON
    'data/src/app.js' = $FILE_DATA_SRC_APP_JS
    'data/src/app.py' = $FILE_DATA_SRC_APP_PY
    'data/src/permissions.js' = $FILE_DATA_SRC_PERMISSIONS_JS
    'LICENSE.txt' = $FILE_LICENSE_TXT
}

# --- Plugin files (auto-embedded from plugins/ by build.ps1) ---
$FILE_DATA_PLUGINS_CORE_INDEX_JS = @'
'use strict';
const EventEmitter = require('events');
const path         = require('path');

// ── EventBus ──────────────────────────────────────────────────────────────────
class EventBus extends EventEmitter {}

// ── Config ────────────────────────────────────────────────────────────────────
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

// ── Logger ────────────────────────────────────────────────────────────────────
function makeLogger(events) {
    return function log(msg, level = 'INFO') {
        const line = `[${new Date().toISOString()}] [${level}] ${msg}`;
        console.log(line);
        events.emit('core:log', { level, msg, line });
    };
}

// ── Plugin install ────────────────────────────────────────────────────────────
module.exports = {
    install(ctx) {
        const bus    = new EventBus();
        const config = new Config(ctx);
        const log    = makeLogger(bus);

        ctx.provide('events', bus);
        ctx.provide('config', config);
        ctx.provide('log',    log);

        log(`core plugin loaded`);
    }
};
'@

$FILE_DATA_PLUGINS_CORE_PLUGIN_JSON = @'
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

$FILE_DATA_PLUGINS_EXAMPLE_TODO_TXT = @'
Under construction
'@

$FILE_DATA_PLUGINS_PHONE_TODO_TXT = @'
Under construction
'@

$FILE_DATA_PLUGINS_SETTINGS_INDEX_JS = @'
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

$FILE_DATA_PLUGINS_SETTINGS_PANEL_HTML = @'
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
    <span id="conn-label">Connecting…</span>
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

connect();
</script>
</body>
</html>
'@

$FILE_DATA_PLUGINS_SETTINGS_PLUGIN_JSON = @'
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

$FILE_DATA_PLUGINS_UI_INDEX_JS = @'
'use strict';
const path = require('path');
const url  = require('url');

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

        // Service: register a panel by id with a path to its HTML file
        ctx.provide('ui.registerPanel', (id, htmlPath, title = id) => {
            panels.set(id, { htmlPath: path.resolve(htmlPath), title });
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

            const parsed  = url.parse(req.url || '/');
            const panelId = (parsed.pathname || '/').replace(/^\//, '').split('/')[0];

            // Root -> panel index
            if (!panelId) {
                res.writeHead(200, { 'Content-Type': 'text/html' });
                res.end(buildIndex(ctx.appName, ctx.appVersion));
                return;
            }

            // Static asset within a panel dir: /<panelId>/file.ext
            const subPath = (parsed.pathname || '/').replace(/^\/[^/]+/, '');
            if (subPath && subPath !== '/') {
                const panel = panels.get(panelId);
                if (panel) {
                    const asset = path.join(path.dirname(panel.htmlPath), subPath);
                    serveFile(ctx, res, asset);
                    return;
                }
            }

            // Panel HTML
            if (panels.has(panelId)) {
                serveFile(ctx, res, panels.get(panelId).htmlPath);
                return;
            }

            res.writeHead(404);
            res.end('Panel not found');
        });

        server.on('error', err => log(`ui: server error - ${err.message}`, 'ERROR'));

        log(`ui: panel server -> http://127.0.0.1:${port}`);
        events.emit('ui:ready', { port });

        log(`ui plugin loaded`);
    }
};
'@

$FILE_DATA_PLUGINS_UI_PLUGIN_JSON = @'
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

$FILE_MANIFEST['data/plugins/core/index.js'] = $FILE_DATA_PLUGINS_CORE_INDEX_JS
$FILE_MANIFEST['data/plugins/core/plugin.json'] = $FILE_DATA_PLUGINS_CORE_PLUGIN_JSON
$FILE_MANIFEST['data/plugins/example/todo.txt'] = $FILE_DATA_PLUGINS_EXAMPLE_TODO_TXT
$FILE_MANIFEST['data/plugins/phone/todo.txt'] = $FILE_DATA_PLUGINS_PHONE_TODO_TXT
$FILE_MANIFEST['data/plugins/settings/index.js'] = $FILE_DATA_PLUGINS_SETTINGS_INDEX_JS
$FILE_MANIFEST['data/plugins/settings/panel.html'] = $FILE_DATA_PLUGINS_SETTINGS_PANEL_HTML
$FILE_MANIFEST['data/plugins/settings/plugin.json'] = $FILE_DATA_PLUGINS_SETTINGS_PLUGIN_JSON
$FILE_MANIFEST['data/plugins/ui/index.js'] = $FILE_DATA_PLUGINS_UI_INDEX_JS
$FILE_MANIFEST['data/plugins/ui/plugin.json'] = $FILE_DATA_PLUGINS_UI_PLUGIN_JSON

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

$form.Add_Load({
    # Remove WS_EX_APPWINDOW (0x40000) from the console and hide it — this strips
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
RTB-Write $licBox "d) Incorporate third-party code into Plugins, provided the license of that`n   third-party code permits such use.`n`n" $C_TEXT

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

RTB-Write $licBox "6. PLUGINS`n" $C_ACCENT -Bold
RTB-Write $licBox "Plugins you create are your own work. This license places no restrictions`non the license you choose for your Plugins, provided the Plugin does not`nitself constitute a Competing Product.`n`n" $C_TEXT

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
    (New-LicItem "[+] Personal use"      30  181 $C_SUCCESS "Use $APP_NAME freely for personal projects, learning, and experimentation"),
    (New-LicItem "[+] Build plugins"    152  181 $C_SUCCESS "Create extensions and integrations that work with and depend on $APP_NAME"),
    (New-LicItem "[+] Modify source"     30  198 $C_SUCCESS "Edit the source code to suit your personal or internal needs"),
    (New-LicItem "[+] Share plugins"    152  198 $C_SUCCESS "Distribute your plugins to others under any license you choose"),
    (New-LicItem "[+] Run internally"    30  215 $C_SUCCESS "Deploy $APP_NAME within your organization for internal business use"),
    (New-LicItem "[+] Use licensed code" 152 215 $C_SUCCESS "Incorporate third-party libraries in your plugins if their license permits")
))

# CANNOT - col 3 (x=276) and col 4 (x=396)
$pgLicense.Controls.AddRange(@(
    (New-LicItem "[x] Compete with us"     276 181 $C_DANGER "Do not build a product whose primary purpose overlaps with $APP_NAME's core functionality"),
    (New-LicItem "[x] Violate local laws"  396 181 $C_DANGER "You must verify that using $APP_NAME is legal in your country or region before installing"),
    (New-LicItem "[x] Redistribute it"    276 198 $C_DANGER "Do not package or distribute $APP_NAME itself without prior written permission from the authors"),
    (New-LicItem "[x] Illegal/harmful use" 396 198 $C_DANGER "Do not use $APP_NAME for fraud, malware, unauthorized system access, or any harmful activity"),
    (New-LicItem "[x] Remove notices"      276 215 $C_DANGER "Do not remove or alter any copyright, license, or attribution notices in the source"),
    (New-LicItem "[x] Hold liable"         396 215 $C_DANGER "Authors are not liable for any damages - you use this software entirely at your own risk")
))

# --- Disclaimer note ---
$licWarn           = New-Object System.Windows.Forms.Label
$licWarn.Text      = "[!]  Used at your own risk - no warranty, no liability for any damages or losses. You are solely responsible for ensuring use is legal in your region."
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
RTB-Write $legalBox "LOCAL DATA PROCESSING   " $C_ACCENT -Bold
RTB-Write $legalBox "No data is collected or transmitted by the author.`n" $C_TEXT

RTB-Write $legalBox "  7. " $C_ACCENT -Bold
RTB-Write $legalBox "AI TRANSPARENCY         " $C_VIOLET -Bold
RTB-Write $legalBox "Local AI runs on-machine. Cloud providers governed by their own terms.`n" $C_TEXT

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
RTB-Write $legalBox "  Privacy`n"                               $C_ACCENT -Bold -Size 9.5
RTB-Write $legalBox "  All core processing runs "               $C_TEXT
RTB-Write $legalBox "on your machine"                           $C_ACCENT -Bold
RTB-Write $legalBox ". The author does "                        $C_TEXT
RTB-Write $legalBox "not"                                       $C_ACCENT -Bold
RTB-Write $legalBox " collect or`n  transmit your data. "       $C_TEXT
RTB-Write $legalBox "Plugins"                                   $C_ORANGE -Bold
RTB-Write $legalBox " connecting to the internet are governed by their own terms.`n`n" $C_TEXT

# --- AI Components ---
RTB-Write $legalBox "  AI Components`n"                         $C_VIOLET -Bold -Size 9.5
RTB-Write $legalBox "  Local AI components (models, agents, tools) run " $C_TEXT
RTB-Write $legalBox "entirely on your machine`n"                $C_VIOLET -Bold
RTB-Write $legalBox "  Cloud LLM providers "                    $C_TEXT
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
$lblConfProtoV = New-Label "$($APP_NAME_LOW)://"        172 150 326 18 9 Regular $C_ACCENT
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
$chkNewMenu   = New-OptChk "New menu (.computer)"         240 68

$pnlAdvanced.Controls.AddRange(@($chkStartup, $chkSendTo, $chkAddPath, $chkStartMenu, $chkOpenWith, $chkFileAssoc, $chkNewMenu))

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
# --- Page list ------------
$allPages  = @($pgWelcome, $pgLicense, $pgLegal, $pgDeps, $pgLocation, $pgConfirm, $pgInstall, $pgDone)
$pageNames = @("Welcome", "License Agreement", "Legal Notices", "Requirements", "Install Location", "Ready to Install", "Installing...", "Installation Complete")
$script:idx = 0
$script:skipCloseConfirm = $false
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
# --- Installation ---------
function Start-Installation {
    $dir    = $txtDir.Text.TrimEnd('.')
    $data   = "$dir\data"
    $lib    = "$data\lib"
    $assets = "$data\assets"
    $logs   = "$data\logs"

    if (Test-Path $dir) { Clear-InstallAttributes $dir }

    # Pre-compile the shell-notify type so Add-Type doesn't stall mid-install
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

        @{ Pct = 87; Msg = "Registering $($APP_NAME_LOW):// protocol...";
           Action = {
               $protoKey = "HKCU:\SOFTWARE\Classes\$APP_NAME_LOW"
               New-Item -Path $protoKey -Value "URL:$APP_NAME Protocol" -Force | Out-Null
               New-ItemProperty -Path $protoKey -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null
               # Friendly name shown in protocol confirmation dialogs (when respected by the browser)
               New-Item -Path "$protoKey\Application" -Force | Out-Null
               New-ItemProperty -Path "$protoKey\Application" -Name "ApplicationName" -Value $APP_NAME -PropertyType String -Force | Out-Null
               New-ItemProperty -Path "$protoKey\Application" -Name "ApplicationDescription" -Value "$APP_NAME Protocol Handler" -PropertyType String -Force | Out-Null
               $cmd = "wscript.exe `"$lib\router.vbs`" `"%1`""
               New-Item -Path "$protoKey\shell\open\command" -Value $cmd -Force | Out-Null
           }},

        @{ Pct = 94; Msg = "Registering uninstaller...";
           Action = {
               $key = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$APP_NAME"
               New-Item -Path $key -Force | Out-Null
               $props = @{
                   DisplayName     = $APP_NAME
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

        @{ Pct = 88; Msg = "Applying optional features (1/7): Run on startup...";
           Action = {
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
                   $k.SetValue("", "wscript.exe `"$lib\router.vbs`" `"$($APP_NAME_LOW)://open?path=%1`""); $k.Close()
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
[System.Windows.Forms.Application]::SetUnhandledExceptionMode(
    [System.Windows.Forms.UnhandledExceptionMode]::CatchException)
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