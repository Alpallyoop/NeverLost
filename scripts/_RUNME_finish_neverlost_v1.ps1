param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { throw ("Missing scripts dir: " + $ScriptsDir) }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ("Parse-Gate missing file: " + $Path) }
  $tk=$null; $er=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tk,[ref]$er)
  if ($er -and @($er).Count -gt 0) { throw ("Parse-Gate error in " + $Path + ": " + ($er | Select-Object -First 1 | ForEach-Object { $_.Message })) }
}

# ---- backup scripts deterministically ----
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ScriptsDir ("_neverlost_backup_finish_v1_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
foreach($p in @("scripts\_lib_neverlost_v1.ps1","scripts\make_allowed_signers_v1.ps1","scripts\show_identity_v1.ps1","scripts\sign_file_v1.ps1","scripts\verify_sig_v1.ps1")){
  $src = Join-Path $RepoRoot $p
  if (Test-Path -LiteralPath $src -PathType Leaf) { Copy-Item -LiteralPath $src -Destination (Join-Path $BackupDir ((Split-Path -Leaf $src)+".pre_finish_v1")) -Force }
}

# =========================================
# Write scripts (LIB + make/show/sign/verify)
# =========================================
$LibPath   = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$MakePath  = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$ShowPath  = Join-Path $ScriptsDir "show_identity_v1.ps1"
$SignPath  = Join-Path $ScriptsDir "sign_file_v1.ps1"
$VerifyPath= Join-Path $ScriptsDir "verify_sig_v1.ps1"

# ---- LIB ----
$lib = New-Object System.Collections.Generic.List[string]
[void]$lib.Add("Set-StrictMode -Version Latest")
[void]$lib.Add("$ErrorActionPreference=""Stop""")
[void]$lib.Add("")
[void]$lib.Add("function NL-Die([string]$m){ throw $m }")
[void]$lib.Add("function NL-HasProp($obj,[string]$name){ if ($null -eq $obj) { return $false } return ($obj.PSObject.Properties.Match($name).Count -gt 0) }")
[void]$lib.Add("function NL-GetProp($obj,[string]$name){ if (NL-HasProp $obj $name) { return $obj.PSObject.Properties[$name].Value } return $null }")
[void]$lib.Add("function NL-CoerceArray($v){ return @(@($v)) }")
[void]$lib.Add("function NL-FirstNonEmpty([object[]]$vals){ foreach($v in @($vals)){ if ($null -eq $v) { continue }; $s=[string]$v; if (-not [string]::IsNullOrWhiteSpace($s)) { return $s } } return "" }")
NL-WriteUtf8NoBomLf $LibPath ((($lib.ToArray()) -join "`n") + "`n")
Parse-GateFile $LibPath

# ---- make_allowed_signers_v1.ps1 (authoritative wrapper) ----
$mk = New-Object System.Collections.Generic.List[string]
[void]$mk.Add("param([Parameter(Mandatory=$true)][string]`$RepoRoot)")
[void]$mk.Add("`$ErrorActionPreference=`"Stop`"")
[void]$mk.Add("Set-StrictMode -Version Latest")
[void]$mk.Add("`$RepoRoot = (Resolve-Path -LiteralPath `$RepoRoot).Path")
[void]$mk.Add("`$ScriptsDir = Join-Path `$RepoRoot `"scripts`"")
[void]$mk.Add(". (Join-Path `$ScriptsDir `"_lib_neverlost_v1.ps1`")")
[void]$mk.Add("`$as = NL-WriteAllowedSigners `$RepoRoot")
[void]$mk.Add("NL-AppendReceipt `$RepoRoot `"neverlost.allowed_signers.write.v1`" @{ allowed_signers_path=`$as; trust_bundle_sha256=(NL-Sha256HexFile (Join-Path `$RepoRoot `"proofs\trust\trust_bundle.json`")) } | Out-Null")
[void]$mk.Add("Write-Host (`"OK: wrote allowed_signers => `"+ `$as) -ForegroundColor Green")
NL-WriteUtf8NoBomLf $MakePath ((($mk.ToArray()) -join "`n") + "`n")
Parse-GateFile $MakePath

# ---- show_identity_v1.ps1 ----
$sh = New-Object System.Collections.Generic.List[string]
[void]$sh.Add("param([Parameter(Mandatory=$true)][string]`$RepoRoot)")
[void]$sh.Add("`$ErrorActionPreference=`"Stop`"")
[void]$sh.Add("Set-StrictMode -Version Latest")
[void]$sh.Add("`$RepoRoot = (Resolve-Path -LiteralPath `$RepoRoot).Path")
[void]$sh.Add("`$ScriptsDir = Join-Path `$RepoRoot `"scripts`"")
[void]$sh.Add(". (Join-Path `$ScriptsDir `"_lib_neverlost_v1.ps1`")")
[void]$sh.Add("`$tbInfo = NL-LoadTrustBundle `$RepoRoot")
[void]$sh.Add("`$tb = `$tbInfo.Tb")
[void]$sh.Add("`$entries = NL-EnumerateSignerEntries `$tb")
[void]$sh.Add("Write-Host (`"TrustBundle: `"+ `$tbInfo.Path) -ForegroundColor Cyan")
[void]$sh.Add("Write-Host (`"TopLevel: `"+ ((@(`$tb.PSObject.Properties.Name) -join `",`"))) -ForegroundColor Cyan")
[void]$sh.Add("Write-Host (`"SignerEntries: `"+ (@(`$entries).Count)) -ForegroundColor Cyan")
[void]$sh.Add("`$byP = @{}")
[void]$sh.Add("foreach(`$e in @(`$entries)){ if ([string]::IsNullOrWhiteSpace([string]`$e.principal)) { continue }; if (-not `$byP.ContainsKey([string]`$e.principal)) { `$byP[[string]`$e.principal] = 0 }; `$byP[[string]`$e.principal] = [int]`$byP[[string]`$e.principal] + 1 }")
[void]$sh.Add("foreach(`$k in (`$byP.Keys | Sort-Object)){ Write-Host (`"- `"+ `$k + `" (keys=`"+ `$byP[`$k] + `")`") -ForegroundColor Yellow }")
[void]$sh.Add("NL-AppendReceipt `$RepoRoot `"neverlost.identity.show.v1`" @{ trust_bundle_sha256=(NL-Sha256HexFile (Join-Path `$RepoRoot `"proofs\trust\trust_bundle.json`")); signer_entry_count=@(`$entries).Count } | Out-Null")
NL-WriteUtf8NoBomLf $ShowPath ((($sh.ToArray()) -join "`n") + "`n")
Parse-GateFile $ShowPath

# ---- sign_file_v1.ps1 ----
$sg = New-Object System.Collections.Generic.List[string]
[void]$sg.Add("param(")
[void]$sg.Add("  [Parameter(Mandatory=$true)][string]`$RepoRoot,")
[void]$sg.Add("  [Parameter(Mandatory=$true)][string]`$Namespace,")
[void]$sg.Add("  [Parameter(Mandatory=$true)][string]`$File,")
[void]$sg.Add("  [Parameter(Mandatory=$true)][string]`$OutSig,")
[void]$sg.Add("  [string]`$Principal = `"`",")
[void]$sg.Add("  [string]`$KeyFile = `"`"")
[void]$sg.Add(")")
[void]$sg.Add("`$ErrorActionPreference=`"Stop`"")
[void]$sg.Add("Set-StrictMode -Version Latest")
[void]$sg.Add("`$RepoRoot = (Resolve-Path -LiteralPath `$RepoRoot).Path")
[void]$sg.Add("`$ScriptsDir = Join-Path `$RepoRoot `"scripts`"")
[void]$sg.Add(". (Join-Path `$ScriptsDir `"_lib_neverlost_v1.ps1`")")
[void]$sg.Add("`$File = (Resolve-Path -LiteralPath `$File).Path")
[void]$sg.Add("`$OutSig = (Resolve-Path -LiteralPath (Split-Path -Parent `$OutSig) -ErrorAction SilentlyContinue).Path + `"\`" + (Split-Path -Leaf `$OutSig) 2>$null")
[void]$sg.Add("`$ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source")
[void]$sg.Add("`$tbInfo = NL-LoadTrustBundle `$RepoRoot")
[void]$sg.Add("`$entries = NL-EnumerateSignerEntries `$tbInfo.Tb")
[void]$sg.Add("if ([string]::IsNullOrWhiteSpace(`$Principal)) { `$Principal = NL-InferPrincipalForNamespace `$entries `$Namespace }")
[void]$sg.Add("`$entry = $null; foreach(`$e in @(`$entries)){ if ([string]`$e.principal -eq `$Principal) { `$entry = `$e; break } }")
[void]$sg.Add("if ($null -eq `$entry) { NL-Die (`"Principal not found in trust bundle: `"+ `$Principal) }")
[void]$sg.Add("`$pub = [string]`$entry.pubkey")
[void]$sg.Add("if ([string]::IsNullOrWhiteSpace(`$pub)) { NL-Die (`"Missing pubkey for principal: `"+ `$Principal) }")
[void]$sg.Add("if ([string]::IsNullOrWhiteSpace(`$KeyFile)) { `$KeyFile = NL-FindPrivateKeyForPubkey `$RepoRoot `$pub }")
[void]$sg.Add("if ([string]::IsNullOrWhiteSpace(`$KeyFile) -or -not (Test-Path -LiteralPath `$KeyFile -PathType Leaf)) { NL-Die (`"No private key found for principal `"+ `$Principal + `". Provide -KeyFile explicitly.`") }")
[void]$sg.Add("`$outDir = Split-Path -Parent `$OutSig; if ($outDir -and -not (Test-Path -LiteralPath `$outDir -PathType Container)) { New-Item -ItemType Directory -Force -Path `$outDir | Out-Null }")
[void]$sg.Add("& `$ssh -Y sign -f `$KeyFile -n `$Namespace -s `$OutSig `$File | Out-Null")
[void]$sg.Add("if ($LASTEXITCODE -ne 0) { NL-Die (`"ssh-keygen -Y sign failed (exit=`"+ `$LASTEXITCODE + `")`") }")
[void]$sg.Add("NL-AppendReceipt `$RepoRoot `"neverlost.sig.sign.v1`" @{ namespace=`$Namespace; principal=`$Principal; key_file=`$KeyFile; file_sha256=(NL-Sha256HexFile `$File); sig_sha256=(NL-Sha256HexFile `$OutSig) } | Out-Null")
[void]$sg.Add("Write-Host (`"OK: signed => `"+ `$OutSig) -ForegroundColor Green")
NL-WriteUtf8NoBomLf $SignPath ((($sg.ToArray()) -join "`n") + "`n")
Parse-GateFile $SignPath

# ---- verify_sig_v1.ps1 ----
$vf = New-Object System.Collections.Generic.List[string]
[void]$vf.Add("param(")
NL-WriteUtf8NoBomLf $VerifyPath ((($vf.ToArray()) -join "`n") + "`n")
Parse-GateFile $VerifyPath

# =========================================
# Selftest (no prompts, deterministic)
# =========================================
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $MakePath -RepoRoot $RepoRoot
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $ShowPath -RepoRoot $RepoRoot
$payload = Join-Path $RepoRoot "proofs\receipts\_nl_test_payload.txt"
"hello neverlost" | Set-Content -LiteralPath $payload -Encoding UTF8
$sig = Join-Path $RepoRoot "proofs\receipts\_nl_test_payload.sig"
# Choose a namespace that exists in your trust_bundle principal namespaces.
# If multiple principals allow it, add -Principal explicitly to sign/verify.
$ns = "watchtower"
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $SignPath -RepoRoot $RepoRoot -Namespace $ns -File $payload -OutSig $sig
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $VerifyPath -RepoRoot $RepoRoot -Namespace $ns -File $payload -Sig $sig

Write-Host ("OK: NeverLost v1 finish complete. Backup: " + $BackupDir) -ForegroundColor Green
