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
            Write-Log "Update: patch $($pi+1)/$($chain.Count) -- v$($patch.version)"
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