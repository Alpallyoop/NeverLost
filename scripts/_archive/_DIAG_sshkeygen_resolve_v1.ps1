param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")

function Sha256Hex([string]$Path){
  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$allowed = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$payload = Join-Path $RepoRoot "proofs\payloads\watchtower_sigproof_v1g.txt"
$sig     = ($payload + ".sig")

$Principal = "single-tenant/watchtower_authority/authority/watchtower"
$Namespace = "watchtower"

foreach($p in @($allowed,$payload,$sig)){
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing required path: $p" }
}

$ssh = NL-ResolveSshKeygen

Write-Host "=== DIAG3: RESOLVED ssh-keygen ===" -ForegroundColor Cyan
Write-Host ("ssh_keygen_path        : " + $ssh)
Write-Host ""
Write-Host "=== DIAG3: INPUT HASHES ===" -ForegroundColor Cyan
Write-Host ("allowed_signers_sha256 : " + (Sha256Hex $allowed))
Write-Host ("payload_sha256         : " + (Sha256Hex $payload))
Write-Host ("sig_sha256             : " + (Sha256Hex $sig))
Write-Host ""

Write-Host "=== A) find-principals ===" -ForegroundColor Cyan
$argsFind = ('-Y find-principals -f "{0}" -s "{1}" "{2}"' -f $allowed, $sig, $payload)
$rA = NL-InvokeProc $ssh $argsFind 15000
$rA | Format-List | Out-String | Write-Host
Write-Host ""

Write-Host "=== B) verify ===" -ForegroundColor Cyan
$argsVer = ('-Y verify -f "{0}" -I "{1}" -n "{2}" -s "{3}" "{4}"' -f $allowed, $Principal, $Namespace, $sig, $payload)
$rB = NL-InvokeProc $ssh $argsVer 15000
$rB | Format-List | Out-String | Write-Host
Write-Host ""

if ($rA.TimedOut -or $rB.TimedOut) { throw "DIAG3: timeout occurred (see above)" }
if ($rA.ExitCode -ne 0) { throw "DIAG3: find-principals failed (see above)" }
if ($rB.ExitCode -ne 0) { throw "DIAG3: verify failed (see above)" }

Write-Host "OK: DIAG3 complete" -ForegroundColor Green
