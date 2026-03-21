# --- Installation ---------
function Start-Installation {
    $dir    = $txtDir.Text
    $data   = "$dir\data"
    $src    = "$data\src"
    $lib    = "$data\lib"
    $assets = "$data\assets"
    $logs   = "$data\logs"

    if (Test-Path $dir) { Clear-InstallAttributes $dir }

    $steps = @(
        @{ Pct =  7; Msg = "Creating directories...";
           Action = {
               New-Item -ItemType Directory -Force -Path $dir    | Out-Null
               New-Item -ItemType Directory -Force -Path $data   | Out-Null
               New-Item -ItemType Directory -Force -Path $src    | Out-Null
               New-Item -ItemType Directory -Force -Path $lib    | Out-Null
               New-Item -ItemType Directory -Force -Path $assets | Out-Null
               New-Item -ItemType Directory -Force -Path $logs   | Out-Null
           }},

        @{ Pct = 15; Msg = "Copying icon...";
           Action = {
               if ($script:iconObject -and (Test-Path $script:iconTemp)) {
                   Copy-Item $script:iconTemp "$assets\$APP_NAME_LOW.ico" -Force
               }
           }},

        @{ Pct = 24; Msg = "Writing app.py...";
           Action = { Write-File "$src\app.py"  $FILE_DATA_SRC_APP_PY }},

        @{ Pct = 33; Msg = "Writing app.js...";
           Action = { Write-File "$src\app.js"  $FILE_DATA_SRC_APP_JS }},

        @{ Pct = 42; Msg = "Writing LICENSE...";
           Action = { Write-File "$dir\LICENSE.txt"  $FILE_LICENSE_TXT }},

        @{ Pct = 51; Msg = "Writing $APP_NAME.cmd...";
           Action = { Write-File "$data\$APP_NAME.cmd" $FILE_DATA_ALI_CMD -Ascii }},

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

        @{ Pct = 65; Msg = "Writing data\lib files...";
           Action = {
               $routerContent = $FILE_DATA_LIB_ROUTER_PS1 -replace '__APP_NAME__', $APP_NAME
               Write-File "$lib\router.ps1"  $routerContent
               Write-File "$lib\router.vbs"  $FILE_DATA_LIB_ROUTER_VBS  -Ascii
               Write-File "$lib\sendto.vbs"  $FILE_DATA_LIB_SENDTO_VBS  -Ascii
               $startupContent = $FILE_DATA_LIB_STARTUP_VBS -replace '__APP_NAME__', $APP_NAME
               Write-File "$lib\startup.vbs"      $startupContent      -Ascii
               Write-File "$lib\check-update.vbs" $FILE_DATA_LIB_CHECK_UPDATE_VBS -Ascii
           }},

        @{ Pct = 72; Msg = "Writing data\lib\uninstall.ps1...";
           Action = {
               $uninstContent = $FILE_DATA_LIB_UNINSTALL_PS1 -replace '__APP_NAME__', $APP_NAME
               Write-File "$lib\uninstall.ps1" $uninstContent
           }},

        @{ Pct = 74; Msg = "Writing data\lib\uninstall.vbs...";
           Action = { Write-File "$lib\uninstall.vbs" $FILE_DATA_LIB_UNINSTALL_VBS -Ascii }},

        @{ Pct = 76; Msg = "Writing data\lib\check-update.ps1...";
           Action = {
               $cuContent = $FILE_DATA_LIB_CHECK_UPDATE_PS1 `
                   -replace '__APP_NAME__',    $APP_NAME `
                   -replace '__APP_VERSION__', $APP_VERSION `
                   -replace '__UPDATE_URL__',  $UPDATE_URL
               Write-File "$lib\check-update.ps1" $cuContent
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

    Write-Log "Installation started -- dir: $dir"
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