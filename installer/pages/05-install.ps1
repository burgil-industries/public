# =============================================================================
# PAGE 5 - INSTALLING
# =============================================================================
$pgInstall = New-Page
$pgInstall.Controls.Add((New-Label "Installing $APP_NAME..." 30 18 480 26 13 Bold $C_TEXT))

$progressBar          = New-Object DarkProgressBar
$progressBar.Location = New-Object System.Drawing.Point(30, 60)
$progressBar.Size     = New-Object System.Drawing.Size(480, 20)
$progressBar.Minimum  = 0
$progressBar.Maximum  = 100

$lblStep = New-Label "Preparing..." 30 90 480 20 10 Regular $C_DIM
$pgInstall.Controls.AddRange(@($progressBar, $lblStep))