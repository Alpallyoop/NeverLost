param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$OutPath,
  [string]$Namespace = "",
  [string]$Consumer = "",
  [string]$TrustBundlePath = ""
)
# Publishes an OpenSSH allowed_signers file derived from the VERIFIED trust bundle for a consuming
# service (contract neverlost.allowed_signers.export.v1). With -Namespace, only keys granted that
# namespace are exported and each line is restricted to it. Consumers read the file; there is no
# runtime dependency on NeverLost. -TrustBundlePath selects a product-specific bundle (SPEC v1 section 3:
# trust bundles are separate per product); the default is proofs/trust/trust_bundle.json. Never overwrites a different existing file silently: an existing
# file with identical bytes is reported as unchanged, different bytes are replaced and receipted.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path (Join-Path $RepoRoot "scripts") "_lib_neverlost_v1.ps1")

if(-not [string]::IsNullOrWhiteSpace($Namespace) -and ($Namespace -cnotmatch $script:NL_NamespaceRegexV1)){ throw ("EXPORT_NAMESPACE_FORMAT: " + $Namespace) }

if([string]::IsNullOrWhiteSpace($TrustBundlePath)){ $TrustBundlePath = Join-Path (Join-Path (Join-Path $RepoRoot "proofs") "trust") "trust_bundle.json" }
$entries = NL-AssertTrustBundleV1 -RepoRoot $RepoRoot -TrustBundlePath $TrustBundlePath
$text = NL-AllowedSignersTextV1 -Entries $entries -Namespace $Namespace
$bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)

$full = [System.IO.Path]::GetFullPath($OutPath)
$dir = Split-Path -Parent $full
if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }

$state = "written"
if(Test-Path -LiteralPath $full -PathType Leaf){
  $old = [System.IO.File]::ReadAllBytes($full)
  if((NL-Sha256HexBytes $old) -ceq (NL-Sha256HexBytes $bytes)){ $state = "unchanged" } else { $state = "replaced" }
}
if($state -ne "unchanged"){
  $tmp = $full + ".tmp"
  [System.IO.File]::WriteAllBytes($tmp, $bytes)
  if(Test-Path -LiteralPath $full -PathType Leaf){ [System.IO.File]::Replace($tmp, $full, [NullString]::Value) } else { [System.IO.File]::Move($tmp, $full) }
}
$sha = NL-Sha256HexFile $full
if($sha -cne (NL-Sha256HexBytes $bytes)){ throw "EXPORT_WRITE_VERIFY_FAILED" }

$tbPath = $TrustBundlePath
NL-AppendReceipt $RepoRoot "neverlost.allowed_signers.export.v1" @{ consumer=$Consumer; namespace=$Namespace; out_path=$full; state=$state; allowed_signers_sha256=$sha; trust_bundle_sha256=(NL-Sha256HexFile $tbPath); signer_lines=[int](@($text.TrimEnd("`n").Split("`n")).Count) } | Out-Null

Write-Output ("EXPORT_STATE=" + $state)
Write-Output ("ALLOWED_SIGNERS_SHA256=" + $sha)
Write-Output "ALLOWED_SIGNERS_EXPORT_OK"
