param([Parameter(Mandatory=$true)][string]$TrustDir)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$TrustDir = (Resolve-Path -LiteralPath $TrustDir).Path
$TbPath   = Join-Path $TrustDir "trust_bundle.json"
$user     = "$env:USERDOMAIN\$env:USERNAME"
Write-Host ("WHOAMI: " + (whoami)) -ForegroundColor Yellow
Write-Host ("USER:   " + $user) -ForegroundColor Yellow
Write-Host ("TRUST:  " + $TrustDir) -ForegroundColor Yellow
Write-Host ("TB:     " + $TbPath) -ForegroundColor Yellow

if(-not (Test-Path -LiteralPath $TbPath -PathType Leaf)){ throw ("MISSING_TRUST_BUNDLE: " + $TbPath) }

Write-Host "---- ICACLS (folder) ----" -ForegroundColor Cyan
& icacls $TrustDir | Out-Host
Write-Host "---- ICACLS (file) ----" -ForegroundColor Cyan
& icacls $TbPath | Out-Host

Write-Host "---- TRY READ (Get-Content -Raw) ----" -ForegroundColor Cyan
try {
  $raw = Get-Content -Raw -LiteralPath $TbPath -Encoding UTF8
  Write-Host ("READ_OK: bytes=" + $raw.Length) -ForegroundColor Green
} catch {
  Write-Host ("READ_FAIL: " + $_.Exception.GetType().FullName + " :: " + $_.Exception.Message) -ForegroundColor Red
  throw
}
