param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Sha256Hex([string]$Path){
  if (-not (Test-Path -LiteralPath $Path)) { throw "sha256 path not found: $Path" }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$PSExe = (Get-Command powershell -ErrorAction Stop).Source

function RunPSFile([string]$File, [object[]]$Args, [string]$What){
  $Args = @(@($Args))   # force array materialization (StrictMode-safe)
  & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $File @Args
  if ($LASTEXITCODE -ne 0) { throw ("CHILD FAIL: " + $What + " exit_code=" + $LASTEXITCODE) }
}

$ssh = (Get-Command ssh-keygen -ErrorAction SilentlyContinue).Source
if (-not $ssh) { throw "ssh-keygen not found on PATH." }

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

# Canonical Watchtower identity
$Principal = "single-tenant/watchtower_authority/authority/watchtower"
$KeyId     = "watchtower-authority-ed25519"
$Namespace = "watchtower"

$payloadDir = Join-Path $RepoRoot "proofs\payloads"
if (-not (Test-Path -LiteralPath $payloadDir)) { New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null }
$payload = Join-Path $payloadDir "watchtower_sigproof_v1d.txt"
$sig     = ($payload + ".sig")

$ok = $false
$err = ""

try {
  # 1) allowed_signers regen
  RunPSFile $make @('-RepoRoot', $RepoRoot) 'make_allowed_signers'

  # 2) payload
  $payloadText = "neverlost.sigproof.v1d`nprincipal=$Principal`nkey_id=$KeyId`nnamespace=$Namespace`nutc=" + (Get-Date).ToUniversalTime().ToString("o") + "`n"
  [System.IO.File]::WriteAllBytes($payload, ([System.Text.UTF8Encoding]::new($false)).GetBytes($payloadText.Replace("`r`n","`n")))

  # 3) sign
  RunPSFile $sign @('-RepoRoot',$RepoRoot,'-FilePath',$payload,'-Namespace',$Namespace,'-Principal',$Principal,'-KeyId',$KeyId,'-PrivateKeyPath',$priv) 'sign_file'
  if (-not (Test-Path -LiteralPath $sig)) { throw "Signature not created: $sig" }

  # 4) verify (hard fail)
  RunPSFile $verify @('-RepoRoot',$RepoRoot,'-FilePath',$payload,'-SigPath',$sig,'-Namespace',$Namespace,'-Principal',$Principal) 'verify_sig'

  # optional: show identity proof
  RunPSFile $show @('-RepoRoot', $RepoRoot) 'show_identity'

  $ok = $true
} catch {
  $ok = $false
  $err = $_.Exception.Message
}

# 5) sigproof receipt always written; throws if ok=false
. $lib
NL-WriteReceipt $rcpt @{
  schema="neverlost.receipt.v1"
  time_utc=(Get-Date).ToUniversalTime().ToString("o")
  action="watchtower_sigproof_v1d"
  ok=$ok
  inputs=@{ principal=$Principal; key_id=$KeyId; namespace=$Namespace; payload=$payload; sig=$sig }
  hashes=@{
    trust_bundle_sha256=(Sha256Hex $trust)
    allowed_signers_sha256=(Sha256Hex $as)
    payload_sha256=(if (Test-Path -LiteralPath $payload) { Sha256Hex $payload } else { "" })
    sig_sha256=(if (Test-Path -LiteralPath $sig) { Sha256Hex $sig } else { "" })
    receipts_sha256=(Sha256Hex $rcpt)
  }
  error=$err
}

if (-not $ok) { throw ("SIGPROOF FAIL: " + $err) }

Write-Host "OK: Watchtower sigproof v1d complete" -ForegroundColor Green
Write-Host ("trust_bundle_sha256     : " + (Sha256Hex $trust))
Write-Host ("allowed_signers_sha256  : " + (Sha256Hex $as))
Write-Host ("payload_sha256          : " + (Sha256Hex $payload))
Write-Host ("sig_sha256              : " + (Sha256Hex $sig))
Write-Host ("receipts_sha256         : " + (Sha256Hex $rcpt))
