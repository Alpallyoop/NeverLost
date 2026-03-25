param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

$RepoRoot   = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath    = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
if(-not (Test-Path -LiteralPath $LibPath -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }

. $LibPath

$tbInfo  = NL-LoadTrustBundleInfoV1 $RepoRoot
$entries = NL-GetTrustBundleEntriesCompat $tbInfo.Obj
$entries = @(@($entries))

Write-Host ("TRUST_BUNDLE: " + $tbInfo.Path) -ForegroundColor Gray
Write-Host ("PRINCIPALS_COUNT: " + $entries.Count) -ForegroundColor Gray

foreach($e in ($entries | Sort-Object principal)){
  $p  = [string]$e.principal
  $ns = @(@($e.namespaces))
  $ns = @(@($ns)) | Sort-Object
  $nsText = ""
  if($ns.Count -gt 0){ $nsText = (" [" + ($ns -join ",") + "]") }
  Write-Host ("PRINCIPAL: " + $p + $nsText) -ForegroundColor White
}

$asPath = Join-Path $RepoRoot "proofs\trust\allowed_signers"
if(Test-Path -LiteralPath $asPath -PathType Leaf){
  Write-Host ("ALLOWED_SIGNERS_PRESENT: " + $asPath) -ForegroundColor Green
} else {
  Write-Host ("ALLOWED_SIGNERS_MISSING: " + $asPath) -ForegroundColor Yellow
}
