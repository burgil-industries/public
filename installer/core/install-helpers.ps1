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

    # -- 1. Registry and shortcut cleanup first ------
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

    # -- 2. Flush Explorer shell cache AFTER registry keys are gone ------------
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

    # -- 3. Clear file attributes then delete --------
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