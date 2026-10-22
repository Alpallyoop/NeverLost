param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$PlanPath = "",
  [string]$DevRoot = "",
  [switch]$Apply
)
# Shows, and with -Apply issues, the identities in config/issuance_plan.v1.json.
#   ISSUED   the principal is already in the trust bundle (never re-issued; rotate with nl rotate)
#   READY    can be issued now
#   WAITING  needs input (node ids, device keys, a consumer's own key) - never issued by the plan
# Consumer-held public keys are found inside the consuming service's folder under the dev root
# (-DevRoot, NEVERLOST_DEV_ROOT, or the folder above this repository's family folder). Nothing outside
# NeverLost is written. Each issued item goes through scripts/issue_identity_v1.ps1 in its own process
# and the run stops at the first failure.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")
. (Join-Path $ScriptsDir "_lib_neverlost_host_v1.ps1")

if([string]::IsNullOrWhiteSpace($PlanPath)){ $PlanPath = Join-Path (Join-Path $RepoRoot "config") "issuance_plan.v1.json" }
$plan = [System.IO.File]::ReadAllText($PlanPath) | ConvertFrom-Json
if([string]$plan.schema -cne "neverlost.issuance_plan.v1"){ throw ("ISSUE_PLAN_SCHEMA: " + [string]$plan.schema) }

if([string]::IsNullOrWhiteSpace($DevRoot)){ $DevRoot = [string]$env:NEVERLOST_DEV_ROOT }
if([string]::IsNullOrWhiteSpace($DevRoot)){
  $parent = Split-Path -Parent $RepoRoot
  if((Split-Path -Leaf $parent).StartsWith("_")){ $DevRoot = Split-Path -Parent $parent } else { $DevRoot = $parent }
}

function Find-Service([string]$Id){
  if(-not (Test-Path -LiteralPath $DevRoot -PathType Container)){ return $null }
  $direct = Join-Path $DevRoot $Id
  if(Test-Path -LiteralPath $direct -PathType Container){ return $direct }
  foreach($fam in @(Get-ChildItem -LiteralPath $DevRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name.StartsWith("_") })){
    foreach($c in @(Get-ChildItem -LiteralPath $fam.FullName -Directory -ErrorAction SilentlyContinue)){ if($c.Name -ieq $Id){ return $c.FullName } }
  }
  return $null
}
function Prop($o,[string]$n){ $p = $o.PSObject.Properties[$n]; if($null -eq $p){ return $null }; return $p.Value }

$entries = NL-AssertTrustBundleV1 -RepoRoot $RepoRoot
$trusted = @{}
foreach($e in $entries){ $trusted[[string]$e.principal] = [string]$e.key_id }

$rows = @()
foreach($it in @($plan.identities)){
  $id = [string]$it.id; $principal = [string]$it.principal
  $ns = (@($it.namespaces) | ForEach-Object { [string]$_ }) -join ","
  $state = "READY"; $detail = ""; $pubPath = ""
  $needs = Prop $it "needs"
  if($needs){ $state = "WAITING"; $detail = [string]$needs }
  elseif($trusted.ContainsKey($principal)){ $state = "ISSUED"; $detail = ("key " + $trusted[$principal]) }
  elseif([string]$it.custody -eq "consumer"){
    $pk = Prop $it "pubkey"
    $svc = $null; if($pk){ $svc = Find-Service ([string]$pk.service) }
    if($null -eq $svc){ $state = "WAITING"; $detail = ("service folder '" + $(if($pk){ [string]$pk.service } else { "?" }) + "' not found under " + $DevRoot) }
    else {
      $cand = $svc; foreach($seg in ([string]$pk.path -split '[\\/]')){ if($seg){ $cand = Join-Path $cand $seg } }
      if(Test-Path -LiteralPath $cand -PathType Leaf){ $pubPath = $cand; $detail = ("enroll " + $cand) }
      else { $state = "WAITING"; $c = Prop $it "consumer_step"; $detail = ("no public key yet at " + $cand + $(if($c){ "; " + [string]$c } else { "" })) }
    }
  } else { $detail = "NeverLost generates the key" }
  $rows += [pscustomobject]@{ Id = $id; State = $state; Principal = $principal; Namespaces = $ns; Detail = $detail; Item = $it; Pub = $pubPath }
}

Write-Output ("PLAN " + $PlanPath)
Write-Output ("DEV_ROOT " + $DevRoot)
foreach($r in $rows){
  Write-Output ("[" + $r.State.PadRight(7) + "] " + $r.Id + "  " + $r.Principal + "  (" + $r.Namespaces + ")")
  if($r.Detail){ Write-Output ("          " + $r.Detail) }
}
$ready = @($rows | Where-Object { $_.State -eq "READY" })
Write-Output ("SUMMARY issued=" + @($rows | Where-Object { $_.State -eq "ISSUED" }).Count + " ready=" + $ready.Count + " waiting=" + @($rows | Where-Object { $_.State -eq "WAITING" }).Count)
if(-not $Apply){ Write-Output "ISSUE_PLAN_SHOWN"; exit 0 }
if($ready.Count -eq 0){ Write-Output "ISSUE_PLAN_NOTHING_TO_DO"; exit 0 }

$io = Join-Path (Join-Path $RepoRoot ".scratch") "issue_plan"
foreach($r in $ready){
  $a = @("-RepoRoot",$RepoRoot,"-Id",$r.Id,"-Principal",$r.Principal,"-Namespaces",$r.Namespaces,"-Consumer",[string]$r.Item.consumer)
  $kid = Prop $r.Item "key_id"; if($kid){ $a += @("-KeyId",[string]$kid) }
  if($r.Pub){ $a += @("-PubkeyPath",$r.Pub) } else { $a += "-Generate" }
  $res = NL-InvokePsFile -File (Join-Path $ScriptsDir "issue_identity_v1.ps1") -Arguments $a -StdoutPath (Join-Path $io ($r.Id + ".out")) -StderrPath (Join-Path $io ($r.Id + ".err"))
  foreach($l in ($res.Stdout -split "`n")){ if($l.Trim()){ Write-Output ("  " + $l.Trim()) } }
  if($res.ExitCode -ne 0 -or $res.Stdout.IndexOf("IDENTITY_ISSUED_OK",[System.StringComparison]::Ordinal) -lt 0){
    throw ("ISSUE_PLAN_STOPPED at " + $r.Id + ": " + $res.Stderr.Trim())
  }
  Write-Output ("ISSUED " + $r.Id)
}
$tb = Join-Path (Join-Path (Join-Path $RepoRoot "proofs") "trust") "trust_bundle.json"
Write-Output ("TRUST_BUNDLE_SHA256=" + (NL-Sha256HexFile $tb))
Write-Output "ISSUE_PLAN_APPLIED"
