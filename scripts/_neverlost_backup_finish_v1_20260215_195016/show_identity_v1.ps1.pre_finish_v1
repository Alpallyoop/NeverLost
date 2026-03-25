param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")

$trust = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$as    = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$rcpt  = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"

$tb = NL-LoadTrustBundle $trust

$asHash = ""
if (Test-Path -LiteralPath $as) { $asHash = NL-Sha256HexPath $as }

Write-Host "NeverLost v1 - Identity Layer (Watchtower contract)"
Write-Host ("trust_bundle_sha256    : " + (NL-Sha256HexPath $trust))
Write-Host ("allowed_signers_sha256 : " + $asHash)
Write-Host ("principals_count       : " + @($tb.principals).Count)
Write-Host ""

foreach($p in (@($tb.principals) | Sort-Object principal)) {
  Write-Host ("principal: " + $p.principal)
  foreach($k in (@($p.keys) | Sort-Object key_id)) {
    Write-Host ("  key_id     : " + $k.key_id)
    Write-Host ("  alg        : " + $k.alg)
    Write-Host ("  pubkey_path: " + $k.pubkey_path)
    Write-Host ("  namespaces : " + ((@($k.namespaces) | Sort-Object) -join ", "))
  }
  Write-Host ""
}

NL-WriteReceipt $rcpt @{
  schema="neverlost.receipt.v1"
  time_utc=(Get-Date).ToUniversalTime().ToString("o")
  action="show_identity"
  ok=$true
  hashes=@{
    trust_bundle_sha256=(NL-Sha256HexPath $trust)
    allowed_signers_sha256=$asHash
  }
}
