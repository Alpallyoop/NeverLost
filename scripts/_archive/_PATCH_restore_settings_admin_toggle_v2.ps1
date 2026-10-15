Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = "C:\dev\neverlost"
$SettingsPath = Join-Path $RepoRoot "src\pages\Settings.tsx"

if(-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)){
  throw "SETTINGS_TSX_MISSING"
}

git -C $RepoRoot checkout -- src/pages/Settings.tsx

$raw = Get-Content -Raw -LiteralPath $SettingsPath -Encoding UTF8

$raw = $raw -replace 'const KEY_AUTO_START_AUTHORITY = "neverlost.settings.auto_start_authority"', "const KEY_AUTO_START_AUTHORITY = "neverlost.settings.auto_start_authority"
const KEY_ADMIN_TOOLS = "neverlost.settings.admin_tools""

$raw = $raw -replace 'const \[autoStartAuthority, setAutoStartAuthority\] = useState\(false\)', "const [autoStartAuthority, setAutoStartAuthority] = useState(false)
  const [adminTools, setAdminTools] = useState(false)"

$raw = $raw -replace 'setAutoStartAuthority\(readBool\(KEY_AUTO_START_AUTHORITY, false\)\)', "setAutoStartAuthority(readBool(KEY_AUTO_START_AUTHORITY, false))
    setAdminTools(readBool(KEY_ADMIN_TOOLS, false))"

$AdminHandler = @'
function handleAdminToolsToggle() {
    const next = !adminTools
    setAdminTools(next)
    writeBool(KEY_ADMIN_TOOLS, next)
    setMessage(next ? "Admin tools enabled for managed sessions." : "Admin tools hidden.")
  }

  async function handleVerifyIntegrity()
'@

$raw = $raw -replace 'async function handleVerifyIntegrity\(\)', $AdminHandler

$AdminCard = @'
<Card title="Admin Tools">
          <div className="grid" style={{ gap: 14 }}>
            <div>
              <div style={{ fontWeight: 700 }}>Show admin controls</div>
              <div className="muted">Hidden by default. Only applies to managed sessions.</div>
              <div style={{ marginTop: 10 }}>
                <button onClick={handleAdminToolsToggle} disabled={busy}>
                  {adminTools ? "Hide Admin Tools" : "Show Admin Tools"}
                </button>
              </div>
            </div>
          </div>
        </Card>

        <Card title="Proofs">
'@

$raw = $raw -replace '<Card title="Proofs">', $AdminCard

$CurrentValue = @'
<div>
              Admin tools:{" "}
              <span className={adminTools ? "pill pill-green" : "pill pill-neutral"}>
                {adminTools ? "Visible" : "Hidden"}
              </span>
            </div>
            <div>
              Managed mode:'@

$raw = $raw -replace '<div>\s*Managed mode:', $CurrentValue

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($SettingsPath, $raw, $enc)

Write-Host "SETTINGS_RESTORED_WITH_ADMIN_TOGGLE_OK" -ForegroundColor Green