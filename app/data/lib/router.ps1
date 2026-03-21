param([string]$Uri)

$AppName = '__APP_NAME__'

Add-Type -AssemblyName System.Windows.Forms

try {
    $parsed = [System.Uri]$Uri
    $msg    = "URI    : $Uri`nScheme : $($parsed.Scheme)`nHost   : $($parsed.Host)`nPath   : $($parsed.AbsolutePath)`nQuery  : $($parsed.Query)"
} catch {
    $msg = "Received: $Uri"
}

[System.Windows.Forms.MessageBox]::Show(
    $msg, "$AppName Protocol Handler",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
)
