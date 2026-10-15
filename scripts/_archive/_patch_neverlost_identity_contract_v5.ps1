param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Ensure-Dir([string]$p){ if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
$enc = [System.Text.UTF8Encoding]::new($false)
function Write-Utf8NoBom([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllBytes($Path, $enc.GetBytes($Text.Replace("`r`n","`n").TrimEnd() + "`n"))
}

if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "RepoRoot not found: $RepoRoot" }
Write-Host ("HOST: " + $PSVersionTable.PSEdition + " " + $PSVersionTable.PSVersion.ToString()) -ForegroundColor Cyan
Write-Host ("EXE : " + (Get-Process -Id $PID).Path) -ForegroundColor Cyan

Ensure-Dir (Join-Path $RepoRoot "scripts")
Ensure-Dir (Join-Path $RepoRoot "proofs\keys")
Ensure-Dir (Join-Path $RepoRoot "proofs\trust")
Ensure-Dir (Join-Path $RepoRoot "proofs\receipts")

$rcptPath = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"
if (-not (Test-Path -LiteralPath $rcptPath)) { Write-Utf8NoBom $rcptPath "" }

# ==========================================================
# 1) HARD OVERWRITE LIB (kills $ordered + fixes ComputeHash + PS5 json depth compat)
# ==========================================================
$libPath = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
$libLines = @()
$libLines += '$ErrorActionPreference="Stop"' 'Set-StrictMode -Version Latest' '' 'function NL-GetUtf8NoBomEncoding(){ [System.Text.UTF8Encoding]::new($false) }' 'function NL-ResolvePath([string]$Path){ (Resolve-Path -LiteralPath $Path).Path }' 'function NL-ReadAllBytes([string]$Path){ [System.IO.File]::ReadAllBytes((NL-ResolvePath $Path)) }' 'function NL-ReadUtf8([string]$Path){ (NL-GetUtf8NoBomEncoding).GetString((NL-ReadAllBytes $Path)) }' 'function NL-WriteUtf8NoBomFile([string]$Path,[string]$Text){' '  $enc = NL-GetUtf8NoBomEncoding' '  $dir = Split-Path -Parent $Path' '  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }' '  [System.IO.File]::WriteAllBytes($Path, $enc.GetBytes($Text.Replace("`r`n","`n").TrimEnd() + "`n"))' '}' '' 'function NL-Sha256HexBytes([byte[]]$Bytes){' '  if ($null -eq $Bytes) { throw "sha256 bytes is null" }' '  $sha = [System.Security.Cryptography.SHA256]::Create()' '  try {' '    $h = $sha.ComputeHash([byte[]]$Bytes)' '    return (([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant())' '  } finally { $sha.Dispose() }' '}' '' 'function NL-Sha256HexPath([string]$Path){' '  if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found for sha256: $Path" }' '  $b = [byte[]](NL-ReadAllBytes $Path)' '  return (NL-Sha256HexBytes $b)' '}' '' '# single-tenant/<tenant_authority>/authority/<producer>' 'function NL-AssertPrincipal([string]$Principal){' '  if ([string]::IsNullOrWhiteSpace($Principal)) { throw "principal is required." }' '  if ($Principal -cne $Principal.ToLowerInvariant()) { throw "principal must be lowercase: $Principal" }' '  if ($Principal -match "\s") { throw "principal must not contain whitespace: $Principal" }' '  if ($Principal.Length -gt 256) { throw "principal too long (>256): $Principal" }' '  $seg = "[a-z0-9][a-z0-9\-_]*"' '  $re  = "^single-tenant\/$seg\/authority\/$seg$"' '  if ($Principal -notmatch $re) { throw "principal format invalid (v1): $Principal" }' '}' '' 'function NL-AssertKeyId([string]$KeyId){' '  if ([string]::IsNullOrWhiteSpace($KeyId)) { throw "key_id is required." }' '  if ($KeyId.Length -gt 128) { throw "key_id too long (>128): $KeyId" }' '  if ($KeyId -match "\s") { throw "key_id must not contain whitespace: $KeyId" }' '  $re = "^[a-z0-9][a-z0-9\-]*[a-z0-9]$"' '  if ($KeyId -notmatch $re) { throw "key_id format invalid: $KeyId" }' '}' '' 'function NL-ConvertFromJsonCompat([string]$Json,[int]$Depth=64){' '  $cmd = Get-Command ConvertFrom-Json -ErrorAction Stop' '  if ($cmd.Parameters.ContainsKey("Depth")) { return ($Json | ConvertFrom-Json -Depth $Depth) }' '  return ($Json | ConvertFrom-Json)' '}' '' '# Deterministic JSON (no [ordered], no OrderedDictionary). Use SortedDictionary.' 'function NL-Canonify($obj){' '  if ($null -eq $obj) { return $null }' '  if ($obj -is [System.Collections.IDictionary]) {' '    $sd = [System.Collections.Generic.SortedDictionary[string,object]]::new()' '    foreach ($k in @($obj.Keys) | Sort-Object) {' '      if ($null -eq $k) { throw "dictionary key is null (invalid)" }' '      $ks = [string]$k' '      $sd[$ks] = NL-Canonify $obj[$k]' '    }' '    return $sd' '  }' '  if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {' '    $arr = New-Object System.Collections.Generic.List[object]' '    foreach ($x in $obj) { [void]$arr.Add((NL-Canonify $x)) }' '    return $arr.ToArray()' '  }' '  return $obj' '}' '' 'function NL-ToCanonJson($obj,[int]$Depth=64){' '  $canon = NL-Canonify $obj' '  return ($canon | ConvertTo-Json -Depth $Depth -Compress)' '}' '' 'function NL-LoadTrustBundle([string]$TrustBundlePath){' '  if (-not (Test-Path -LiteralPath $TrustBundlePath)) { throw "trust_bundle.json not found: $TrustBundlePath" }' '  $txt = NL-ReadUtf8 $TrustBundlePath' '  $tb  = NL-ConvertFromJsonCompat $txt 64' '  if ($tb.schema -ne "neverlost.trust_bundle.v1") { throw "trust_bundle.json schema must be neverlost.trust_bundle.v1" }' '  if (-not $tb.principals) { throw "trust_bundle.json missing principals" }' '  foreach ($p in $tb.principals) {' '    NL-AssertPrincipal $p.principal' '    if (-not $p.keys) { throw "principal missing keys: $($p.principal)" }' '    foreach ($k in $p.keys) {' '      NL-AssertKeyId $k.key_id' '      if (-not $k.namespaces) { throw "key missing namespaces for principal=$($p.principal) key_id=$($k.key_id)" }' '      if (-not $k.pubkey_path) { throw "key missing pubkey_path for principal=$($p.principal) key_id=$($k.key_id)" }' '      if (-not $k.pubkey_sha256) { throw "key missing pubkey_sha256 for principal=$($p.principal) key_id=$($k.key_id)" }' '      if (-not $k.alg) { $k | Add-Member -NotePropertyName "alg" -NotePropertyValue "ssh-ed25519" -Force }' '    }' '  }' '  return $tb' '}' '' 'function NL-WriteAllowedSigners([string]$TrustBundlePath,[string]$RepoRoot,[string]$OutPath){' '  $tb = NL-LoadTrustBundle $TrustBundlePath' '  $lines = @()' '  foreach ($p in ($tb.principals | Sort-Object principal)) {' '    foreach ($k in ($p.keys | Sort-Object key_id)) {' '      $pubAbs = Join-Path $RepoRoot ($k.pubkey_path -replace "/","\")' '      if (-not (Test-Path -LiteralPath $pubAbs)) { throw "pubkey not found: $pubAbs" }' '      $pubFileHash = NL-Sha256HexPath $pubAbs' '      if ($pubFileHash -ne $k.pubkey_sha256) {' '        throw "pubkey_sha256 mismatch. principal=$($p.principal) key_id=$($k.key_id) expected=$($k.pubkey_sha256) actual=$pubFileHash"' '      }' '      $pubLine = (NL-ReadUtf8 $pubAbs).Trim()' '      foreach ($ns in @($k.namespaces | Sort-Object)) {' '        if ([string]::IsNullOrWhiteSpace($ns)) { throw "namespace is empty for principal=$($p.principal) key_id=$($k.key_id)" }' '        $lines += ("{0} namespaces=`"{1}`" {2}" -f $p.principal, $ns, $pubLine)' '      }' '    }' '  }' '  NL-WriteUtf8NoBomFile $OutPath (($lines -join "`n") + "`n")' '  return $true' '}' '' 'function NL-WriteReceipt([string]$ReceiptsPath, $Obj){' '  $line = (NL-ToCanonJson $Obj)' '  $enc = NL-GetUtf8NoBomEncoding' '  $bytes = $enc.GetBytes($line + "`n")' '  $fs = [System.IO.File]::Open($ReceiptsPath,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)' '  try { $fs.Write($bytes,0,$bytes.Length) } finally { $fs.Dispose() }' '}'
Write-Utf8NoBom $libPath (($libLines -join "`n") + "`n")

# PROOF: lib on disk must not contain $ordered and must contain NL-Canonify
$libTxt = [System.IO.File]::ReadAllText($libPath, $enc)
if ($libTxt -match '\$ordered') { throw "LIB PROOF FAILED: `$ordered still present." }
if ($libTxt -notmatch 'function NL-Canonify') { throw "LIB PROOF FAILED: NL-Canonify missing." }

. $libPath

# ==========================================================
# 2) Rewrite trust_bundle.json (Watchtower canonical shape)
# ==========================================================
$trustPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$pubRel    = "proofs/keys/watchtower_authority_ed25519.pub"
$pubAbs    = Join-Path $RepoRoot "proofs\keys\watchtower_authority_ed25519.pub"
if (-not (Test-Path -LiteralPath $pubAbs)) { throw "Missing pubkey: $pubAbs" }
$principal = "single-tenant/watchtower_authority/authority/watchtower"
$keyId     = "watchtower-authority-ed25519"
$pubLine   = (NL-ReadUtf8 $pubAbs).Trim()
$bundle = @{
  schema      = "neverlost.trust_bundle.v1"
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  principals  = @(
    @{
      principal = $principal
      keys      = @(
        @{
          key_id        = $keyId
          alg           = "ssh-ed25519"
          pubkey_path   = $pubRel
          pubkey_sha256 = (NL-Sha256HexPath $pubAbs)
          pubkey        = $pubLine
          namespaces    = @("packet/envelope","watchtower","watchtower/device-pledge","nfl/ingest-receipt")
        }
      )
    }
  )
}
NL-WriteUtf8NoBomFile $trustPath ((NL-ToCanonJson $bundle) + "`n")

# ==========================================================
# 3) Generate allowed_signers
# ==========================================================
$allowed = Join-Path $RepoRoot "proofs\trust\allowed_signers"
[void](NL-WriteAllowedSigners $trustPath $RepoRoot $allowed)

# ==========================================================
# 4) Overwrite entry scripts
# ==========================================================
$mk = Join-Path $RepoRoot "scripts\make_allowed_signers_v1.ps1"
Write-Utf8NoBom $mk @"
param([Parameter(Mandatory=`$true)][string]`$RepoRoot)
`$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path `$PSScriptRoot "_lib_neverlost_v1.ps1")
`$trust = Join-Path `$RepoRoot "proofs\trust\trust_bundle.json"
`$out   = Join-Path `$RepoRoot "proofs\trust\allowed_signers"
`$rcpt  = Join-Path `$RepoRoot "proofs\receipts\neverlost.ndjson"
[void](NL-WriteAllowedSigners `$trust `$RepoRoot `$out)
NL-WriteReceipt `$rcpt @{
  schema="neverlost.receipt.v1"
  time_utc=(Get-Date).ToUniversalTime().ToString("o")
  action="make_allowed_signers"
  ok=`$true
  hashes=@{
    trust_bundle_sha256=(NL-Sha256HexPath `$trust)
    allowed_signers_sha256=(NL-Sha256HexPath `$out)
  }
}
"@

$si = Join-Path $RepoRoot "scripts\show_identity_v1.ps1"
Write-Utf8NoBom $si @"
param([Parameter(Mandatory=`$true)][string]`$RepoRoot)
`$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path `$PSScriptRoot "_lib_neverlost_v1.ps1")
`$trust = Join-Path `$RepoRoot "proofs\trust\trust_bundle.json"
`$as    = Join-Path `$RepoRoot "proofs\trust\allowed_signers"
`$rcpt  = Join-Path `$RepoRoot "proofs\receipts\neverlost.ndjson"
`$tb = NL-LoadTrustBundle `$trust
Write-Host "NeverLost v1 - Identity Layer (Watchtower contract)"
Write-Host ("trust_bundle_sha256    : " + (NL-Sha256HexPath `$trust))
Write-Host ("allowed_signers_sha256 : " + (if (Test-Path -LiteralPath `$as) { NL-Sha256HexPath `$as } else { "" }))
Write-Host ("principals_count       : " + @(`$tb.principals).Count)
Write-Host ""
foreach(`$p in (`$tb.principals | Sort-Object principal)) {
  Write-Host ("principal: " + `$p.principal)
  foreach(`$k in (`$p.keys | Sort-Object key_id)) {
    Write-Host ("  key_id     : " + `$k.key_id)
    Write-Host ("  alg        : " + `$k.alg)
    Write-Host ("  pubkey_path: " + `$k.pubkey_path)
    Write-Host ("  namespaces : " + ((@(`$k.namespaces) | Sort-Object) -join ", "))
  }
  Write-Host ""
}
NL-WriteReceipt `$rcpt @{
  schema="neverlost.receipt.v1"
  time_utc=(Get-Date).ToUniversalTime().ToString("o")
  action="show_identity"
  ok=`$true
  hashes=@{
    trust_bundle_sha256=(NL-Sha256HexPath `$trust)
    allowed_signers_sha256=(if (Test-Path -LiteralPath `$as) { NL-Sha256HexPath `$as } else { "" })
  }
}
"@

# ==========================================================
# 5) Patch receipt + final proofs
# ==========================================================
NL-WriteReceipt $rcptPath @{
  schema="neverlost.receipt.v1"
  time_utc=(Get-Date).ToUniversalTime().ToString("o")
  action="patch_neverlost_identity_contract_v5"
  ok=$true
  hashes=@{
    lib_sha256=(NL-Sha256HexPath $libPath)
    trust_bundle_sha256=(NL-Sha256HexPath $trustPath)
    allowed_signers_sha256=(NL-Sha256HexPath $allowed)
    make_allowed_signers_sha256=(NL-Sha256HexPath $mk)
    show_identity_sha256=(NL-Sha256HexPath $si)
  }
}

# Final: prove $ordered is absent on disk (regex, not -SimpleMatch)
if (Select-String -LiteralPath $libPath -Pattern '\$ordered' -AllMatches -ErrorAction SilentlyContinue) {
  throw "FINAL PROOF FAILED: `$ordered still found in _lib_neverlost_v1.ps1"
}

Write-Host "OK: NeverLost v1 patched (identity contract v5)" -ForegroundColor Green
Write-Host ("lib_sha256            : " + (NL-Sha256HexPath $libPath))
Write-Host ("trust_bundle_sha256    : " + (NL-Sha256HexPath $trustPath))
Write-Host ("allowed_signers_sha256 : " + (NL-Sha256HexPath $allowed))
