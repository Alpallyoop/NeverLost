param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $u = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path, $u.GetBytes($t))
}
function Parse-GatePs1([string]$p){ [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $p -Encoding UTF8)) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
if(-not (Test-Path -LiteralPath $LibPath -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }

$raw = Get-Content -Raw -LiteralPath $LibPath -Encoding UTF8
$anchor = "# === NL_TRUSTBUNDLE_PRINCIPALS_COMPAT_V1 ==="
$idx = $raw.IndexOf($anchor, [System.StringComparison]::Ordinal)
if($idx -lt 0){ Die ("ANCHOR_NOT_FOUND: " + $anchor + " in " + $LibPath) }
$head = $raw.Substring(0, $idx)

# Build known-good compat tail (no \" escaping; no malformed tokens)
$T = New-Object System.Collections.Generic.List[string]
[void]$T.Add("# === NL_TRUSTBUNDLE_PRINCIPALS_COMPAT_V1 ===")
[void]$T.Add("# Supports trust_bundle.principals[] (new) and trust_bundle.signers[] (legacy)")
[void]$T.Add("function NL-LoadTrustBundleInfoV1([string]$RepoRoot){")
[void]$T.Add("  $rb = (Resolve-Path -LiteralPath $RepoRoot).Path")
[void]$T.Add("  $tbPath = Join-Path $rb 'proofs\trust\trust_bundle.json'")
[void]$T.Add("  if(-not (Test-Path -LiteralPath $tbPath -PathType Leaf)){ throw ('MISSING_TRUST_BUNDLE: ' + $tbPath) }")
[void]$T.Add("  $raw = Get-Content -Raw -LiteralPath $tbPath -Encoding UTF8")
[void]$T.Add("  $obj = $raw | ConvertFrom-Json")
[void]$T.Add("  return @{ Path=$tbPath; Raw=$raw; Obj=$obj }")
[void]$T.Add("}")

[void]$T.Add("function NL-GetTrustBundleEntriesCompat([object]$TrustBundleObj){")
[void]$T.Add("  if($null -eq $TrustBundleObj){ throw 'TRUST_BUNDLE_NULL' }")
[void]$T.Add("  $hasPrincipals = $false")
[void]$T.Add("  $hasSigners = $false")
[void]$T.Add("  if($TrustBundleObj.PSObject -and $TrustBundleObj.PSObject.Properties){")
[void]$T.Add("    $hasPrincipals = @($TrustBundleObj.PSObject.Properties.Name) -contains 'principals'")
[void]$T.Add("    $hasSigners    = @($TrustBundleObj.PSObject.Properties.Name) -contains 'signers'")
[void]$T.Add("  }")
[void]$T.Add("  $src = $null")
[void]$T.Add("  if($hasPrincipals){ $src = @(@($TrustBundleObj.principals)) } elseif($hasSigners){ $src = @(@($TrustBundleObj.signers)) } else {")
[void]$T.Add("    $keys = @()")
[void]$T.Add("    if($TrustBundleObj.PSObject -and $TrustBundleObj.PSObject.Properties){ $keys = @($TrustBundleObj.PSObject.Properties.Name) }")
[void]$T.Add("    throw ('TRUST_BUNDLE_SCHEMA_UNKNOWN: expected principals[] or signers[]; top_keys=' + ($keys -join ', '))")
[void]$T.Add("  }")
[void]$T.Add("  $out = New-Object System.Collections.Generic.List[object]")
[void]$T.Add("  foreach($p in $src){")
[void]$T.Add("    if($null -eq $p){ continue }")
[void]$T.Add("    $principal = [string]$p.principal")
[void]$T.Add("    $keyId     = [string]$p.key_id")
[void]$T.Add("    $pubkey    = [string]$p.pubkey")
[void]$T.Add("    $ns = @(@($p.namespaces)) | Where-Object { $_ -ne $null -and ([string]$_).Trim().Length -gt 0 } | ForEach-Object { ([string]$_).Trim() }")
[void]$T.Add("    if(-not $principal){ throw 'TRUST_BUNDLE_PRINCIPAL_MISSING' }")
[void]$T.Add("    if(-not $pubkey){ throw ('TRUST_BUNDLE_PUBKEY_MISSING principal=' + $principal) }")
[void]$T.Add("    $ns = @(@($ns)) | Sort-Object")
[void]$T.Add("    [void]$out.Add(@{ principal=$principal; key_id=$keyId; pubkey=$pubkey; namespaces=$ns })")
[void]$T.Add("  }")
[void]$T.Add("  return @(@($out))")
[void]$T.Add("}")

[void]$T.Add("# Override: NL-WriteAllowedSignersFromTrust (last definition wins)")
[void]$T.Add("function NL-WriteAllowedSignersFromTrust([string]$RepoRoot){")
[void]$T.Add("  $rb = (Resolve-Path -LiteralPath $RepoRoot).Path")
[void]$T.Add("  $tbInfo = NL-LoadTrustBundleInfoV1 $rb")
[void]$T.Add("  $entries = NL-GetTrustBundleEntriesCompat $tbInfo.Obj")
[void]$T.Add("  $asPath = Join-Path $rb 'proofs\trust\allowed_signers'")
[void]$T.Add("  $lines = New-Object System.Collections.Generic.List[string]")
[void]$T.Add("  foreach($e in ($entries | Sort-Object principal)){")
[void]$T.Add("    $principal = [string]$e.principal")
[void]$T.Add("    $pubkey    = [string]$e.pubkey")
[void]$T.Add("    $ns = @(@($e.namespaces)) | Sort-Object")
[void]$T.Add("    if($ns.Count -gt 0){")
[void]$T.Add("      [void]$lines.Add(($principal + ' ' + $pubkey + ' namespaces=' + ($ns -join ',')))")
[void]$T.Add("    } else {")
[void]$T.Add("      [void]$lines.Add(($principal + ' ' + $pubkey))")
[void]$T.Add("    }")
[void]$T.Add("  }")
[void]$T.Add("  $txt = (@($lines) -join ""`n"") + ""`n""")
[void]$T.Add("  $t = ($txt -replace ""`r`n"",""`n"") -replace ""`r"",""`n""")
[void]$T.Add("  if(-not $t.EndsWith(""`n"")){ $t += ""`n"" }")
[void]$T.Add("  [System.IO.File]::WriteAllBytes($asPath, (New-Object System.Text.UTF8Encoding($false)).GetBytes($t))")
[void]$T.Add("  return $asPath")
[void]$T.Add("}")

$tail = ((@($T) -join "`n") + "`n")
$head2 = (($head -replace "`r`n","`n") -replace "`r","`n")
if(-not $head2.EndsWith("`n")){ $head2 += "`n" }
$fixed = $head2 + $tail
Write-Utf8NoBomLf $LibPath $fixed
Parse-GatePs1 $LibPath
Write-Host ("PATCH_OK: repaired compat tail in " + $LibPath) -ForegroundColor Green

Write-Host "NEXT:" -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $ScriptsDir "make_allowed_signers_v1.ps1") + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
Write-Host ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $ScriptsDir "show_identity_v1.ps1") + "`" -RepoRoot `"" + $RepoRoot + "`"") -ForegroundColor Gray
