# --- Custom controls: DarkButton + GlowProgressBar + DarkMode ----------------
$refs = @(
    [System.Reflection.Assembly]::GetAssembly([System.Windows.Forms.Control]).Location,
    [System.Reflection.Assembly]::GetAssembly([System.Drawing.Graphics]).Location
)
$_csButton = @"
{{FILE:installer/controls/DarkButton.cs}}
"@
$_csProgress = @"
{{FILE:installer/controls/DarkProgressBar.cs}}
"@
$_csDarkMode = @"
{{FILE:installer/controls/DarkMode.cs}}
"@
if (-not ([System.Management.Automation.PSTypeName]'DarkButton').Type) {
    Add-Type -ReferencedAssemblies $refs -TypeDefinition $_csButton
}
if (-not ([System.Management.Automation.PSTypeName]'DarkProgressBar').Type) {
    Add-Type -ReferencedAssemblies $refs -TypeDefinition $_csProgress
}
if (-not ([System.Management.Automation.PSTypeName]'DarkMode').Type) {
    Add-Type -ReferencedAssemblies $refs -TypeDefinition $_csDarkMode
}