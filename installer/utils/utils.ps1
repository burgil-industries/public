# --- Encoding-safe file writer ----------------------
function Write-File {
    param([string]$Path, [string]$Content, [switch]$Ascii)
    $enc = if ($Ascii) { [System.Text.Encoding]::ASCII } else { New-Object System.Text.UTF8Encoding($false) }
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

# --- Non-blocking subprocess helper ----------------
# Runs a process and pumps DoEvents every 50 ms while waiting, so the UI stays
# responsive. Returns combined stdout+stderr trimmed - use for version commands
# (python --version writes to stderr on Python 2).
function Invoke-Async {
    param([string]$Command, [string]$Arguments = '')
    # Always run through cmd.exe so .cmd/.bat scripts (npm, pip, etc.) resolve
    # correctly via PATHEXT without needing the full path or extension.
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo('cmd.exe', "/c $Command $Arguments")
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow         = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        while (-not $p.WaitForExit(50)) {
            [System.Windows.Forms.Application]::DoEvents()
        }
        return ($p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd()).Trim()
    } catch { return '' }
}

# --- Modern dark dialog (replaces MessageBox::Show) 
function Show-Dialog {
    param([string]$Title, [string]$Message, [string[]]$Buttons = @("OK"))
    # Use a single-element array as a captured-by-reference result box.
    # Avoids $script: scope issues inside nested ShowDialog message loops.
    # Default = last button (what X / no-choice means).
    $res = @($Buttons[$Buttons.Count - 1])

    $d = New-Object System.Windows.Forms.Form
    $d.Text            = $Title
    $d.ClientSize      = New-Object System.Drawing.Size(420, 100)
    $d.StartPosition   = "CenterScreen"
    $d.FormBorderStyle = "FixedDialog"
    $d.MaximizeBox     = $false
    $d.MinimizeBox     = $false
    $d.BackColor       = $C_CARD
    $d.Add_Load({ [DarkMode]::Enable($d.Handle) }.GetNewClosure())

    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Text      = $Message
    $lbl.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
    $lbl.ForeColor = $C_TEXT
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $maxW = 380
    $size = [System.Windows.Forms.TextRenderer]::MeasureText(
        $Message, $lbl.Font,
        (New-Object System.Drawing.Size($maxW, 0)),
        [System.Windows.Forms.TextFormatFlags]::WordBreak)
    $lbl.Location  = New-Object System.Drawing.Point(20, 12)
    $lbl.Size      = New-Object System.Drawing.Size($maxW, $size.Height)
    $d.Controls.Add($lbl)

    $minH    = 84
    $dialogH = [Math]::Max($minH, $lbl.Bottom + 50)
    $d.ClientSize = New-Object System.Drawing.Size(420, $dialogH)

    $btnW   = 90
    $gap    = 10
    $total  = ($btnW * $Buttons.Count) + ($gap * ($Buttons.Count - 1))
    $startX = (420 - $total) / 2
    $btnY   = $d.ClientSize.Height - 42

    for ($i = 0; $i -lt $Buttons.Count; $i++) {
        $label = $Buttons[$i]
        $btn   = New-Object System.Windows.Forms.Button
        $btn.Text     = $label
        $btn.FlatStyle = "Flat"
        $btn.FlatAppearance.BorderColor = $C_BORDER
        $btn.FlatAppearance.BorderSize  = 1
        $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38, 44, 52)
        $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(24, 28, 34)
        $btn.BackColor = $C_CARD
        $btn.ForeColor = $C_TEXT
        $btn.UseVisualStyleBackColor = $false
        $btn.Font   = New-Object System.Drawing.Font("Segoe UI", 9.5)
        $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btn.TabStop = $false
        $btn.Location = New-Object System.Drawing.Point(($startX + $i * ($btnW + $gap)), $btnY)
        $btn.Size     = New-Object System.Drawing.Size($btnW, 30)
        $btn.Add_Click({
            $res[0] = $label   # write into the shared reference box
            $d.Close()         # close dialog; ShowDialog returns
        }.GetNewClosure())
        $d.Controls.Add($btn)
    }

    $d.ShowDialog() | Out-Null
    return $res[0]
}