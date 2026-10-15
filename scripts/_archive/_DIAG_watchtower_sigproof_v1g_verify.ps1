param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Sha256Hex([string]$Path){
  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$PSExe = (Get-Command powershell -ErrorAction Stop).Source

# Canonical Watchtower identity
$Principal = "single-tenant/watchtower_authority/authority/watchtower"
$KeyId     = "watchtower-authority-ed25519"
$Namespace = "watchtower"

# Paths
$make   = Join-Path $RepoRoot "scripts\make_allowed_signers_v1.ps1"
$show   = Join-Path $RepoRoot "scripts\show_identity_v1.ps1"
$sign   = Join-Path $RepoRoot "scripts\sign_file_v1.ps1"
$verify = Join-Path $RepoRoot "scripts\verify_sig_v1.ps1"

$trust  = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$as     = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$rcpt   = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"

$payload = Join-Path $RepoRoot "proofs\payloads\watchtower_sigproof_v1g.txt"
$sig     = ($payload + ".sig")

foreach($p in @($make,$show,$sign,$verify,$trust,$rcpt)){
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing required path: $p" }
}

if (-not (Test-Path -LiteralPath $payload)) { throw "Missing payload (expected from v1g): $payload" }
if (-not (Test-Path -LiteralPath $sig))     { throw "Missing sig (expected from v1g): $sig" }

Write-Host "=== DIAG: CURRENT FILE HASHES ===" -ForegroundColor Cyan
Write-Host ("trust_bundle_sha256    : " + (Sha256Hex $trust))
Write-Host ("allowed_signers_sha256 : " + (Sha256Hex $as))
Write-Host ("payload_sha256         : " + (Sha256Hex $payload))
Write-Host ("sig_sha256             : " + (Sha256Hex $sig))
Write-Host ("receipts_sha256        : " + (Sha256Hex $rcpt))
Write-Host ""

# 1) Ensure allowed_signers matches trust_bundle (regen)
Write-Host "=== STEP 1: make_allowed_signers ===" -ForegroundColor Cyan
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $make -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) { throw ("make_allowed_signers exit_code=" + $LASTEXITCODE) }
Write-Host "OK: make_allowed_signers" -ForegroundColor Green
Write-Host ("allowed_signers_sha256 : " + (Sha256Hex $as))
Write-Host ""

# 2) Verify existing signature (NO wrappers)
Write-Host "=== STEP 2: verify_sig (existing payload+sig) ===" -ForegroundColor Cyan
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $verify -RepoRoot $RepoRoot -FilePath $payload -SigPath $sig -Namespace $Namespace -Principal $Principal
if ($LASTEXITCODE -ne 0) { throw ("verify_sig exit_code=" + $LASTEXITCODE) }
Write-Host "OK: verify_sig" -ForegroundColor Green
Write-Host ""

# 3) show_identity proof (for sanity)
Write-Host "=== STEP 3: show_identity ===" -ForegroundColor Cyan
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $show -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) { throw ("show_identity exit_code=" + $LASTEXITCODE) }
Write-Host ""

# 4) Print last receipt lines (evidence)
Write-Host "=== STEP 4: receipts tail ===" -ForegroundColor Cyan
$tail = Get-Content -LiteralPath $rcpt -Encoding UTF8 -Tail 8
$tail | ForEach-Object { Write-Host $_ }
Write-Host ""

Write-Host "OK: DIAG complete (verify is working)" -ForegroundColor Green
