param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Make = Join-Path (Join-Path $RepoRoot "scripts") "make_allowed_signers_v1.ps1"
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $Make -RepoRoot $RepoRoot
Write-Host ("OK: v15 applied (backup: C:\\dev\\neverlost\\scripts\\_neverlost_backup_make_allowed_signers_v15_20260209_220417)") -ForegroundColor Green
