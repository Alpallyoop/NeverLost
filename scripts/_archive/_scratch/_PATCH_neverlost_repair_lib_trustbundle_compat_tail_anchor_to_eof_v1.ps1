param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $u = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path, $u.GetBytes($t))
}
function Parse-GatePs1([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ throw ("PARSE_GATE_MISSING: " + $p) }
  [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $p -Encoding UTF8))
}

$RepoRoot   = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath    = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
if(-not (Test-Path -LiteralPath $LibPath -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }

# Backup
$stamp = (Get-Date).ToString("yyyyMMdd_HHmmssfff")
$bkDir = Join-Path $ScriptsDir ("_scratch\backups\" + $stamp)
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
Copy-Item -LiteralPath $LibPath -Destination (Join-Path $bkDir "_lib_neverlost_v1.ps1") -Force
Write-Host ("BACKUP_OK: " + $bkDir) -ForegroundColor DarkGray

$raw = Get-Content -Raw -LiteralPath $LibPath -Encoding UTF8
$anchor = "# === NL_TRUSTBUNDLE_PRINCIPALS_COMPAT_V1 ==="
$idx = $raw.IndexOf($anchor, [System.StringComparison]::Ordinal)
if($idx -lt 0){ Die ("ANCHOR_NOT_FOUND: " + $anchor) }

$head = $raw.Substring(0, $idx)
$head2 = (($head -replace "`r`n","`n") -replace "`r","`n")
if(-not $head2.EndsWith("`n")){ $head2 += "`n" }

# Replace tail FROM ANCHOR TO EOF with known-good compat tail.
# NOTE: single-quoted here-string => no variable expansion.
$tail = @'
# === NL_TRUSTBUNDLE_PRINCIPALS_COMPAT_V1 ===
# Supports trust_bundle.principals[] (new) and trust_bundle.signers[] (legacy)

function NL-LoadTrustBundleInfoV1([string]$RepoRoot){
  $root   = (Resolve-Path -LiteralPath $RepoRoot).Path
  $tbPath = Join-Path $root 'proofs\trust\trust_bundle.json'
  if(-not (Test-Path -LiteralPath $tbPath -PathType Leaf)){ throw ('MISSING_TRUST_BUNDLE: ' + $tbPath) }
  $raw = Get-Content -Raw -LiteralPath $tbPath -Encoding UTF8
  $obj = $raw | ConvertFrom-Json
  return @{ Path=$tbPath; Raw=$raw; Obj=$obj }
}

function NL-GetTrustBundleEntriesCompat([object]$TrustBundleObj){
  if($null -eq $TrustBundleObj){ throw 'TRUST_BUNDLE_NULL' }

  $names = @()
  if($TrustBundleObj.PSObject -and $TrustBundleObj.PSObject.Properties){
    $names = @($TrustBundleObj.PSObject.Properties.Name)
  }

  $hasPrincipals = ($names -contains 'principals')
  $hasSigners    = ($names -contains 'signers')

  $src = $null
  if($hasPrincipals){
    $src = @(@($TrustBundleObj.principals))
  } elseif($hasSigners){
    $src = @(@($TrustBundleObj.signers))
  } else {
    throw ('TRUST_BUNDLE_SCHEMA_UNKNOWN: expected principals[] or signers[]; top_keys=' + ($names -join ', '))
  }

  $out = New-Object System.Collections.Generic.List[object]
  foreach($p in $src){
    if($null -eq $p){ continue }

    $principal = [string]$p.principal
    $keyId     = [string]$p.key_id

    # pubkey field compat: pubkey OR public_key
    $pubkey = [string]$p.pubkey
    if([string]::IsNullOrWhiteSpace($pubkey)){
      $pubkey = [string]$p.public_key
    }

    $ns = @()
    try { $ns = @(@($p.namespaces)) } catch { $ns = @() }
    $ns = @(@($ns)) | Where-Object { $_ -ne $null -and ([string]$_).Trim().Length -gt 0 } | ForEach-Object { ([string]$_).Trim() }
    $ns = @(@($ns)) | Sort-Object

    if([string]::IsNullOrWhiteSpace($principal)){ throw 'TRUST_BUNDLE_PRINCIPAL_MISSING' }
    if([string]::IsNullOrWhiteSpace($pubkey)){ throw ('TRUST_BUNDLE_PUBKEY_MISSING principal=' + $principal) }

    [void]$out.Add(@{ principal=$principal; key_id=$keyId; pubkey=$pubkey; namespaces=$ns })
  }

  return @(@($out))
}

# Override: NL-WriteAllowedSignersFromTrust (last definition wins)
function NL-WriteAllowedSignersFromTrust([string]$RepoRoot){
  $root    = (Resolve-Path -LiteralPath $RepoRoot).Path
  $tbInfo  = NL-LoadTrustBundleInfoV1 $root
  $entries = NL-GetTrustBundleEntriesCompat $tbInfo.Obj

  $asPath = Join-Path $root 'proofs\trust\allowed_signers'
  $lines  = New-Object System.Collections.Generic.List[string]

  foreach($e in ($entries | Sort-Object principal)){
    $principal = [string]$e.principal
    $pubkey    = [string]$e.pubkey
    $ns        = @(@($e.namespaces)) | Sort-Object

    # OpenSSH allowed_signers format: principal [options] pubkey
    if($ns.Count -gt 0){
      $opt = 'namespaces="' + ($ns -join ',') + '"'
      [void]$lines.Add(($principal + ' ' + $opt + ' ' + $pubkey))
    } else {
      [void]$lines.Add(($principal + ' ' + $pubkey))
    }
  }

  $txt = (@($lines) -join "`n") + "`n"
  $t = ($txt -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllBytes($asPath, (New-Object System.Text.UTF8Encoding($false)).GetBytes($t))
  return $asPath
}
