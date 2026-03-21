# =============================================================================
# PAGE 6 - DONE  (setup complete + credits + ad, combined)
# =============================================================================
$pgDone = New-Page

$lblDoneTitle = New-Label "Setup complete!" 30  8 480 30 16 Bold    $C_SUCCESS
$lblDonePath  = New-Label ""               30 38 390 18  9 Regular $C_DIM

$btnOpenDir = New-ActionButton "Open folder" 420 38 90 22
$btnOpenDir.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($txtDir.Text)`"" })

$doneSep           = New-Object System.Windows.Forms.Panel
$doneSep.Location  = New-Object System.Drawing.Point(30, 64)
$doneSep.Size      = New-Object System.Drawing.Size(480, 1)
$doneSep.BackColor = $C_BORDER

# Ad strip - try to load banner image from $AD_URL, fall back to placeholder text
# $script:adStream kept alive at script scope so GC doesn't corrupt the image
$script:adImage  = $null
$script:adStream = $null
if ($AD_URL) {
    try {
        $adBytes         = (New-Object System.Net.WebClient).DownloadData($AD_URL)
        $script:adStream = New-Object System.IO.MemoryStream(,$adBytes)
        $script:adImage  = [System.Drawing.Image]::FromStream($script:adStream)
        Write-Log "Ad loaded: $AD_URL"
    } catch {
        Write-Log "Ad load failed: $_" "WARN"
    }
} else {
    Write-Log "Ad URL not set - showing placeholder"
}

$adBox           = New-Object System.Windows.Forms.Panel
$adBox.Location  = New-Object System.Drawing.Point(30, 74)
$adBox.Size      = New-Object System.Drawing.Size(480, 100)
$adBox.BackColor = $C_CARD

if ($script:adImage) {
    # Image fills full 480x82, contact text sits below it at y=83
    $adPic           = New-Object System.Windows.Forms.PictureBox
    $adPic.Location  = New-Object System.Drawing.Point(0, 0)
    $adPic.Size      = New-Object System.Drawing.Size(480, 82)
    $adPic.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
    $adPic.BackColor = $C_CARD
    $adPic.Image     = $script:adImage
    if ($AD_LINK) {
        $adPic.Cursor = [System.Windows.Forms.Cursors]::Hand
        $adPic.Add_Click({ Write-Log "Ad clicked: $AD_LINK"; Start-Process $AD_LINK })
    }
    $adBox.Controls.Add($adPic)

    $adSub                = New-Object System.Windows.Forms.LinkLabel
    $adSub.Text           = "Reach  people  installing  $APP_NAME  -  Contact us to advertise"
    $adSub.Location       = New-Object System.Drawing.Point(0, 83)
    $adSub.Size           = New-Object System.Drawing.Size(480, 16)
    $adSub.Font           = New-Object System.Drawing.Font("Segoe UI", 8)
    $adSub.TextAlign      = "MiddleCenter"
    $adSub.ForeColor      = $C_DIM
    $adSub.BackColor      = $C_CARD
    $adSub.LinkColor      = $C_ACCENT
    $adSub.ActiveLinkColor = $C_ACCENT
    $adSub.Links.Clear()
    $linkOffset = "Reach  people  installing  $APP_NAME  -  ".Length
    $adSub.Links.Add($linkOffset, "Contact us to advertise".Length, $CONTACT_US) | Out-Null
    $adSub.Add_LinkClicked({ param($s,$e) Start-Process $e.Link.LinkData })
    $adBox.Controls.Add($adSub)
} else {
    # Dashed border placeholder - "Your Ad Here" + contact line both inside the box
    $adBox.Add_Paint({
        param($s, $e)
        $dash = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 88, 166, 255), 1)
        $dash.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        $e.Graphics.DrawRectangle($dash, 2, 2, $s.Width - 5, 79)
        $dash.Dispose()
    })
    $adTitle           = New-Label "Your Ad Here" 0 16 480 24 14 Bold $C_DIM
    $adTitle.TextAlign = "MiddleCenter"
    $adSub                = New-Object System.Windows.Forms.LinkLabel
    $adSub.Text           = "Reach  people  installing  $APP_NAME  -  Contact us to advertise"
    $adSub.Location       = New-Object System.Drawing.Point(0, 48)
    $adSub.Size           = New-Object System.Drawing.Size(480, 16)
    $adSub.Font           = New-Object System.Drawing.Font("Segoe UI", 8)
    $adSub.TextAlign      = "MiddleCenter"
    $adSub.ForeColor      = $C_DIM
    $adSub.BackColor      = $C_CARD
    $adSub.LinkColor      = $C_ACCENT
    $adSub.ActiveLinkColor = $C_ACCENT
    $adSub.Links.Clear()
    $linkOffset = "Reach  people  installing  $APP_NAME  -  ".Length
    $adSub.Links.Add($linkOffset, "Contact us to advertise".Length, $CONTACT_US) | Out-Null
    $adSub.Add_LinkClicked({ param($s,$e) Start-Process $e.Link.LinkData })
    $adBox.Controls.Add($adTitle)
    $adBox.Controls.Add($adSub)
}

# Checkboxes
$chkLaunch           = New-Object System.Windows.Forms.CheckBox
$chkLaunch.Text      = "Launch $APP_NAME now"
$chkLaunch.Checked   = $true
$chkLaunch.Location  = New-Object System.Drawing.Point(30, 186)
$chkLaunch.Size      = New-Object System.Drawing.Size(480, 22)
$chkLaunch.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$chkLaunch.ForeColor = $C_TEXT
$chkLaunch.BackColor = $C_BG

$pgDone.Controls.AddRange(@($lblDoneTitle, $lblDonePath, $btnOpenDir, $doneSep, $adBox, $chkLaunch))
