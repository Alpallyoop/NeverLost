param([string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

Write-Host "RUNNER_START" -ForegroundColor Yellow

$Acl = Join-Path $RepoRoot "scripts\enforce_trust_acl_v1.ps1"

if(-not (Test-Path $Acl)){
throw "ACL_MISSING"
}

$PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `  -File $Acl`
-RepoRoot $RepoRoot

Write-Host "NEVERLOST_TRUST_PIPELINE_FULL_GREEN" -ForegroundColor Green