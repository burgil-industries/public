# =============================================================================
# PAGE 0 - WELCOME
# =============================================================================
$pgWelcome = New-Page
$pgWelcome.Controls.AddRange(@(
    (New-Label "Welcome to $APP_NAME Setup" 30 28 480 34 16 Bold   $C_TEXT),
    (New-Label "Version $APP_VERSION  -  $APP_NAME Source License  -  Open Source" 33 70 480 20 9 Regular $C_DIM),
    (New-Label "This wizard will guide you through installing $APP_NAME" 30 112 480 20 10 Regular $C_TEXT),
    (New-Label "on your computer." 30 134 480 20 10 Regular $C_TEXT),
    (New-Label "Click Next to begin." 30 172 480 20 10 Regular $C_DIM),
    (New-Label "Creator"        30  218  68 18 9 Bold    $C_DIM),
    (New-Label "Wizard Burgil 42" 104 218 200 18 9 Regular $C_ACCENT),
    (New-Label "License"        312 218  52 18 9 Bold    $C_DIM),
    (New-Label "$APP_NAME Source License" 370 218 160 18 9 Regular $C_DIM)
))