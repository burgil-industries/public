# --- Page list ------------
$allPages  = @($pgWelcome, $pgLicense, $pgDeps, $pgLocation, $pgConfirm, $pgInstall, $pgDone)
$pageNames = @("Welcome", "License Agreement", "Requirements", "Install Location", "Ready to Install", "Installing...", "Installation Complete")
$script:idx = 0
$script:skipCloseConfirm = $false