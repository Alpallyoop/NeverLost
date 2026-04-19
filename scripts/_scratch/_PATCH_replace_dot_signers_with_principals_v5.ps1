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
$MakePath = Join-Path $Scripts "make_allowed_signers_v1.ps1"
$ShowPath = Join-Path $Scripts "show_identity_v1.ps1"
if(-not (Test-Path -LiteralPath $MakePath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $MakePath) }
if(-not (Test-Path -LiteralPath $ShowPath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $ShowPath) }

function Patch-File([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  $before = $raw
  $raw = [regex]::Replace($raw, '(?i)\.signers\b', '.principals')
  if($raw -eq $before){ Write-Host ("PATCH_NOTE: no .signers token found in " + $Path) -ForegroundColor DarkYellow }
  Write-Utf8NoBomLf $Path $raw
  Parse-GatePs1 $Path
  $after = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  if($after -match '(?i)\.signers\b'){ Die ("PATCH_INCOMPLETE: .signers still present in " + $Path) }
  Write-Host ("PATCH_OK: " + $Path) -ForegroundColor Green
}

Patch-File $MakePath
Patch-File $ShowPath

Write-Host "NEXT:" -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $MakePath + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $ShowPath + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
