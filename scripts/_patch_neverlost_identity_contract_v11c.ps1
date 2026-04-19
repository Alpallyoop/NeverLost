param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "RepoRoot not found: $RepoRoot" }

$enc = [System.Text.UTF8Encoding]::new($false)
function Write-Utf8NoBomFile([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").TrimEnd() + "`n"
  [System.IO.File]::WriteAllBytes($Path, $enc.GetBytes($t))
}
function Ensure-Dir([string]$p){ if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }

Ensure-Dir (Join-Path $RepoRoot "scripts")
Ensure-Dir (Join-Path $RepoRoot "proofs\keys")
Ensure-Dir (Join-Path $RepoRoot "proofs\trust")
Ensure-Dir (Join-Path $RepoRoot "proofs\receipts")

$rcptPath = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"
if (-not (Test-Path -LiteralPath $rcptPath)) { [System.IO.File]::WriteAllBytes($rcptPath, $enc.GetBytes("")) }

# ------------------------------------------------------------
# 1) OVERWRITE scripts\_lib_neverlost_v1.ps1 (defines NL-*)
# ------------------------------------------------------------
$libPath = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
$libLines = @(
  '$ErrorActionPreference="Stop"',
  'Set-StrictMode -Version Latest',
  '',
  'function NL-GetUtf8NoBomEncoding(){ [System.Text.UTF8Encoding]::new($false) }',
  'function NL-ResolvePath([string]$Path){ (Resolve-Path -LiteralPath $Path).Path }',
  'function NL-ReadAllBytes([string]$Path){ [System.IO.File]::ReadAllBytes((NL-ResolvePath $Path)) }',
  'function NL-ReadUtf8([string]$Path){ (NL-GetUtf8NoBomEncoding).GetString((NL-ReadAllBytes $Path)) }',
  'function NL-WriteUtf8NoBomFile([string]$Path,[string]$Text){',
  '  $enc2 = NL-GetUtf8NoBomEncoding',
  '  $dir = Split-Path -Parent $Path',
  '  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }',
  '  [System.IO.File]::WriteAllBytes($Path, $enc2.GetBytes($Text.Replace("`r`n","`n").TrimEnd() + "`n"))',
  '}',
  'function NL-Sha256HexBytes([byte[]]$Bytes){',
  '  if ($null -eq $Bytes) { throw "sha256 bytes is null" }',
  '  $sha = [System.Security.Cryptography.SHA256]::Create()',
  '  try { $h = $sha.ComputeHash([byte[]]$Bytes); return (([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant()) } finally { $sha.Dispose() }',
  '}',
  'function NL-Sha256HexPath([string]$Path){ if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found for sha256: $Path" }; return (NL-Sha256HexBytes ([byte[]](NL-ReadAllBytes $Path))) }',
  'function NL-ConvertFromJsonCompat([string]$Json,[int]$Depth=64){ $cmd=Get-Command ConvertFrom-Json -ErrorAction Stop; if ($cmd.Parameters.ContainsKey("Depth")) { return ($Json | ConvertFrom-Json -Depth $Depth) } return ($Json | ConvertFrom-Json) }',
  'function NL-Canonify($obj){ if ($null -eq $obj) { return $null }; if ($obj -is [System.Collections.IDictionary]){ $sd=[System.Collections.Generic.SortedDictionary[string,object]]::new(); foreach($k in @($obj.Keys)|Sort-Object){ if($null -eq $k){throw "dictionary key is null"}; $ks=[string]$k; $sd[$ks]=NL-Canonify $obj[$k] }; return $sd }; if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])){ $arr=New-Object System.Collections.Generic.List[object]; foreach($x in $obj){ [void]$arr.Add((NL-Canonify $x)) }; return $arr.ToArray() }; return $obj }',
  'function NL-ToCanonJson($obj,[int]$Depth=64){ $canon=NL-Canonify $obj; return ($canon | ConvertTo-Json -Depth $Depth -Compress) }',
  'function NL-AssertPrincipal([string]$Principal){ if ([string]::IsNullOrWhiteSpace($Principal)) { throw "principal is required." }; if ($Principal -cne $Principal.ToLowerInvariant()) { throw "principal must be lowercase: $Principal" }; if ($Principal -match "\s") { throw "principal must not contain whitespace: $Principal" }; $seg="[a-z0-9][a-z0-9\-_]*"; $re="^single-tenant\/$seg\/authority\/$seg$"; if ($Principal -notmatch $re) { throw "principal format invalid (v1): $Principal" } }',
  'function NL-AssertKeyId([string]$KeyId){ if ([string]::IsNullOrWhiteSpace($KeyId)) { throw "key_id is required." }; if ($KeyId -match "\s") { throw "key_id must not contain whitespace: $KeyId" }; $re="^[a-z0-9][a-z0-9\-]*[a-z0-9]$"; if ($KeyId -notmatch $re) { throw "key_id format invalid: $KeyId" } }',
  'function NL-LoadTrustBundle([string]$TrustBundlePath){ if (-not (Test-Path -LiteralPath $TrustBundlePath)) { throw "trust_bundle.json not found: $TrustBundlePath" }; $tb=NL-ConvertFromJsonCompat (NL-ReadUtf8 $TrustBundlePath) 64; if ($tb.schema -ne "neverlost.trust_bundle.v1") { throw "trust_bundle schema must be neverlost.trust_bundle.v1" }; if (-not $tb.principals) { throw "trust_bundle missing principals" }; foreach($p in @($tb.principals)){ if ($null -eq $p -or -not ($p.PSObject.Properties.Name -contains "principal")) { throw "principal object missing principal" }; NL-AssertPrincipal $p.principal; if (-not $p.keys) { throw "principal missing keys: $($p.principal)" }; foreach($k in @($p.keys)){ if (-not ($k.PSObject.Properties.Name -contains "key_id")) { throw "key missing key_id" }; NL-AssertKeyId $k.key_id; if (-not $k.namespaces) { throw "key missing namespaces" }; if (-not $k.pubkey_path) { throw "key missing pubkey_path" }; if (-not $k.pubkey_sha256) { throw "key missing pubkey_sha256" }; if (-not $k.alg) { $k | Add-Member -NotePropertyName "alg" -NotePropertyValue "ssh-ed25519" -Force } } }; return $tb }',
  'function NL-WriteAllowedSigners([string]$TrustBundlePath,[string]$RepoRoot,[string]$OutPath){ $tb=NL-LoadTrustBundle $TrustBundlePath; $lines=@(); foreach($p in (@($tb.principals)|Sort-Object principal)){ foreach($k in (@($p.keys)|Sort-Object key_id)){ $pubAbs=Join-Path $RepoRoot ($k.pubkey_path -replace "/","\"); if (-not (Test-Path -LiteralPath $pubAbs)) { throw "pubkey not found: $pubAbs" }; $pubFileHash=NL-Sha256HexPath $pubAbs; if ($pubFileHash -ne $k.pubkey_sha256) { throw "pubkey_sha256 mismatch principal=$($p.principal) key_id=$($k.key_id)" }; $pubLine=(NL-ReadUtf8 $pubAbs).Trim(); foreach($ns in @($k.namespaces|Sort-Object)){ if([string]::IsNullOrWhiteSpace($ns)){ throw "namespace empty principal=$($p.principal) key_id=$($k.key_id)" }; $lines += ("{0} namespaces=`"{1}`" {2}" -f $p.principal, $ns, $pubLine) } } }; NL-WriteUtf8NoBomFile $OutPath (($lines -join "`n") + "`n"); return $true }',
  'function NL-WriteReceipt([string]$ReceiptsPath, $Obj){ $enc3=NL-GetUtf8NoBomEncoding; $line=(NL-ToCanonJson $Obj); $bytes=$enc3.GetBytes($line + "`n"); $dir=Split-Path -Parent $ReceiptsPath; if($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $fs=[System.IO.File]::Open($ReceiptsPath,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read); try { $fs.Write($bytes,0,$bytes.Length) } finally { $fs.Dispose() } }'
)
$libText = ($libLines -join "`n") + "`n"
Write-Utf8NoBomFile $libPath $libText
$libDisk = [System.IO.File]::ReadAllText($libPath, $enc)
if ($libDisk -match '\$ordered') { throw "LIB PROOF FAILED: `$ordered present" }
. $libPath

# ------------------------------------------------------------
# 2) OVERWRITE trust_bundle.json to canonical Watchtower shape
# ------------------------------------------------------------
$trustPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$allowed   = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$pubRel    = "proofs/keys/watchtower_authority_ed25519.pub"
$pubAbs    = Join-Path $RepoRoot "proofs\keys\watchtower_authority_ed25519.pub"
if (-not (Test-Path -LiteralPath $pubAbs)) { throw "Missing pubkey: $pubAbs" }
$principal = "single-tenant/watchtower_authority/authority/watchtower"
$keyId     = "watchtower-authority-ed25519"
$pubLine   = (NL-ReadUtf8 $pubAbs).Trim()
$bundle = [pscustomobject]@{
  schema="neverlost.trust_bundle.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  principals=@(
    [pscustomobject]@{
      principal=$principal
      keys=@(
        [pscustomobject]@{
          key_id=$keyId
          alg="ssh-ed25519"
          pubkey_path=$pubRel
          pubkey_sha256=(NL-Sha256HexPath $pubAbs)
          pubkey=$pubLine
          namespaces=@("packet/envelope","watchtower","watchtower/device-pledge","nfl/ingest-receipt")
        }
      )
    }
  )
}
NL-WriteUtf8NoBomFile $trustPath ((NL-ToCanonJson $bundle) + "`n")
$tb2 = NL-ConvertFromJsonCompat (NL-ReadUtf8 $trustPath) 64
$ps = @($tb2.principals)
if ($ps.Count -lt 1) { throw "PROOF FAILED: principals empty after write." }
foreach($p in $ps){ if (-not ($p.PSObject.Properties.Name -contains "principal")) { throw "PROOF FAILED: principals element missing principal." } }

[void](NL-WriteAllowedSigners $trustPath $RepoRoot $allowed)

# ------------------------------------------------------------
# 3) Receipt + print
# ------------------------------------------------------------
NL-WriteReceipt $rcptPath @{ schema="neverlost.receipt.v1"; time_utc=(Get-Date).ToUniversalTime().ToString("o"); action="patch_neverlost_identity_contract_v11c"; ok=$true; hashes=@{ lib_sha256=(NL-Sha256HexPath $libPath); trust_bundle_sha256=(NL-Sha256HexPath $trustPath); allowed_signers_sha256=(NL-Sha256HexPath $allowed) } }
Write-Host "OK: NeverLost v1 patched (identity contract v11c)" -ForegroundColor Green
Write-Host ("trust_bundle_sha256    : " + (NL-Sha256HexPath $trustPath))
Write-Host ("allowed_signers_sha256 : " + (NL-Sha256HexPath $allowed))
