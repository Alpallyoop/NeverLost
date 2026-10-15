param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ Ensure-Dir $dir }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $u = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path, $u.GetBytes($t))
}
function Parse-GatePs1([string]$p){ [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $p -Encoding UTF8)) }
function Die([string]$m){ throw $m }

$Scripts = Join-Path $RepoRoot "scripts"
$LibPath = Join-Path $Scripts "_lib_neverlost_v1.ps1"
$MakePath = Join-Path $Scripts "make_allowed_signers_v1.ps1"
$ShowPath = Join-Path $Scripts "show_identity_v1.ps1"
$TBPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"

if(-not (Test-Path -LiteralPath $LibPath -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }
if(-not (Test-Path -LiteralPath $MakePath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $MakePath) }
if(-not (Test-Path -LiteralPath $ShowPath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $ShowPath) }
if(-not (Test-Path -LiteralPath $TBPath -PathType Leaf)){ Die ("MISSING_TRUST_BUNDLE: " + $TBPath) }

# --- quick visibility: what keys exist? (helps confirm shape) ---
$tbObj = (Get-Content -Raw -LiteralPath $TBPath -Encoding UTF8 | ConvertFrom-Json)
$tbProps = @(@($tbObj.PSObject.Properties | ForEach-Object { $_.Name }))
Write-Host ("TRUST_BUNDLE_TOP_KEYS: " + ($tbProps -join ", ")) -ForegroundColor DarkGray

# --- patch _lib: add Get-TrustBundleSigners helper if missing ---
$lib = Get-Content -Raw -LiteralPath $LibPath -Encoding UTF8
if($lib -notmatch "(?im)^\s*function\s+Get-TrustBundleSigners\s*\("){
  $inject = @()
  $inject += ""
  $inject += "function Get-TrustBundleSigners([object]$TrustBundle){"
  $inject += "  # Schema-tolerant signer extraction (StrictMode-safe)"
  $inject += "  if($null -eq $TrustBundle){ return @() }"
  $inject += "  $p = $TrustBundle.PSObject.Properties.Name"
  $inject += "  # Preferred canonical shape: signers[]"
  $inject += "  if(@(@($p)) -contains 'signers'){ return @(@($TrustBundle.signers)) }"
  $inject += "  # Common alternates: keys[] / identities[] / principals[]"
  $inject += "  if(@(@($p)) -contains 'keys'){ return @(@($TrustBundle.keys)) }"
  $inject += "  if(@(@($p)) -contains 'identities'){ return @(@($TrustBundle.identities)) }"
  $inject += "  if(@(@($p)) -contains 'principals'){ return @(@($TrustBundle.principals)) }"
  $inject += "  # Nested: trust_bundle.signers or trust.signers"
  $inject += "  if(@(@($p)) -contains 'trust_bundle'){"
  $inject += "    $t2 = $TrustBundle.trust_bundle"
  $inject += "    if($t2 -and @(@($t2.PSObject.Properties.Name)) -contains 'signers'){ return @(@($t2.signers)) }"
  $inject += "    if($t2 -and @(@($t2.PSObject.Properties.Name)) -contains 'keys'){ return @(@($t2.keys)) }"
  $inject += "  }"
  $inject += "  if(@(@($p)) -contains 'trust'){"
  $inject += "    $t3 = $TrustBundle.trust"
  $inject += "    if($t3 -and @(@($t3.PSObject.Properties.Name)) -contains 'signers'){ return @(@($t3.signers)) }"
  $inject += "    if($t3 -and @(@($t3.PSObject.Properties.Name)) -contains 'keys'){ return @(@($t3.keys)) }"
  $inject += "  }"
  $inject += "  return @()"
  $inject += "}"

  $ins = ($inject -join "`n")
  # Insert near top: after StrictMode line if present; else prepend
  if($lib -match "(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$"){
    $lib = [regex]::Replace($lib, "(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$", "$0`n$ins", 1)
  } else {
    $lib = $ins + $lib
  }
}
Write-Utf8NoBomLf $LibPath $lib
Parse-GatePs1 $LibPath
Write-Host ("PATCH_OK: lib updated " + $LibPath) -ForegroundColor Green

# --- patch scripts to stop referencing $tb.signers directly ---
function Patch-File([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  $before = $raw
  # Replace property access patterns with helper call (covers $tb.signers and $trust.signers)
  $raw = [regex]::Replace($raw, "(?i)\$tb\.signers\b", "(Get-TrustBundleSigners `$tb)")
  $raw = [regex]::Replace($raw, "(?i)\$trust\.signers\b", "(Get-TrustBundleSigners `$trust)")
  if($raw -eq $before){ Write-Host ("PATCH_NOTE: no signers refs found in " + $Path) -ForegroundColor DarkYellow }
  Write-Utf8NoBomLf $Path $raw
  Parse-GatePs1 $Path
  Write-Host ("PATCH_OK: " + $Path) -ForegroundColor Green
}
Patch-File $MakePath
Patch-File $ShowPath

Write-Host "NEXT: re-run make_allowed_signers + show_identity" -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $MakePath + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $ShowPath + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
