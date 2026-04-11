# public

> **Part of [burgil-industries/computer](https://github.com/burgil-industries/computer)**
> [`computer`](https://github.com/burgil-industries/computer) → [`app`](https://github.com/burgil-industries/app) | [`installer`](https://github.com/burgil-industries/installer) | **`public`** | [`plugins`](https://github.com/burgil-industries/plugins)

---

This repository is the **web root** served at [computer.burgil.dev](https://computer.burgil.dev). It contains both static assets and the generated installer script.

## Generated files — do not edit directly

| File | How it's produced |
|---|---|
| `install.ps1` | Run `.\build.ps1` from the root repo. Assembled from `installer/` templates + embedded `app/` files + plugin files. |

```powershell
# From the computer/ root:
.\build.ps1
```

## Static files — edit directly

| File / folder | Purpose |
|---|---|
| `install.sh` | Stub that fetches and runs `install.ps1` on Linux/macOS |
| `favicon.ico` | Site favicon |
| `install.gif` | Demo GIF shown on the website |
| `ads/` | Ad images (e.g. sponsor banners) |
| `packages/index.json` | Package registry — curated bundles of plugins shown in the marketplace UI |
| `plugins/index.json` | Plugin metadata registry — individual plugin listings |
| `updates/latest.json` | **Current version** — read by `build.ps1` to stamp `{{VERSION}}` into the installer |
| `updates/patches/` | Incremental patch payloads for in-app updates |

## Versioning

`updates/latest.json` controls the version number embedded in `install.ps1`. Bump this file before running `build.ps1` to produce a new versioned build.

```json
{ "version": "1.0.1" }
```

## Layout

```
install.ps1             ← GENERATED — do not edit
install.sh              Download + run stub for Unix
favicon.ico
install.gif
ads/                    Sponsor / ad images
packages/
  index.json            Package registry
plugins/
  index.json            Plugin metadata
updates/
  latest.json           Current version (read by build.ps1)
  patches/
    <version>/
      patch.json        Patch manifest
      files/            Changed files for this patch
```
