# =============================================================================
# PAGE 1 - LICENSE
# =============================================================================
$pgLicense = New-Page
$pgLicense.Controls.Add((New-Label "License Agreement" 30 18 480 22 13 Bold $C_TEXT))

$licBox             = New-Object System.Windows.Forms.RichTextBox
$licBox.Location    = New-Object System.Drawing.Point(30, 44)
$licBox.Size        = New-Object System.Drawing.Size(480, 108)
$licBox.ReadOnly    = $true
$licBox.BackColor   = $C_INPUT
$licBox.ForeColor   = $C_TEXT
$licBox.BorderStyle = "FixedSingle"
$licBox.Font        = New-Object System.Drawing.Font("Consolas", 8)
$licBox.Text        = $FILE_LICENSE_TXT
$pgLicense.Controls.Add($licBox)

# --- 4-column summary grid ---
# Columns: [CAN 1 x=30] [CAN 2 x=152] | [CANT 1 x=276] [CANT 2 x=396]

$chk = [char]0x2713   # checkmark
$xmk = [char]0x2717   # ballot X

# Section headers
$pgLicense.Controls.Add((New-Label "$chk  YOU CAN"    30  162 238 15 8 Bold $C_SUCCESS))
$pgLicense.Controls.Add((New-Label "$xmk  YOU CANNOT" 276 162 238 15 8 Bold $C_DANGER))

# Vertical divider
$licDiv           = New-Object System.Windows.Forms.Panel
$licDiv.Location  = New-Object System.Drawing.Point(265, 160)
$licDiv.Size      = New-Object System.Drawing.Size(1, 82)
$licDiv.BackColor = $C_BORDER
$pgLicense.Controls.Add($licDiv)

# Tooltip for all summary items
$licTip = New-Object System.Windows.Forms.ToolTip

function New-LicItem([string]$t, [int]$x, [int]$y, [System.Drawing.Color]$c, [string]$tip) {
    $lbl = New-Label $t $x $y 118 14 8 Regular $c
    $licTip.SetToolTip($lbl, $tip)
    return $lbl
}

# CAN DO -- col 1 (x=30) and col 2 (x=152)
$pgLicense.Controls.AddRange(@(
    (New-LicItem "$chk Personal use"      30  181 $C_SUCCESS "Use $APP_NAME freely for personal projects, learning, and experimentation"),
    (New-LicItem "$chk Build plugins"    152  181 $C_SUCCESS "Create extensions and integrations that work with and depend on $APP_NAME"),
    (New-LicItem "$chk Modify source"     30  198 $C_SUCCESS "Edit the source code to suit your personal or internal needs"),
    (New-LicItem "$chk Share plugins"    152  198 $C_SUCCESS "Distribute your plugins to others under any license you choose"),
    (New-LicItem "$chk Run internally"    30  215 $C_SUCCESS "Deploy $APP_NAME within your organization for internal business use"),
    (New-LicItem "$chk Use licensed code" 152 215 $C_SUCCESS "Incorporate third-party libraries in your plugins if their license permits")
))

# CANNOT -- col 3 (x=276) and col 4 (x=396)
$pgLicense.Controls.AddRange(@(
    (New-LicItem "$xmk Compete with $APP_NAME"    276 181 $C_DANGER "Do not build a product whose primary purpose overlaps with $APP_NAME's core functionality"),
    (New-LicItem "$xmk Violate local laws"  396 181 $C_DANGER "You must verify that using $APP_NAME is legal in your country or region before installing"),
    (New-LicItem "$xmk Redistribute $APP_NAME"    276 198 $C_DANGER "Do not package or distribute $APP_NAME itself without prior written permission from the authors"),
    (New-LicItem "$xmk Illegal/harmful use" 396 198 $C_DANGER "Do not use $APP_NAME for fraud, malware, unauthorized system access, or any harmful activity"),
    (New-LicItem "$xmk Remove notices"      276 215 $C_DANGER "Do not remove or alter any copyright, license, or attribution notices in the source"),
    (New-LicItem "$xmk Hold liable"         396 215 $C_DANGER "Authors are not liable for any damages - you use this software entirely at your own risk")
))

# --- Disclaimer note ---
$warn = [char]0x26A0
$licWarn           = New-Object System.Windows.Forms.Label
$licWarn.Text      = "$warn  Used at your own risk -- no warranty, no liability for any damages or losses. You are solely responsible for ensuring use is legal in your region."
$licWarn.Location  = New-Object System.Drawing.Point(30, 247)
$licWarn.Size      = New-Object System.Drawing.Size(480, 30)
$licWarn.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$licWarn.ForeColor = $C_DIM
$licWarn.BackColor = [System.Drawing.Color]::Transparent
$pgLicense.Controls.Add($licWarn)

# --- Accept checkbox ---
$chkLicense           = New-Object System.Windows.Forms.CheckBox
$chkLicense.Text      = "I accept the terms of the license agreement"
$chkLicense.Location  = New-Object System.Drawing.Point(30, 286)
$chkLicense.Size      = New-Object System.Drawing.Size(480, 24)
$chkLicense.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$chkLicense.ForeColor = $C_TEXT
$chkLicense.BackColor = $C_BG
$chkLicense.Add_CheckedChanged({
    $btnNext.Enabled = $chkLicense.Checked
    if ($chkLicense.Checked) { Write-Log "License accepted" }
})
$pgLicense.Controls.Add($chkLicense)
