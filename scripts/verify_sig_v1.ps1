param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetPath,
  [Parameter(Mandatory=$true)][string]$SigPath,
  [Parameter(Mandatory=$true)][string]$SigNamespace,
  [Parameter(Mandatory=$true)][string]$Principal,
  [int]$TimeoutSec = 30
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$TargetPath=(Resolve-Path -LiteralPath $TargetPath).Path
$SigPath=(Resolve-Path -LiteralPath $SigPath).Path
$ScriptsDir=Join-Path $RepoRoot "scripts"
. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")
$ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source
$asPath = Join-Path $RepoRoot "proofs\trust\allowed_signers"
if (-not (Test-Path -LiteralPath $asPath -PathType Leaf)) { NL-Die ("MISSING_ALLOWED_SIGNERS: " + $asPath + " (run make_allowed_signers_v1.ps1)") }
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ssh
$psi.Arguments = ("-Y verify -f `"" + $asPath + "`" -I `"" + $Principal + "`" -n `"" + $SigNamespace + "`" -s `"" + $SigPath + "`"")
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
Write-Host ("VERIFY_CMD: " + $ssh + " " + $psi.Arguments) -ForegroundColor DarkGray
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
$bytes = [System.IO.File]::ReadAllBytes($TargetPath)
$p.StandardInput.BaseStream.Write($bytes,0,$bytes.Length)
$p.StandardInput.Close()
if(-not $p.WaitForExit($TimeoutSec*1000)){ try{ $p.Kill() } catch { }; NL-AppendReceipt $RepoRoot "neverlost.sig.verify.timeout.v1" @{ target=$TargetPath; sig=$SigPath; namespace=$SigNamespace; principal=$Principal; timeout_sec=$TimeoutSec; target_sha256=(NL-Sha256HexFile $TargetPath); sig_sha256=(NL-Sha256HexFile $SigPath) } | Out-Null; NL-Die ("VERIFY_TIMEOUT sec=" + $TimeoutSec) }
$out = $p.StandardOutput.ReadToEnd()
$err = $p.StandardError.ReadToEnd()
$code = [int]$p.ExitCode
if ($code -ne 0) { NL-AppendReceipt $RepoRoot "neverlost.sig.verify.fail.v1" @{ target=$TargetPath; sig=$SigPath; namespace=$SigNamespace; principal=$Principal; exit_code=$code; stdout=$out; stderr=$err; target_sha256=(NL-Sha256HexFile $TargetPath); sig_sha256=(NL-Sha256HexFile $SigPath); allowed_signers_sha256=(NL-Sha256HexFile $asPath) } | Out-Null; NL-Die ("VERIFY_FAILED exit=" + $code + " stderr=" + $err) }
NL-AppendReceipt $RepoRoot "neverlost.sig.verify.ok.v1" @{ target=$TargetPath; sig=$SigPath; namespace=$SigNamespace; principal=$Principal; stdout=$out; stderr=$err; target_sha256=(NL-Sha256HexFile $TargetPath); sig_sha256=(NL-Sha256HexFile $SigPath); allowed_signers_sha256=(NL-Sha256HexFile $asPath) } | Out-Null
Write-Host "OK: verify PASS" -ForegroundColor Green
