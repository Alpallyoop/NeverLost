param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Id,
  [Parameter(Mandatory=$true)][string]$Principal,
  [Parameter(Mandatory=$true)][string]$Namespaces,
  [string]$KeyId = "",
  [string]$PubkeyPath = "",
  [switch]$Generate,
  [string]$Consumer = "",
  [switch]$Replace
)
# Issues a signing identity (contract neverlost.trust.issue.v1): a principal, one ssh-ed25519 key and the
# namespaces that key may sign, added to proofs/trust/trust_bundle.json.
#
#   -Generate     NeverLost creates the key pair in proofs/keys/<Id>_ed25519 (private key git-ignored and
#                 restricted to the current user); NeverLost holds custody, the consuming service is
#                 configured with the key's path.
#   -PubkeyPath   enroll a public key the consuming service created and keeps (consumer custody).
#   -Replace      rotate: the principal's existing key is replaced and its files moved to proofs/keys/retired/.
#
# Fail-closed order: the current bundle must verify; the candidate bundle must verify; only then is the live
# bundle replaced, allowed_signers rebuilt, the trust ACL re-applied, a receipt appended and the bundle hash
# published (proofs/published/). With -Consumer the consumer's signer list and hand-off are published too.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")
. (Join-Path $ScriptsDir "_lib_neverlost_host_v1.ps1")

function Fail([string]$Code,[string]$Detail){ throw ("ISSUE_" + $Code + $(if($Detail){ ": " + $Detail } else { "" })) }

if($Id -cnotmatch '^[a-z0-9][a-z0-9-]{0,62}$'){ Fail "ID_FORMAT" $Id }
if($Principal -cnotmatch $script:NL_PrincipalRegexV1){ Fail "PRINCIPAL_FORMAT" ($Principal + " (single-tenant/<owner|org_admin|device_admin|operator|auditor|device_agent|watchtower_authority>/<subject>)") }
$nsList = @($Namespaces.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
if($nsList.Count -lt 1){ Fail "NAMESPACES_EMPTY" "" }
foreach($n in $nsList){ if($n -cnotmatch $script:NL_NamespaceRegexV1){ Fail "NAMESPACE_FORMAT" $n } }
if(@($nsList | Select-Object -Unique).Count -ne $nsList.Count){ Fail "NAMESPACE_DUPLICATE" "" }
$nsSorted = NL-SortOrdinal ([string[]]$nsList)
if([string]::IsNullOrWhiteSpace($KeyId)){ $KeyId = $Id + "-ed25519" }
if($KeyId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$'){ Fail "KEY_ID_FORMAT" $KeyId }
if($Generate -and $PubkeyPath){ Fail "KEY_SOURCE_AMBIGUOUS" "use -Generate or -PubkeyPath, not both" }
if(-not $Generate -and -not $PubkeyPath){ Fail "KEY_SOURCE_MISSING" "use -Generate (NeverLost custody) or -PubkeyPath (consumer custody)" }
if($Consumer -and $Consumer -cnotmatch '^[a-z0-9][a-z0-9-]{0,62}$'){ Fail "CONSUMER_FORMAT" $Consumer }

$trustDir = Join-Path (Join-Path $RepoRoot "proofs") "trust"
$keysDir = Join-Path (Join-Path $RepoRoot "proofs") "keys"
$tbPath = Join-Path $trustDir "trust_bundle.json"
$model = NL-ReadTrustBundleModelV1 $RepoRoot $tbPath

# Existing principal / key id checks.
$existing = $null
foreach($p in $model.Principals){ if($p.principal -ceq $Principal){ $existing = $p } }
foreach($p in $model.Principals){
  foreach($k in $p.keys){
    if($k.key_id -ceq $KeyId -and -not ($Replace -and $p.principal -ceq $Principal)){ Fail "KEY_ID_EXISTS" ($KeyId + " (principal " + $p.principal + ")") }
  }
}
if($null -ne $existing -and -not $Replace){ Fail "PRINCIPAL_EXISTS" ($Principal + " is already issued; use -Replace to rotate its key") }
if($null -eq $existing -and $Replace){ Fail "REPLACE_UNKNOWN_PRINCIPAL" $Principal }

$ssh = NL-ResolveSshKeygen
$privPath = Join-Path $keysDir ($Id + "_ed25519")
$pubPath = $privPath + ".pub"
$pubRel = "proofs/keys/" + $Id + "_ed25519.pub"
$retired = @()

if($Replace){
  $retDir = Join-Path $keysDir "retired"
  if(-not (Test-Path -LiteralPath $retDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $retDir | Out-Null }
  $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
  foreach($f in @($privPath,$pubPath)){
    if(Test-Path -LiteralPath $f -PathType Leaf){
      $dest = Join-Path $retDir ([System.IO.Path]::GetFileName($f) + "." + $stamp)
      Move-Item -LiteralPath $f -Destination $dest
      $retired += $dest
    }
  }
}

if(-not (Test-Path -LiteralPath $keysDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $keysDir | Out-Null }
if($Generate){
  if((Test-Path -LiteralPath $privPath) -or (Test-Path -LiteralPath $pubPath)){ Fail "KEY_FILE_EXISTS" ($privPath + " (move it away or use -Replace)") }
  $kg = NL-InvokeNative -Exe $ssh -Arguments @("-q","-t","ed25519","-N","","-C",$Principal,"-f",$privPath) -NullStdin
  if($kg.Code -ne 0 -or -not (Test-Path -LiteralPath $privPath -PathType Leaf) -or -not (Test-Path -LiteralPath $pubPath -PathType Leaf)){ Fail "KEYGEN_FAILED" $kg.Output }
  NL-ProtectPrivateKey $privPath
  # Store the public key as one LF-terminated line so its hash never depends on line-ending conversion.
  $core = NL-PubkeyCore ([System.IO.File]::ReadAllText($pubPath))
  [System.IO.File]::WriteAllBytes($pubPath, (New-Object System.Text.UTF8Encoding($false)).GetBytes($core + " " + $Principal + "`n"))
  $custody = "neverlost"
} else {
  $src = (Resolve-Path -LiteralPath $PubkeyPath).Path
  $core = NL-PubkeyCore ([System.IO.File]::ReadAllText($src))
  if($core -cnotmatch $script:NL_PubkeyRegexV1){ Fail "PUBKEY_FORMAT" ($src + " is not an ssh-ed25519 public key") }
  if([System.IO.Path]::GetFullPath($src) -ne [System.IO.Path]::GetFullPath($pubPath)){
    if(Test-Path -LiteralPath $pubPath){ Fail "KEY_FILE_EXISTS" $pubPath }
    [System.IO.File]::WriteAllBytes($pubPath, (New-Object System.Text.UTF8Encoding($false)).GetBytes($core + " " + $Principal + "`n"))
  }
  $custody = "consumer"
}

# A key may be trusted under one principal only.
foreach($p in $model.Principals){
  if($p.principal -ceq $Principal){ continue }
  foreach($k in $p.keys){ if((NL-PubkeyCore $k.pubkey) -ceq $core){ Fail "KEY_ALREADY_TRUSTED" ("same key is trusted for " + $p.principal) } }
}

$newKey = [ordered]@{ key_id=$KeyId; alg="ssh-ed25519"; pubkey_path=$pubRel; pubkey_sha256=(NL-Sha256HexFile $pubPath); pubkey=$core; namespaces=[string[]]$nsSorted }
if($null -ne $existing){
  $existing.keys = New-Object System.Collections.Generic.List[object]
  [void]$existing.keys.Add($newKey)
} else {
  $keys = New-Object System.Collections.Generic.List[object]
  [void]$keys.Add($newKey)
  [void]$model.Principals.Add([ordered]@{ principal=$Principal; namespaces=$null; keys=$keys })
}

$hashes = NL-SaveTrustBundleV1 $RepoRoot $model
$asPath = NL-WriteAllowedSignersFromTrust $RepoRoot
$entries = NL-AssertTrustBundleV1 -RepoRoot $RepoRoot
NL-AssertAllowedSignersCurrentV1 $RepoRoot $entries

$acl = NL-InvokePsFile -File (Join-Path $ScriptsDir "enforce_trust_acl_v1.ps1") -Arguments @("-RepoRoot",$RepoRoot) -StdoutPath (Join-Path $RepoRoot ".scratch/issue_acl.out") -StderrPath (Join-Path $RepoRoot ".scratch/issue_acl.err")
if($acl.ExitCode -ne 0){ Write-Warning ("Trust ACL not re-applied (run scripts/enforce_trust_acl_v1.ps1): " + $acl.Stderr) }

$action = $(if($Replace){ "rotate" } else { "issue" })
NL-AppendReceipt $RepoRoot "neverlost.trust.issue.v1" @{ action=$action; principal=$Principal; key_id=$KeyId; namespaces=(@($nsSorted) -join ","); custody=$custody; consumer=$Consumer; pubkey_sha256=$newKey.pubkey_sha256; trust_bundle_sha256_before=$hashes.Before; trust_bundle_sha256=$hashes.After; allowed_signers_sha256=(NL-Sha256HexFile $asPath) } | Out-Null

$pub = NL-PublishTrustV1 -RepoRoot $RepoRoot
$handoff = $null
if($Consumer){ $handoff = NL-PublishConsumerV1 -RepoRoot $RepoRoot -Consumer $Consumer -Principal $Principal -PrivateKeyPath $(if($custody -eq "neverlost"){ $privPath } else { "" }) }

Write-Output ("PRINCIPAL=" + $Principal)
Write-Output ("KEY_ID=" + $KeyId)
Write-Output ("NAMESPACES=" + (@($nsSorted) -join ","))
Write-Output ("CUSTODY=" + $custody)
if($custody -eq "neverlost"){ Write-Output ("PRIVATE_KEY=" + $privPath) }
foreach($r in $retired){ Write-Output ("RETIRED=" + $r) }
Write-Output ("TRUST_BUNDLE_SHA256=" + $hashes.After)
Write-Output ("PUBLISHED=" + $pub)
if($handoff){ Write-Output ("HANDOFF=" + $handoff) }
Write-Output "IDENTITY_ISSUED_OK"
