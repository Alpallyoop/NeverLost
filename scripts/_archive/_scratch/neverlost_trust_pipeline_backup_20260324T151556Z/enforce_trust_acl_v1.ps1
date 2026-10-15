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

function EnsureFileExists([string]$Path,[string]$InitialText){
  $dir = Split-Path -Parent $Path
  if($dir){
    EnsureDir $dir
  }
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllBytes($Path,$enc.GetBytes($InitialText))
  }
}

function GetCurrentUser(){
  return ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
}

function Invoke-Icacls([string[]]$Args){
  & icacls @Args | Out-Null
  if($LASTEXITCODE -ne 0){
    throw ('ICACLS_FAILED: ' + ($Args -join ' '))
  }
}

function Set-DeterministicFileAcl([string]$Path,[string]$UserGrant){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ('ACL_TARGET_MISSING_FILE: ' + $Path)
  }

  $user = GetCurrentUser

  Invoke-Icacls -Args @($Path,'/inheritance:r')
  Invoke-Icacls -Args @($Path,'/remove:g','Users')
  Invoke-Icacls -Args @($Path,'/remove:g','Authenticated Users')
  Invoke-Icacls -Args @($Path,'/remove:g','Everyone')
  Invoke-Icacls -Args @($Path,'/grant:r',($user + ':'
+ $UserGrant),'SYSTEM:(F)','Administrators:(F)')
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TrustDir = Join-Path $RepoRoot 'proofs\trust'
EnsureDir $TrustDir

$TrustBundlePath = Join-Path $TrustDir 'trust_bundle.json'
$AllowedSignersPath = Join-Path $TrustDir 'allowed_signers'
$ExpectedPrincipalPath = Join-Path $TrustDir 'expected_principal0.txt'
$ExpectedNamespacesPath = Join-Path $TrustDir 'expected_namespaces_principal0.txt'

if(-not (Test-Path -LiteralPath $TrustBundlePath -PathType Leaf)){
  Die ('MISSING_TRUST_BUNDLE: ' + $TrustBundlePath)
}

EnsureFileExists -Path $AllowedSignersPath -InitialText ''
EnsureFileExists -Path $ExpectedPrincipalPath -InitialText ''
EnsureFileExists -Path $ExpectedNamespacesPath -InitialText ''

Set-DeterministicFileAcl -Path $TrustBundlePath -UserGrant '(R)'
Set-DeterministicFileAcl -Path $AllowedSignersPath -UserGrant '(M)'
Set-DeterministicFileAcl -Path $ExpectedPrincipalPath -UserGrant '(M)'
Set-DeterministicFileAcl -Path $ExpectedNamespacesPath -UserGrant '(M)'

Write-Host ('TRUST_ACL_OK: ' + $TrustDir) -ForegroundColor Green
