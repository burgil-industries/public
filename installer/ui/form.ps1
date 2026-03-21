# --- Main form ------------
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "$APP_NAME $APP_VERSION Setup"
$form.ClientSize      = New-Object System.Drawing.Size(540, 475)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.BackColor       = $C_BG
if ($script:iconObject) { $form.Icon = $script:iconObject }

$form.Add_Load({ [DarkMode]::Enable($form.Handle) })

$form.Add_FormClosing({
    param($s, $e)
    if ($script:idx -eq 5) { $e.Cancel = $true; return }   # block close during installation
    if ($script:skipCloseConfirm) { return }               # after uninstall, allow closing
    if ($pgReinstall.Visible -or $pgUpdate.Visible) { return }  # maintenance pages - no confirmation
    if ($script:idx -lt 6) {
        $r = Show-Dialog "Cancel Setup" "Are you sure you want to cancel the installation?" @("Yes", "No")
        if ($r -ne "Yes") { $e.Cancel = $true }
    }
})

$form.Add_FormClosed({
    if ($script:iconObject) {
        $form.Icon = $null
        $script:iconObject.Dispose()
        $script:iconObject = $null
    }
    if ($script:iconImage) {
        $script:iconImage.Dispose()
        $script:iconImage = $null
    }
    if (Test-Path $script:iconTemp) {
        Remove-Item $script:iconTemp -Force -ErrorAction SilentlyContinue
    }
})

# --- Header: y=0, h=80 ----
$header           = New-Object System.Windows.Forms.Panel
$header.Location  = New-Object System.Drawing.Point(0, 0)
$header.Size      = New-Object System.Drawing.Size(540, 80)
$header.BackColor = $C_CARD

$picIcon           = New-Object System.Windows.Forms.PictureBox
$picIcon.Location  = New-Object System.Drawing.Point(16, 12)
$picIcon.Size      = New-Object System.Drawing.Size(56, 56)
$picIcon.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picIcon.BackColor = $C_CARD

if ($script:iconImage) {
    $_bmp = New-Object System.Drawing.Bitmap(56, 56)
    $_gfx = [System.Drawing.Graphics]::FromImage($_bmp)
    $_gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $_gfx.Clear($C_CARD)
    $_gfx.DrawImage($script:iconImage, 0, 0, 56, 56)
    $_gfx.Dispose()
    $picIcon.Image   = $_bmp
    $lblTitle        = New-Label $APP_NAME  82 10 260 38 22 Bold    $C_TEXT
    $lblSubtitle     = New-Label "Welcome"  85 52 430 22 10 Regular $C_DIM
} else {
    $lblTitle        = New-Label $APP_NAME  20 10 300 38 22 Bold    $C_TEXT
    $lblSubtitle     = New-Label "Welcome"  23 52 490 22 10 Regular $C_DIM
}

$header.Controls.AddRange(@($picIcon, $lblTitle, $lblSubtitle))
$form.Controls.Add($header)

# --- Accent separator: y=80, h=2 --------------------
$hdrLine           = New-Object System.Windows.Forms.Panel
$hdrLine.Location  = New-Object System.Drawing.Point(0, 80)
$hdrLine.Size      = New-Object System.Drawing.Size(540, 2)
$hdrLine.BackColor = $C_PRIMARY
$form.Controls.Add($hdrLine)

# --- Content: y=82, h=263 -
$body           = New-Object System.Windows.Forms.Panel
$body.Location  = New-Object System.Drawing.Point(0, 82)
$body.Size      = New-Object System.Drawing.Size(540, 338)
$body.BackColor = $C_BG
$form.Controls.Add($body)

# --- Footer: y=345, h=55 --
$footer           = New-Object System.Windows.Forms.Panel
$footer.Location  = New-Object System.Drawing.Point(0, 420)
$footer.Size      = New-Object System.Drawing.Size(540, 55)
$footer.BackColor = $C_CARD
$footer.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen($C_BORDER, 1)
    $e.Graphics.DrawLine($pen, 0, 0, $footer.Width, 0)
    $pen.Dispose()
})

$btnBack   = New-NavButton "< Back"  250
$btnNext   = New-NavButton "Next >"  345
$btnCancel = New-NavButton "Cancel"  440

$btnNext.NormalColor = $C_PRIMARY
$btnNext.HoverColor  = [System.Drawing.Color]::FromArgb(56, 139, 253)
$btnNext.PressColor  = [System.Drawing.Color]::FromArgb(17,  88, 199)

$footer.Controls.AddRange(@($btnBack, $btnNext, $btnCancel))
$form.Controls.Add($footer)

# --- Page factory ---------
function New-Page {
    $p           = New-Object System.Windows.Forms.Panel
    $p.Location  = New-Object System.Drawing.Point(0, 0)
    $p.Size      = New-Object System.Drawing.Size(540, 338)
    $p.BackColor = $C_BG
    $p.Visible   = $false
    $body.Controls.Add($p)
    return $p
}