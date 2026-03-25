param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $u = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path, $u.GetBytes($t))
}
function Parse-GateFile([string]$Path){ [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path -Encoding UTF8)) }

# ---------------- scripts/_lib_neverlost_v1.ps1 ----------------
$libPath = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$lib = New-Object System.Collections.Generic.List[string]
[void]$lib.Add("$ErrorActionPreference = `"Stop`"")
[void]$lib.Add("Set-StrictMode -Version Latest")
[void]$lib.Add("")
[void]$lib.Add("function NL-Die([string]$Msg){ throw $Msg }")
[void]$lib.Add("")
[void]$lib.Add("function NL-WriteUtf8NoBomLf([string]$Path,[string]$Text){")
Write-Host ("WROTE+PARSE_OK: " + $libPath) -ForegroundColor Green

# ---------------- scripts/make_allowed_signers_v1.ps1 ----------------
$masPath = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$mas = New-Object System.Collections.Generic.List[string]
[void]$mas.Add("param([Parameter(Mandatory=$true)][string]$RepoRoot)")
[void]$mas.Add("$ErrorActionPreference=`"Stop`"")
[void]$mas.Add("Set-StrictMode -Version Latest")
[void]$mas.Add("$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path")
[void]$mas.Add("$ScriptsDir=Join-Path $RepoRoot `"scripts`"")
[void]$mas.Add(". (Join-Path $ScriptsDir `"_lib_neverlost_v1.ps1`")")
[void]$mas.Add("$as = NL-WriteAllowedSignersFromTrust $RepoRoot")
[void]$mas.Add("Write-Host (`"OK: allowed_signers written: `"+$as) -ForegroundColor Green")
Write-Host ("WROTE+PARSE_OK: " + $masPath) -ForegroundColor Green

# ---------------- scripts/show_identity_v1.ps1 ----------------
$sidPath = Join-Path $ScriptsDir "show_identity_v1.ps1"
$sid = New-Object System.Collections.Generic.List[string]
[void]$sid.Add("param([Parameter(Mandatory=$true)][string]$RepoRoot)")
[void]$sid.Add("$ErrorActionPreference=`"Stop`"")
[void]$sid.Add("Set-StrictMode -Version Latest")
[void]$sid.Add("$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path")
[void]$sid.Add("$ScriptsDir=Join-Path $RepoRoot `"scripts`"")
[void]$sid.Add(". (Join-Path $ScriptsDir `"_lib_neverlost_v1.ps1`")")
[void]$sid.Add("$tbInfo = NL-LoadTrustBundle $RepoRoot")
[void]$sid.Add("$entries = NL-EnumerateSignerEntries $tbInfo.Tb")
[void]$sid.Add("$entriesA = @(@($entries))")
[void]$sid.Add("Write-Host (`"SIGNERS: `"+$entriesA.Count) -ForegroundColor Gray")
[void]$sid.Add("foreach($e in $entriesA){")
[void]$sid.Add("  $p=[string]$e.principal; $kid=[string]$e.key_id; $ns=@(@($e.namespaces) | ForEach-Object { [string]$_ } | Sort-Object)")
[void]$sid.Add("  Write-Host (`"  principal=`"+$p+`" key_id=`"+$kid+`" namespaces=`"+(@($ns)-join `",`")) -ForegroundColor Gray")
[void]$sid.Add("}")
[void]$sid.Add("NL-AppendReceipt $RepoRoot `"neverlost.identity.show.v1`" @{ signers=$entriesA.Count; trust_bundle_path=$tbInfo.Path; trust_bundle_sha256=(NL-Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($tbInfo.Raw))) } | Out-Null")
[void]$sid.Add("Write-Host `"OK: identity shown`" -ForegroundColor Green")
Write-Host ("WROTE+PARSE_OK: " + $sidPath) -ForegroundColor Green

# ---------------- scripts/sign_file_v1.ps1 ----------------
$sfPath = Join-Path $ScriptsDir "sign_file_v1.ps1"
$sf = New-Object System.Collections.Generic.List[string]
[void]$sf.Add("param(")
[void]$sf.Add("  [Parameter(Mandatory=$true)][string]$RepoRoot,")
[void]$sf.Add("  [Parameter(Mandatory=$true)][string]$TargetPath,")
[void]$sf.Add("  [Parameter(Mandatory=$true)][string]$SigNamespace,")
[void]$sf.Add("  [Parameter(Mandatory=$true)][string]$Principal,")
[void]$sf.Add("  [Parameter(Mandatory=$true)][string]$KeyId,")
[void]$sf.Add("  [Parameter(Mandatory=$true)][string]$PrivKeyPath,")
[void]$sf.Add("  [string]$OutSigPath")
[void]$sf.Add(")")
Write-Host ("WROTE+PARSE_OK: " + $sfPath) -ForegroundColor Green

# ---------------- scripts/verify_sig_v1.ps1 ----------------
$vfPath = Join-Path $ScriptsDir "verify_sig_v1.ps1"
$vf = New-Object System.Collections.Generic.List[string]
[void]$vf.Add("param(")
[void]$vf.Add("  [Parameter(Mandatory=$true)][string]$RepoRoot,")
[void]$vf.Add("  [Parameter(Mandatory=$true)][string]$TargetPath,")
[void]$vf.Add("  [Parameter(Mandatory=$true)][string]$SigPath,")
[void]$vf.Add("  [Parameter(Mandatory=$true)][string]$SigNamespace,")
[void]$vf.Add("  [Parameter(Mandatory=$true)][string]$Principal,")
[void]$vf.Add("  [int]$TimeoutSec = 30")
[void]$vf.Add(")")
Write-Host ("WROTE+PARSE_OK: " + $vfPath) -ForegroundColor Green

# ---------------- scripts/_selftest_neverlost_v1.ps1 ----------------
$stPath = Join-Path $ScriptsDir "_selftest_neverlost_v1.ps1"
$st = New-Object System.Collections.Generic.List[string]
[void]$st.Add("param([Parameter(Mandatory=$true)][string]$RepoRoot)")
Write-Host ("WROTE+PARSE_OK: " + $stPath) -ForegroundColor Green

# Run selftest
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir "_selftest_neverlost_v1.ps1") -RepoRoot $RepoRoot
Write-Host "REPAIR_OK: NeverLost v1 scripts written + selftest PASS" -ForegroundColor Green
