# --- Icon: download to temp, shown in installer window, copied to install dir -
$script:iconTemp   = "$env:TEMP\$($APP_NAME_LOW)_setup.ico"
$script:iconObject = $null   # System.Drawing.Icon  - for the form title bar (requires real .ico)
$script:iconImage  = $null   # System.Drawing.Image - for PictureBox (accepts PNG, ICO, anything)

if ($ICON_URL) {
    try {
        if (Test-Path $script:iconTemp) { Remove-Item $script:iconTemp -Force -ErrorAction SilentlyContinue }
        (New-Object System.Net.WebClient).DownloadFile($ICON_URL, $script:iconTemp)
        $script:iconImage = [System.Drawing.Image]::FromFile($script:iconTemp)
        try { $script:iconObject = New-Object System.Drawing.Icon($script:iconTemp) } catch { }
    } catch {
        Write-Log "Icon download failed: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "Could not reach the $APP_NAME servers.`n`nPlease check your internet connection and try again later.",
            "$APP_NAME Setup",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        $script:_mutex.Dispose()
        exit
    }
}