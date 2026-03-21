$APP_NAME      = "ALI"
$APP_NAME_LOW  = $APP_NAME.ToLower()
$APP_VERSION   = "{{VERSION}}"
$ICON_URL      = "http://127.0.0.1:5500/favicon.ico"
$UPDATE_URL    = "http://127.0.0.1:5500/updates"
$AD_URL        = "http://127.0.0.1:5500/ads/softwisor.com.png"   # URL to a 480x82 banner image - leave empty to show placeholder
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
