# ALI -- Module 0: The Installer

> Zero-budget, production-grade Windows installer. No NSIS. No Inno Setup. No paid tools. No admin rights. Just PowerShell.

This is **Module 0** of the ALI project -- the foundation everything else builds on. It took 14 years of software work to realize this approach existed, and it's completely free.

## Project structure

```
ALI/
  src/                              # Source files (edit these)
    LICENSE.txt                     # License text shown in wizard
    data/
      ALI.cmd                       # App launcher batch file
      lib/
        check-update.ps1            # Update checker (placeholders substituted at install)
        check-update.vbs            # VBS launcher for update checker (no terminal flash)
        router.ps1                  # ali:// protocol handler (placeholder substituted)
        router.vbs                  # VBS launcher for protocol handler
        sendto.vbs                  # Send To handler
        startup.vbs                 # Startup launcher (placeholder substituted)
        uninstall.ps1               # Standalone uninstaller (placeholder substituted)
        uninstall.vbs               # VBS launcher for uninstaller (no terminal flash)
      src/
        app.py                      # Python component
        app.js                      # Node.js component
  installer/                        # Installer template (edit these)
    main.ps1                        # Assembly order ({{INCLUDE:...}} directives)
    bootstrap.ps1                   # App constants, console hide, mutex, CTRL+C fix
    run.ps1                         # Form.Add_Load + Application::Run
    config/
      colors.ps1                    # Color palette constants
      state.ps1                     # Page list array + state variables
    ui/
      icon.ps1                      # Icon download logic
      factories.ps1                 # New-Label, New-NavButton, New-ActionButton
      form.ps1                      # Main form, header, body, footer, New-Page
    utils/
      controls.ps1                  # C# control compilation (references .cs files)
      utils.ps1                     # Write-File, Invoke-Async, Show-Dialog
    controls/                       # C# source files for custom WinForms controls
      DarkButton.cs                 # Fully owner-drawn dark button
      DarkProgressBar.cs            # Gradient progress bar
      DarkMode.cs                   # DWM dark title bar
    pages/                          # One file per wizard page
      00-welcome.ps1                # Welcome page
      01-license.ps1                # License agreement (4-column summary grid)
      02-deps.ps1                   # Dependency checks (Python, Node.js)
      03-location.ps1               # Install location picker
      04-confirm.ps1                # Optional features + pre-install summary
      05-install.ps1                # Progress bar page
      06-done.ps1                   # Completion page with credits/ad
      07-reinstall.ps1              # Maintenance page (repair/uninstall/update check)
      08-update.ps1                 # Update page (changelog, apply patches)
    core/
      install-helpers.ps1           # Clear-InstallAttributes, Remove-ExistingInstall
      install-steps.ps1             # Start-Installation (step-by-step file writes)
      navigation.ps1                # Show-Page function
      handlers.ps1                  # Button click handlers
  updates/                          # Update system
    latest.json                     # Current version + patch list
    patches/                        # One folder per version
      1.0.1/
        patch.json                  # Changelog, actions, metadata
        files/                      # Files to deploy (referenced by patch.json)
  build.ps1                         # Build script: template + src -> install.ps1
  install.ps1                       # Generated installer (do not edit directly)
```

---

## Running the installer

### Development

```powershell
# Run directly from local file
iex ./install.ps1

# Run from a local dev server (e.g. Live Server on port 5500)
irm http://localhost:5500/install.ps1 | iex

# Explicit execution policy bypass
powershell -ExecutionPolicy Bypass -File install.ps1

# One-liner from URL
powershell -Command "irm http://localhost:5500/install.ps1 | iex"

# Hidden window (no console flash)
powershell -WindowStyle Hidden -Command "irm http://localhost:5500/install.ps1 | iex"
```

> **Note:** `iwr` (Invoke-WebRequest) is not recommended -- use `irm` (Invoke-RestMethod) instead.

### Execution policy

If scripts are blocked on the machine, enable them for the current user:

```powershell
# Enable
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Disable (restore default)
Set-ExecutionPolicy -ExecutionPolicy Restricted -Scope CurrentUser
```

This is required if you see: `File cannot be loaded because running scripts is disabled on this system`.

### Installer log

The installer always writes a log to:
```
%TEMP%\ali_install.log
```

---

## Building

`install.ps1` is a **generated file**. Do not edit it directly -- edit files in `installer/` and `src/`, then build.

```powershell
.\build.ps1
```

### How the build works

The build starts from `installer/main.ps1`, which is a list of `{{INCLUDE:...}}` directives that define the assembly order. The build script recursively resolves three placeholder types:

| Placeholder | Replaced with |
|---|---|
| `{{INCLUDE:path}}` | Recursively processed contents of another template file |
| `{{VERSION}}` | Version string from `updates/latest.json` |
| `{{EMBED_DIR:path}}` | Scans a directory tree and emits one `$FILE_*` variable per file |

Example in `installer/bootstrap.ps1`:
```powershell
$APP_VERSION = "{{VERSION}}"
```

Example in `installer/main.ps1`:
```powershell
{{EMBED_DIR:src}}
```

This scans every file under `src/` and emits variables named after their path, e.g.:
- `src/data/lib/router.ps1` → `$FILE_DATA_LIB_ROUTER_PS1`
- `src/data/src/app.py` → `$FILE_DATA_SRC_APP_PY`
- `src/LICENSE.txt` → `$FILE_LICENSE_TXT`

These variables are then used in `install-steps.ps1` to write the files to the install directory.

Example in `installer/utils/controls.ps1`:
```powershell
$_csButton = @"
... reads DarkButton.cs at build time ...
"@
```

After build, `install.ps1` contains everything assembled and expanded into a single self-contained script.

---

## What the installer does

Presents a dark-themed GUI wizard with these pages:

1. **Welcome** -- app name, version, and license
2. **License** -- custom license text with 4-column CAN / CANNOT summary grid, required acceptance checkbox
3. **Requirements** -- checks Python and Node.js are installed, shows versions, opens download pages if missing
4. **Location** -- choose install directory (default: `%LOCALAPPDATA%\Programs\ALI`, no admin needed)
5. **Confirm** -- optional features (startup, PATH, right-click menu, Send To, Start Menu, file association, New menu)
6. **Installing** -- progress bar with step-by-step status
7. **Done** -- launch checkbox, open folder button, close/finish

### Reinstall detection

If ALI is already installed, the wizard shows a **maintenance page** instead:
- Checks for updates automatically on load
- **Repair / Reinstall** -- re-runs the full wizard
- **Uninstall** -- removes all files and registry entries
- **Open folder** -- opens the install directory in Explorer
- **Recheck** button -- polls for updates every 3 seconds

### Single-instance guard

A global mutex (`Global\ALI_Setup_Mutex`) prevents running two installers simultaneously. The second instance shows a message box and exits.

### Console hiding

The PowerShell console window is hidden immediately on script start via `ShowWindow(GetConsoleWindow(), SW_HIDE)`, so only the WinForms GUI is visible.

### Files written to the install directory

```
%LOCALAPPDATA%\Programs\ALI\
  data/
    ALI.cmd                   # Launcher: runs app.py and app.js
    assets/
      ali.ico                 # App icon (if ICON_URL is set)
    desktop.ini               # Folder icon config (hidden+system)
    lib/
      check-update.ps1        # Update checker script
      check-update.vbs        # VBS launcher (no terminal flash)
      router.ps1              # ali:// protocol handler
      router.vbs              # VBS launcher for protocol handler
      sendto.vbs              # Send To handler
      startup.vbs             # Startup launcher
      uninstall.ps1           # Uninstaller script
      uninstall.vbs           # VBS launcher for uninstaller
    logs/                     # Log directory
    src/
      app.py                  # Python component
      app.js                  # Node.js component
  ALI.lnk                     # Main launcher shortcut
  Check for Updates.lnk       # Shortcut to update checker
  Uninstall.lnk               # Shortcut to uninstaller
  LICENSE.txt                 # License file
```

### Registry entries written

**ali:// protocol handler** -- lets any browser or Run dialog open `ali://` links:
```
HKCU\SOFTWARE\Classes\ali
  (Default)   = "URL:ALI Protocol"
  URL Protocol = ""

HKCU\SOFTWARE\Classes\ali\shell\open\command
  (Default)   = powershell.exe ... router.ps1 "%1"
```

**Add/Remove Programs entry** -- appears in Settings > Apps:
```
HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ALI
  DisplayName     = "ALI 1.0.0"
  DisplayVersion  = "1.0.0"
  Publisher       = "ALI"
  InstallLocation = "..."
  UninstallString = wscript.exe "...\uninstall.vbs"
  DisplayIcon     = "...\ali.ico"
```

---

## Update system

### How updates work

1. The installer fetches `{UPDATE_URL}/latest.json` to check for newer versions
2. If a newer version exists, it fetches each patch in the chain
3. The user sees a combined changelog grouped by version
4. Patches are applied sequentially, with registry progress saved after each

### latest.json

```json
{
  "version": "1.0.0",
  "date": "2026-03-21",
  "patches": []
}
```

When releasing version 1.0.3 with three patches:
```json
{
  "version": "1.0.3",
  "date": "2026-03-25",
  "patches": [
    { "version": "1.0.1", "date": "2026-03-22" },
    { "version": "1.0.2", "date": "2026-03-23" },
    { "version": "1.0.3", "date": "2026-03-25" }
  ]
}
```

### patch.json

Each patch lives in `updates/patches/{version}/patch.json`:

```json
{
  "version": "1.0.1",
  "fromVersion": "1.0.0",
  "date": "2026-03-22",
  "description": "Bug fixes and improvements",
  "changelog": [
    "Fixed: App crash on startup",
    "Added: Dark mode support",
    "Removed: Deprecated legacy endpoint"
  ],
  "requiresLicense": false,
  "newLicense": null,
  "actions": [
    { "type": "write",  "path": "data/app.py",    "source": "files/app.py" },
    { "type": "delete", "path": "data/old_file.py" },
    { "type": "mkdir",  "path": "data/plugins" },
    { "type": "rmdir",  "path": "data/legacy" },
    { "type": "run",    "command": "echo done",    "workdir": "." }
  ]
}
```

### Patch action types

| Type | Description |
|---|---|
| `write` | Download `source` from the server and write it to `path` in the install directory |
| `delete` | Delete a file |
| `mkdir` | Create a directory |
| `rmdir` | Remove a directory tree |
| `run` | Execute a shell command (via `cmd /c`). `workdir` is relative to install dir, `.` = install root |

### Source files for write actions

Place the files to deploy under `updates/patches/{version}/files/`:
```
updates/patches/1.0.1/
  patch.json
  files/
    app.py          # referenced as "source": "files/app.py"
    app.js
```

The installer downloads from `{UPDATE_URL}/patches/{version}/{source}`.

### License updates

If a patch sets `"requiresLicense": true`, the user must accept the license before updating. If `"newLicense"` contains a string, it replaces the LICENSE file in the install directory.

### Clients that missed updates

The system handles skipped versions automatically. If a client is on v1.0.0 and the latest is v1.0.3, the installer:
1. Filters patches newer than v1.0.0 from the `patches` array in `latest.json`
2. Downloads each patch.json in version order
3. Shows a combined changelog (grouped by version)
4. Applies patches 1.0.1, then 1.0.2, then 1.0.3 sequentially
5. Saves progress to registry after each patch (so a failure mid-chain preserves partial progress)

---

## Releasing an update

Step-by-step:

1. **Edit source files** in `src/` as needed

2. **Create the patch folder:**
   ```
   updates/patches/1.0.1/
     patch.json
     files/          # any files that changed
   ```

3. **Write patch.json** with changelog, actions, and metadata

4. **Update latest.json:**
   ```json
   {
     "version": "1.0.1",
     "date": "2026-03-22",
     "patches": [
       { "version": "1.0.1", "date": "2026-03-22" }
     ]
   }
   ```

5. **Rebuild the installer:**
   ```powershell
   powershell -File build.ps1
   ```

6. **Deploy** -- upload the `updates/` folder and `install.ps1` to your server

---

## How to customize

### App name and version

Edit `updates/latest.json` for the version, and the top of `installer/bootstrap.ps1` for the name:
```powershell
$APP_NAME    = "ALI"
$APP_VERSION = "{{VERSION}}"
```

Run `build.ps1` to regenerate. Everything (window title, registry keys, shortcut name, uninstaller) updates automatically.

### Icon
```powershell
$ICON_URL = "https://your-website.com/favicon.ico"
```
When set, the installer:
- Downloads the `.ico` to `%TEMP%\ali_setup.ico`
- Sets it as the installer window icon
- Copies it to the install directory as `ali.ico`
- Uses it for the desktop shortcut, Add/Remove Programs icon, and folder icon via `desktop.ini`

Leave it empty (`""`) to skip all icon features.

### Update URL
```powershell
$UPDATE_URL = "http://127.0.0.1:5500/updates"
```
Points to the server hosting `latest.json` and patch folders. Change this to your production URL before release.

### Replace the placeholder app

Edit the files in `src/data/` -- they get embedded into `install.ps1` during build.

### Extend the ali:// router

Edit `src/data/router.ps1`. It receives the full `ali://` URL as `$Uri`. Currently it parses scheme/host/path/query and shows a dialog.

---

## Design decisions

### Why PowerShell + Windows Forms instead of NSIS or Inno Setup?

NSIS and Inno Setup require installing a build tool, learning a separate scripting language, and adding a compile step. A `.ps1` file is readable, editable, and runs on every Windows machine since Vista with zero setup. The GUI framework (`System.Windows.Forms`) and registry access are both built into Windows.

### Why HKCU instead of HKLM?

`HKEY_CURRENT_USER` requires no administrator privileges. The installer runs as a normal user with no UAC prompt. This is the same pattern used by VS Code, Spotify, Discord, and most modern per-user software.

### Why a custom DarkButton control?

Standard WinForms buttons don't support dark themes properly. `DarkButton` is a fully owner-drawn `Control` subclass compiled at runtime via `Add-Type`. It intercepts `WM_LBUTTONUP` directly for deterministic single-fire clicks and explicitly releases mouse capture to prevent the cursor from getting stuck.

### Why timer-based dependency checking?

`Update-DepStatus` calls `Invoke-Async` which pumps `DoEvents()` while waiting for subprocess results. Running this directly from a button click's `WndProc` chain causes mouse capture issues. A 50ms `System.Windows.Forms.Timer` defers the check to a clean message loop iteration.

### Why `cmd.exe /c` for all subprocess calls?

npm, pip, and other tools on Windows are `.cmd` batch files. `System.Diagnostics.ProcessStartInfo` cannot execute `.cmd` files directly. Wrapping all calls as `cmd.exe /c command args` lets cmd.exe resolve PATHEXT and handle batch files natively.

### Why single-quoted here-strings for embedded scripts?

PowerShell's double-quoted here-strings (`@"..."@`) expand `$variables`. The scripts embedded in the installer contain their own `$variables` that must survive as literals. Single-quoted here-strings (`@'...'@`) treat everything literally.

### Why `[System.IO.File]::WriteAllText` instead of `Set-Content -Encoding UTF8`?

PowerShell 5.1's `Set-Content -Encoding UTF8` prepends a UTF-8 BOM (`EF BB BF`). CMD.exe tries to execute that BOM as a command and fails. `WriteAllText` with `UTF8Encoding($false)` gives BOM-free UTF-8. Batch files get pure ASCII.

### Why explicit panel coordinates instead of Dock=Fill?

WinForms' Dock layout depends on Z-order, which is ambiguous. On Windows 11 the content panel appeared behind the header. Hardcoded `Location` and `Size` values are deterministic:

```
Header:    y=0,   h=80
Separator: y=80,  h=2
Content:   y=82,  h=263
Footer:    y=345, h=55
              Total: 400px
```

---

## Uninstalling

Run `Uninstall.lnk` from the install directory, or go to Settings > Apps > ALI > Uninstall.

The uninstaller:
- Self-relaunches from `%TEMP%` to release file handles on the install directory
- Shows a dark-themed confirmation dialog with a Shield icon
- Removes all registry entries first (file association, protocol handler, right-click menus, uninstall entry, startup run key)
- Flushes Explorer's icon/shell cache via `SHChangeNotify` after registry cleanup so `.ali` icons are released before file deletion
- Removes shortcuts (desktop, Start Menu, Send To, Startup folder, `Check for Updates.lnk`)
- Strips the install directory from the user PATH
- Removes the install directory (with attribute clearing and retry fallbacks)

---

## License

ALI Source License -- open source, plugins allowed, no competing products. See `src/LICENSE.txt`.

---

## Known Problems

1. The icon for the startup doesnt work (run on startup)

# Banner Ad - Setup & Specs

The installer's completion screen has an ad strip that displays either a banner image (loaded from a URL) or a placeholder when no URL is configured.

## Banner specifications

| Property | Value |
|---|---|
| Width | 480 px |
| Height | 82 px |
| Aspect ratio | ~5.85 : 1 |
| Format | PNG (recommended) or JPG |
| Background color | `#161b22` - matches the installer card color |
| Max file size | 200 KB (loads at install-complete time, should be instant) |

## Design tips

- Use a **dark background** (`#161b22` or similar) so the banner blends into the installer
- Keep the message short - users see this screen for only a few seconds
- A left-aligned logo + right-aligned CTA works well in the narrow strip format
- Avoid bright white backgrounds - they look jarring against the dark UI
- Test at 100% zoom (480x82 actual pixels) before publishing

## Adding it to the installer

### 1. Host the image

Upload the PNG to any static file server - your own server, GitHub, Cloudflare, etc. You need a direct image URL (not a webpage URL).

Examples:
```
https://yoursite.com/assets/ad-banner.png
https://raw.githubusercontent.com/yourname/yourrepo/main/ad.png
http://127.0.0.1:5500/ad.png
```

### 2. Set the URL in bootstrap.ps1

Open [template/bootstrap.ps1](../template/bootstrap.ps1) and fill in:

```powershell
$AD_URL  = "https://yoursite.com/assets/ad-banner.png"
$AD_LINK = "https://yoursite.com"   # opened when user clicks the banner
```

Leave `$AD_LINK` empty (`""`) to make the banner non-clickable.

### 3. Rebuild

```powershell
.\build.ps1
```

### 4. Deploy

Upload the updated `install.ps1` to your server. The banner image is **not** embedded in the installer - it's fetched at runtime when the completion screen is shown. This lets you change or rotate the ad without rebuilding the installer.

## How it works

When the installer reaches the completion page (after files are written), it attempts to download the image from `$AD_URL`:

- **Success** - displays the image in a `PictureBox` (Zoom mode). If `$AD_LINK` is set, the banner is clickable.
- **Failure** (URL empty, network error, 404) - falls back silently to the dashed placeholder with "Your Ad Here" text.

The download is synchronous but happens after installation is already complete, so a slow or failing ad server does not affect the install process.

## Removing the ad strip entirely

Delete the ad strip section from [template/pages/06-done.ps1](../template/pages/06-done.ps1) and adjust the `$chkLaunch` Y position upward to fill the space. Then rebuild.
