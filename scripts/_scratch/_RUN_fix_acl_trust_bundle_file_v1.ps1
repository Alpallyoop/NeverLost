param([Parameter(Mandatory=$true)][string]$TrustDir)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$TrustDir = (Resolve-Path -LiteralPath $TrustDir).Path
$TbPath   = Join-Path $TrustDir "trust_bundle.json"
$user     = "$env:USERDOMAIN\$env:USERNAME"
Write-Host ("TB:   " + $TbPath) -ForegroundColor Yellow
Write-Host ("USER: " + $user) -ForegroundColor Yellow
if(-not (Test-Path -LiteralPath $TbPath -PathType Leaf)){ throw ("MISSING_TRUST_BUNDLE: " + $TbPath) }

Write-Host "BEFORE:" -ForegroundColor Cyan
& icacls $TbPath | Out-Host

# 1) Stop inheritance on the file (explicit ACL only)
& icacls $TbPath /inheritance:r | Out-Host

# 2) Remove common DENY entries that override ALLOW
& icacls $TbPath /remove:d "${user}" | Out-Host
& icacls $TbPath /remove:d "Users" | Out-Host
& icacls $TbPath /remove:d "Authenticated Users" | Out-Host
& icacls $TbPath /remove:d "Everyone" | Out-Host

# 3) Set a known-good minimal ACL on the file
& icacls $TbPath /grant:r "${user}:R" "SYSTEM:F" "Administrators:F" | Out-Host

Write-Host "AFTER:" -ForegroundColor Cyan
& icacls $TbPath | Out-Host

Write-Host "READ_TEST:" -ForegroundColor Cyan
$raw = Get-Content -Raw -LiteralPath $TbPath -Encoding UTF8
if([string]::IsNullOrWhiteSpace($raw)){ throw "TRUST_BUNDLE_EMPTY" }
Write-Host ("READ_OK: bytes=" + $raw.Length) -ForegroundColor Green
