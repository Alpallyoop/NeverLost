param()
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$RepoRoot = 'C:\dev\neverlost'
$Pwsh     = 'C:\Program Files\PowerShell\7\pwsh.exe'
$Patch    = 'C:\dev\neverlost\scripts\_patch_neverlost_identity_contract_v11e.ps1'

# Parse-gate PATCH (hard fail)
$parseCmd = "try { [ScriptBlock]::Create((Get-Content -Raw -LiteralPath '" + $Patch + "')) | Out-Null; 'PATCH v11e parses OK' } catch { Write-Error ('PATCH PARSE FAIL: ' + `$_.Exception.Message); exit 1 }"
& $Pwsh -NoProfile -Command $parseCmd

# Run patch in fresh pwsh
& $Pwsh -NoProfile -ExecutionPolicy Bypass -File $Patch -RepoRoot $RepoRoot

# Proof runs in fresh pwsh processes
& $Pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\make_allowed_signers_v1.ps1') -RepoRoot $RepoRoot
& $Pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\show_identity_v1.ps1') -RepoRoot $RepoRoot
