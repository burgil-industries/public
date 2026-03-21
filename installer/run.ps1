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
[System.Windows.Forms.Application]::Run($form)