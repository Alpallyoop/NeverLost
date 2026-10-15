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

$ExpectedNamespaces = @(
  "nfl/ingest-receipt",
  "packet/envelope",
  "watchtower",
  "watchtower/device-pledge"
)

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$TrustDir   = Join-Path $RepoRoot "proofs\trust"
$LibPath    = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$AclPath    = Join-Path $ScriptsDir "enforce_trust_acl_v1.ps1"

Parse-GatePs1 $LibPath
Parse-GatePs1 $AclPath

$PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){ Die ("MISSING_POWERSHELL_EXE: " + $PSExe) }

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AclPath -RepoRoot $RepoRoot | Out-Null
if($LASTEXITCODE -ne 0){ Die ("ACL_CHILD_FAILED: " + $LASTEXITCODE) }

. $LibPath

if(-not (Get-Command NL-LoadTrustBundleInfoV1 -ErrorAction SilentlyContinue)){ Die "VECTOR_FAIL: MISSING_FUNC NL-LoadTrustBundleInfoV1" }
if(-not (Get-Command NL-GetTrustBundleEntriesCompat -ErrorAction SilentlyContinue)){ Die "VECTOR_FAIL: MISSING_FUNC NL-GetTrustBundleEntriesCompat" }

$info = NL-LoadTrustBundleInfoV1 $RepoRoot
$entries = @(NL-GetTrustBundleEntriesCompat $info.Obj)
if($entries.Count -lt 1){ Die ("VECTOR_FAIL: PRINCIPALS_COUNT_LT_1 actual=" + $entries.Count) }

$principal0 = [string]$entries[0].principal
$nsActual = @($entries[0].namespaces) |
  ForEach-Object { ([string]$_).Trim() } |
  Where-Object { $_.Length -gt 0 } |
  Sort-Object -Unique
$nsExpected = @($ExpectedNamespaces) | Sort-Object -Unique

# positive
if($principal0 -ne $ExpectedPrincipalGood){
  Die ("NEVERLOST_VECTOR_POSITIVE_FAIL: PRINCIPAL actual=" + $principal0 + " expected=" + $ExpectedPrincipalGood)
}
if($nsActual.Count -ne $nsExpected.Count){
  Die ("NEVERLOST_VECTOR_POSITIVE_FAIL: NAMESPACE_COUNT actual=" + $nsActual.Count + " expected=" + $nsExpected.Count)
}
for($i = 0; $i -lt $nsExpected.Count; $i++){
  if($nsActual[$i] -ne $nsExpected[$i]){
    Die ("NEVERLOST_VECTOR_POSITIVE_FAIL: NAMESPACE idx=" + $i + " actual=" + $nsActual[$i] + " expected=" + $nsExpected[$i])
  }
}
Write-Host "NEVERLOST_VECTOR_POSITIVE_OK" -ForegroundColor Green

# negative
$negativeTriggered = $false
try {
  if($principal0 -ne $ExpectedPrincipalBad){
    throw ("NEGATIVE_EXPECTED_PRINCIPAL_MISMATCH actual=" + $principal0 + " expected=" + $ExpectedPrincipalBad)
  }
  throw "NEGATIVE_VECTOR_DID_NOT_FAIL"
}
catch {
  $msg = $_.Exception.Message
  if($msg -like "NEGATIVE_EXPECTED_PRINCIPAL_MISMATCH*"){
    $negativeTriggered = $true
  } else {
    throw
  }
}

if(-not $negativeTriggered){
  Die "NEVERLOST_VECTOR_NEGATIVE_FAIL"
}

Write-Host "NEVERLOST_VECTOR_NEGATIVE_OK" -ForegroundColor Green
Write-Host "NEVERLOST_VECTORS_FULL_GREEN" -ForegroundColor Green
