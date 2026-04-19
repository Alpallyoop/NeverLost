param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")

$ssh = NL-ResolveSshKeygen
Write-Host ("ssh_keygen_path         : " + $ssh) -ForegroundColor Cyan

$r = NL-InvokeProc $ssh "-Y help" 3000
if ($r.TimedOut) { throw "TIMEOUT: ssh-keygen -Y help" }

$txt = (($r.Stdout + "`n" + $r.Stderr) -replace "`r`n","`n")
if ($txt -notmatch 'find-principals|verify|sign') {
  throw "ssh-keygen does not appear to support -Y operations (no sign/verify/find-principals in output)."
}

Write-Host "OK: ssh-keygen appears to support -Y." -ForegroundColor Green
