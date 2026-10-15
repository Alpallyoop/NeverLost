param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function GetUser(){ return ("$env:USERDOMAIN\$env:USERNAME") }

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ Die "EnsureDir: empty" }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function EnsureFileExists([string]$p,[string]$initial){
  $dir = Split-Path -Parent $p
  if($dir){ EnsureDir $dir }
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    [System.IO.File]::WriteAllBytes(
      $p,
      (New-Object System.Text.UTF8Encoding($false)).GetBytes($initial)
    )
  }
}

function SetFileAcl([string]$Path,[string]$UserRights){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("ACL_TARGET_MISSING_FILE: " + $Path) }

  $user = GetUser

  & icacls $Path /inheritance:r | Out-Host
  & icacls $Path /remove:d "${user}" | Out-Host
  & icacls $Path /remove:d "Users" | Out-Host
  & icacls $Path /remove:d "Authenticated Users" | Out-Host
  & icacls $Path /remove:d "Everyone" | Out-Host
  & icacls $Path /grant:r "${user}:${UserRights}" "SYSTEM:F" "Administrators:F" | Out-Host
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TrustDir = Join-Path $RepoRoot "proofs\trust"
EnsureDir $TrustDir

$tb = Join-Path $TrustDir "trust_bundle.json"
if(-not (Test-Path -LiteralPath $tb -PathType Leaf)){ Die ("MISSING_TRUST_BUNDLE: " + $tb) }

$as = Join-Path $TrustDir "allowed_signers"
$p0 = Join-Path $TrustDir "expected_principal0.txt"
$ns = Join-Path $TrustDir "expected_namespaces_principal0.txt"

EnsureFileExists $as ""
EnsureFileExists $p0 ""
EnsureFileExists $ns ""

SetFileAcl $tb "(R)"
SetFileAcl $as "(M)"
SetFileAcl $p0 "(M)"
SetFileAcl $ns "(M)"

Write-Host ("TRUST_ACL_OK: " + $TrustDir) -ForegroundColor Green
