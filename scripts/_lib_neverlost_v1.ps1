$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-TrustBundleSigners([object]$TrustBundle){
  # Schema-tolerant signer extraction (StrictMode-safe)
  if($null -eq $TrustBundle){ return @() }
  $props = @(@($TrustBundle.PSObject.Properties.Name))
  # Preferred/legacy keys: signers[]
  if($props -contains 'signers'){ return @(@($TrustBundle.signers)) }
  # Your observed canonical key: principals[]
  if($props -contains 'principals'){ return @(@($TrustBundle.principals)) }
  # Common alternates
  if($props -contains 'keys'){ return @(@($TrustBundle.keys)) }
  if($props -contains 'identities'){ return @(@($TrustBundle.identities)) }
  # Nested: trust_bundle.* or trust.*
  if($props -contains 'trust_bundle'){
    $t2 = $TrustBundle.trust_bundle
    if($t2){
      $p2 = @(@($t2.PSObject.Properties.Name))
      if($p2 -contains 'signers'){ return @(@($t2.signers)) }
      if($p2 -contains 'principals'){ return @(@($t2.principals)) }
      if($p2 -contains 'keys'){ return @(@($t2.keys)) }
    }
  }
  if($props -contains 'trust'){
    $t3 = $TrustBundle.trust
    if($t3){
      $p3 = @(@($t3.PSObject.Properties.Name))
      if($p3 -contains 'signers'){ return @(@($t3.signers)) }
      if($p3 -contains 'principals'){ return @(@($t3.principals)) }
      if($p3 -contains 'keys'){ return @(@($t3.keys)) }
    }
  }
  return @()
}

function NL-Die([string]$Msg){ throw $Msg }

function NL-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $u = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path, $u.GetBytes($t))
}

function NL-NowUtc(){ [DateTime]::UtcNow.ToString("o") }

function NL-Sha256HexBytes([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes = @() }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $h = $sha.ComputeHash([byte[]]$Bytes) } finally { $sha.Dispose() }
  $sb = New-Object System.Text.StringBuilder
  foreach($b in $h){ [void]$sb.Append($b.ToString("x2")) }
  return $sb.ToString()
}

function NL-Sha256HexFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { NL-Die ("MISSING_FILE: " + $Path) }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  return NL-Sha256HexBytes $bytes
}

function NL-JsonEscape([string]$s){
  if($null -eq $s){ return "" }
  $sb = New-Object System.Text.StringBuilder
  foreach($ch in $s.ToCharArray()){
    $code = [int][char]$ch
    if($ch -eq """"){ [void]$sb.Append("\"""); continue }
    if($ch -eq "\"){ [void]$sb.Append("\\"); continue }
    if($code -eq 8){ [void]$sb.Append("\b"); continue }
    if($code -eq 9){ [void]$sb.Append("\t"); continue }
    if($code -eq 10){ [void]$sb.Append("\n"); continue }
    if($code -eq 12){ [void]$sb.Append("\f"); continue }
    if($code -eq 13){ [void]$sb.Append("\r"); continue }
    if($code -lt 32){ [void]$sb.Append("\u" + $code.ToString("x4")); continue }
    [void]$sb.Append($ch)
  }
  return $sb.ToString()
}

function NL-JsonCanon($v){
  if($null -eq $v){ return "null" }
  if($v -is [bool]){ if($v){ return "true" } else { return "false" } }
  if($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]){ return ([string]$v) }
  if($v -is [datetime]){ return ("""" + (NL-JsonEscape $v.ToUniversalTime().ToString("o")) + """") }
  if($v -is [string]){ return ("""" + (NL-JsonEscape $v) + """") }
  if($v -is [System.Collections.IDictionary]){
    $keys = [string[]]@(@($v.Keys) | ForEach-Object { [string]$_ }); [System.Array]::Sort($keys, [System.StringComparer]::Ordinal)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach($k in $keys){ [void]$parts.Add(("""" + (NL-JsonEscape $k) + """") + ":" + (NL-JsonCanon $v[$k])) }
    return ("{" + (($parts.ToArray()) -join ",") + "}")
  }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){
    $items = New-Object System.Collections.Generic.List[string]
    foreach($x in @($v)){ [void]$items.Add((NL-JsonCanon $x)) }
    return ("[" + (($items.ToArray()) -join ",") + "]")
  }
  return ("""" + (NL-JsonEscape ([string]$v)) + """")
}

function NL-AppendReceipt([string]$RepoRoot,[string]$EventType,[hashtable]$Data){
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  $rdir = Join-Path $RepoRoot "proofs\receipts"
  if (-not (Test-Path -LiteralPath $rdir -PathType Container)) { New-Item -ItemType Directory -Force -Path $rdir | Out-Null }
  $rpath = Join-Path $rdir "neverlost.ndjson"
  $obj = @{ ts = (NL-NowUtc); event_type = $EventType; data = $Data }
  $line = NL-JsonCanon $obj
  $u = New-Object System.Text.UTF8Encoding($false)
  $b = $u.GetBytes($line + "`n")
  $fs = New-Object System.IO.FileStream($rpath,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
  try { $fs.Write($b,0,$b.Length) } finally { $fs.Dispose() }
  return $rpath
}

function NL-LoadTrustBundle([string]$RepoRoot){
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  $p = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { NL-Die ("MISSING_TRUST_BUNDLE: " + $p) }
  $raw = Get-Content -Raw -LiteralPath $p -Encoding UTF8
  $tb = $raw | ConvertFrom-Json
  return @{ Path=$p; Raw=$raw; Tb=$tb }
}

function NL-EnumerateSignerEntries($Tb){
  $out = New-Object System.Collections.Generic.List[object]
  if($null -eq $Tb){ return @() }
  $signers = $Tb.signers
  $signersA = @(@($signers))
  foreach($s in $signersA){ if($null -eq $s){ continue }; [void]$out.Add($s) }
  return $out.ToArray()
}

# === NL_TRUSTBUNDLE_PRINCIPALS_COMPAT_V1 ===
# Supports:
# - trust_bundle.principals[].keys[]  (new)
# - trust_bundle.principals[] direct pubkey fields (older)
# - trust_bundle.signers[] (legacy)
# StrictMode-safe property reads + deterministic flattening + PSCustomObject outputs

function NL-LoadTrustBundleInfoV1([string]$RepoRoot){
  $root   = (Resolve-Path -LiteralPath $RepoRoot).Path
  $tbPath = Join-Path $root 'proofs\trust\trust_bundle.json'
  if(-not (Test-Path -LiteralPath $tbPath -PathType Leaf)){ throw ('MISSING_TRUST_BUNDLE: ' + $tbPath) }
  $raw = Get-Content -Raw -LiteralPath $tbPath -Encoding UTF8
  $obj = $raw | ConvertFrom-Json
  return @{ Path=$tbPath; Raw=$raw; Obj=$obj }
}

function NL-GetPropStr([object]$Obj,[string]$Name){
  if($null -eq $Obj){ return "" }
  if($Obj.PSObject -and $Obj.PSObject.Properties){
    $p = $Obj.PSObject.Properties[$Name]
    if($null -ne $p -and $null -ne $p.Value){ return [string]$p.Value }
  }
  return ""
}

function NL-GetPropObj([object]$Obj,[string]$Name){
  if($null -eq $Obj){ return $null }
  if($Obj.PSObject -and $Obj.PSObject.Properties){
    $p = $Obj.PSObject.Properties[$Name]
    if($null -ne $p){ return $p.Value }
  }
  return $null
}

function NL-GetPropNames([object]$Obj){
  if($null -eq $Obj){ return @() }
  if($Obj.PSObject -and $Obj.PSObject.Properties){ return @($Obj.PSObject.Properties.Name) }
  return @()
}

function NL-FindSshPubkeyHeuristic([object]$Obj){
  if($null -eq $Obj){ return "" }
  if($Obj.PSObject -and $Obj.PSObject.Properties){
    foreach($pp in $Obj.PSObject.Properties){
      try {
        if($pp.Value -is [string]){
          $s = ([string]$pp.Value).Trim()
          if($s -match '^\s*ssh-ed25519\s+'){ return $s }
        }
      } catch { }
    }
  }
  return ""
}

function NL-ExtractKeyIdCompat([object]$Obj){
  $keyId = (NL-GetPropStr $Obj 'key_id')
  if([string]::IsNullOrWhiteSpace($keyId)){ $keyId = (NL-GetPropStr $Obj 'keyid') }
  if([string]::IsNullOrWhiteSpace($keyId)){ $keyId = (NL-GetPropStr $Obj 'keyId') }
  if([string]::IsNullOrWhiteSpace($keyId)){ $keyId = (NL-GetPropStr $Obj 'id') }
  if([string]::IsNullOrWhiteSpace($keyId)){ $keyId = (NL-GetPropStr $Obj 'kid') }
  return $keyId
}

function NL-ExtractPubkeyCompat([object]$Obj){
  $pubkey = (NL-GetPropStr $Obj 'pubkey')
  if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-GetPropStr $Obj 'public_key') }
  if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-GetPropStr $Obj 'ssh_pubkey') }
  if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-GetPropStr $Obj 'ssh_public_key') }
  if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-GetPropStr $Obj 'publicKey') }
  if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-GetPropStr $Obj 'pub') }
  if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-FindSshPubkeyHeuristic $Obj) }
  return $pubkey
}

function NL-ExtractNamespacesCompat([object]$Obj){
  $nsObj = (NL-GetPropObj $Obj 'namespaces')
  $ns = @()
  if($null -ne $nsObj){ $ns = @($nsObj) }   # flatten once
  $ns = @($ns) | Where-Object { $_ -ne $null -and ([string]$_).Trim().Length -gt 0 } | ForEach-Object { ([string]$_).Trim() }
  return @($ns) | Sort-Object
}

function NL-GetTrustBundleEntriesCompat([object]$TrustBundleObj){
  if($null -eq $TrustBundleObj){ throw 'TRUST_BUNDLE_NULL' }

  $topNames = NL-GetPropNames $TrustBundleObj
  $hasPrincipals = ($topNames -contains 'principals')
  $hasSigners    = ($topNames -contains 'signers')

  $srcObj = $null
  if($hasPrincipals){
    $srcObj = (NL-GetPropObj $TrustBundleObj 'principals')
  } elseif($hasSigners){
    $srcObj = (NL-GetPropObj $TrustBundleObj 'signers')
  } else {
    throw ('TRUST_BUNDLE_SCHEMA_UNKNOWN: expected principals[] or signers[]; top_keys=' + ($topNames -join ', '))
  }

  $src = @()
  if($null -ne $srcObj){ $src = @($srcObj) }   # flatten once

  $out = New-Object System.Collections.Generic.List[object]

  foreach($p in $src){
    if($null -eq $p){ continue }

    $principal = (NL-GetPropStr $p 'principal')
    if([string]::IsNullOrWhiteSpace($principal)){ throw 'TRUST_BUNDLE_PRINCIPAL_MISSING' }

    $pNames = NL-GetPropNames $p
    $hasKeys = ($pNames -contains 'keys')

    $nsPrincipal = NL-ExtractNamespacesCompat $p

    if($hasKeys){
      $keysObj = (NL-GetPropObj $p 'keys')
      $keys = @()
      if($null -ne $keysObj){ $keys = @($keysObj) }   # flatten once

      foreach($k in $keys){
        if($null -eq $k){ continue }

        $keyId = NL-ExtractKeyIdCompat $k
        $pubkey = NL-ExtractPubkeyCompat $k
        $nsKey = NL-ExtractNamespacesCompat $k

        $nsAll = @()
        $nsAll += @($nsPrincipal)
        $nsAll += @($nsKey)
        $nsAll = @($nsAll) | Where-Object { $_ -ne $null -and ([string]$_).Trim().Length -gt 0 } | ForEach-Object { ([string]$_).Trim() }
        $nsAll = @($nsAll) | Sort-Object -Unique

        if([string]::IsNullOrWhiteSpace($pubkey)){ throw ('TRUST_BUNDLE_PUBKEY_MISSING principal=' + $principal) }

        [void]$out.Add([pscustomobject]@{ principal=$principal; key_id=$keyId; pubkey=$pubkey; namespaces=$nsAll })
      }

      continue
    }

    # Fallback: principal object has a direct pubkey
    $keyId2  = NL-ExtractKeyIdCompat $p
    $pubkey2 = NL-ExtractPubkeyCompat $p
    if([string]::IsNullOrWhiteSpace($pubkey2)){ throw ('TRUST_BUNDLE_PUBKEY_MISSING principal=' + $principal) }

    [void]$out.Add([pscustomobject]@{ principal=$principal; key_id=$keyId2; pubkey=$pubkey2; namespaces=$nsPrincipal })
  }

  return @($out.ToArray())
}

# === NL_TRUSTBUNDLE_VERIFIER_V1 ===
# Fail-closed verifier for neverlost.trust_bundle.v1 (schemas/trust_bundle_v1.schema.json).
# Recomputes every claim it can: principal format and closed role set, key fields, pubkey_sha256 over
# the exact bytes of pubkey_path, pubkey equality with the key file, namespace sets, uniqueness.
# Every failure throws "TRUST_BUNDLE_INVALID:<CODE> <detail>" or "TRUST_EXPECTED_<...>".
# Returns normalized entries: principal, key_id, pubkey (type + base64 only), pubkey_sha256, namespaces (ordinal-sorted).

function NL-GetPropRaw([object]$Obj,[string]$Name){
  # Like NL-GetPropObj but never unrolls arrays (a one-element JSON array stays an array).
  if($null -eq $Obj){ return $null }
  if($Obj.PSObject -and $Obj.PSObject.Properties){
    $p = $Obj.PSObject.Properties[$Name]
    if($null -ne $p){
      if($null -eq $p.Value){ return $null }
      return ,$p.Value
    }
  }
  return $null
}

$script:NL_TrustRolesV1 = @("owner","org_admin","device_admin","operator","auditor","device_agent","watchtower_authority")
$script:NL_PrincipalRegexV1 = '^single-tenant/(owner|org_admin|device_admin|operator|auditor|device_agent|watchtower_authority)/[^\s,"]+$'
$script:NL_NamespaceRegexV1 = '^[A-Za-z0-9][A-Za-z0-9._/\-]*$'
$script:NL_PubkeyRegexV1 = '^ssh-ed25519 [A-Za-z0-9+/]+={0,2}$'

function NL-SortOrdinal([string[]]$Items){
  $arr = @(@($Items) | Where-Object { $null -ne $_ })
  $a = [string[]]$arr
  [System.Array]::Sort($a, [System.StringComparer]::Ordinal)
  return ,$a
}

function NL-TrustFail([string]$Code,[string]$Detail){
  $m = "TRUST_BUNDLE_INVALID:" + $Code
  if(-not [string]::IsNullOrWhiteSpace($Detail)){ $m = $m + " " + $Detail }
  throw $m
}

function NL-AssertOnlyProps([object]$Obj,[string[]]$Allowed,[string]$Where){
  foreach($n in @(NL-GetPropNames $Obj)){
    if(@($Allowed) -notcontains $n){ NL-TrustFail "UNKNOWN_FIELD" ($Where + "." + $n) }
  }
}

function NL-IsJsonArray([object]$v){
  return ($v -is [System.Array]) -or ($v -is [System.Collections.IList] -and -not ($v -is [string]))
}

function NL-ReadNamespaceList([object]$Owner,[string]$Prop,[string]$Where,[bool]$Required){
  $names = @(NL-GetPropNames $Owner)
  if($names -notcontains $Prop){
    if($Required){ NL-TrustFail "NAMESPACES_MISSING" $Where }
    return @()
  }
  $v = (NL-GetPropRaw $Owner $Prop)
  if(-not (NL-IsJsonArray $v)){ NL-TrustFail "NAMESPACES_NOT_ARRAY" $Where }
  $list = @($v)
  if($list.Count -lt 1){ NL-TrustFail "NAMESPACES_EMPTY" $Where }
  $seen = @{}
  $out = New-Object System.Collections.Generic.List[string]
  foreach($x in $list){
    if(-not ($x -is [string])){ NL-TrustFail "NAMESPACE_NOT_STRING" $Where }
    $s = [string]$x
    if($s -cnotmatch $script:NL_NamespaceRegexV1){ NL-TrustFail "NAMESPACE_FORMAT" ($Where + " value=" + $s) }
    if($seen.ContainsKey($s)){ NL-TrustFail "NAMESPACE_DUPLICATE" ($Where + " value=" + $s) }
    $seen[$s] = $true
    [void]$out.Add($s)
  }
  return @($out.ToArray())
}

function NL-ReadRequiredString([object]$Obj,[string]$Prop,[string]$Where){
  if(@(NL-GetPropNames $Obj) -notcontains $Prop){ NL-TrustFail "FIELD_MISSING" ($Where + "." + $Prop) }
  $v = NL-GetPropRaw $Obj $Prop
  if(-not ($v -is [string]) -or [string]::IsNullOrWhiteSpace([string]$v)){ NL-TrustFail "FIELD_EMPTY_OR_NOT_STRING" ($Where + "." + $Prop) }
  return [string]$v
}

function NL-ResolvePubkeyFile([string]$RepoRoot,[string]$Rel,[string]$Where){
  if($Rel -match '^[A-Za-z]:' -or $Rel.StartsWith('/') -or $Rel.StartsWith('\')){ NL-TrustFail "PUBKEY_PATH_NOT_RELATIVE" ($Where + " " + $Rel) }
  foreach($seg in ($Rel -split '[\\/]')){ if($seg -eq '..'){ NL-TrustFail "PUBKEY_PATH_TRAVERSAL" ($Where + " " + $Rel) } }
  $p = $RepoRoot
  foreach($seg in ($Rel -split '[\\/]')){ if($seg.Length -gt 0){ $p = Join-Path $p $seg } }
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ NL-TrustFail "PUBKEY_FILE_MISSING" ($Where + " " + $Rel) }
  return $p
}

function NL-PubkeyCore([string]$Text){
  $t = ($Text -replace "[\r\n]+"," ").Trim()
  $parts = @($t -split '\s+')
  if($parts.Count -lt 2){ return "" }
  return ($parts[0] + " " + $parts[1])
}

function NL-VerifyKeyMaterial([string]$RepoRoot,[string]$PubkeyPath,[string]$ClaimedSha,[string]$ClaimedPubkey,[string]$Where){
  if($ClaimedSha -cnotmatch '^[a-f0-9]{64}$'){ NL-TrustFail "PUBKEY_SHA256_FORMAT" $Where }
  $file = NL-ResolvePubkeyFile $RepoRoot $PubkeyPath $Where
  $actualSha = NL-Sha256HexFile $file
  if($actualSha -cne $ClaimedSha){ NL-TrustFail "PUBKEY_SHA256_MISMATCH" ($Where + " claimed=" + $ClaimedSha + " actual=" + $actualSha) }
  $fileCore = NL-PubkeyCore ([System.IO.File]::ReadAllText($file))
  if($fileCore -cnotmatch $script:NL_PubkeyRegexV1){ NL-TrustFail "PUBKEY_FILE_FORMAT" $Where }
  if(-not [string]::IsNullOrEmpty($ClaimedPubkey)){
    $claimCore = NL-PubkeyCore $ClaimedPubkey
    if($claimCore -cnotmatch $script:NL_PubkeyRegexV1){ NL-TrustFail "PUBKEY_FORMAT" $Where }
    if($claimCore -cne $fileCore){ NL-TrustFail "PUBKEY_FILE_MISMATCH" $Where }
  }
  return $fileCore
}

function NL-AssertTrustBundleV1 {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$TrustBundlePath = "",
    [string]$ExpectedPrincipal = "",
    [string[]]$ExpectedNamespaces = @()
  )
  $root = (Resolve-Path -LiteralPath $RepoRoot).Path
  if([string]::IsNullOrWhiteSpace($TrustBundlePath)){ $TrustBundlePath = Join-Path (Join-Path (Join-Path $root "proofs") "trust") "trust_bundle.json" }
  if(-not (Test-Path -LiteralPath $TrustBundlePath -PathType Leaf)){ NL-TrustFail "MISSING" $TrustBundlePath }

  $bytes = [System.IO.File]::ReadAllBytes($TrustBundlePath)
  if($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){ NL-TrustFail "UTF8_BOM" "" }
  $raw = (New-Object System.Text.UTF8Encoding($false,$true)).GetString($bytes)
  if([string]::IsNullOrWhiteSpace($raw)){ NL-TrustFail "EMPTY" "" }
  try { $obj = $raw | ConvertFrom-Json -ErrorAction Stop } catch { NL-TrustFail "JSON_PARSE" $_.Exception.Message }
  if($null -eq $obj -or -not ($obj -is [System.Management.Automation.PSCustomObject])){ NL-TrustFail "NOT_OBJECT" "" }

  $top = @(NL-GetPropNames $obj)
  $entries = New-Object System.Collections.Generic.List[object]
  $seenPrincipals = @{}
  $seenKeyIds = @{}

  if($top -contains "principals"){
    NL-AssertOnlyProps $obj @("schema","created_utc","principals") "bundle"
    $schema = NL-GetPropRaw $obj "schema"
    if(-not ($schema -is [string]) -or [string]$schema -cne "neverlost.trust_bundle.v1"){ NL-TrustFail "SCHEMA_ID" ([string]$schema) }
    if($top -contains "created_utc"){
      $cu = NL-GetPropRaw $obj "created_utc"
      if(-not ($cu -is [string]) -and -not ($cu -is [datetime])){ NL-TrustFail "CREATED_UTC_NOT_STRING" "" }
    }
    $pv = NL-GetPropRaw $obj "principals"
    if(-not (NL-IsJsonArray $pv)){ NL-TrustFail "PRINCIPALS_NOT_ARRAY" "" }
    $plist = @($pv)
    if($plist.Count -lt 1){ NL-TrustFail "PRINCIPALS_EMPTY" "" }
    $pi = 0
    foreach($p in $plist){
      $w = "principals[" + $pi + "]"
      if(-not ($p -is [System.Management.Automation.PSCustomObject])){ NL-TrustFail "PRINCIPAL_NOT_OBJECT" $w }
      NL-AssertOnlyProps $p @("principal","namespaces","keys") $w
      $principal = NL-ReadRequiredString $p "principal" $w
      if($principal -cnotmatch $script:NL_PrincipalRegexV1){ NL-TrustFail "PRINCIPAL_FORMAT" ($w + " " + $principal) }
      if($seenPrincipals.ContainsKey($principal)){ NL-TrustFail "PRINCIPAL_DUPLICATE" $principal }
      $seenPrincipals[$principal] = $true
      $nsP = NL-ReadNamespaceList $p "namespaces" $w $false
      $kv = NL-GetPropRaw $p "keys"
      if(@(NL-GetPropNames $p) -notcontains "keys"){ NL-TrustFail "KEYS_MISSING" $w }
      if(-not (NL-IsJsonArray $kv)){ NL-TrustFail "KEYS_NOT_ARRAY" $w }
      $klist = @($kv)
      if($klist.Count -lt 1){ NL-TrustFail "KEYS_EMPTY" $w }
      $ki = 0
      foreach($k in $klist){
        $wk = $w + ".keys[" + $ki + "]"
        if(-not ($k -is [System.Management.Automation.PSCustomObject])){ NL-TrustFail "KEY_NOT_OBJECT" $wk }
        NL-AssertOnlyProps $k @("key_id","alg","pubkey_path","pubkey_sha256","pubkey","namespaces") $wk
        $keyId = NL-ReadRequiredString $k "key_id" $wk
        $alg = NL-ReadRequiredString $k "alg" $wk
        if($alg -cne "ssh-ed25519"){ NL-TrustFail "ALG_UNSUPPORTED" ($wk + " " + $alg) }
        $pp = NL-ReadRequiredString $k "pubkey_path" $wk
        $ps = NL-ReadRequiredString $k "pubkey_sha256" $wk
        $pk = NL-ReadRequiredString $k "pubkey" $wk
        if($seenKeyIds.ContainsKey($keyId)){ NL-TrustFail "KEY_ID_DUPLICATE" $keyId }
        $seenKeyIds[$keyId] = $true
        $core = NL-VerifyKeyMaterial $root $pp $ps $pk $wk
        $nsK = NL-ReadNamespaceList $k "namespaces" $wk $false
        $nsAll = @{}
        foreach($n in @($nsP) + @($nsK)){ if($null -ne $n){ $nsAll[[string]$n] = $true } }
        if($nsAll.Count -lt 1){ NL-TrustFail "NAMESPACES_MISSING" $wk }
        [void]$entries.Add([pscustomobject]@{ principal=$principal; key_id=$keyId; pubkey=$core; pubkey_sha256=$ps; namespaces=(NL-SortOrdinal ([string[]]@($nsAll.Keys))) })
        $ki++
      }
      $pi++
    }
  }
  elseif($top -contains "authorities"){
    # Legacy v1 shape (schemas/trust_bundle_v1.schema.json authoritiesBundle). Accepted until migrated.
    NL-AssertOnlyProps $obj @("version","authorities") "bundle"
    $ver = NL-GetPropRaw $obj "version"
    if(-not (($ver -is [int]) -or ($ver -is [long])) -or [long]$ver -ne 1){ NL-TrustFail "LEGACY_VERSION" ([string]$ver) }
    $av = NL-GetPropRaw $obj "authorities"
    if(-not (NL-IsJsonArray $av)){ NL-TrustFail "AUTHORITIES_NOT_ARRAY" "" }
    $alist = @($av)
    if($alist.Count -lt 1){ NL-TrustFail "AUTHORITIES_EMPTY" "" }
    $ai = 0
    foreach($a in $alist){
      $w = "authorities[" + $ai + "]"
      if(-not ($a -is [System.Management.Automation.PSCustomObject])){ NL-TrustFail "AUTHORITY_NOT_OBJECT" $w }
      NL-AssertOnlyProps $a @("principal","key_id","alg","pubkey_path","pubkey_sha256","allowed_namespaces") $w
      $principal = NL-ReadRequiredString $a "principal" $w
      if($principal -cnotmatch $script:NL_PrincipalRegexV1){ NL-TrustFail "PRINCIPAL_FORMAT" ($w + " " + $principal) }
      $keyId = NL-ReadRequiredString $a "key_id" $w
      $alg = NL-ReadRequiredString $a "alg" $w
      if($alg -cne "ssh-ed25519"){ NL-TrustFail "ALG_UNSUPPORTED" ($w + " " + $alg) }
      if($seenKeyIds.ContainsKey($keyId)){ NL-TrustFail "KEY_ID_DUPLICATE" $keyId }
      $seenKeyIds[$keyId] = $true
      $pp = NL-ReadRequiredString $a "pubkey_path" $w
      $ps = NL-ReadRequiredString $a "pubkey_sha256" $w
      $core = NL-VerifyKeyMaterial $root $pp $ps "" $w
      $ns = NL-ReadNamespaceList $a "allowed_namespaces" $w $true
      [void]$entries.Add([pscustomobject]@{ principal=$principal; key_id=$keyId; pubkey=$core; pubkey_sha256=$ps; namespaces=(NL-SortOrdinal ([string[]]$ns)) })
      $ai++
    }
  }
  else {
    NL-TrustFail "SHAPE_UNKNOWN" ("top_keys=" + (@($top) -join ","))
  }

  $out = @($entries.ToArray())

  if(-not [string]::IsNullOrWhiteSpace($ExpectedPrincipal)){
    $match = @($out | Where-Object { [string]$_.principal -ceq $ExpectedPrincipal })
    if($match.Count -lt 1){ throw ("TRUST_EXPECTED_PRINCIPAL_MISMATCH expected=" + $ExpectedPrincipal) }
    if(@($ExpectedNamespaces).Count -gt 0){
      $want = (NL-SortOrdinal ([string[]]@($ExpectedNamespaces | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_.Length -gt 0 } | Select-Object -Unique))) -join ","
      $ok = $false
      foreach($m in $match){ if(((@($m.namespaces)) -join ",") -ceq $want){ $ok = $true } }
      if(-not $ok){ throw ("TRUST_EXPECTED_NAMESPACES_MISMATCH principal=" + $ExpectedPrincipal + " expected=" + $want + " actual=" + ((@($match[0].namespaces)) -join ",")) }
    }
  }
  return ,$out
}

# Canonical OpenSSH allowed_signers text derived from verified trust entries.
# One line per key: <principal> namespaces="<ns,...>" <type> <base64>; lines ordinal-sorted; LF; trailing LF.
# -Namespace filters to keys that may sign that namespace and restricts the namespaces option to it.
function NL-AllowedSignersTextV1 {
  param(
    [Parameter(Mandatory=$true)][object[]]$Entries,
    [string]$Namespace = ""
  )
  $lines = New-Object System.Collections.Generic.List[string]
  foreach($e in @($Entries)){
    $ns = @($e.namespaces)
    if(-not [string]::IsNullOrWhiteSpace($Namespace)){
      if($ns -cnotcontains $Namespace){ continue }
      $ns = @($Namespace)
    }
    if($ns.Count -lt 1){ throw ("SIGNER_MISSING_NAMESPACES principal=" + [string]$e.principal) }
    [void]$lines.Add(([string]$e.principal + ' namespaces="' + ((NL-SortOrdinal ([string[]]$ns)) -join ',') + '" ' + [string]$e.pubkey))
  }
  if($lines.Count -lt 1){ throw "ALLOWED_SIGNERS_NO_MATCHING_SIGNERS" }
  $sorted = NL-SortOrdinal ([string[]]$lines.ToArray())
  return ((@($sorted) -join "`n") + "`n")
}

# Writes proofs/trust/allowed_signers from the VERIFIED trust bundle (fail closed on any trust defect).
function NL-WriteAllowedSignersFromTrust([string]$RepoRoot){
  $root = (Resolve-Path -LiteralPath $RepoRoot).Path
  $entries = NL-AssertTrustBundleV1 -RepoRoot $root
  $text = NL-AllowedSignersTextV1 -Entries $entries
  $asPath = Join-Path (Join-Path (Join-Path $root "proofs") "trust") "allowed_signers"
  [System.IO.File]::WriteAllBytes($asPath, (New-Object System.Text.UTF8Encoding($false)).GetBytes($text))
  return $asPath
}

# Fails closed when proofs/trust/allowed_signers is not exactly what the verified trust bundle derives.
function NL-AssertAllowedSignersCurrentV1([string]$RepoRoot,[object[]]$Entries){
  $root = (Resolve-Path -LiteralPath $RepoRoot).Path
  $asPath = Join-Path (Join-Path (Join-Path $root "proofs") "trust") "allowed_signers"
  if(-not (Test-Path -LiteralPath $asPath -PathType Leaf)){ throw ("TRUST_ALLOWED_SIGNERS_MISSING: " + $asPath) }
  $want = NL-AllowedSignersTextV1 -Entries $Entries
  $have = (New-Object System.Text.UTF8Encoding($false)).GetString([System.IO.File]::ReadAllBytes($asPath))
  if($have -cne $want){ throw "TRUST_ALLOWED_SIGNERS_STALE (run scripts/make_allowed_signers_v1.ps1)" }
}

# === NL_TRUSTBUNDLE_WRITER_V1 ===
# Model of a principals-form trust bundle that round-trips byte for byte: serializing an unchanged model
# reproduces the exact bytes it was read from (compact JSON, field order schema, created_utc, principals;
# principal, namespaces, keys; key_id, alg, pubkey_path, pubkey_sha256, pubkey, namespaces; the final
# line ending, if any, is kept as read).

function NL-ReadTrustBundleModelV1([string]$RepoRoot,[string]$TrustBundlePath){
  [void](NL-AssertTrustBundleV1 -RepoRoot $RepoRoot -TrustBundlePath $TrustBundlePath)
  $raw = (New-Object System.Text.UTF8Encoding($false,$true)).GetString([System.IO.File]::ReadAllBytes($TrustBundlePath))
  $obj = $raw | ConvertFrom-Json
  if(@(NL-GetPropNames $obj) -notcontains "principals"){ throw "TRUST_BUNDLE_LEGACY_SHAPE_READONLY: migrate the authorities[] bundle to principals[] before issuing" }
  $created = $null
  $m = [regex]::Match($raw, '"created_utc"\s*:\s*"((?:[^"\\]|\\.)*)"')
  if($m.Success){ $created = $m.Groups[1].Value }
  $principals = New-Object System.Collections.Generic.List[object]
  $plist = NL-GetPropRaw $obj "principals"
  foreach($p in $plist){
    $keys = New-Object System.Collections.Generic.List[object]
    $klist = NL-GetPropRaw $p "keys"
    foreach($k in $klist){
      $kn = $null; if(@(NL-GetPropNames $k) -contains "namespaces"){ $kn = [string[]](NL-GetPropRaw $k "namespaces") }
      [void]$keys.Add([ordered]@{ key_id=[string]$k.key_id; alg=[string]$k.alg; pubkey_path=[string]$k.pubkey_path; pubkey_sha256=[string]$k.pubkey_sha256; pubkey=[string]$k.pubkey; namespaces=$kn })
    }
    $pn = $null; if(@(NL-GetPropNames $p) -contains "namespaces"){ $pn = [string[]](NL-GetPropRaw $p "namespaces") }
    [void]$principals.Add([ordered]@{ principal=[string]$p.principal; namespaces=$pn; keys=$keys })
  }
  $eol = ""
  if($raw.EndsWith("`r`n")){ $eol = "`r`n" } elseif($raw.EndsWith("`n")){ $eol = "`n" }
  return @{ CreatedUtc = $created; Principals = $principals; Raw = $raw; FinalEol = $eol }
}

function NL-JsonStr([string]$s){ return ('"' + (NL-JsonEscape $s) + '"') }

function NL-TrustBundleJsonV1($Model){
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('{"schema":"neverlost.trust_bundle.v1"')
  if($null -ne $Model.CreatedUtc){ [void]$sb.Append(',"created_utc":' + (NL-JsonStr $Model.CreatedUtc)) }
  [void]$sb.Append(',"principals":[')
  $pi = 0
  foreach($p in $Model.Principals){
    if($pi -gt 0){ [void]$sb.Append(',') }
    [void]$sb.Append('{"principal":' + (NL-JsonStr $p.principal))
    if($null -ne $p.namespaces){ [void]$sb.Append(',"namespaces":[' + ((@($p.namespaces) | ForEach-Object { NL-JsonStr $_ }) -join ',') + ']') }
    [void]$sb.Append(',"keys":[')
    $ki = 0
    foreach($k in $p.keys){
      if($ki -gt 0){ [void]$sb.Append(',') }
      [void]$sb.Append('{"key_id":' + (NL-JsonStr $k.key_id) + ',"alg":' + (NL-JsonStr $k.alg) + ',"pubkey_path":' + (NL-JsonStr $k.pubkey_path) + ',"pubkey_sha256":' + (NL-JsonStr $k.pubkey_sha256) + ',"pubkey":' + (NL-JsonStr $k.pubkey))
      if($null -ne $k.namespaces){ [void]$sb.Append(',"namespaces":[' + ((@($k.namespaces) | ForEach-Object { NL-JsonStr $_ }) -join ',') + ']') }
      [void]$sb.Append('}')
      $ki++
    }
    [void]$sb.Append(']}')
    $pi++
  }
  [void]$sb.Append(']}')
  if($Model.Contains("FinalEol") -and $Model.FinalEol){ [void]$sb.Append([string]$Model.FinalEol) }
  return $sb.ToString()
}

# Writes a new bundle only after the candidate verifies; returns @{ Before; After } hashes.
# The live bundle is owner-read-only after the ACL lane, so its protection is lifted for the swap; the
# caller re-applies scripts/enforce_trust_acl_v1.ps1 afterwards.
function NL-SaveTrustBundleV1([string]$RepoRoot,$Model){
  $root = (Resolve-Path -LiteralPath $RepoRoot).Path
  $tbPath = Join-Path (Join-Path (Join-Path $root "proofs") "trust") "trust_bundle.json"
  $before = NL-Sha256HexFile $tbPath
  $json = NL-TrustBundleJsonV1 $Model
  $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
  $tmp = $tbPath + ".candidate.tmp"
  [System.IO.File]::WriteAllBytes($tmp, $bytes)
  try { [void](NL-AssertTrustBundleV1 -RepoRoot $root -TrustBundlePath $tmp) }
  catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw ("TRUST_BUNDLE_CANDIDATE_REJECTED: " + $_.Exception.Message) }
  $isWin = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try {
    if($isWin){ & icacls $tbPath /reset /Q 2>&1 | Out-Null } else { & chmod 600 $tbPath 2>&1 | Out-Null }
  } finally { $ErrorActionPreference = $prev }
  [System.IO.File]::Copy($tmp, $tbPath, $true)
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  $after = NL-Sha256HexFile $tbPath
  if($after -cne (NL-Sha256HexBytes $bytes)){ throw "TRUST_BUNDLE_WRITE_VERIFY_FAILED" }
  [void](NL-AssertTrustBundleV1 -RepoRoot $root)
  return @{ Before = $before; After = $after }
}

# === NL_PUBLISH_V1 ===
# proofs/published/ is what other services read: the bundle, its hash (to pin out of band), the derived
# allowed_signers, and per consumer a signer list for its own principal plus a hand-off note.

function NL-WriteTextLf([string]$Path,[string]$Text){
  $d = Split-Path -Parent $Path
  if($d -and -not (Test-Path -LiteralPath $d -PathType Container)){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
  $t = ($Text -replace "`r`n","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllBytes($Path, (New-Object System.Text.UTF8Encoding($false)).GetBytes($t))
}

function NL-PublishTrustV1([string]$RepoRoot){
  $root = (Resolve-Path -LiteralPath $RepoRoot).Path
  $entries = NL-AssertTrustBundleV1 -RepoRoot $root
  $tb = Join-Path (Join-Path (Join-Path $root "proofs") "trust") "trust_bundle.json"
  $pubDir = Join-Path (Join-Path $root "proofs") "published"
  if(-not (Test-Path -LiteralPath $pubDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $pubDir | Out-Null }
  $sha = NL-Sha256HexFile $tb
  [System.IO.File]::Copy($tb, (Join-Path $pubDir "trust_bundle.json"), $true)
  NL-WriteTextLf (Join-Path $pubDir "trust_bundle.sha256") ($sha + "  trust_bundle.json")
  NL-WriteTextLf (Join-Path $pubDir "allowed_signers") (NL-AllowedSignersTextV1 -Entries $entries)
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add("# NeverLost published trust")
  [void]$lines.Add("")
  [void]$lines.Add("Pin this hash out of band (for example courier.ps1 trust-import -ExpectedSha256):")
  [void]$lines.Add("")
  [void]$lines.Add("    trust_bundle.json  sha256 " + $sha)
  [void]$lines.Add("")
  [void]$lines.Add("| Principal | Key id | Namespaces |")
  [void]$lines.Add("|---|---|---|")
  foreach($e in $entries){ [void]$lines.Add("| " + [string]$e.principal + " | " + [string]$e.key_id + " | " + ((@($e.namespaces)) -join ", ") + " |") }
  [void]$lines.Add("")
  [void]$lines.Add("Generated by NeverLost (scripts/_lib_neverlost_v1.ps1 NL-PublishTrustV1). Do not edit; re-issue instead.")
  NL-WriteTextLf (Join-Path $pubDir "README.md") (($lines.ToArray()) -join "`n")
  return $pubDir
}

function NL-PublishConsumerV1 {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$Consumer,
    [Parameter(Mandatory=$true)][string]$Principal,
    [string]$PrivateKeyPath = ""
  )
  $root = (Resolve-Path -LiteralPath $RepoRoot).Path
  $all = NL-AssertTrustBundleV1 -RepoRoot $root
  $entries = @($all | Where-Object { [string]$_.principal -ceq $Principal })
  if($entries.Count -lt 1){ throw ("PUBLISH_PRINCIPAL_NOT_TRUSTED: " + $Principal) }
  $dir = Join-Path (Join-Path (Join-Path $root "proofs") "published") $Consumer
  $as = Join-Path $dir "allowed_signers"
  NL-WriteTextLf $as (NL-AllowedSignersTextV1 -Entries $entries)
  $tb = Join-Path (Join-Path (Join-Path $root "proofs") "trust") "trust_bundle.json"
  $sha = NL-Sha256HexFile $tb
  $ns = @($entries[0].namespaces)
  $keyLine = $(if($PrivateKeyPath){ $PrivateKeyPath } else { "(held by " + $Consumer + "; NeverLost has only the public key)" })
  $l = New-Object System.Collections.Generic.List[string]
  [void]$l.Add("# NeverLost identity for " + $Consumer)
  [void]$l.Add("")
  [void]$l.Add("| Field | Value |")
  [void]$l.Add("|---|---|")
  [void]$l.Add("| Principal | ``" + $Principal + "`` |")
  [void]$l.Add("| Key id | ``" + [string]$entries[0].key_id + "`` |")
  [void]$l.Add("| Namespaces | " + (($ns | ForEach-Object { "``" + $_ + "``" }) -join ", ") + " |")
  [void]$l.Add("| Private key | ``" + $keyLine + "`` |")
  [void]$l.Add("| Signer list (this principal) | ``" + $as + "`` |")
  [void]$l.Add("| Full signer list | ``" + (Join-Path (Join-Path (Join-Path $root "proofs") "published") "allowed_signers") + "`` |")
  [void]$l.Add("| Trust bundle | ``" + $tb + "`` |")
  [void]$l.Add("| Trust bundle sha256 (pin) | ``" + $sha + "`` |")
  [void]$l.Add("")
  [void]$l.Add("## Configure " + $Consumer)
  [void]$l.Add("")
  switch($Consumer){
    "bountygate" {
      [void]$l.Add("In BountyGate's ``config/integrations.local.json`` (git-ignored):")
      [void]$l.Add("")
      [void]$l.Add("    ""neverlost"": { ""allowedSigners"": ""<signer list above>"", ""signingKey"": ""<private key above>"", ""principal"": """ + $Principal + """, ""namespace"": """ + $ns[0] + """ }")
    }
    "lawvm" {
      [void]$l.Add("    .\lawvm.ps1 seal-receipts -Key ""<private key above>"" -Signer " + $Principal)
      [void]$l.Add("    .\lawvm.ps1 verify-receipts -RequireSignature   (allowed_signers: the signer list above)")
    }
    "echo-transport" {
      [void]$l.Add("    E trust-import -SourceTrustBundle ""<trust bundle above>"" -SourceRoot ""<NeverLost folder>""")
      [void]$l.Add("Then sign with the private key above as " + $Principal + " (namespace packet/envelope) and retire the old unencrypted producer key.")
    }
    "covenant-courier" {
      [void]$l.Add("    .\courier.ps1 trust-import -TrustBundlePath ""<trust bundle above>"" -ExpectedSha256 " + $sha + " -NeverLostRoot ""<NeverLost folder>""")
    }
    "covenant-gate" {
      [void]$l.Add("Sign decision documents with ``ssh-keygen -Y sign -f <private key above> -n covenant-gate/decision``; verifiers use the signer list above.")
    }
    "nfl" {
      [void]$l.Add("Use the private key above for ``nfl_ledger_seal_v1.ps1`` / ``nfl_ledger_export_v1.ps1`` / ``nfl_sign_ledger_packet_v1.ps1`` instead of the dev key in NFL's ``proofs/keys``; verifiers use the signer list above.")
    }
    default {
      [void]$l.Add("Sign with ``ssh-keygen -Y sign -n <namespace>`` using the private key above; verify against the signer list above.")
    }
  }
  [void]$l.Add("")
  [void]$l.Add("After any re-issue the bundle hash changes: re-import or re-pin. Generated by NeverLost; do not edit.")
  $handoff = Join-Path $dir "HANDOFF.md"
  NL-WriteTextLf $handoff (($l.ToArray()) -join "`n")
  NL-AppendReceipt $root "neverlost.allowed_signers.export.v1" @{ consumer=$Consumer; principal=$Principal; out_path=$as; allowed_signers_sha256=(NL-Sha256HexFile $as); trust_bundle_sha256=$sha; state="written" } | Out-Null
  return $handoff
}
