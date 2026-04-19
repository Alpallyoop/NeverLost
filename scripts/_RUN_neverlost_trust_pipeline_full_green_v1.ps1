param([string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

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

Write-Host "RUNNER_START" -ForegroundColor Yellow

$ScriptsDir = Join-Path $RepoRoot "scripts"
$Acl = Join-Path $ScriptsDir "enforce_trust_acl_v1.ps1"
$Selftest = Join-Path $ScriptsDir "selftest_neverlost_trustbundle_v2.ps1"
$Lib = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"

if(-not (Test-Path -LiteralPath $Acl)){ throw "ACL_MISSING" }
if(-not (Test-Path -LiteralPath $Selftest)){ throw "SELFTEST_MISSING" }
if(-not (Test-Path -LiteralPath $Lib)){ throw "LIB_MISSING" }

Parse-GatePs1 $Acl
Parse-GatePs1 $Selftest
Parse-GatePs1 $Lib

. $Lib

if(-not (Get-Command NL-LoadTrustBundleInfoV1 -ErrorAction SilentlyContinue)){ Die "LIB_COMPAT_FAIL: MISSING_FUNC NL-LoadTrustBundleInfoV1" }
if(-not (Get-Command NL-GetTrustBundleEntriesCompat -ErrorAction SilentlyContinue)){ Die "LIB_COMPAT_FAIL: MISSING_FUNC NL-GetTrustBundleEntriesCompat" }
if(-not (Get-Command NL-WriteAllowedSignersFromTrust -ErrorAction SilentlyContinue)){ Die "LIB_COMPAT_FAIL: MISSING_FUNC NL-WriteAllowedSignersFromTrust" }

Write-Host "LIB_COMPAT_OK" -ForegroundColor Green

$PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){
  throw ("MISSING_POWERSHELL_EXE: " + $PSExe)
}

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Acl -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){
  throw ("ACL_CHILD_FAILED: " + $LASTEXITCODE)
}

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Selftest -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){
  throw ("SELFTEST_CHILD_FAILED: " + $LASTEXITCODE)
}

Write-Host "NEVERLOST_TRUST_PIPELINE_FULL_GREEN" -ForegroundColor Green
