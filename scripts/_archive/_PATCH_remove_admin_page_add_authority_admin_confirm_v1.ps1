param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$AppPath = Join-Path $RepoRoot "src\App.tsx"
$AuthorityPath = Join-Path $RepoRoot "src\pages\Authority.tsx"
$ApiPath = Join-Path $RepoRoot "src\lib\api.ts"

foreach($p in @($AppPath,$AuthorityPath,$ApiPath)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ throw ("MISSING_FILE: " + $p) }
}

# Remove Admin page from shell.
$app = Get-Content -Raw -LiteralPath $AppPath -Encoding UTF8
$app = $app -replace 'import Admin from "\./pages/Admin"\s*', ''
$app = $app -replace '\s*\| "admin"', ''
$app = [regex]::Replace($app, '\s*\{managedMode \? \(\s*<button className=\{page === "admin" \? "active" : ""\} onClick=\{\(\) => setPage\("admin"\)\}>\s*Admin\s*</button>\s*\) : null\}', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$app = [regex]::Replace($app, '\s*\{page === "admin" && managedMode && <Admin />\}', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
[System.IO.File]::WriteAllText($AppPath,$app,(New-Object System.Text.UTF8Encoding($false)))
Write-Host "ADMIN_PAGE_REMOVED_FROM_APP_OK" -ForegroundColor Green

# Ensure adminConfirmCurrentSession API wrapper.
$api = Get-Content -Raw -LiteralPath $ApiPath -Encoding UTF8
if($api -notmatch 'adminConfirmCurrentSession'){
  $add = @(
    ''
    'export async function adminConfirmCurrentSession('
    '  mode: "local" | "managed" = "managed",'
    '): Promise<CliActionResult> {'
    '  return await invoke<CliActionResult>("admin_confirm_current_session", { mode })'
    '}'
  ) -join "`n"
  $api = $api.TrimEnd() + "`n" + $add + "`n"
}
[System.IO.File]::WriteAllText($ApiPath,$api,(New-Object System.Text.UTF8Encoding($false)))
Write-Host "ADMIN_CONFIRM_API_PRESENT_OK" -ForegroundColor Green

# Patch Authority import.
$auth = Get-Content -Raw -LiteralPath $AuthorityPath -Encoding UTF8
if($auth -notmatch 'adminConfirmCurrentSession'){
  $auth = $auth -replace 'getWorkbenchMode,', "getWorkbenchMode,`n  adminConfirmCurrentSession,"
}

# Add runAdminConfirm before timeline.
if($auth -notmatch 'async function runAdminConfirm'){
  $fn = @(
    '  async function runAdminConfirm() {'
    '    const actionMode = currentMode()'
    ''
    '    setBusy(true)'
    '    setMessage("")'
    '    setErrorMessage("")'
    ''
    '    try {'
    '      const result = await adminConfirmCurrentSession(actionMode)'
    ''
    '      setLastResult(result)'
    '      setLastMode(actionMode)'
    ''
    '      await refresh()'
    '      await emit("rebuild_tray_now")'
    ''
    '      if (result.ok) {'
    '        setMessage(`Admin confirmed current ${modeLabel(actionMode)} session.`)'
    '      } else {'
    '        setErrorMessage(`Admin confirm denied or failed: ${result.stderr || result.exit_code}`)'
    '      }'
    '    } catch (error) {'
    '      const text = error instanceof Error ? error.message : String(error)'
    '      setErrorMessage(`Admin confirm failed: ${text}`)'
    '    } finally {'
    '      setBusy(false)'
    '    }'
    '  }'
    ''
    '  const timeline = useMemo'
  ) -join "`n"
  $auth = $auth -replace '  const timeline = useMemo', $fn
}

# Insert managed-only admin confirm card before timeline.
if($auth -notmatch 'Managed Admin Confirmation'){
  $card = @(
    '{mode === "managed" ? ('
    '        <section className="card section">'
    '          <div className="card-title">Managed Admin Confirmation</div>'
    ''
    '          <div className="grid" style={{ gap: 10 }}>'
    '            <div className="muted">'
    '              Managed-mode only. Records an admin confirmation through the admin plugin path.'
    '            </div>'
    '            <div>'
    '              <button onClick={() => void runAdminConfirm()} disabled={busy || !status?.active}>'
    '                Admin Confirm Current Session'
    '              </button>'
    '            </div>'
    '          </div>'
    '        </section>'
    '      ) : null}'
    ''
    '      <section className="card section">'
    '        <div className="card-title">Authority Timeline</div>'
  ) -join "`n"
  $auth = [regex]::Replace($auth, '<section className="card section">\s*<div className="card-title">Authority Timeline</div>', $card, 1)
}

# Dynamic source display.
$auth = $auth -replace '<div className="muted">Source</div>\s*<div>workbench</div>', '<div className="muted">Source</div>' + "`n" + '                <div>{lastResult.source ?? "workbench"}</div>'

# Actor display below source.
if($auth -notmatch 'lastResult\.actor_display_name'){
  $actor = @(
    '<div>{lastResult.source ?? "workbench"}</div>'
    '              </div>'
    ''
    '              {(lastResult.actor_display_name || lastResult.actor_role) ? ('
    '                <div>'
    '                  <div className="muted">Actor</div>'
    '                  <div>'
    '                    {lastResult.actor_display_name ?? lastResult.actor_id ?? "unknown"}'
    '                    {lastResult.actor_role ? ` (${lastResult.actor_role})` : ""}'
    '                  </div>'
    '                </div>'
    '              ) : null}'
  ) -join "`n"
  $auth = $auth -replace '<div>\{lastResult\.source \?\? "workbench"\}</div>\s*</div>', $actor
}

[System.IO.File]::WriteAllText($AuthorityPath,$auth,(New-Object System.Text.UTF8Encoding($false)))
Write-Host "AUTHORITY_ADMIN_CONFIRM_ONLY_OK" -ForegroundColor Green

Set-Location $RepoRoot
npm run build
if($LASTEXITCODE -ne 0){ throw "NEVERLOST_BUILD_FAILED_AFTER_ADMIN_UI_REMOVAL" }
Write-Host "NEVERLOST_ADMIN_UI_SIMPLIFIED_BUILD_GREEN" -ForegroundColor Green
