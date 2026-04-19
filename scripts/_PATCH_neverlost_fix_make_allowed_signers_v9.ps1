param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("Parse-Gate missing file: " + $Path) }
  $tk=$null; $er=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tk,[ref]$er)
  if ($er -and @($er).Count -gt 0) {
    Die ("Parse-Gate error in " + $Path + ": " + (($er | Select-Object -First 1 | ForEach-Object { $_.Message })))
  }
}

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("Missing RepoRoot: " + $RepoRoot) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("Missing scripts dir: " + $ScriptsDir) }

$Make = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$TrustBundle = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$AllowedSigners = Join-Path $RepoRoot "proofs\trust\allowed_signers"

# ---- backup ----
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ScriptsDir ("_neverlost_backup_make_allowed_signers_v9_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
if (Test-Path -LiteralPath $Make -PathType Leaf) {
  Copy-Item -LiteralPath $Make -Destination (Join-Path $BackupDir "make_allowed_signers_v1.ps1.pre_v9") -Force
}

# ---- write NEW make_allowed_signers_v1.ps1 (self-contained; no NL-WriteAllowedSigners) ----
$M = New-Object System.Collections.Generic.List[string]
[void]$M.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot)')
[void]$M.Add('$ErrorActionPreference="Stop"')
[void]$M.Add('Set-StrictMode -Version Latest')
[void]$M.Add('')
[void]$M.Add('function Die([string]$m){ throw $m }')
[void]$M.Add('function Write-Utf8NoBomLf([string]$Path,[string]$Text){')
[void]$M.Add('  $dir = Split-Path -Parent $Path')
[void]$M.Add('  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }')
[void]$M.Add('  $t = $Text -replace "`r`n","`n" -replace "`r","`n"')
[void]$M.Add('  $enc = New-Object System.Text.UTF8Encoding($false)')
[void]$M.Add('  [System.IO.File]::WriteAllText($Path,$t,$enc)')
[void]$M.Add('}')
[void]$M.Add('')
[void]$M.Add('if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("Missing RepoRoot: " + $RepoRoot) }')
[void]$M.Add('$tbPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"')
[void]$M.Add('$asPath = Join-Path $RepoRoot "proofs\trust\allowed_signers"')
[void]$M.Add('if (-not (Test-Path -LiteralPath $tbPath -PathType Leaf)) { Die ("Missing trust bundle: " + $tbPath) }')
[void]$M.Add('')
[void]$M.Add('$raw = Get-Content -Raw -LiteralPath $tbPath -Encoding UTF8')
[void]$M.Add('if ([string]::IsNullOrWhiteSpace($raw)) { Die ("Empty trust bundle: " + $tbPath) }')
[void]$M.Add('$tb = $raw | ConvertFrom-Json')
[void]$M.Add('if (-not $tb) { Die ("Failed to parse trust bundle JSON: " + $tbPath) }')
[void]$M.Add('')
[void]$M.Add('# Expect: tb.keys[] with principal, public_key, namespaces (optional)')
[void]$M.Add('$keys = @(@($tb.keys))')
[void]$M.Add('if (-not $keys -or $keys.Count -lt 1) { Die "trust_bundle.json missing keys[]" }')
[void]$M.Add('')
[void]$M.Add('$lines = New-Object System.Collections.Generic.List[string]')
[void]$M.Add('foreach($k in $keys){')
[void]$M.Add('  $principal = [string]$k.principal')
[void]$M.Add('  $pubkey    = [string]$k.public_key')
[void]$M.Add('  $nsRaw     = $k.namespaces')
[void]$M.Add('  if ([string]::IsNullOrWhiteSpace($principal)) { Die "trust_bundle key missing principal" }')
[void]$M.Add('  if ([string]::IsNullOrWhiteSpace($pubkey))    { Die ("trust_bundle key for principal ''" + $principal + "'' missing public_key") }')
[void]$M.Add('  $ns = @(@($nsRaw) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })')
[void]$M.Add('  if ($ns.Count -gt 0) {')
[void]$M.Add('    $opt = ''namespaces="'' + (($ns | ForEach-Object { $_ -replace ''"'',''''} ) -join '','') + ''"''')
[void]$M.Add('    [void]$lines.Add(($principal + " " + $opt + " " + $pubkey).Trim())')
[void]$M.Add('  } else {')
[void]$M.Add('    [void]$lines.Add(($principal + " " + $pubkey).Trim())')
[void]$M.Add('  }')
[void]$M.Add('}')
[void]$M.Add('')
[void]$M.Add('$sorted = $lines.ToArray() | Sort-Object')
[void]$M.Add('Write-Utf8NoBomLf $asPath (($sorted -join "`n") + "`n")')
[void]$M.Add('Write-Host ("OK: wrote allowed_signers => " + $asPath) -ForegroundColor Green')
[void]$M.Add('')

$makeText = ($M.ToArray() -join "`n") + "`n"
Write-Utf8NoBomLf $Make $makeText
Parse-GateFile $Make

# ---- verify NL-WriteAllowedSigners is gone (hard fail if present) ----
$hits = Select-String -LiteralPath $Make -Pattern "NL-WriteAllowedSigners" -SimpleMatch -ErrorAction SilentlyContinue
if ($hits) {
  Die ("FAIL: make_allowed_signers still references NL-WriteAllowedSigners at: " + ($hits | Select-Object -First 1 | ForEach-Object { $_.Path + ":" + $_.LineNumber }))
}

Write-Host ("OK: patch v9 complete. Backup at: " + $BackupDir) -ForegroundColor Green