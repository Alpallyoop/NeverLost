param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $Pwsh) { throw "pwsh not found in PATH. Install PowerShell 7+." }

$enc = [System.Text.UTF8Encoding]::new($false)
function Write-Utf8NoBomFile([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $norm = $Text.Replace("`r`n","`n").TrimEnd() + "`n"
  [System.IO.File]::WriteAllBytes($Path, $enc.GetBytes($norm))
}

$Patch = Join-Path $RepoRoot "scripts\_patch_neverlost_identity_contract_v8.ps1"

$patchText = @'
param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

# -------------------------
# Minimal deterministic lib (self-contained for patch)
# -------------------------
$enc = [System.Text.UTF8Encoding]::new($false)

function NL-WriteUtf8NoBomFile([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllBytes($Path, $enc.GetBytes($Text.Replace("`r`n","`n").TrimEnd() + "`n"))
}
function NL-ResolvePath([string]$Path){ (Resolve-Path -LiteralPath $Path).Path }
function NL-ReadAllBytes([string]$Path){ [System.IO.File]::ReadAllBytes((NL-ResolvePath $Path)) }
function NL-ReadUtf8([string]$Path){ $enc.GetString((NL-ReadAllBytes $Path)) }

function NL-Sha256HexBytes([byte[]]$Bytes){
  if ($null -eq $Bytes) { throw "sha256 bytes is null" }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $h = $sha.ComputeHash([byte[]]$Bytes)
    return (([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant())
  } finally { $sha.Dispose() }
}
function NL-Sha256HexPath([string]$Path){
  if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found for sha256: $Path" }
  return (NL-Sha256HexBytes ([byte[]](NL-ReadAllBytes $Path)))
}

function NL-ConvertFromJsonCompat([string]$Json,[int]$Depth=64){
  $cmd = Get-Command ConvertFrom-Json -ErrorAction Stop
  if ($cmd.Parameters.ContainsKey("Depth")) { return ($Json | ConvertFrom-Json -Depth $Depth) }
  return ($Json | ConvertFrom-Json)
}

function NL-Canonify($obj){
  if ($null -eq $obj) { return $null }

  if ($obj -is [System.Collections.IDictionary]) {
    $sd = [System.Collections.Generic.SortedDictionary[string,object]]::new()
    foreach ($k in @($obj.Keys) | Sort-Object) {
      if ($null -eq $k) { throw "dictionary key is null (invalid)" }
      $ks = [string]$k
      $sd[$ks] = NL-Canonify $obj[$k]
    }
    return $sd
  }

  if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
    $arr = New-Object System.Collections.Generic.List[object]
    foreach ($x in $obj) { [void]$arr.Add((NL-Canonify $x)) }
    return $arr.ToArray()
  }

  return $obj
}

function NL-ToCanonJson($obj,[int]$Depth=64){
  $canon = NL-Canonify $obj
  return ($canon | ConvertTo-Json -Depth $Depth -Compress)
}

function NL-AssertPrincipal([string]$Principal){
  if ([string]::IsNullOrWhiteSpace($Principal)) { throw "principal is required." }
  if ($Principal -cne $Principal.ToLowerInvariant()) { throw "principal must be lowercase: $Principal" }
  if ($Principal -match "\s") { throw "principal must not contain whitespace: $Principal" }
  $seg = "[a-z0-9][a-z0-9\-_]*"
  $re  = "^single-tenant\/$seg\/authority\/$seg$"
  if ($Principal -notmatch $re) { throw "principal format invalid (v1): $Principal" }
}

function NL-LoadTrustBundle([string]$TrustBundlePath){
  $txt = NL-ReadUtf8 $TrustBundlePath
  $tb  = NL-ConvertFromJsonCompat $txt 64
  if ($tb.schema -ne "neverlost.trust_bundle.v1") { throw "trust_bundle schema must be neverlost.trust_bundle.v1" }
  if (-not $tb.principals) { throw "trust_bundle missing principals" }

  $principals = @($tb.principals)
  foreach ($p in $principals) {
    if ($null -eq $p -or -not ($p.PSObject.Properties.Name -contains "principal")) {
      throw "trust_bundle principals[] must be objects with property 'principal' (bad element: $($p | Out-String))"
    }
    NL-AssertPrincipal $p.principal
    if (-not ($p.PSObject.Properties.Name -contains "keys") -or -not $p.keys) {
      throw "principal missing keys: $($p.principal)"
    }
  }
  return $tb
}

function NL-WriteAllowedSigners([string]$TrustBundlePath,[string]$RepoRoot,[string]$OutPath){
  $tb = NL-LoadTrustBundle $TrustBundlePath
  $lines = @()

  foreach ($p in (@($tb.principals) | Sort-Object principal)) {
    foreach ($k in (@($p.keys) | Sort-Object key_id)) {
      $pubAbs = Join-Path $RepoRoot ($k.pubkey_path -replace "/","\")
      if (-not (Test-Path -LiteralPath $pubAbs)) { throw "pubkey not found: $pubAbs" }

      $pubFileHash = NL-Sha256HexPath $pubAbs
      if ($pubFileHash -ne $k.pubkey_sha256) {
        throw "pubkey_sha256 mismatch. principal=$($p.principal) key_id=$($k.key_id) expected=$($k.pubkey_sha256) actual=$pubFileHash"
      }

      $pubLine = (NL-ReadUtf8 $pubAbs).Trim()
      foreach ($ns in @($k.namespaces | Sort-Object)) {
        if ([string]::IsNullOrWhiteSpace($ns)) { throw "namespace is empty for principal=$($p.principal) key_id=$($k.key_id)" }
        $lines += ("{0} namespaces=`"{1}`" {2}" -f $p.principal, $ns, $pubLine)
      }
    }
  }

  NL-WriteUtf8NoBomFile $OutPath (($lines -join "`n") + "`n")
  return $true
}

function NL-WriteReceipt([string]$ReceiptsPath, $Obj){
  $line  = (NL-ToCanonJson $Obj)
  $bytes = $enc.GetBytes($line + "`n")
  $dir = Split-Path -Parent $ReceiptsPath
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $fs = [System.IO.File]::Open($ReceiptsPath,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
  try { $fs.Write($bytes,0,$bytes.Length) } finally { $fs.Dispose() }
}

# -------------------------
# Patch begins (NO interactive fragments)
# -------------------------
$trustPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$allowed   = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$rcptPath  = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"

$pubRel    = "proofs/keys/watchtower_authority_ed25519.pub"
$pubAbs    = Join-Path $RepoRoot "proofs\keys\watchtower_authority_ed25519.pub"
if (-not (Test-Path -LiteralPath $pubAbs)) { throw "Missing pubkey: $pubAbs" }

$principal = "single-tenant/watchtower_authority/authority/watchtower"
$keyId     = "watchtower-authority-ed25519"
$pubLine   = (NL-ReadUtf8 $pubAbs).Trim()

# Hard overwrite trust bundle (fixes your corrupt principals object)
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

# PROOF: principals contains objects with .principal
$tb2 = NL-ConvertFromJsonCompat (NL-ReadUtf8 $trustPath) 64
$ps  = @($tb2.principals)
if ($ps.Count -lt 1) { throw "PROOF FAILED: principals empty after write." }
foreach($p in $ps){
  if (-not ($p.PSObject.Properties.Name -contains "principal")) { throw "PROOF FAILED: principals element missing 'principal'." }
}

# allowed_signers
[void](NL-WriteAllowedSigners $trustPath $RepoRoot $allowed)

# Entry scripts (valid here-strings)
$mkPath = Join-Path $RepoRoot "scripts\make_allowed_signers_v1.ps1"
$mkText = @'
param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")

$trust = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$out   = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$rcpt  = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"

[void](NL-WriteAllowedSigners $trust $RepoRoot $out)

NL-WriteReceipt $rcpt @{
  schema="neverlost.receipt.v1"
  time_utc=(Get-Date).ToUniversalTime().ToString("o")
  action="make_allowed_signers"
  ok=$true
  hashes=@{
    trust_bundle_sha256=(NL-Sha256HexPath $trust)
    allowed_signers_sha256=(NL-Sha256HexPath $out)
  }
}
