# =============================================================================
# PAGE 4 - CONFIRM
# =============================================================================
$pgConfirm = New-Page
$pgConfirm.Controls.Add((New-Label "Ready to Install" 30 18 480 26 13 Bold $C_TEXT))
$pgConfirm.Controls.Add((New-Label "Review your choices, then click Install:" 30 48 480 20 10 Regular $C_DIM))

$lblConfAppL   = New-Label "Application :"  30  86 134 22 10 Bold    $C_DIM
$lblConfAppV   = New-Label "$APP_NAME $APP_VERSION" 172  86 326 22 10 Regular $C_TEXT
$lblConfDirL   = New-Label "Location :"     30 112 134 22 10 Bold    $C_DIM
$lblConfDirV   = New-Label ""              172 112 326 22 10 Regular $C_TEXT
$lblConfScL    = New-Label "Shortcut :"     30 138 134 22 10 Bold    $C_DIM
$lblConfScV    = New-Label ""              172 138 326 22 10 Regular $C_TEXT
$lblConfProtoL = New-Label "Protocol :"     30 164 134 22 10 Bold    $C_DIM
$lblConfProtoV = New-Label "$($APP_NAME_LOW)://"        172 164 326 22 10 Regular $C_ACCENT
$lblConfUninL  = New-Label "Uninstaller :"  30 190 134 22 10 Bold    $C_DIM
$lblConfUninV  = New-Label "Yes (Add/Remove Programs)" 172 190 326 22 10 Regular $C_SUCCESS

$confirmSep           = New-Object System.Windows.Forms.Panel
$confirmSep.Location  = New-Object System.Drawing.Point(30, 218)
$confirmSep.Size      = New-Object System.Drawing.Size(480, 1)
$confirmSep.BackColor = $C_BORDER

# Optional features - 2-column grid (col1 x=30, col2 x=285)
function New-OptChk([string]$text, [int]$x, [int]$y) {
    $c           = New-Object System.Windows.Forms.CheckBox
    $c.Text      = $text
    $c.Checked   = $true
    $c.Location  = New-Object System.Drawing.Point($x, $y)
    $c.Size      = New-Object System.Drawing.Size(240, 20)
    $c.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $c.ForeColor = $C_TEXT
    $c.BackColor = $C_BG
    return $c
}

$chkStartup   = New-OptChk "Run on Startup"          30  226
$chkSendTo    = New-OptChk "Add to Send To menu"     285 226
$chkAddPath   = New-OptChk "Add to Path"              30  250
$chkStartMenu = New-OptChk "Start Menu shortcut"     285 250
$chkOpenWith  = New-OptChk "Right-click menu"         30  274
$chkFileAssoc = New-OptChk "File type (.ali)"        285 274
$chkNewMenu   = New-OptChk "New menu (.ali)"         285 298

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

# Tooltips for all optional feature checkboxes
$optTip = New-Object System.Windows.Forms.ToolTip
$optTip.SetToolTip($chkStartup,   "Launch $APP_NAME automatically when Windows starts")
$optTip.SetToolTip($chkSendTo,    "Add 'Send to $APP_NAME' to the right-click Send To submenu")
$optTip.SetToolTip($chkAddPath,   "Add $APP_NAME to PATH so you can run '$APP_NAME_LOW' from any terminal")
$optTip.SetToolTip($chkStartMenu, "Create a $APP_NAME shortcut in the Windows Start Menu")
$optTip.SetToolTip($chkOpenWith,  "Add 'Open with $APP_NAME' to the right-click menu for files and folders")
$optTip.SetToolTip($chkFileAssoc, "Open .ali files with $APP_NAME on double-click")
$optTip.SetToolTip($chkNewMenu,   "Add 'New > $APP_NAME File (.ali)' to the right-click New submenu (requires File type)")

$pgConfirm.Controls.AddRange(@(
    $lblConfAppL, $lblConfAppV, $lblConfDirL, $lblConfDirV,
    $lblConfScL,  $lblConfScV,  $lblConfProtoL, $lblConfProtoV,
    $lblConfUninL, $lblConfUninV,
    $confirmSep,
    $chkStartup, $chkSendTo, $chkAddPath, $chkStartMenu, $chkOpenWith, $chkFileAssoc, $chkNewMenu
))
