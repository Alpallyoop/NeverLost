param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("status","confirm")]
  [string]$Command
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

. (Join-Path $PSScriptRoot "_lib_neverlost_host_v1.ps1")
$PSExe = NL-ResolvePsHost
$AdminCli = Join-Path $RepoRoot "scripts\neverlost_admin_plugin_minimal_v1.ps1"

if(-not (Test-Path $AdminCli)){
  throw "ADMIN_PLUGIN_NOT_FOUND"
}

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $AdminCli `
  -RepoRoot $RepoRoot `
  -Action $Command `
  -TargetMode managed `
  -NodeId local-loopback