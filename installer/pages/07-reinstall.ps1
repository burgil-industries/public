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

# -- Update check logic ---
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