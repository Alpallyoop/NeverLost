param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ Die "EnsureDir: empty path" }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path,$enc.GetBytes($t))
}

function Parse-GatePs1([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("PARSE_GATE_MISSING: " + $Path)
  }
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message)
  }
}

$ExpectedPrincipalGood = "single-tenant/watchtower_authority/authority/watchtower"
$ExpectedPrincipalBad  = "single-tenant/watchtower_authority/authority/not-watchtower"

$ExpectedNamespacesGood = @(
  "nfl/ingest-receipt",
  "packet/envelope",
  "watchtower",
  "watchtower/device-pledge"
)

$ExpectedNamespacesBad = @(
  "nfl/ingest-receipt",
  "packet/envelope",
  "watchtower",
  "watchtower/device-pledge-WRONG"
)

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$TrustDir = Join-Path $RepoRoot "proofs\trust"
$LibPath = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$AclPath = Join-Path $ScriptsDir "enforce_trust_acl_v1.ps1"
$TrustBundlePath = Join-Path $TrustDir "trust_bundle.json"
$MalformedPath = Join-Path $TrustDir "trust_bundle.malformed_test.json"

Parse-GatePs1 $LibPath
Parse-GatePs1 $AclPath

$PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){
  Die ("MISSING_POWERSHELL_EXE: " + $PSExe)
}

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AclPath -RepoRoot $RepoRoot | Out-Null
if($LASTEXITCODE -ne 0){
  Die ("ACL_CHILD_FAILED: " + $LASTEXITCODE)
}

. $LibPath

if(-not (Get-Command NL-LoadTrustBundleInfoV1 -ErrorAction SilentlyContinue)){ Die "VECTOR_FAIL: MISSING_FUNC NL-LoadTrustBundleInfoV1" }
if(-not (Get-Command NL-GetTrustBundleEntriesCompat -ErrorAction SilentlyContinue)){ Die "VECTOR_FAIL: MISSING_FUNC NL-GetTrustBundleEntriesCompat" }

$info = NL-LoadTrustBundleInfoV1 $RepoRoot
$entries = @(NL-GetTrustBundleEntriesCompat $info.Obj)
if($entries.Count -lt 1){
  Die ("VECTOR_FAIL: PRINCIPALS_COUNT_LT_1 actual=" + $entries.Count)
}

$principal0 = [string]$entries[0].principal
$nsActual = @($entries[0].namespaces) |
  ForEach-Object { ([string]$_).Trim() } |
  Where-Object { $_.Length -gt 0 } |
  Sort-Object -Unique

$nsExpectedGood = @($ExpectedNamespacesGood) | Sort-Object -Unique
$nsExpectedBad  = @($ExpectedNamespacesBad)  | Sort-Object -Unique

if($principal0 -ne $ExpectedPrincipalGood){
  Die ("NEVERLOST_VECTOR_POSITIVE_FAIL: PRINCIPAL actual=" + $principal0 + " expected=" + $ExpectedPrincipalGood)
}
if($nsActual.Count -ne $nsExpectedGood.Count){
  Die ("NEVERLOST_VECTOR_POSITIVE_FAIL: NAMESPACE_COUNT actual=" + $nsActual.Count + " expected=" + $nsExpectedGood.Count)
}
for($i = 0; $i -lt $nsExpectedGood.Count; $i++){
  if($nsActual[$i] -ne $nsExpectedGood[$i]){
    Die ("NEVERLOST_VECTOR_POSITIVE_FAIL: NAMESPACE idx=" + $i + " actual=" + $nsActual[$i] + " expected=" + $nsExpectedGood[$i])
  }
}
Write-Host "NEVERLOST_VECTOR_POSITIVE_OK" -ForegroundColor Green

$negativeWrongPrincipalTriggered = $false
try {
  if($principal0 -ne $ExpectedPrincipalBad){
    throw ("NEGATIVE_WRONG_PRINCIPAL_MISMATCH actual=" + $principal0 + " expected=" + $ExpectedPrincipalBad)
  }
  throw "NEGATIVE_WRONG_PRINCIPAL_DID_NOT_FAIL"
}
catch {
  $msg = $_.Exception.Message
  if($msg -like "NEGATIVE_WRONG_PRINCIPAL_MISMATCH*"){
    $negativeWrongPrincipalTriggered = $true
  } else {
    throw
  }
}
if(-not $negativeWrongPrincipalTriggered){
  Die "NEVERLOST_VECTOR_NEGATIVE_WRONG_PRINCIPAL_FAIL"
}
Write-Host "NEVERLOST_VECTOR_NEGATIVE_WRONG_PRINCIPAL_OK" -ForegroundColor Green

$negativeNamespaceTriggered = $false
try {
  if($nsActual.Count -ne $nsExpectedBad.Count){
    throw ("NEGATIVE_NAMESPACE_COUNT_MISMATCH actual=" + $nsActual.Count + " expected=" + $nsExpectedBad.Count)
  }
  for($i = 0; $i -lt $nsExpectedBad.Count; $i++){
    if($nsActual[$i] -ne $nsExpectedBad[$i]){
      throw ("NEGATIVE_NAMESPACE_VALUE_MISMATCH idx=" + $i + " actual=" + $nsActual[$i] + " expected=" + $nsExpectedBad[$i])
    }
  }
  throw "NEGATIVE_NAMESPACE_DID_NOT_FAIL"
}
catch {
  $msg = $_.Exception.Message
  if($msg -like "NEGATIVE_NAMESPACE_*"){
    $negativeNamespaceTriggered = $true
  } else {
    throw
  }
}
if(-not $negativeNamespaceTriggered){
  Die "NEVERLOST_VECTOR_NEGATIVE_NAMESPACE_FAIL"
}
Write-Host "NEVERLOST_VECTOR_NEGATIVE_NAMESPACE_OK" -ForegroundColor Green

Copy-Item -LiteralPath $TrustBundlePath -Destination $MalformedPath -Force
try {
  Write-Utf8NoBomLf -Path $MalformedPath -Text '{"schema":"neverlost.trust_bundle.v1","principals":"not-an-array"}'
  $negativeMalformedTriggered = $false
  try {
    $badInfo = NL-LoadTrustBundleInfoV1 $RepoRoot
    $badEntries = @(NL-GetTrustBundleEntriesCompat $badInfo.Obj)
    if($badEntries.Count -lt 1){
      throw "NEGATIVE_MALFORMED_SHAPE_COUNT_LT_1"
    }
    throw "NEGATIVE_MALFORMED_SHAPE_DID_NOT_FAIL"
  }
  catch {
    $msg = $_.Exception.Message
    if(
      $msg -like "NEGATIVE_MALFORMED_SHAPE_*" -or
      $msg -like "*Cannot index*" -or
      $msg -like "*method invocation failed*" -or
      $msg -like "*Cannot convert*" -or
      $msg -like "*property*cannot be found*"
    ){
      $negativeMalformedTriggered = $true
    } else {
      throw
    }
  }

  if(-not $negativeMalformedTriggered){
    Die "NEVERLOST_VECTOR_NEGATIVE_MALFORMED_SHAPE_FAIL"
  }
}
finally {
  Remove-Item -LiteralPath $MalformedPath -Force -ErrorAction SilentlyContinue
}

Write-Host "NEVERLOST_VECTOR_NEGATIVE_MALFORMED_SHAPE_OK" -ForegroundColor Green
Write-Host "NEVERLOST_VECTORS_FULL_GREEN" -ForegroundColor Green
