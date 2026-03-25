param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

$RepoRoot   = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath    = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
if(-not (Test-Path -LiteralPath $LibPath -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }

. $LibPath

# Uses compat tail override (last definition wins)
$asPath = NL-WriteAllowedSignersFromTrust $RepoRoot
if(-not (Test-Path -LiteralPath $asPath -PathType Leaf)){ Die ("ALLOWED_SIGNERS_MISSING_AFTER_WRITE: " + $asPath) }

Write-Host ("ALLOWED_SIGNERS_OK: " + $asPath) -ForegroundColor Green
