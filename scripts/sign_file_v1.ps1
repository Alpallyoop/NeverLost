param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetPath,
  [Parameter(Mandatory=$true)][string]$SigNamespace,
  [Parameter(Mandatory=$true)][string]$Principal,
  [Parameter(Mandatory=$true)][string]$KeyId,
  [Parameter(Mandatory=$true)][string]$PrivKeyPath,
  [string]$OutSigPath
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$TargetPath=(Resolve-Path -LiteralPath $TargetPath).Path
$PrivKeyPath=(Resolve-Path -LiteralPath $PrivKeyPath).Path
$ScriptsDir=Join-Path $RepoRoot "scripts"
. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")
$ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source
if([string]::IsNullOrWhiteSpace($OutSigPath)){ $OutSigPath = ($TargetPath + ".sig") }
$outDir = Split-Path -Parent $OutSigPath
if($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$args = @("-Y","sign","-f",$PrivKeyPath,"-n",$SigNamespace,"-I",$Principal,"-O",("keyid="+$KeyId),"-s",$OutSigPath,$TargetPath)
Write-Host ("SIGN_CMD: " + $ssh + " " + (@($args) -join " ")) -ForegroundColor DarkGray
$out = & $ssh @args 2>&1
if($LASTEXITCODE -ne 0){
  NL-AppendReceipt $RepoRoot "neverlost.sig.sign.fail.v1" @{ target=$TargetPath; sig=$OutSigPath; namespace=$SigNamespace; principal=$Principal; key_id=$KeyId; exit_code=[int]$LASTEXITCODE; output=(@($out)-join "`n"); target_sha256=(NL-Sha256HexFile $TargetPath) } | Out-Null
  NL-Die ("SIGN_FAILED exit=" + $LASTEXITCODE + " output=" + (@($out)-join "`n"))
}
NL-AppendReceipt $RepoRoot "neverlost.sig.sign.ok.v1" @{ target=$TargetPath; sig=$OutSigPath; namespace=$SigNamespace; principal=$Principal; key_id=$KeyId; target_sha256=(NL-Sha256HexFile $TargetPath); sig_sha256=(NL-Sha256HexFile $OutSigPath) } | Out-Null
Write-Host ("OK: signed -> " + $OutSigPath) -ForegroundColor Green
