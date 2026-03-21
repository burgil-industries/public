# --- Control factories ----
function New-Label {
    param(
        [string]$Text,
        [int]$X, [int]$Y,
        [int]$W = 480, [int]$H = 22,
        [float]$FontSize = 10,
        [System.Drawing.FontStyle]$FontStyle = "Regular",
        [System.Drawing.Color]$Color = [System.Drawing.Color]::FromArgb(240, 246, 252)
    )
    $l           = New-Object System.Windows.Forms.Label
    $l.Text      = $Text
    $l.Location  = New-Object System.Drawing.Point($X, $Y)
    $l.Size      = New-Object System.Drawing.Size($W, $H)
    $l.Font      = New-Object System.Drawing.Font("Segoe UI", $FontSize, $FontStyle)
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    return $l
}

function New-NavButton {
    param([string]$Text, [int]$X)
    $b          = New-Object DarkButton
    $b.Text     = $Text
    $b.Location = New-Object System.Drawing.Point($X, 12)
    $b.Size     = New-Object System.Drawing.Size(90, 30)
    return $b
}

function New-ActionButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 115, [int]$H = 28)
    $b          = New-Object DarkButton
    $b.Text     = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size     = New-Object System.Drawing.Size($W, $H)
    $b.Corner   = 0
    return $b
}