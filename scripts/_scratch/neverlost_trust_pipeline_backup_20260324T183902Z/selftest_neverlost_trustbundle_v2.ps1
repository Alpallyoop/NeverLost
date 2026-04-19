param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Die([string]$m){
  throw $m
}

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){
    Die 'EnsureDir: empty path'
  }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){
    EnsureDir $dir
  }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){
    $t += "`n"
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path,$enc.GetBytes($t))
}

$ExpectedPrincipal = 'single-tenant/watchtower_authority/authority/watchtower'
$ExpectedNamespaces = @(
  'nfl/ingest-receipt',
  'packet/envelope',
  'watchtower',
  'watchtower/device-pledge'
)

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot 'scripts'
$TrustDir = Join-Path $RepoRoot 'proofs\trust'
$LibPath = Join-Path $ScriptsDir '_lib_neverlost_v1.ps1'
$AclPath = Join-Path $ScriptsDir 'enforce_trust_acl_v1.ps1'

if(-not (Test-Path -LiteralPath $LibPath -PathType Leaf)){
  Die ('MISSING_LIB: ' + $LibPath)
}
if(-not (Test-Path -LiteralPath $AclPath -PathType Leaf)){
  Die ('MISSING_ACL_ENFORCER: ' + $AclPath)
}

$PSExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){
  Die ('MISSING_POWERSHELL_EXE: ' + $PSExe)
}

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AclPath -RepoRoot $RepoRoot | Out-Host

. $LibPath

if(-not (Get-Command NL-LoadTrustBundleInfoV1 -ErrorAction SilentlyContinue)){
  Die 'SELFTEST_FAIL: MISSING_FUNC NL-LoadTrustBundleInfoV1'
}
if(-not (Get-Command NL-GetTrustBundleEntriesCompat -ErrorAction SilentlyContinue)){
  Die 'SELFTEST_FAIL: MISSING_FUNC NL-GetTrustBundleEntriesCompat'
}
if(-not (Get-Command NL-WriteAllowedSignersFromTrust -ErrorAction SilentlyContinue)){
  Die 'SELFTEST_FAIL: MISSING_FUNC NL-WriteAllowedSignersFromTrust'
}

$info = NL-LoadTrustBundleInfoV1 $RepoRoot
$entries = @(NL-GetTrustBundleEntriesCompat $info.Obj)
if($entries.Count -lt 1){
  Die ('SELFTEST_FAIL: PRINCIPALS_COUNT_LT_1 actual=' + $entries.Count)
}

$principal0 = [string]$entries[0].principal
if([string]::IsNullOrWhiteSpace($principal0)){
  Die 'SELFTEST_FAIL: FIRST_PRINCIPAL_EMPTY'
}
if($principal0 -ne $ExpectedPrincipal){
  Die ('SELFTEST_FAIL: PRINCIPAL0_MISMATCH actual=' + $principal0 + ' expected=' + $ExpectedPrincipal)
}

$nsActual = @($entries[0].namespaces) |
  ForEach-Object { ([string]$_).Trim() } |
  Where-Object { $_.Length -gt 0 } |
  Sort-Object -Unique

$nsExpected = @($ExpectedNamespaces) | Sort-Object -Unique

if($nsActual.Count -ne $nsExpected.Count){
  Die ('SELFTEST_FAIL: NAMESPACE_COUNT_MISMATCH actual=' + $nsActual.Count + ' expected=' + $nsExpected.Count)
}

for($i = 0; $i -lt $nsExpected.Count; $i++){
  if($nsActual[$i] -ne $nsExpected[$i]){
    Die ('SELFTEST_FAIL: NAMESPACE_MISMATCH idx=' + $i + ' actual=' + $nsActual[$i] + ' expected=' + $nsExpected[$i])
  }
}

$ExpectedPrincipalPath = Join-Path $TrustDir 'expected_principal0.txt'
$ExpectedNamespacesPath = Join-Path $TrustDir 'expected_namespaces_principal0.txt'

Write-Utf8NoBomLf -Path $ExpectedPrincipalPath -Text $ExpectedPrincipal
Write-Utf8NoBomLf -Path $ExpectedNamespacesPath -Text ($nsExpected -join "`n")

$principalFile = ((Get-Content -LiteralPath $ExpectedPrincipalPath -Encoding UTF8 | Select-Object -First 1) + '').Trim()
if($principalFile -ne $ExpectedPrincipal){
  Die ('SELFTEST_FAIL: EXPECTED_PRINCIPAL_FILE_MISMATCH actual=' + $principalFile + ' expected=' + $ExpectedPrincipal)
}

$nsFile = @(Get-Content -LiteralPath $ExpectedNamespacesPath -Encoding UTF8) |
  ForEach-Object { ([string]$_).Trim() } |
  Where-Object { $_.Length -gt 0 } |
  Sort-Object -Unique

if($nsFile.Count -ne $nsExpected.Count){
  Die ('SELFTEST_FAIL: EXPECTED_NAMESPACE_FILE_COUNT_MISMATCH actual=' + $nsFile.Count + ' expected=' + $nsExpected.Count)
}

for($i = 0; $i -lt $nsExpected.Count; $i++){
  if($nsFile[$i] -ne $nsExpected[$i]){
    Die ('SELFTEST_FAIL: EXPECTED_NAMESPACE_FILE_VALUE_MISMATCH idx=' + $i + ' actual=' + $nsFile[$i] + ' expected=' + $nsExpected[$i])
  }
}

$AllowedSignersPath = NL-WriteAllowedSignersFromTrust $RepoRoot
if(-not (Test-Path -LiteralPath $AllowedSignersPath -PathType Leaf)){
  Die ('SELFTEST_FAIL: ALLOWED_SIGNERS_MISSING_AFTER_WRITE: ' + $AllowedSignersPath)
}

$firstLine = (Get-Content -LiteralPath $AllowedSignersPath -Encoding UTF8 | Select-Object -First 1)
if($null -eq $firstLine){
  Die 'SELFTEST_FAIL: ALLOWED_SIGNERS_EMPTY'
}

if(-not $firstLine.StartsWith(($ExpectedPrincipal + ' '),[System.StringComparison]::Ordinal)){
  Die ('SELFTEST_FAIL: ALLOWED_SIGNERS_PREFIX_MISMATCH actual_line=' + $firstLine)
}

Write-Host ('SELFTEST_OK: principal=' + $ExpectedPrincipal + ' namespaces=' + $nsExpected.Count + ' allowed_signers=' + $AllowedSignersPath) -ForegroundColor Green
