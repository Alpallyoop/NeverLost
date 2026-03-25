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
    $keys = @(@($v.Keys) | ForEach-Object { [string]$_ } | Sort-Object)
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

function NL-WriteAllowedSignersFromTrust([string]$RepoRoot){
  $tbInfo = NL-LoadTrustBundle $RepoRoot
  $entries = NL-EnumerateSignerEntries $tbInfo.Tb
  $entriesA = @(@($entries))
  if($entriesA.Count -lt 1){ NL-Die "TRUST_BUNDLE_HAS_NO_SIGNERS" }
  $rows = New-Object System.Collections.Generic.List[string]
  foreach($e in $entriesA){
    $principal = [string]$e.principal
    $pub = [string]$e.pubkey
    $kid = [string]$e.key_id
    $ns = @(@($e.namespaces) | ForEach-Object { [string]$_ } | Sort-Object)
    $nsCsv = (@($ns) -join ",")
    if([string]::IsNullOrWhiteSpace($principal)){ NL-Die "SIGNER_MISSING_PRINCIPAL" }
    if([string]::IsNullOrWhiteSpace($pub)){ NL-Die ("SIGNER_MISSING_PUBKEY principal=" + $principal) }
    if([string]::IsNullOrWhiteSpace($nsCsv)){ NL-Die ("SIGNER_MISSING_NAMESPACES principal=" + $principal) }
    $opt = ("namespaces=" + $nsCsv)
    $line = $principal + " " + $opt + " " + $pub
    if(-not [string]::IsNullOrWhiteSpace($kid)){ $line = $line + " " + $kid }
    [void]$rows.Add($line)
  }
  $rows2 = @(@($rows.ToArray()) | Sort-Object)
  $asPath = Join-Path $RepoRoot "proofs\trust\allowed_signers"
  NL-WriteUtf8NoBomLf $asPath ((@($rows2) -join "`n") + "`n")
  NL-AppendReceipt $RepoRoot "neverlost.allowed_signers.write.v1" @{ allowed_signers=$asPath; allowed_signers_sha256=(NL-Sha256HexFile $asPath); trust_bundle_sha256=(NL-Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($tbInfo.Raw))) } | Out-Null
  return $asPath
}

# === NL_TRUSTBUNDLE_PRINCIPALS_COMPAT_V1 ===
# Supports trust_bundle.principals[] (new) and trust_bundle.signers[] (legacy)
# StrictMode-safe property reads + pubkey heuristics

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
    $src = @(@(NL-GetPropObj $TrustBundleObj 'principals'))
  } elseif($hasSigners){
    $src = @(@(NL-GetPropObj $TrustBundleObj 'signers'))
  } else {
    throw ('TRUST_BUNDLE_SCHEMA_UNKNOWN: expected principals[] or signers[]; top_keys=' + ($names -join ', '))
  }

  $out = New-Object System.Collections.Generic.List[object]
  foreach($p in $src){
    if($null -eq $p){ continue }

    $principal = (NL-GetPropStr $p 'principal')

    $keyId = (NL-GetPropStr $p 'key_id')
    if([string]::IsNullOrWhiteSpace($keyId)){ $keyId = (NL-GetPropStr $p 'keyid') }
    if([string]::IsNullOrWhiteSpace($keyId)){ $keyId = (NL-GetPropStr $p 'keyId') }

    # pubkey compat: try multiple names + heuristic scan
    $pubkey = (NL-GetPropStr $p 'pubkey')
    if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-GetPropStr $p 'public_key') }
    if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-GetPropStr $p 'ssh_pubkey') }
    if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-GetPropStr $p 'ssh_public_key') }
    if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-GetPropStr $p 'publicKey') }
    if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-GetPropStr $p 'pub') }
    if([string]::IsNullOrWhiteSpace($pubkey)){ $pubkey = (NL-FindSshPubkeyHeuristic $p) }

    $nsObj = (NL-GetPropObj $p 'namespaces')
    $ns = @()
    if($null -ne $nsObj){ $ns = @(@($nsObj)) }
    $ns = @(@($ns)) | Where-Object { $_ -ne $null -and ([string]$_).Trim().Length -gt 0 } | ForEach-Object { ([string]$_).Trim() }
    $ns = @(@($ns)) | Sort-Object

    if([string]::IsNullOrWhiteSpace($principal)){ throw 'TRUST_BUNDLE_PRINCIPAL_MISSING' }
    if([string]::IsNullOrWhiteSpace($pubkey)){ throw ('TRUST_BUNDLE_PUBKEY_MISSING principal=' + $principal) }

    [void]$out.Add(@{ principal=$principal; key_id=$keyId; pubkey=$pubkey; namespaces=$ns })
  }

  return @(@($out))
}

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
