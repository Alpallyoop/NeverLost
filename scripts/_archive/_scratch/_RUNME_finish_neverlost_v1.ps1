param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { throw ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }
$ScratchDir = Join-Path $ScriptsDir "_scratch"
if (-not (Test-Path -LiteralPath $ScratchDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null }

function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("PARSE_GATE_MISSING_FILE: " + $Path) }
  $tk=$null; $er=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tk,[ref]$er)
  if ($er -and @($er).Count -gt 0) {
    $msg = ($er | Select-Object -First 1 | ForEach-Object { $_.Message })
    Die ("PARSE_GATE_FAIL: " + $Path + " :: " + $msg)
  }
}

# ---- ensure required skeleton dirs ----
foreach($d in @("proofs\keys","proofs\trust","proofs\receipts")){
  $p = Join-Path $RepoRoot $d
  if (-not (Test-Path -LiteralPath $p -PathType Container)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

# ---- backup existing scripts deterministically ----
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ScriptsDir ("_neverlost_backup_finish_v1_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
foreach($p in @(
  "scripts\_lib_neverlost_v1.ps1",
  "scripts\make_allowed_signers_v1.ps1",
  "scripts\show_identity_v1.ps1",
  "scripts\sign_file_v1.ps1",
  "scripts\verify_sig_v1.ps1",
  "scripts\_selftest_neverlost_v1.ps1"
)){
  $src = Join-Path $RepoRoot $p
  if (Test-Path -LiteralPath $src -PathType Leaf) {
    Copy-Item -LiteralPath $src -Destination (Join-Path $BackupDir ((Split-Path -Leaf $src)+".pre_finish_v1")) -Force
  }
}

# ==================================================================
# Write scripts
# ==================================================================
$LibPath    = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$MakePath   = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$ShowPath   = Join-Path $ScriptsDir "show_identity_v1.ps1"
$SignPath   = Join-Path $ScriptsDir "sign_file_v1.ps1"
$VerifyPath = Join-Path $ScriptsDir "verify_sig_v1.ps1"
$SelfPath   = Join-Path $ScriptsDir "_selftest_neverlost_v1.ps1"

# ---------------- LIB ----------------
$L = New-Object System.Collections.Generic.List[string]
[void]$L.Add("$ErrorActionPreference=""Stop""")
[void]$L.Add("Set-StrictMode -Version Latest")
[void]$L.Add("")
[void]$L.Add("function NL-Die([string]`$m){ throw `$m }")
[void]$L.Add("function NL-NowUtc(){ return (Get-Date).ToUniversalTime().ToString(""o"") }")
[void]$L.Add("function NL-CoerceArray(`$v){ return @(@(`$v)) }")
[void]$L.Add("function NL-HasProp(`$obj,[string]`$name){ if (`$null -eq `$obj) { return `$false } return (`$obj.PSObject.Properties.Match(`$name).Count -gt 0) }")
[void]$L.Add("function NL-GetProp(`$obj,[string]`$name){ if (NL-HasProp `$obj `$name) { return `$obj.PSObject.Properties[`$name].Value } return `$null }")
[void]$L.Add("function NL-FirstNonEmpty([object[]]`$vals){ foreach(`$v in @(`$vals)){ if (`$null -eq `$v) { continue }; `$s=[string]`$v; if (-not [string]::IsNullOrWhiteSpace(`$s)) { return `$s } } return "" }")

[void]$L.Add("function NL-WriteUtf8NoBomLf([string]`$Path,[string]`$Text){")
[void]$L.Add("  `$dir = Split-Path -Parent `$Path")
[void]$L.Add("  if (`$dir -and -not (Test-Path -LiteralPath `$dir -PathType Container)) { New-Item -ItemType Directory -Force -Path `$dir | Out-Null }")
[void]$L.Add("  `$t = `$Text -replace ""`r`n"",""`n"" -replace ""`r"",""`n""")
[void]$L.Add("  if (-not `$t.EndsWith(""`n"")) { `$t += ""`n"" }")
[void]$L.Add("  `$enc = New-Object System.Text.UTF8Encoding(`$false)")
[void]$L.Add("  [System.IO.File]::WriteAllText(`$Path,`$t,`$enc)")
[void]$L.Add("}")

[void]$L.Add("function NL-ParseGate([string]`$Path){")
[void]$L.Add("  if (-not (Test-Path -LiteralPath `$Path -PathType Leaf)) { NL-Die (""PARSE_GATE_MISSING_FILE: "" + `$Path) }")
[void]$L.Add("  `$tk=`$null; `$er=`$null")
[void]$L.Add("  [void][System.Management.Automation.Language.Parser]::ParseFile(`$Path,[ref]`$tk,[ref]`$er)")
[void]$L.Add("  if (`$er -and @(`$er).Count -gt 0) {")
[void]$L.Add("    `$msg = (`$er | Select-Object -First 1 | ForEach-Object { `$_.Message })")
[void]$L.Add("    NL-Die (""PARSE_GATE_FAIL: "" + `$Path + "" :: "" + `$msg)")
[void]$L.Add("  }")
[void]$L.Add("}")

[void]$L.Add("function NL-JsonEscape([string]`$s){")
[void]$L.Add("  if (`$null -eq `$s) { return """" }")
[void]$L.Add("  `$sb = New-Object System.Text.StringBuilder")
[void]$L.Add("  foreach(`$ch in `$s.ToCharArray()){")
[void]$L.Add("    `$c = [int][char]`$ch")
[void]$L.Add("    if (`$c -eq 34)  { [void]`$sb.Append([char]92); [void]`$sb.Append([char]34) }")
[void]$L.Add("    elseif(`$c -eq 92){ [void]`$sb.Append([char]92); [void]`$sb.Append([char]92) }")
[void]$L.Add("    elseif(`$c -eq 8) { [void]`$sb.Append([char]92); [void]`$sb.Append([char]98) }")
[void]$L.Add("    elseif(`$c -eq 12){ [void]`$sb.Append([char]92); [void]`$sb.Append([char]102) }")
[void]$L.Add("    elseif(`$c -eq 10){ [void]`$sb.Append([char]92); [void]`$sb.Append([char]110) }")
[void]$L.Add("    elseif(`$c -eq 13){ [void]`$sb.Append([char]92); [void]`$sb.Append([char]114) }")
[void]$L.Add("    elseif(`$c -eq 9) { [void]`$sb.Append([char]92); [void]`$sb.Append([char]116) }")
[void]$L.Add("    elseif(`$c -lt 32){ [void]`$sb.AppendFormat(""\\u{0:x4}"",`$c) }")
[void]$L.Add("    else { [void]`$sb.Append(`$ch) }")
[void]$L.Add("  }")
[void]$L.Add("  return `$sb.ToString()")
[void]$L.Add("}")

[void]$L.Add("function NL-ToCanonJson(`$v){")
[void]$L.Add("  if (`$null -eq `$v) { return ""null"" }")
[void]$L.Add("  if (`$v -is [bool]) { return (if(`$v){""true""}else{""false""}) }")
[void]$L.Add("  if (`$v -is [int] -or `$v -is [long] -or `$v -is [double] -or `$v -is [decimal]) { return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,""{0}"",`$v)) }")
[void]$L.Add("  if (`$v -is [string]) { return (""`"" + (NL-JsonEscape `$v) + ""`"") }")
[void]$L.Add("  if (`$v -is [datetime]) { return (""`"" + (`$v.ToUniversalTime().ToString(""o"")) + ""`"") }")
[void]$L.Add("  if (`$v -is [System.Collections.IDictionary]) {")
[void]$L.Add("    `$names = New-Object System.Collections.Generic.List[string]")
[void]$L.Add("    foreach(`$k in @(`$v.Keys)){ if (`$null -ne `$k) { [void]`$names.Add([string]`$k) } }")
[void]$L.Add("    `$sorted = `$names.ToArray() | Sort-Object")
[void]$L.Add("    `$pairs = New-Object System.Collections.Generic.List[string]")
[void]$L.Add("    foreach(`$n in `$sorted){")
[void]$L.Add("      `$k = ""`"" + (NL-JsonEscape `$n) + ""`""")
[void]$L.Add("      `$j = NL-ToCanonJson `$v[`$n]")
[void]$L.Add("      [void]`$pairs.Add((`$k + "":"" + `$j))")
[void]$L.Add("    }")
[void]$L.Add("    return (""{"" + ((`$pairs.ToArray()) -join "","") + ""}"")")
[void]$L.Add("  }")
[void]$L.Add("  if (`$v -is [System.Collections.IEnumerable] -and -not (`$v -is [string])) {")
[void]$L.Add("    # treat PSObject as object (not array)")
[void]$L.Add("    if (`$v.PSObject -and `$v.PSObject.Properties -and `$v.PSObject.Properties.Count -gt 0) {")
[void]$L.Add("      # fall through")
[void]$L.Add("    } else {")
[void]$L.Add("      `$items = New-Object System.Collections.Generic.List[string]")
[void]$L.Add("      foreach(`$x in @(`$v)){ [void]`$items.Add((NL-ToCanonJson `$x)) }")
[void]$L.Add("      return (""["" + ((`$items.ToArray()) -join "","") + ""]"")")
[void]$L.Add("    }")
[void]$L.Add("  }")
[void]$L.Add("  # object")
[void]$L.Add("  `$names = New-Object System.Collections.Generic.List[string]")
[void]$L.Add("  foreach(`$p in @(`$v.PSObject.Properties)){ if (`$p -and -not [string]::IsNullOrWhiteSpace(`$p.Name)) { [void]`$names.Add([string]`$p.Name) } }")
[void]$L.Add("  `$sorted = `$names.ToArray() | Sort-Object")
[void]$L.Add("  `$pairs = New-Object System.Collections.Generic.List[string]")
[void]$L.Add("  foreach(`$n in `$sorted){")
[void]$L.Add("    `$val = `$v.PSObject.Properties[`$n].Value")
[void]$L.Add("    `$k = ""`"" + (NL-JsonEscape `$n) + ""`""")
[void]$L.Add("    `$j = NL-ToCanonJson `$val")
[void]$L.Add("    [void]`$pairs.Add((`$k + "":"" + `$j))")
[void]$L.Add("  }")
[void]$L.Add("  return (""{"" + ((`$pairs.ToArray()) -join "","") + ""}"")")
[void]$L.Add("}")

[void]$L.Add("function NL-Sha256HexBytes([byte[]]`$b){")
[void]$L.Add("  if (`$null -eq `$b) { `$b = @() }")
[void]$L.Add("  `$sha = [System.Security.Cryptography.SHA256]::Create()")
[void]$L.Add("  try { `$h = `$sha.ComputeHash(`$b) } finally { `$sha.Dispose() }")
[void]$L.Add("  `$sb = New-Object System.Text.StringBuilder")
[void]$L.Add("  foreach(`$x in `$h){ [void]`$sb.AppendFormat(""{0:x2}"",`$x) }")
[void]$L.Add("  return `$sb.ToString()")
[void]$L.Add("}")
[void]$L.Add("function NL-Sha256HexFile([string]`$Path){")
[void]$L.Add("  if (-not (Test-Path -LiteralPath `$Path -PathType Leaf)) { NL-Die (""SHA256_MISSING_FILE: "" + `$Path) }")
[void]$L.Add("  `$fs = [System.IO.File]::OpenRead(`$Path)")
[void]$L.Add("  `$sha = [System.Security.Cryptography.SHA256]::Create()")
[void]$L.Add("  try { `$h = `$sha.ComputeHash(`$fs) } finally { `$sha.Dispose(); `$fs.Dispose() }")
[void]$L.Add("  `$sb = New-Object System.Text.StringBuilder")
[void]$L.Add("  foreach(`$x in `$h){ [void]`$sb.AppendFormat(""{0:x2}"",`$x) }")
[void]$L.Add("  return `$sb.ToString()")
[void]$L.Add("}")

[void]$L.Add("function NL-LoadTrustBundle([string]`$RepoRoot){")
[void]$L.Add("  `$p = Join-Path `$RepoRoot ""proofs\trust\trust_bundle.json""")
[void]$L.Add("  if (-not (Test-Path -LiteralPath `$p -PathType Leaf)) { NL-Die (""MISSING_TRUST_BUNDLE: "" + `$p) }")
[void]$L.Add("  `$raw = Get-Content -Raw -LiteralPath `$p -Encoding UTF8")
[void]$L.Add("  if ([string]::IsNullOrWhiteSpace(`$raw)) { NL-Die (""EMPTY_TRUST_BUNDLE: "" + `$p) }")
[void]$L.Add("  `$tb = `$raw | ConvertFrom-Json")
[void]$L.Add("  if (`$null -eq `$tb) { NL-Die (""TRUST_BUNDLE_PARSE_FAIL: "" + `$p) }")
[void]$L.Add("  return @{ Path=`$p; Raw=`$raw; Tb=`$tb }")
[void]$L.Add("}")

[void]$L.Add("function NL-EnumerateSignerEntries([object]`$tb){")
[void]$L.Add("  `$out = New-Object System.Collections.Generic.List[object]")
[void]$L.Add("  if (NL-HasProp `$tb ""keys"") {")
[void]$L.Add("    foreach(`$k in @(NL-CoerceArray (NL-GetProp `$tb ""keys""))){")
[void]$L.Add("      `$principal = [string](NL-GetProp `$k ""principal"")")
[void]$L.Add("      `$pub = NL-FirstNonEmpty @((NL-GetProp `$k ""pubkey""),(NL-GetProp `$k ""public_key""),(NL-GetProp `$k ""publicKey""),(NL-GetProp `$k ""pub_key""))")
[void]$L.Add("      `$ns = `$null; foreach(`$n in @(""namespaces"",""namespace"",""ns"")){ if (NL-HasProp `$k `$n) { `$ns = NL-GetProp `$k `$n; break } }")
[void]$L.Add("      `$kid = NL-FirstNonEmpty @((NL-GetProp `$k ""key_id""),(NL-GetProp `$k ""keyId""),(NL-GetProp `$k ""kid""))")
[void]$L.Add("      [void]`$out.Add([pscustomobject]@{ principal=`$principal; pubkey=`$pub; namespaces=@(@(`$ns)); key_id=`$kid; raw=`$k })")
[void]$L.Add("    }")
[void]$L.Add("    return @(@(`$out))")
[void]$L.Add("  }")
[void]$L.Add("  if (NL-HasProp `$tb ""principals"") {")
[void]$L.Add("    foreach(`$pobj in @(NL-CoerceArray (NL-GetProp `$tb ""principals""))){")
[void]$L.Add("      `$principal = NL-FirstNonEmpty @((NL-GetProp `$pobj ""principal""),(NL-GetProp `$pobj ""signer_identity""),(NL-GetProp `$pobj ""identity""),(NL-GetProp `$pobj ""id""))")
[void]$L.Add("      `$karr = @(); if (NL-HasProp `$pobj ""keys"") { `$karr = NL-CoerceArray (NL-GetProp `$pobj ""keys"") }")
[void]$L.Add("      foreach(`$k in @(`$karr)){")
[void]$L.Add("        `$pub = NL-FirstNonEmpty @((NL-GetProp `$k ""pubkey""),(NL-GetProp `$k ""public_key""),(NL-GetProp `$k ""publicKey""),(NL-GetProp `$k ""pub_key""))")
[void]$L.Add("        `$ns = `$null; foreach(`$n in @(""namespaces"",""namespace"",""ns"")){ if (NL-HasProp `$k `$n) { `$ns = NL-GetProp `$k `$n; break } }")
[void]$L.Add("        `$kid = NL-FirstNonEmpty @((NL-GetProp `$k ""key_id""),(NL-GetProp `$k ""keyId""),(NL-GetProp `$k ""kid""))")
[void]$L.Add("        [void]`$out.Add([pscustomobject]@{ principal=`$principal; pubkey=`$pub; namespaces=@(@(`$ns)); key_id=`$kid; raw=`$k })")
[void]$L.Add("      }")
[void]$L.Add("    }")
[void]$L.Add("    return @(@(`$out))")
[void]$L.Add("  }")
[void]$L.Add("  return @()")
[void]$L.Add("}")

[void]$L.Add("function NL-WriteAllowedSigners([string]`$RepoRoot){")
[void]$L.Add("  `$tbInfo = NL-LoadTrustBundle `$RepoRoot")
[void]$L.Add("  `$tb = `$tbInfo.Tb")
[void]$L.Add("  `$asPath = Join-Path `$RepoRoot ""proofs\trust\allowed_signers""")
[void]$L.Add("  `$entries = NL-EnumerateSignerEntries `$tb")
[void]$L.Add("  if (`$null -eq `$entries -or @(`$entries).Count -lt 1) { NL-Die (""NO_SIGNER_ENTRIES_IN_TRUST_BUNDLE"") }")
[void]$L.Add("  `$lines = New-Object System.Collections.Generic.List[string]")
[void]$L.Add("  foreach(`$e in @(`$entries)){")
[void]$L.Add("    `$principal = [string]`$e.principal")
[void]$L.Add("    `$pubkey = [string]`$e.pubkey")
[void]$L.Add("    if ([string]::IsNullOrWhiteSpace(`$principal)) { NL-Die ""TRUST_BUNDLE_ENTRY_MISSING_PRINCIPAL"" }")
[void]$L.Add("    if ([string]::IsNullOrWhiteSpace(`$pubkey)) { NL-Die (""TRUST_BUNDLE_ENTRY_MISSING_PUBKEY principal="" + `$principal) }")
[void]$L.Add("    `$ns = @(@(`$e.namespaces) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]`$_) } | ForEach-Object { [string]`$_ })")
[void]$L.Add("    if (`$ns.Count -gt 0) {")
[void]$L.Add("      `$opt = ""namespaces=`"" + ((`$ns | ForEach-Object { [string]`$_ -replace ""`"""","""" } ) -join "","") + ""`"""")
[void]$L.Add("      [void]`$lines.Add((`$principal + "" "" + `$opt + "" "" + `$pubkey).Trim())")
[void]$L.Add("    } else {")
[void]$L.Add("      [void]`$lines.Add((`$principal + "" "" + `$pubkey).Trim())")
[void]$L.Add("    }")
[void]$L.Add("  }")
[void]$L.Add("  `$sorted = `$lines.ToArray() | Sort-Object")
[void]$L.Add("  NL-WriteUtf8NoBomLf `$asPath ((`$sorted -join ""`n"") + ""`n"")")
[void]$L.Add("  return `$asPath")
[void]$L.Add("}")

[void]$L.Add("function NL-AppendReceipt([string]`$RepoRoot,[string]`$event_type,[hashtable]`$data){")
[void]$L.Add("  `$rpath = Join-Path `$RepoRoot ""proofs\receipts\neverlost.ndjson""")
[void]$L.Add("  `$obj = New-Object System.Collections.Hashtable")
[void]$L.Add("  `$obj[""ts_utc""] = NL-NowUtc")
[void]$L.Add("  `$obj[""event_type""] = [string]`$event_type")
[void]$L.Add("  foreach(`$k in @(`$data.Keys)){ `$obj[`$k] = `$data[`$k] }")
[void]$L.Add("  `$line = NL-ToCanonJson ([pscustomobject]`$obj)")
[void]$L.Add("  `$enc = New-Object System.Text.UTF8Encoding(`$false)")
[void]$L.Add("  `$fs = New-Object System.IO.FileStream(`$rpath,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)")
[void]$L.Add("  try {")
[void]$L.Add("    `$bytes = `$enc.GetBytes(`$line + ""`n"")")
[void]$L.Add("    `$fs.Write(`$bytes,0,`$bytes.Length)")
[void]$L.Add("  } finally { `$fs.Dispose() }")
[void]$L.Add("  return `$rpath")
[void]$L.Add("}")

[void]$L.Add("$null = 1")
NL-WriteUtf8NoBomLf $LibPath ((($L.ToArray()) -join "`n") + "`n")
Parse-GateFile $LibPath

# ---------------- make_allowed_signers_v1.ps1 ----------------
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

# ---------------- show_identity_v1.ps1 ----------------
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

# ---------------- sign_file_v1.ps1 ----------------
$sg = New-Object System.Collections.Generic.List[string]
[void]$sg.Add("param(")
[void]$sg.Add("  [Parameter(Mandatory=$true)][string]`$RepoRoot,")
[void]$sg.Add("  [Parameter(Mandatory=$true)][string]`$TargetPath,")
[void]$sg.Add("  [Parameter(Mandatory=$true)][string]`$SigNamespace,")
[void]$sg.Add("  [Parameter(Mandatory=$false)][string]`$Principal,")
[void]$sg.Add("  [Parameter(Mandatory=$false)][string]`$KeyId,")
[void]$sg.Add("  [Parameter(Mandatory=$false)][string]`$PrivKeyPath")
[void]$sg.Add(")")
[void]$sg.Add("`$ErrorActionPreference=`"Stop`"")
[void]$sg.Add("Set-StrictMode -Version Latest")
[void]$sg.Add("`$RepoRoot = (Resolve-Path -LiteralPath `$RepoRoot).Path")
[void]$sg.Add("`$TargetPath = (Resolve-Path -LiteralPath `$TargetPath).Path")
[void]$sg.Add("`$ScriptsDir = Join-Path `$RepoRoot `"scripts`"")
[void]$sg.Add(". (Join-Path `$ScriptsDir `"_lib_neverlost_v1.ps1`")")
[void]$sg.Add("`$ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source")
[void]$sg.Add("if ([string]::IsNullOrWhiteSpace(`$PrivKeyPath)) { NL-Die `"sign_file_v1 requires -PrivKeyPath (private key path)`" }")
[void]$sg.Add("if (-not (Test-Path -LiteralPath `$PrivKeyPath -PathType Leaf)) { NL-Die (`"MISSING_PRIVATE_KEY: `" + `$PrivKeyPath) }")
[void]$sg.Add("if ([string]::IsNullOrWhiteSpace(`$Principal)) { NL-Die `"sign_file_v1 requires -Principal`" }")
[void]$sg.Add("if ([string]::IsNullOrWhiteSpace(`$KeyId)) { NL-Die `"sign_file_v1 requires -KeyId`" }")
[void]$sg.Add("`$sigPath = `$TargetPath + `".sig`"")
[void]$sg.Add("`$cmd = `"`$ssh -Y sign -f `"`"`$PrivKeyPath`"`" -I `"`"`$Principal`"`" -n `"`"`$SigNamespace`"`" `"`"`$TargetPath`"`"`"")
[void]$sg.Add("Write-Host (`"SIGN_CMD: `"+ `$cmd) -ForegroundColor DarkGray")
[void]$sg.Add("& `$ssh -Y sign -f `$PrivKeyPath -I `$Principal -n `$SigNamespace `$TargetPath | Out-Null")
[void]$sg.Add("if (`$LASTEXITCODE -ne 0) { NL-Die (`"SIGN_FAILED exit=`" + `$LASTEXITCODE) }")
[void]$sg.Add("if (-not (Test-Path -LiteralPath `$sigPath -PathType Leaf)) { NL-Die (`"SIGN_MISSING_SIG_FILE: `" + `$sigPath) }")
[void]$sg.Add("NL-AppendReceipt `$RepoRoot `"neverlost.sig.sign.v1`" @{ target=`$TargetPath; sig=`$sigPath; namespace=`$SigNamespace; principal=`$Principal; key_id=`$KeyId; sig_sha256=(NL-Sha256HexFile `$sigPath); target_sha256=(NL-Sha256HexFile `$TargetPath) } | Out-Null")
[void]$sg.Add("Write-Host (`"OK: signed => `"+ `$sigPath) -ForegroundColor Green")
NL-WriteUtf8NoBomLf $SignPath ((($sg.ToArray()) -join "`n") + "`n")
Parse-GateFile $SignPath

# ---------------- verify_sig_v1.ps1 ----------------
$vf = New-Object System.Collections.Generic.List[string]
[void]$vf.Add("param(")
[void]$vf.Add("  [Parameter(Mandatory=$true)][string]`$RepoRoot,")
[void]$vf.Add("  [Parameter(Mandatory=$true)][string]`$TargetPath,")
[void]$vf.Add("  [Parameter(Mandatory=$true)][string]`$SigPath,")
[void]$vf.Add("  [Parameter(Mandatory=$true)][string]`$SigNamespace,")
[void]$vf.Add("  [Parameter(Mandatory=$true)][string]`$Principal")
[void]$vf.Add(")")
[void]$vf.Add("`$ErrorActionPreference=`"Stop`"")
[void]$vf.Add("Set-StrictMode -Version Latest")
[void]$vf.Add("`$RepoRoot = (Resolve-Path -LiteralPath `$RepoRoot).Path")
[void]$vf.Add("`$TargetPath = (Resolve-Path -LiteralPath `$TargetPath).Path")
[void]$vf.Add("`$SigPath = (Resolve-Path -LiteralPath `$SigPath).Path")
[void]$vf.Add("`$ScriptsDir = Join-Path `$RepoRoot `"scripts`"")
[void]$vf.Add(". (Join-Path `$ScriptsDir `"_lib_neverlost_v1.ps1`")")
NL-WriteUtf8NoBomLf $VerifyPath ((($vf.ToArray()) -join "`n") + "`n")
Parse-GateFile $VerifyPath

# ---------------- _selftest_neverlost_v1.ps1 ----------------
$st = New-Object System.Collections.Generic.List[string]
[void]$st.Add("param([Parameter(Mandatory=$true)][string]`$RepoRoot)")
NL-WriteUtf8NoBomLf $SelfPath ((($st.ToArray()) -join "`n") + "`n")
Parse-GateFile $SelfPath

# ==================================================================
# Run selftest
# ==================================================================
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SelfPath -RepoRoot $RepoRoot

Write-Host ("FINISH_OK: wrote core NeverLost scripts; backups at: " + $BackupDir) -ForegroundColor Green
Write-Host "NEXT (commit only final scripts, not scratch/backups):" -ForegroundColor Gray
Write-Host "  git add scripts/_lib_neverlost_v1.ps1 scripts/make_allowed_signers_v1.ps1 scripts/show_identity_v1.ps1 scripts/sign_file_v1.ps1 scripts/verify_sig_v1.ps1 scripts/_selftest_neverlost_v1.ps1" -ForegroundColor Gray
