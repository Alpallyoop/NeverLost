param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Sha256Hex([string]$Path){
  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$ssh = (Get-Command ssh-keygen -ErrorAction SilentlyContinue).Source
if (-not $ssh) { throw "ssh-keygen not found on PATH." }

$allowed = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$payload = Join-Path $RepoRoot "proofs\payloads\watchtower_sigproof_v1g.txt"
$sig     = ($payload + ".sig")

$Principal = "single-tenant/watchtower_authority/authority/watchtower"
$Namespace = "watchtower"

foreach($p in @($allowed,$payload,$sig)){
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing required path: $p" }
}

function Invoke-Proc([string]$Exe, [string]$Args, [int]$TimeoutMs){
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = $Args
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.RedirectStandardInput  = $true
  $psi.UseShellExecute        = $false
  $psi.CreateNoWindow         = $true

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()

  try { $p.StandardInput.Close() } catch { }

  if (-not $p.WaitForExit($TimeoutMs)) {
    try { $p.Kill() } catch { }
    $o=""; $e=""
    try { $o = $p.StandardOutput.ReadToEnd() } catch { }
    try { $e = $p.StandardError.ReadToEnd() } catch { }
    return [pscustomobject]@{ TimedOut=$true; ExitCode=-1; Stdout=$o; Stderr=$e }
  }

  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  return [pscustomobject]@{ TimedOut=$false; ExitCode=[int]$p.ExitCode; Stdout=[string]$out; Stderr=[string]$err }
}

Write-Host "=== DIAG2: INPUT HASHES ===" -ForegroundColor Cyan
Write-Host ("allowed_signers_sha256 : " + (Sha256Hex $allowed))
Write-Host ("payload_sha256         : " + (Sha256Hex $payload))
Write-Host ("sig_sha256             : " + (Sha256Hex $sig))
Write-Host ""

# A) find-principals
Write-Host "=== A) ssh-keygen -Y find-principals ===" -ForegroundColor Cyan
$argsFind = ('-Y find-principals -f "{0}" -s "{1}" "{2}"' -f $allowed, $sig, $payload)
$rA = Invoke-Proc -Exe $ssh -Args $argsFind -TimeoutMs 15000
$rA | Format-List | Out-String | Write-Host
Write-Host ""

# B) verify
Write-Host "=== B) ssh-keygen -Y verify ===" -ForegroundColor Cyan
$argsVer = ('-Y verify -f "{0}" -I "{1}" -n "{2}" -s "{3}" "{4}"' -f $allowed, $Principal, $Namespace, $sig, $payload)
$rB = Invoke-Proc -Exe $ssh -Args $argsVer -TimeoutMs 15000
$rB | Format-List | Out-String | Write-Host
Write-Host ""

if ($rA.TimedOut -or $rB.TimedOut) { throw "DIAG2: timeout occurred (see above)" }
Write-Host "OK: DIAG2 complete" -ForegroundColor Green
