param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$TrustBundlePath = "",
  [string]$ExpectedPrincipal = "",
  [string[]]$ExpectedNamespaces = @(),
  [switch]$UseExpectedFiles
)
# Non-mutating verifier for neverlost.trust_bundle.v1 (contract: docs/contracts/NEVERLOST_CONTRACTS_v1.md).
# Exit 0 + TRUST_BUNDLE_VERIFY_OK only when every recomputable claim holds; any defect fails closed.
# -UseExpectedFiles also checks proofs/trust/expected_principal0.txt and expected_namespaces_principal0.txt.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path (Join-Path $RepoRoot "scripts") "_lib_neverlost_v1.ps1")

if($UseExpectedFiles){
  $trustDir = Join-Path (Join-Path $RepoRoot "proofs") "trust"
  $pp = Join-Path $trustDir "expected_principal0.txt"
  $np = Join-Path $trustDir "expected_namespaces_principal0.txt"
  if(-not (Test-Path -LiteralPath $pp -PathType Leaf)){ throw ("EXPECTED_PRINCIPAL_FILE_MISSING: " + $pp) }
  $ExpectedPrincipal = ([System.IO.File]::ReadAllText($pp).Split("`n")[0]).Trim()
  if(Test-Path -LiteralPath $np -PathType Leaf){
    $ExpectedNamespaces = @([System.IO.File]::ReadAllText($np).Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
  }
}

$entries = NL-AssertTrustBundleV1 -RepoRoot $RepoRoot -TrustBundlePath $TrustBundlePath -ExpectedPrincipal $ExpectedPrincipal -ExpectedNamespaces $ExpectedNamespaces
$tbPath = $TrustBundlePath
if([string]::IsNullOrWhiteSpace($tbPath)){ $tbPath = Join-Path (Join-Path (Join-Path $RepoRoot "proofs") "trust") "trust_bundle.json" }

Write-Output ("TRUST_BUNDLE_SHA256=" + (NL-Sha256HexFile $tbPath))
Write-Output ("SIGNER_KEYS=" + @($entries).Count)
foreach($e in $entries){
  Write-Output ("SIGNER=" + [string]$e.principal + " key_id=" + [string]$e.key_id + " namespaces=" + ((@($e.namespaces)) -join ","))
}
Write-Output "TRUST_BUNDLE_VERIFY_OK"
