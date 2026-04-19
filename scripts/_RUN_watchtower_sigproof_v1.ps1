param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Sha256Hex([string]$Path){
  if (-not (Test-Path -LiteralPath $Path)) { throw "sha256 path not found: $Path" }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

# --- Required tools ---
$ssh = (Get-Command ssh-keygen -ErrorAction SilentlyContinue).Source
if (-not $ssh) { throw "ssh-keygen not found on PATH. Install OpenSSH client (Windows optional feature) or ensure ssh-keygen is available." }

# --- Required files ---
$lib    = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
$make   = Join-Path $RepoRoot "scripts\make_allowed_signers_v1.ps1"
$show   = Join-Path $RepoRoot "scripts\show_identity_v1.ps1"
$sign   = Join-Path $RepoRoot "scripts\sign_file_v1.ps1"
$verify = Join-Path $RepoRoot "scripts\verify_sig_v1.ps1"

$trust  = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$as     = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$rcpt   = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"

$priv   = Join-Path $RepoRoot "proofs\keys\watchtower_authority_ed25519"
$pub    = Join-Path $RepoRoot "proofs\keys\watchtower_authority_ed25519.pub"

foreach($p in @($lib,$make,$show,$sign,$verify,$trust,$priv,$pub)){
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing required path: $p" }
}

# --- Canonical Watchtower identity ---
$Principal = "single-tenant/watchtower_authority/authority/watchtower"
$Namespace = "watchtower"

# --- Step 1: regenerate allowed_signers deterministically ---
& powershell -NoProfile -ExecutionPolicy Bypass -File $make -RepoRoot $RepoRoot

# --- Step 2: create deterministic payload ---
$payloadDir = Join-Path $RepoRoot "proofs\payloads"
if (-not (Test-Path -LiteralPath $payloadDir)) { New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null }

$payload = Join-Path $payloadDir "watchtower_sigproof_v1.txt"

# deterministic content; always ends with newline
$payloadText = "neverlost.sigproof.v1
principal=$Principal
namespace=$Namespace
utc=" + (Get-Date).ToUniversalTime().ToString("o") + "
"
[System.IO.File]::WriteAllBytes($payload, ([System.Text.UTF8Encoding]::new($false)).GetBytes($payloadText.Replace("
","
")))

# --- Step 3: sign payload (creates .sig next to file) ---
& powershell -NoProfile -ExecutionPolicy Bypass -File $sign -RepoRoot $RepoRoot -FilePath $payload -Namespace $Namespace -PrivateKeyPath $priv

$sig = ($payload + ".sig")
if (-not (Test-Path -LiteralPath $sig)) { throw "Signature not created: $sig" }

# --- Step 4: verify signature (allowed_signers -> principal+namespace) ---
& powershell -NoProfile -ExecutionPolicy Bypass -File $verify -RepoRoot $RepoRoot -FilePath $payload -SigPath $sig -Namespace $Namespace -Principal $Principal

# --- Step 5: append explicit sigproof receipt (uses NeverLost lib) ---
. $lib

NL-WriteReceipt $rcpt @{
  schema="neverlost.receipt.v1"
  time_utc=(Get-Date).ToUniversalTime().ToString("o")
  action="watchtower_sigproof_v1"
  ok=$true
  inputs=@{
    principal=$Principal
    namespace=$Namespace
    payload=$payload
    sig=$sig
  }
  hashes=@{
    trust_bundle_sha256=(Sha256Hex $trust)
    allowed_signers_sha256=(Sha256Hex $as)
    payload_sha256=(Sha256Hex $payload)
    sig_sha256=(Sha256Hex $sig)
    receipts_sha256=(Sha256Hex $rcpt)
  }
}

# --- Final print ---
Write-Host "OK: Watchtower sigproof v1 complete" -ForegroundColor Green
Write-Host ("trust_bundle_sha256     : " + (Sha256Hex $trust))
Write-Host ("allowed_signers_sha256  : " + (Sha256Hex $as))
Write-Host ("payload_sha256          : " + (Sha256Hex $payload))
Write-Host ("sig_sha256              : " + (Sha256Hex $sig))
Write-Host ("receipts_sha256         : " + (Sha256Hex $rcpt))
Write-Host ""
Write-Host ("payload_path            : " + $payload)
Write-Host ("sig_path                : " + $sig)
