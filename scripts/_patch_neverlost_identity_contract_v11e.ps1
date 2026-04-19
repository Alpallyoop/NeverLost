param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$libPath = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
if (-not (Test-Path -LiteralPath $libPath)) { throw "Missing lib: $libPath" }
. $libPath

$trustPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$allowed   = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$rcptPath  = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"

$pubRel = "proofs/keys/watchtower_authority_ed25519.pub"
$pubAbs = Join-Path $RepoRoot "proofs\keys\watchtower_authority_ed25519.pub"
if (-not (Test-Path -LiteralPath $pubAbs)) { throw "Missing pubkey: $pubAbs" }

$principal = "single-tenant/watchtower_authority/authority/watchtower"
$keyId     = "watchtower-authority-ed25519"

# Canonicalize embedded pubkey: strip trailing comment, keep sha256 bound to file bytes
$pubRaw  = (NL-ReadUtf8 $pubAbs).Trim()
$parts   = @($pubRaw -split "\s+")
if ($parts.Count -lt 2) { throw "Invalid pubkey line in $pubAbs (expected: 'ssh-ed25519 <base64> [comment]')" }
$pubCanon = ($parts[0] + " " + $parts[1])

$bundle = [pscustomobject]@{
  schema      = "neverlost.trust_bundle.v1"
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  principals  = @(
    [pscustomobject]@{
      principal = $principal
      keys      = @(
        [pscustomobject]@{
          key_id        = $keyId
          alg           = "ssh-ed25519"
          pubkey_path   = $pubRel
          pubkey_sha256 = (NL-Sha256HexPath $pubAbs)
          pubkey        = $pubCanon
          namespaces    = @("packet/envelope","watchtower","watchtower/device-pledge","nfl/ingest-receipt")
        }
      )
    }
  )
}

NL-WriteUtf8NoBomFile $trustPath ((NL-ToCanonJson $bundle) + "`n")

# Shape proof
$tb2 = NL-ConvertFromJsonCompat (NL-ReadUtf8 $trustPath) 64
$ps  = @($tb2.principals)
if ($ps.Count -lt 1) { throw "PROOF FAILED: principals empty after write." }
foreach($p in $ps){
  if (-not ($p.PSObject.Properties.Name -contains "principal")) { throw "PROOF FAILED: principals element missing principal." }
}

# allowed_signers regeneration
[void](NL-WriteAllowedSigners $trustPath $RepoRoot $allowed)

# Receipt
NL-WriteReceipt $rcptPath @{
  schema="neverlost.receipt.v1"
  time_utc=(Get-Date).ToUniversalTime().ToString("o")
  action="patch_neverlost_identity_contract_v11e"
  ok=$true
  hashes=@{
    trust_bundle_sha256=(NL-Sha256HexPath $trustPath)
    allowed_signers_sha256=(NL-Sha256HexPath $allowed)
    lib_sha256=(NL-Sha256HexPath $libPath)
  }
}

Write-Host "OK: NeverLost v1 patched (identity contract v11e)" -ForegroundColor Green
Write-Host ("trust_bundle_sha256    : " + (NL-Sha256HexPath $trustPath))
Write-Host ("allowed_signers_sha256 : " + (NL-Sha256HexPath $allowed))
