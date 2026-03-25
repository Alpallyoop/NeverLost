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

if(-not (Test-Path -LiteralPath $LibPath  -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }
if(-not (Test-Path -LiteralPath $MakePath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $MakePath) }
if(-not (Test-Path -LiteralPath $ShowPath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $ShowPath) }

# Ensure helper exists (fail fast if missing)
$libRaw = Get-Content -Raw -LiteralPath $LibPath -Encoding UTF8
if($libRaw -notmatch "(?im)^\s*function\s+Get-TrustBundleSigners\s*\("){ Die "MISSING_HELPER: Get-TrustBundleSigners not found in _lib_neverlost_v1.ps1" }

function Patch-File([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  $before = $raw
  $re = '(?im)\$([A-Za-z_][A-Za-z0-9_]*)\.signers\b'
  $raw = [regex]::Replace($raw, $re, { param($m) '(Get-TrustBundleSigners $' + $m.Groups[1].Value + ')' })
  if($raw -eq $before){ Write-Host ("PATCH_NOTE: no .signers refs found in " + $Path) -ForegroundColor DarkYellow }
  Write-Utf8NoBomLf $Path $raw
  Parse-GatePs1 $Path
  $after = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  if($after -match '(?im)\$[A-Za-z_][A-Za-z0-9_]*\.signers\b'){
    $hits = @(@([regex]::Matches($after, '(?im)\$[A-Za-z_][A-Za-z0-9_]*\.signers\b') | ForEach-Object { $_.Value } | Select-Object -Unique))
    Die ("PATCH_INCOMPLETE: remaining $name.signers in " + $Path + " hits=" + ($hits -join ","))
  }
  Write-Host ("PATCH_OK: " + $Path) -ForegroundColor Green
}

Patch-File $MakePath
Patch-File $ShowPath

Write-Host "NEXT:" -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $MakePath + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $ShowPath + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
