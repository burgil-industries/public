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