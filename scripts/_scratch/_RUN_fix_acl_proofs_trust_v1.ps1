param([Parameter(Mandatory=$true)][string]$TrustDir)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$TrustDir = (Resolve-Path -LiteralPath $TrustDir).Path
$user = "$env:USERDOMAIN\$env:USERNAME"
Write-Host ("ACL_TARGET: " + $TrustDir) -ForegroundColor Yellow
Write-Host ("ACL_USER:   " + $user) -ForegroundColor Yellow

# Remove inheritance (explicit) and grant explicit rights:
# - User: Read+Execute on folder + all children (so Get-Content works)
# - SYSTEM: Full control (device/system processes)
& icacls $TrustDir /inheritance:r | Out-Host
& icacls $TrustDir /grant:r "${user}:(OI)(CI)RX" "SYSTEM:(OI)(CI)F" /t | Out-Host

# Sanity: try to read trust_bundle.json
$tb = Join-Path $TrustDir "trust_bundle.json"
if(-not (Test-Path -LiteralPath $tb -PathType Leaf)){ throw ("MISSING_TRUST_BUNDLE: " + $tb) }
$raw = Get-Content -Raw -LiteralPath $tb -Encoding UTF8
if([string]::IsNullOrWhiteSpace($raw)){ throw "TRUST_BUNDLE_EMPTY" }
Write-Host "ACL_FIX_OK: trust_bundle.json readable" -ForegroundColor Green
