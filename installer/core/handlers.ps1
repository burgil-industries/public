# --- Button handlers ------
$btnNext.Add_Click({
    if ($script:idx -eq 6) {
        Write-Log "Finish clicked"
        if ($chkLaunch.Checked) {
            Write-Log "Launching $APP_NAME"
            Start-Process cmd.exe -ArgumentList "/c `"$($txtDir.Text)\data\$APP_NAME.cmd`""
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