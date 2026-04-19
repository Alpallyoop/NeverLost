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
$LibPath  = Join-Path $Scripts "_lib_neverlost_v1.ps1"
$MakePath = Join-Path $Scripts "make_allowed_signers_v1.ps1"
$ShowPath = Join-Path $Scripts "show_identity_v1.ps1"
$TBPath   = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"

if(-not (Test-Path -LiteralPath $LibPath  -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }
if(-not (Test-Path -LiteralPath $MakePath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $MakePath) }
if(-not (Test-Path -LiteralPath $ShowPath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $ShowPath) }
if(-not (Test-Path -LiteralPath $TBPath   -PathType Leaf)){ Die ("MISSING_TRUST_BUNDLE: " + $TBPath) }

$tbObj = (Get-Content -Raw -LiteralPath $TBPath -Encoding UTF8 | ConvertFrom-Json)
$tbProps = @(@($tbObj.PSObject.Properties | ForEach-Object { $_.Name }))
Write-Host ("TRUST_BUNDLE_TOP_KEYS: " + ($tbProps -join ", ")) -ForegroundColor DarkGray

# --- Inject helper into lib if missing ---
$libLines = @(@(Get-Content -LiteralPath $LibPath -Encoding UTF8))
$libText  = ($libLines -join "`n") + "`n"
if($libText -notmatch "(?im)^\s*function\s+Get-TrustBundleSigners\s*\("){
  $inject = New-Object System.Collections.Generic.List[string]
  [void]$inject.Add("")
  [void]$inject.Add("function Get-TrustBundleSigners([object]`$TrustBundle){")
  [void]$inject.Add("  # Schema-tolerant signer extraction (StrictMode-safe)")
  [void]$inject.Add("  if(`$null -eq `$TrustBundle){ return @() }")
  [void]$inject.Add("  `$props = @(@(`$TrustBundle.PSObject.Properties.Name))")
  [void]$inject.Add("  # Preferred/legacy keys: signers[]")
  [void]$inject.Add("  if(`$props -contains 'signers'){ return @(@(`$TrustBundle.signers)) }")
  [void]$inject.Add("  # Your observed canonical key: principals[]")
  [void]$inject.Add("  if(`$props -contains 'principals'){ return @(@(`$TrustBundle.principals)) }")
  [void]$inject.Add("  # Common alternates")
  [void]$inject.Add("  if(`$props -contains 'keys'){ return @(@(`$TrustBundle.keys)) }")
  [void]$inject.Add("  if(`$props -contains 'identities'){ return @(@(`$TrustBundle.identities)) }")
  [void]$inject.Add("  # Nested: trust_bundle.* or trust.*")
  [void]$inject.Add("  if(`$props -contains 'trust_bundle'){")
  [void]$inject.Add("    `$t2 = `$TrustBundle.trust_bundle")
  [void]$inject.Add("    if(`$t2){")
  [void]$inject.Add("      `$p2 = @(@(`$t2.PSObject.Properties.Name))")
  [void]$inject.Add("      if(`$p2 -contains 'signers'){ return @(@(`$t2.signers)) }")
  [void]$inject.Add("      if(`$p2 -contains 'principals'){ return @(@(`$t2.principals)) }")
  [void]$inject.Add("      if(`$p2 -contains 'keys'){ return @(@(`$t2.keys)) }")
  [void]$inject.Add("    }")
  [void]$inject.Add("  }")
  [void]$inject.Add("  if(`$props -contains 'trust'){")
  [void]$inject.Add("    `$t3 = `$TrustBundle.trust")
  [void]$inject.Add("    if(`$t3){")
  [void]$inject.Add("      `$p3 = @(@(`$t3.PSObject.Properties.Name))")
  [void]$inject.Add("      if(`$p3 -contains 'signers'){ return @(@(`$t3.signers)) }")
  [void]$inject.Add("      if(`$p3 -contains 'principals'){ return @(@(`$t3.principals)) }")
  [void]$inject.Add("      if(`$p3 -contains 'keys'){ return @(@(`$t3.keys)) }")
  [void]$inject.Add("    }")
  [void]$inject.Add("  }")
  [void]$inject.Add("  return @()")
  [void]$inject.Add("}")

  $insText = (@($inject) -join "`n") + "`n"

  # Insert after Set-StrictMode line if present; else prepend
  $idx = -1
  for($i=0; $i -lt $libLines.Count; $i++){ if($libLines[$i] -match "(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$"){ $idx = $i; break } }
  if($idx -ge 0){
    $new = New-Object System.Collections.Generic.List[string]
    for($i=0; $i -le $idx; $i++){ [void]$new.Add($libLines[$i]) }
    foreach($ln in @($inject)){ [void]$new.Add($ln) }
    for($i=$idx+1; $i -lt $libLines.Count; $i++){ [void]$new.Add($libLines[$i]) }
    $libText = (@($new) -join "`n") + "`n"
  } else {
    $libText = $insText + $libText
  }
}
Write-Utf8NoBomLf $LibPath $libText
Parse-GatePs1 $LibPath
Write-Host ("PATCH_OK: lib " + $LibPath) -ForegroundColor Green

# --- Patch make/show to stop referencing .signers directly ---
function Patch-File([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  $before = $raw
  $raw = [regex]::Replace($raw, '(?i)\$tb\.signers\b', '(Get-TrustBundleSigners $tb)')
  $raw = [regex]::Replace($raw, '(?i)\$trust\.signers\b', '(Get-TrustBundleSigners $trust)')
  if($raw -eq $before){ Write-Host ("PATCH_NOTE: no signers refs found in " + $Path) -ForegroundColor DarkYellow }
  Write-Utf8NoBomLf $Path $raw
  Parse-GatePs1 $Path
  Write-Host ("PATCH_OK: " + $Path) -ForegroundColor Green
}
Patch-File $MakePath
Patch-File $ShowPath

Write-Host "NEXT:" -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $MakePath + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $ShowPath + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
