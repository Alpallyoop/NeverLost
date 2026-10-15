param([string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path $RepoRoot).Path

$AdminCliPath = Join-Path $RepoRoot "scripts\neverlost_admin_plugin_minimal_v1.ps1"
$SelftestPath = Join-Path $RepoRoot "scripts\_selftest_neverlost_admin_plugin_minimal_v1.ps1"
$DocsPath     = Join-Path $RepoRoot "docs\ADMIN_PLUGIN_MINIMAL_v1.md"

New-Item -ItemType Directory -Force -Path (Split-Path $AdminCliPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $SelftestPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $DocsPath) | Out-Null

Set-Content $AdminCliPath "Write-Host 'ADMIN_PLUGIN_MINIMAL_READY'" -Encoding UTF8
Set-Content $SelftestPath "Write-Host 'ADMIN_PLUGIN_SELFTEST_READY'" -Encoding UTF8
Set-Content $DocsPath "Admin Plugin Minimal v1" -Encoding UTF8

Write-Host "ADMIN_PLUGIN_FILES_WRITTEN"