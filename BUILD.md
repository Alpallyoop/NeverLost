# NeverLost Workbench Build

## Development

```powershell
npm install
npm run tauri dev
```

## Checks

```powershell
npm run typecheck
npm run build
cargo check --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml
```

## Release (Windows)

```powershell
npm run tauri build
.\scripts\_RUN_neverlost_release_package_smoke_v1.ps1 -RepoRoot .
```

The bundle target is MSI. `src-tauri/icons/icon.png` is the window/tray icon on Linux; `icon.ico` on Windows.
