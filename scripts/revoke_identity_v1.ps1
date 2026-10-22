param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Principal,
  [string]$KeyId = ""
)
# Revokes a principal (or one of its keys) from proofs/trust/trust_bundle.json (contract
# neverlost.trust.revoke.v1). The expected principal (proofs/trust/expected_principal0.txt) cannot be
# revoked here, and the bundle can never become empty. Key files move to proofs/keys/retired/ (never
# deleted). Rebuilds allowed_signers, re-applies the ACL, appends a receipt and republishes.
# Every consumer must re-import or re-pin afterwards.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")
. (Join-Path $ScriptsDir "_lib_neverlost_host_v1.ps1")

$trustDir = Join-Path (Join-Path $RepoRoot "proofs") "trust"
$tbPath = Join-Path $trustDir "trust_bundle.json"
$expPath = Join-Path $trustDir "expected_principal0.txt"
if(Test-Path -LiteralPath $expPath -PathType Leaf){
  $exp = ([System.IO.File]::ReadAllText($expPath).Split("`n")[0]).Trim()
  if($exp -ceq $Principal){ throw ("REVOKE_REFUSED_EXPECTED_PRINCIPAL: " + $Principal + " is the expected principal of this trust root") }
}

$model = NL-ReadTrustBundleModelV1 $RepoRoot $tbPath
$target = $null; $targetIndex = -1
for($i = 0; $i -lt $model.Principals.Count; $i++){ if($model.Principals[$i].principal -ceq $Principal){ $target = $model.Principals[$i]; $targetIndex = $i } }
if($null -eq $target){ throw ("REVOKE_UNKNOWN_PRINCIPAL: " + $Principal) }

$removed = @()
if($KeyId){
  $k = @($target.keys.ToArray() | Where-Object { $_.key_id -ceq $KeyId })
  if($k.Count -lt 1){ throw ("REVOKE_UNKNOWN_KEY: " + $KeyId) }
  $removed = $k
  if($target.keys.Count -le 1){ $model.Principals.RemoveAt($targetIndex) }
  else { for($j = 0; $j -lt $target.keys.Count; $j++){ if($target.keys[$j].key_id -ceq $KeyId){ $target.keys.RemoveAt($j); break } } }
} else {
  $removed = $target.keys.ToArray()
  $model.Principals.RemoveAt($targetIndex)
}
if($model.Principals.Count -lt 1){ throw "REVOKE_REFUSED_EMPTY_BUNDLE" }

$hashes = NL-SaveTrustBundleV1 $RepoRoot $model
$asPath = NL-WriteAllowedSignersFromTrust $RepoRoot

$retDir = Join-Path (Join-Path (Join-Path $RepoRoot "proofs") "keys") "retired"
$stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$moved = @()
foreach($k in $removed){
  $stillUsed = $false
  foreach($p in $model.Principals){ foreach($kk in $p.keys){ if(([string]$kk.pubkey_path) -ceq ([string]$k.pubkey_path)){ $stillUsed = $true } } }
  if($stillUsed){ continue }
  $pub = $RepoRoot; foreach($seg in ([string]$k.pubkey_path -split '[\\/]')){ if($seg){ $pub = Join-Path $pub $seg } }
  foreach($f in @(($pub -replace '\.pub$',''), $pub)){
    if(Test-Path -LiteralPath $f -PathType Leaf){
      if(-not (Test-Path -LiteralPath $retDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $retDir | Out-Null }
      $dest = Join-Path $retDir ([System.IO.Path]::GetFileName($f) + "." + $stamp)
      Move-Item -LiteralPath $f -Destination $dest
      $moved += $dest
    }
  }
}

$acl = NL-InvokePsFile -File (Join-Path $ScriptsDir "enforce_trust_acl_v1.ps1") -Arguments @("-RepoRoot",$RepoRoot) -StdoutPath (Join-Path $RepoRoot ".scratch/revoke_acl.out") -StderrPath (Join-Path $RepoRoot ".scratch/revoke_acl.err")
if($acl.ExitCode -ne 0){ Write-Warning ("Trust ACL not re-applied (run scripts/enforce_trust_acl_v1.ps1): " + $acl.Stderr) }

$keyIds = (@($removed) | ForEach-Object { [string]$_.key_id }) -join ","
NL-AppendReceipt $RepoRoot "neverlost.trust.revoke.v1" @{ principal=$Principal; key_ids=$keyIds; trust_bundle_sha256_before=$hashes.Before; trust_bundle_sha256=$hashes.After; allowed_signers_sha256=(NL-Sha256HexFile $asPath) } | Out-Null
$pub = NL-PublishTrustV1 -RepoRoot $RepoRoot

Write-Output ("REVOKED=" + $Principal + " keys=" + $keyIds)
foreach($m in $moved){ Write-Output ("RETIRED=" + $m) }
Write-Output ("TRUST_BUNDLE_SHA256=" + $hashes.After)
Write-Output ("PUBLISHED=" + $pub)
Write-Output "IDENTITY_REVOKED_OK"
