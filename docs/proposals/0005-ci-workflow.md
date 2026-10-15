# Proposal 0005 - GitHub Actions workflow (drafted, not enabled)

| Field | Value |
|---|---|
| Status | Proposed 2026-10-15 - enable only with the owner's approval (private repositories use paid minutes) |

To enable, copy the YAML below to `.github/workflows/ci.yml`. It runs the portable proof lanes against the
committed fixture trust root (a clean clone has no `proofs/`), the frontend type check and build, and the
Rust checks and tests, on Linux (Windows PowerShell is not available there) and Windows (Windows
PowerShell 5.1, the canonical lane).

```yaml
name: ci
on:
  push:
  pull_request:
jobs:
  proof-lanes:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    env:
      NEVERLOST_TRUST_SOURCE: fixture
    steps:
      - uses: actions/checkout@v4
      - name: Proof lanes (PowerShell 7)
        shell: pwsh
        run: ./scripts/_RUN_neverlost_ci_v1.ps1 -RepoRoot .
      - name: Proof lanes (Windows PowerShell 5.1)
        if: runner.os == 'Windows'
        shell: powershell
        run: .\scripts\_RUN_neverlost_ci_v1.ps1 -RepoRoot .
  workbench:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: npm ci
      - run: npx tsc --noEmit
      - run: npm run build
      - name: Tauri system libraries
        run: sudo apt-get update && sudo apt-get install -y libwebkit2gtk-4.1-dev libgtk-3-dev libsoup-3.0-dev libjavascriptcoregtk-4.1-dev librsvg2-dev libayatana-appindicator3-dev
      - run: cargo check --manifest-path src-tauri/Cargo.toml
      - run: cargo test --manifest-path src-tauri/Cargo.toml
```
