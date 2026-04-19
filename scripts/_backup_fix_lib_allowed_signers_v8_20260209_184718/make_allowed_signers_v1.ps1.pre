param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")

$trust = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$out   = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$rcpt  = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"

[void](NL-WriteAllowedSigners $trust $RepoRoot $out)

NL-WriteReceipt $rcpt @{
  schema="neverlost.receipt.v1"
  time_utc=(Get-Date).ToUniversalTime().ToString("o")
  action="make_allowed_signers"
  ok=$true
  hashes=@{
    trust_bundle_sha256=(NL-Sha256HexPath $trust)
    allowed_signers_sha256=(NL-Sha256HexPath $out)
  }
}