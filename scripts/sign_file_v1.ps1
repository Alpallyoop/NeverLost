param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetPath,
  [Parameter(Mandatory=$true)][string]$SigNamespace,
  [Parameter(Mandatory=$true)][string]$Principal,
  [Parameter(Mandatory=$true)][string]$KeyId,
  [Parameter(Mandatory=$true)][string]$PrivKeyPath,
  [string]$OutSigPath
)
# Identity-bound signing (neverlost.sig.sign.v1).
# The principal, key id and namespace must be granted by the verified trust bundle, and the private key
# must be the private half of that trusted public key. The signature is verified against the trusted
# signer line before the success token is printed. Never overwrites an existing signature.
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$TargetPath=(Resolve-Path -LiteralPath $TargetPath).Path
$PrivKeyPath=(Resolve-Path -LiteralPath $PrivKeyPath).Path
$ScriptsDir=Join-Path $RepoRoot "scripts"
. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")
. (Join-Path $ScriptsDir "_lib_neverlost_host_v1.ps1")
$ssh = NL-ResolveSshKeygen

$trustEntries = NL-AssertTrustBundleV1 -RepoRoot $RepoRoot
$grant = @($trustEntries | Where-Object { [string]$_.principal -ceq $Principal -and [string]$_.key_id -ceq $KeyId })
if($grant.Count -lt 1){ NL-Die ("SIGN_DENIED_UNTRUSTED_SIGNER principal=" + $Principal + " key_id=" + $KeyId) }
if(@($grant[0].namespaces) -cnotcontains $SigNamespace){ NL-Die ("SIGN_DENIED_NAMESPACE principal=" + $Principal + " namespace=" + $SigNamespace) }
$derivedRun = NL-InvokeNative -Exe $ssh -Arguments @("-y","-f",$PrivKeyPath)
if($derivedRun.Code -ne 0){ NL-Die ("SIGN_DENIED_KEY_UNREADABLE exit=" + $derivedRun.Code) }
if((NL-PubkeyCore $derivedRun.Output) -cne [string]$grant[0].pubkey){ NL-Die ("SIGN_DENIED_KEY_MISMATCH key_id=" + $KeyId) }

$defaultSig = $TargetPath + ".sig"
if([string]::IsNullOrWhiteSpace($OutSigPath)){ $OutSigPath = $defaultSig }
$OutSigPath = [System.IO.Path]::GetFullPath($OutSigPath)
if(Test-Path -LiteralPath $OutSigPath){ NL-Die ("SIGN_OUTPUT_EXISTS: " + $OutSigPath) }
if(($OutSigPath -ne $defaultSig) -and (Test-Path -LiteralPath $defaultSig)){ NL-Die ("SIGN_DEFAULT_OUTPUT_EXISTS: " + $defaultSig) }
$outDir = Split-Path -Parent $OutSigPath
if($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$sshArgs = @("-Y","sign","-f",$PrivKeyPath,"-n",$SigNamespace,$TargetPath)
Write-Host ("SIGN_CMD: ssh-keygen -Y sign -n " + $SigNamespace + " (principal=" + $Principal + " key_id=" + $KeyId + ")") -ForegroundColor DarkGray
$signRun = NL-InvokeNative -Exe $ssh -Arguments $sshArgs
$out = $signRun.Output
$code = $signRun.Code
if($code -ne 0 -or -not (Test-Path -LiteralPath $defaultSig -PathType Leaf)){
  NL-AppendReceipt $RepoRoot "neverlost.sig.sign.fail.v1" @{ target=$TargetPath; sig=$OutSigPath; namespace=$SigNamespace; principal=$Principal; key_id=$KeyId; exit_code=$code; output=((@($out) | ForEach-Object { [string]$_ }) -join "`n"); target_sha256=(NL-Sha256HexFile $TargetPath) } | Out-Null
  NL-Die ("SIGN_FAILED exit=" + $code + " output=" + ((@($out) | ForEach-Object { [string]$_ }) -join "`n"))
}
if($OutSigPath -ne $defaultSig){ Move-Item -LiteralPath $defaultSig -Destination $OutSigPath }

# Verify the new signature against the trusted signer line before claiming success.
$scratch = Join-Path $RepoRoot ".scratch"
if(-not (Test-Path -LiteralPath $scratch -PathType Container)){ New-Item -ItemType Directory -Force -Path $scratch | Out-Null }
$tmpSigners = Join-Path $scratch ("sign_check_" + [Guid]::NewGuid().ToString("N") + ".allowed_signers")
try {
  [System.IO.File]::WriteAllBytes($tmpSigners, (New-Object System.Text.UTF8Encoding($false)).GetBytes((NL-AllowedSignersTextV1 -Entries $grant -Namespace $SigNamespace)))
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $ssh
  $psi.Arguments = ("-Y verify -f `"" + $tmpSigners + "`" -I `"" + $Principal + "`" -n `"" + $SigNamespace + "`" -s `"" + $OutSigPath + "`"")
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $bytes = [System.IO.File]::ReadAllBytes($TargetPath)
  $p.StandardInput.BaseStream.Write($bytes,0,$bytes.Length)
  $p.StandardInput.Close()
  $vOut = $p.StandardOutput.ReadToEnd()
  $vErr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  if($p.ExitCode -ne 0){ NL-Die ("SIGN_SELF_VERIFY_FAILED exit=" + $p.ExitCode + " stderr=" + $vErr) }
} finally {
  Remove-Item -LiteralPath $tmpSigners -Force -ErrorAction SilentlyContinue
}

NL-AppendReceipt $RepoRoot "neverlost.sig.sign.ok.v1" @{ alg="ssh-ed25519"; target=$TargetPath; sig=$OutSigPath; namespace=$SigNamespace; principal=$Principal; key_id=$KeyId; target_sha256=(NL-Sha256HexFile $TargetPath); sig_sha256=(NL-Sha256HexFile $OutSigPath) } | Out-Null
Write-Host ("OK: signed -> " + $OutSigPath) -ForegroundColor Green
