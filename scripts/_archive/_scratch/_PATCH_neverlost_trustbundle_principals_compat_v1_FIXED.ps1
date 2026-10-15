param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if($p -and -not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $u = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path, $u.GetBytes($t))
}
function Parse-GatePs1([string]$p){ [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $p -Encoding UTF8)) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath  = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$MakePath = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$ShowPath = Join-Path $ScriptsDir "show_identity_v1.ps1"
if(-not (Test-Path -LiteralPath $LibPath -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }

$libRaw = Get-Content -Raw -LiteralPath $LibPath -Encoding UTF8
if($libRaw -notmatch "NL_TRUSTBUNDLE_PRINCIPALS_COMPAT_V1"){
  $append = New-Object System.Collections.Generic.List[string]
  [void]$append.Add("")
  [void]$append.Add("# === NL_TRUSTBUNDLE_PRINCIPALS_COMPAT_V1 ===")
  [void]$append.Add("# Supports trust_bundle.principals[] (new) and trust_bundle.signers[] (legacy)")
  [void]$append.Add("function NL-LoadTrustBundleInfoV1([string]`$RepoRoot){")
  [void]$append.Add("  `$rb = (Resolve-Path -LiteralPath `$RepoRoot).Path")
  [void]$append.Add("  `$tbPath = Join-Path `$rb `"proofs\trust\trust_bundle.json`"")
  [void]$append.Add("  if(-not (Test-Path -LiteralPath `$tbPath -PathType Leaf)){ throw (`"MISSING_TRUST_BUNDLE: `"+`$tbPath) }")
  [void]$append.Add("  `$raw = Get-Content -Raw -LiteralPath `$tbPath -Encoding UTF8")
  [void]$append.Add("  `$obj = `$raw | ConvertFrom-Json")
  [void]$append.Add("  return @{ Path=`$tbPath; Raw=`$raw; Obj=`$obj }")
  [void]$append.Add("}")

  [void]$append.Add("function NL-GetTrustBundleEntriesCompat([object]`$TrustBundleObj){")
  [void]$append.Add("  if(`$null -eq `$TrustBundleObj){ throw `"TRUST_BUNDLE_NULL`" }")
  [void]$append.Add("  if((`$TrustBundleObj | Get-Member -Name principals -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)){")
  [void]$append.Add("    `$arr = @(@(`$TrustBundleObj.principals))")
  [void]$append.Add("    `$out = New-Object System.Collections.Generic.List[object]")
  [void]$append.Add("    foreach(`$p in `$arr){")
  [void]$append.Add("      if(`$null -eq `$p){ continue }")
  [void]$append.Add("      `$principal = [string]`$p.principal")
  [void]$append.Add("      `$keyId     = [string]`$p.key_id")
  [void]$append.Add("      `$pubkey    = [string]`$p.pubkey")
  [void]$append.Add("      `$ns = @(@(`$p.namespaces)) | Where-Object { `$_ -ne `$null -and ([string]`$_).Trim().Length -gt 0 } | ForEach-Object { ([string]`$_).Trim() }")
  [void]$append.Add("      if(-not `$principal){ throw `"TRUST_BUNDLE_PRINCIPAL_MISSING`" }")
  [void]$append.Add("      if(-not `$pubkey){ throw (`"TRUST_BUNDLE_PUBKEY_MISSING principal=`"+`$principal) }")
  [void]$append.Add("      `$ns = @(@(`$ns)) | Sort-Object")
  [void]$append.Add("      [void]`$out.Add(@{ principal=`$principal; key_id=`$keyId; pubkey=`$pubkey; namespaces=`$ns })")
  [void]$append.Add("    }")
  [void]$append.Add("    return @(@(`$out))")
  [void]$append.Add("  }")

  [void]$append.Add("  if((`$TrustBundleObj | Get-Member -Name signers -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)){")
  [void]$append.Add("    `$arr = @(@(`$TrustBundleObj.signers))")
  [void]$append.Add("    `$out = New-Object System.Collections.Generic.List[object]")
  [void]$append.Add("    foreach(`$s in `$arr){")
  [void]$append.Add("      if(`$null -eq `$s){ continue }")
  [void]$append.Add("      `$principal = [string]`$s.principal")
  [void]$append.Add("      `$keyId     = [string]`$s.key_id")
  [void]$append.Add("      `$pubkey    = [string]`$s.pubkey")
  [void]$append.Add("      `$ns = @(@(`$s.namespaces)) | Where-Object { `$_ -ne `$null -and ([string]`$_).Trim().Length -gt 0 } | ForEach-Object { ([string]`$_).Trim() }")
  [void]$append.Add("      if(-not `$principal){ throw `"TRUST_BUNDLE_PRINCIPAL_MISSING`" }")
  [void]$append.Add("      if(-not `$pubkey){ throw (`"TRUST_BUNDLE_PUBKEY_MISSING principal=`"+`$principal) }")
  [void]$append.Add("      `$ns = @(@(`$ns)) | Sort-Object")
  [void]$append.Add("      [void]`$out.Add(@{ principal=`$principal; key_id=`$keyId; pubkey=`$pubkey; namespaces=`$ns })")
  [void]$append.Add("    }")
  [void]$append.Add("    return @(@(`$out))")
  [void]$append.Add("  }")

  [void]$append.Add("  `$keys = (@(`$TrustBundleObj.PSObject.Properties) | ForEach-Object { `$_ .Name }) -join `", `"" )
  [void]$append.Add("  throw (`"TRUST_BUNDLE_SCHEMA_UNKNOWN: expected principals[] or signers[]; top_keys=`" + `$keys)")
  [void]$append.Add("}")

  [void]$append.Add("# Override: NL-WriteAllowedSignersFromTrust (last definition wins)")
  [void]$append.Add("function NL-WriteAllowedSignersFromTrust([string]`$RepoRoot){")
  [void]$append.Add("  `$rb = (Resolve-Path -LiteralPath `$RepoRoot).Path")
  [void]$append.Add("  `$tbInfo = NL-LoadTrustBundleInfoV1 `$rb")
  [void]$append.Add("  `$entries = NL-GetTrustBundleEntriesCompat `$tbInfo.Obj")
  [void]$append.Add("  `$asPath = Join-Path `$rb `"proofs\trust\allowed_signers`"")
  [void]$append.Add("  `$lines = New-Object System.Collections.Generic.List[string]")
  [void]$append.Add("  foreach(`$e in (`$entries | Sort-Object principal)){")
  [void]$append.Add("    `$principal = [string]`$e.principal")
  [void]$append.Add("    `$pubkey = [string]`$e.pubkey")
  [void]$append.Add("    `$ns = @(@(`$e.namespaces)) | Sort-Object")
  [void]$append.Add("    `$opt = `"`"")
  [void]$append.Add("    if(`$ns.Count -gt 0){ `$opt = (`" namespaces=\`"`" + (`$ns -join `",`") + `"\`"`") }")
  [void]$append.Add("    [void]`$lines.Add((`$principal + `" `" + `$pubkey + `$opt))")
  [void]$append.Add("  }")
  [void]$append.Add("  `$txt = (@(`$lines) -join `"`n`") + `"`n`"")
  [void]$append.Add("  if(Get-Command Write-Utf8NoBomLf -ErrorAction SilentlyContinue){ Write-Utf8NoBomLf `$asPath `$txt } else {")
  [void]$append.Add("    `$t = (`$txt -replace `"`r`n`",`"`n`") -replace `"`r`",`"`n`"")
  [void]$append.Add("    if(-not `$t.EndsWith(`"`n`")){ `$t += `"`n`" }")
  [void]$append.Add("    [System.IO.File]::WriteAllBytes(`$asPath, (New-Object System.Text.UTF8Encoding(`$false)).GetBytes(`$t))")
  [void]$append.Add("  }")
  [void]$append.Add("  return `$asPath")
  [void]$append.Add("}")

  $compatText = (@($append) -join "`n") + "`n"
  $libNorm = (($libRaw -replace "`r`n","`n") -replace "`r","`n")
  if(-not $libNorm.EndsWith("`n")){ $libNorm += "`n" }
  Write-Utf8NoBomLf $LibPath ($libNorm + $compatText)
  Parse-GatePs1 $LibPath
  Write-Host ("PATCH_OK: lib " + $LibPath) -ForegroundColor Green
} else {
  Write-Host ("OK: compat already present in lib: " + $LibPath) -ForegroundColor Yellow
}

# Overwrite make_allowed_signers_v1.ps1
$make = New-Object System.Collections.Generic.List[string]
[void]$make.Add("param([Parameter(Mandatory=`$true)][string]`$RepoRoot)")
[void]$make.Add("`$ErrorActionPreference=`"Stop`"")
[void]$make.Add("Set-StrictMode -Version Latest")
[void]$make.Add("`$RepoRoot=(Resolve-Path -LiteralPath `$RepoRoot).Path")
[void]$make.Add("`$ScriptsDir=Join-Path `$RepoRoot `"scripts`"")
[void]$make.Add(". (Join-Path `$ScriptsDir `"_lib_neverlost_v1.ps1`")")
[void]$make.Add("`$as = NL-WriteAllowedSignersFromTrust `$RepoRoot")
[void]$make.Add("Write-Host (`"OK: allowed_signers written: `"+`$as) -ForegroundColor Green")
Write-Utf8NoBomLf $MakePath ((@($make) -join "`n") + "`n")
Parse-GatePs1 $MakePath
Write-Host ("PATCH_OK: " + $MakePath) -ForegroundColor Green

# Overwrite show_identity_v1.ps1
$show = New-Object System.Collections.Generic.List[string]
[void]$show.Add("param([Parameter(Mandatory=`$true)][string]`$RepoRoot)")
[void]$show.Add("`$ErrorActionPreference=`"Stop`"")
[void]$show.Add("Set-StrictMode -Version Latest")
[void]$show.Add("`$RepoRoot=(Resolve-Path -LiteralPath `$RepoRoot).Path")
[void]$show.Add("`$ScriptsDir=Join-Path `$RepoRoot `"scripts`"")
[void]$show.Add(". (Join-Path `$ScriptsDir `"_lib_neverlost_v1.ps1`")")
[void]$show.Add("`$tbInfo = NL-LoadTrustBundleInfoV1 `$RepoRoot")
[void]$show.Add("`$entries = NL-GetTrustBundleEntriesCompat `$tbInfo.Obj")
[void]$show.Add("Write-Host (`"TRUST_BUNDLE: `"+`$tbInfo.Path) -ForegroundColor Gray")
[void]$show.Add("Write-Host (`"SIGNERS: `"+(@(`$entries).Count)) -ForegroundColor Gray")
[void]$show.Add("foreach(`$e in (`$entries | Sort-Object principal)){")
[void]$show.Add("  `$p=[string]`$e.principal; `$k=[string]`$e.key_id; `$ns=@(@(`$e.namespaces)) -join `",`"")
[void]$show.Add("  Write-Host (`"  `"+`$p+`"  key_id=`"+`$k+`"  namespaces=`"+`$ns) -ForegroundColor White")
[void]$show.Add("}")
Write-Utf8NoBomLf $ShowPath ((@($show) -join "`n") + "`n")
Parse-GatePs1 $ShowPath
Write-Host ("PATCH_OK: " + $ShowPath) -ForegroundColor Green

Write-Host "NEXT:" -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $MakePath + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $ShowPath + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
