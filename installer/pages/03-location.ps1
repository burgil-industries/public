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