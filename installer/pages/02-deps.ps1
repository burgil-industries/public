# =============================================================================
# PAGE 2 - DEPENDENCIES
# =============================================================================
$pgDeps = New-Page
$pgDeps.Controls.Add((New-Label "Required Software" 30 18 480 26 13 Bold $C_TEXT))
$pgDeps.Controls.Add((New-Label "The following must be installed before $APP_NAME can run:" 30 48 480 20 10 Regular $C_DIM))

$lblPy       = New-Label "Python >= $MIN_PYTHON"  30  94 140 22 10 Regular $C_TEXT
$lblPyStatus = New-Label "..."                   178  94 192 22 10

$btnGetPy           = New-ActionButton "Get Python" 375 91
$btnGetPy.Add_Click({ Start-Process "https://www.python.org/downloads/" })

$lblNode       = New-Label "Node.js >= $MIN_NODE"  30 128 140 22 10 Regular $C_TEXT
$lblNodeStatus = New-Label "..."                  178 128 192 22 10

$btnGetNode           = New-ActionButton "Get Node.js" 375 125
$btnGetNode.Add_Click({ Start-Process "https://nodejs.org/en/download/" })

$btnRecheck = New-ActionButton "Recheck" 30 167 90 28

function Start-DepCheck {
    Write-Log "Dep check started"
    # Resets labels to "Checking..." and queues Update-DepStatus via a timer.
    # Using a timer means the dep check runs AFTER the current WndProc chain
    # (including DefWndProc / mouse-capture release) has fully unwound - so
    # DoEvents calls inside the check never see a captured button.
    $lblPyStatus.Text        = "Checking..."
    $lblPyStatus.ForeColor   = $C_DIM
    $lblNodeStatus.Text      = "Checking..."
    $lblNodeStatus.ForeColor = $C_DIM
    $btnGetPy.Visible        = $false
    $btnGetNode.Visible      = $false
    $btnNext.Enabled         = $false
    if ($script:_depTimer) { $script:_depTimer.Stop() }
    $script:_depTimer = New-Object System.Windows.Forms.Timer
    $script:_depTimer.Interval = 50
    $script:_depTimer.Add_Tick({
        try { $script:_depTimer.Stop(); Update-DepStatus } catch {}
    })
    $script:_depTimer.Start()
}

function Update-DepStatus {
    # Each Invoke-Async call pumps DoEvents - a Back/Next click can fire mid-run.
    # Guard every state change so navigating away doesn't corrupt the new page.
    if ($script:idx -ne 2) { return }

    # -- Python: existence -
    $hasPy = [bool]((Invoke-Async 'where.exe' 'python').Trim())
    if ($script:idx -ne 2) { return }
    if ($hasPy) { $lblPyStatus.Text = "Detected..."; $lblPyStatus.ForeColor = $C_SUCCESS }
    else        { $lblPyStatus.Text = "Not found";   $lblPyStatus.ForeColor = $C_DANGER; $btnGetPy.Visible = $true }

    # -- Node: existence ---
    $hasNode = [bool]((Invoke-Async 'where.exe' 'node').Trim())
    if ($script:idx -ne 2) { return }
    if ($hasNode) { $lblNodeStatus.Text = "Detected..."; $lblNodeStatus.ForeColor = $C_SUCCESS }
    else          { $lblNodeStatus.Text = "Not found";   $lblNodeStatus.ForeColor = $C_DANGER; $btnGetNode.Visible = $true }

    # -- Python version, then pip appended ----------
    if ($hasPy) {
        $raw   = Invoke-Async 'python' '--version'
        if ($script:idx -ne 2) { return }
        $pyVer = if ($raw -match 'Python\s+(\S+)') { $Matches[1] } else { $raw }
        $lblPyStatus.Text = if ($pyVer) { $pyVer } else { "Detected" }

        $raw    = Invoke-Async 'pip' '--version'
        if ($script:idx -ne 2) { return }
        $pipVer = if ($raw -match '^pip\s+(\S+)') { $Matches[1] } else { '' }
        if ($pipVer) { $lblPyStatus.Text = "$pyVer  /  pip $pipVer" }
    }

    # -- Node version, then npm appended ------------
    if ($hasNode) {
        $raw     = Invoke-Async 'node' '--version'
        if ($script:idx -ne 2) { return }
        $nodeVer = if ($raw -match 'v?(\d[\d.]*)') { $Matches[1] } else { $raw }
        $lblNodeStatus.Text = if ($nodeVer) { "v$nodeVer" } else { "Detected" }

        $raw    = Invoke-Async 'npm' '--version'
        if ($script:idx -ne 2) { return }
        $npmVer = if ($raw -match '^\d') { ($raw -split '\r?\n')[0].Trim() } else { '' }
        if ($npmVer) { $lblNodeStatus.Text = "v$nodeVer  /  npm $npmVer" }
    }

    # -- Enable Next only after ALL checks complete --
    Write-Log ("Dep check done -- python={0} node={1}" -f $lblPyStatus.Text, $lblNodeStatus.Text)
    if (-not $hasPy)   { Write-Log "Python not found" "WARN" }
    if (-not $hasNode) { Write-Log "Node.js not found" "WARN" }
    if ($script:idx -eq 2) { $btnNext.Enabled = $hasPy -and $hasNode }
}

$btnRecheck.Add_Click({ Write-Log "Dep recheck requested"; Start-DepCheck })
$pgDeps.Controls.AddRange(@($lblPy, $lblPyStatus, $btnGetPy, $lblNode, $lblNodeStatus, $btnGetNode, $btnRecheck))