param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $u = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path, $u.GetBytes($t))
}
function Parse-GatePs1([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("PARSE_GATE_MISSING: " + $p) }
  [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $p -Encoding UTF8))
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
EnsureDir $ScriptsDir

# ---------------- scripts/_lib_neverlost_v1.ps1 ----------------
$libPath = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$lib = New-Object System.Collections.Generic.List[string]

[void]$lib.Add('$ErrorActionPreference = "Stop"')
[void]$lib.Add('Set-StrictMode -Version Latest')
[void]$lib.Add('')
[void]$lib.Add('function NL-Die([string]$Msg){ throw $Msg }')
[void]$lib.Add('')
[void]$lib.Add('function NL-WriteUtf8NoBomLf([string]$Path,[string]$Text){')
[void]$lib.Add('  $dir = Split-Path -Parent $Path')
[void]$lib.Add('  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }')
[void]$lib.Add('  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"')
[void]$lib.Add('  if(-not $t.EndsWith("`n")){ $t += "`n" }')
[void]$lib.Add('  $u = New-Object System.Text.UTF8Encoding($false)')
[void]$lib.Add('  [System.IO.File]::WriteAllBytes($Path, $u.GetBytes($t))')
[void]$lib.Add('}')
[void]$lib.Add('')
[void]$lib.Add('function NL-NowUtc(){ [DateTime]::UtcNow.ToString("o") }')
[void]$lib.Add('')
[void]$lib.Add('function NL-Sha256HexBytes([byte[]]$Bytes){')
[void]$lib.Add('  if($null -eq $Bytes){ $Bytes = @() }')
[void]$lib.Add('  $sha = [System.Security.Cryptography.SHA256]::Create()')
[void]$lib.Add('  try { $h = $sha.ComputeHash([byte[]]$Bytes) } finally { $sha.Dispose() }')
[void]$lib.Add('  $sb = New-Object System.Text.StringBuilder')
[void]$lib.Add('  foreach($b in $h){ [void]$sb.Append($b.ToString("x2")) }')
[void]$lib.Add('  return $sb.ToString()')
[void]$lib.Add('}')
[void]$lib.Add('')
[void]$lib.Add('function NL-Sha256HexFile([string]$Path){')
[void]$lib.Add('  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { NL-Die ("MISSING_FILE: " + $Path) }')
[void]$lib.Add('  $bytes = [System.IO.File]::ReadAllBytes($Path)')
[void]$lib.Add('  return NL-Sha256HexBytes $bytes')
[void]$lib.Add('}')
[void]$lib.Add('')
[void]$lib.Add('function NL-JsonEscape([string]$s){')
[void]$lib.Add('  if($null -eq $s){ return "" }')
[void]$lib.Add('  $sb = New-Object System.Text.StringBuilder')
[void]$lib.Add('  foreach($ch in $s.ToCharArray()){')
[void]$lib.Add('    $code = [int][char]$ch')
[void]$lib.Add('    if($ch -eq """"){ [void]$sb.Append("\"""); continue }')
[void]$lib.Add('    if($ch -eq "\"){ [void]$sb.Append("\\"); continue }')
[void]$lib.Add('    if($code -eq 8){ [void]$sb.Append("\b"); continue }')
[void]$lib.Add('    if($code -eq 9){ [void]$sb.Append("\t"); continue }')
[void]$lib.Add('    if($code -eq 10){ [void]$sb.Append("\n"); continue }')
[void]$lib.Add('    if($code -eq 12){ [void]$sb.Append("\f"); continue }')
[void]$lib.Add('    if($code -eq 13){ [void]$sb.Append("\r"); continue }')
[void]$lib.Add('    if($code -lt 32){ [void]$sb.Append("\u" + $code.ToString("x4")); continue }')
[void]$lib.Add('    [void]$sb.Append($ch)')
[void]$lib.Add('  }')
[void]$lib.Add('  return $sb.ToString()')
[void]$lib.Add('}')
[void]$lib.Add('')
[void]$lib.Add('function NL-JsonCanon($v){')
[void]$lib.Add('  if($null -eq $v){ return "null" }')
[void]$lib.Add('  if($v -is [bool]){ if($v){ return "true" } else { return "false" } }')
[void]$lib.Add('  if($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]){ return ([string]$v) }')
[void]$lib.Add('  if($v -is [datetime]){ return ("""" + (NL-JsonEscape $v.ToUniversalTime().ToString("o")) + """") }')
[void]$lib.Add('  if($v -is [string]){ return ("""" + (NL-JsonEscape $v) + """") }')
[void]$lib.Add('  if($v -is [System.Collections.IDictionary]){')
[void]$lib.Add('    $keys = @(@($v.Keys) | ForEach-Object { [string]$_ } | Sort-Object)')
[void]$lib.Add('    $parts = New-Object System.Collections.Generic.List[string]')
[void]$lib.Add('    foreach($k in $keys){ [void]$parts.Add(("""" + (NL-JsonEscape $k) + """") + ":" + (NL-JsonCanon $v[$k])) }')
[void]$lib.Add('    return ("{" + (($parts.ToArray()) -join ",") + "}")')
[void]$lib.Add('  }')
[void]$lib.Add('  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){')
[void]$lib.Add('    $items = New-Object System.Collections.Generic.List[string]')
[void]$lib.Add('    foreach($x in @($v)){ [void]$items.Add((NL-JsonCanon $x)) }')
[void]$lib.Add('    return ("[" + (($items.ToArray()) -join ",") + "]")')
[void]$lib.Add('  }')
[void]$lib.Add('  return ("""" + (NL-JsonEscape ([string]$v)) + """")')
[void]$lib.Add('}')
[void]$lib.Add('')
[void]$lib.Add('function NL-AppendReceipt([string]$RepoRoot,[string]$EventType,[hashtable]$Data){')
[void]$lib.Add('  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$lib.Add('  $rdir = Join-Path $RepoRoot "proofs\receipts"')
[void]$lib.Add('  if (-not (Test-Path -LiteralPath $rdir -PathType Container)) { New-Item -ItemType Directory -Force -Path $rdir | Out-Null }')
[void]$lib.Add('  $rpath = Join-Path $rdir "neverlost.ndjson"')
[void]$lib.Add('  $obj = @{ ts = (NL-NowUtc); event_type = $EventType; data = $Data }')
[void]$lib.Add('  $line = NL-JsonCanon $obj')
[void]$lib.Add('  $u = New-Object System.Text.UTF8Encoding($false)')
[void]$lib.Add('  $b = $u.GetBytes($line + "`n")')
[void]$lib.Add('  $fs = New-Object System.IO.FileStream($rpath,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)')
[void]$lib.Add('  try { $fs.Write($b,0,$b.Length) } finally { $fs.Dispose() }')
[void]$lib.Add('  return $rpath')
[void]$lib.Add('}')
[void]$lib.Add('')
[void]$lib.Add('function NL-LoadTrustBundle([string]$RepoRoot){')
[void]$lib.Add('  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$lib.Add('  $p = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"')
[void]$lib.Add('  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { NL-Die ("MISSING_TRUST_BUNDLE: " + $p) }')
[void]$lib.Add('  $raw = Get-Content -Raw -LiteralPath $p -Encoding UTF8')
[void]$lib.Add('  $tb = $raw | ConvertFrom-Json')
[void]$lib.Add('  return @{ Path=$p; Raw=$raw; Tb=$tb }')
[void]$lib.Add('}')
[void]$lib.Add('')
[void]$lib.Add('function NL-EnumerateSignerEntries($Tb){')
[void]$lib.Add('  $out = New-Object System.Collections.Generic.List[object]')
[void]$lib.Add('  if($null -eq $Tb){ return @() }')
[void]$lib.Add('  $signers = $Tb.signers')
[void]$lib.Add('  $signersA = @(@($signers))')
[void]$lib.Add('  foreach($s in $signersA){ if($null -eq $s){ continue }; [void]$out.Add($s) }')
[void]$lib.Add('  return $out.ToArray()')
[void]$lib.Add('}')
[void]$lib.Add('')
[void]$lib.Add('function NL-WriteAllowedSignersFromTrust([string]$RepoRoot){')
[void]$lib.Add('  $tbInfo = NL-LoadTrustBundle $RepoRoot')
[void]$lib.Add('  $entries = NL-EnumerateSignerEntries $tbInfo.Tb')
[void]$lib.Add('  $entriesA = @(@($entries))')
[void]$lib.Add('  if($entriesA.Count -lt 1){ NL-Die "TRUST_BUNDLE_HAS_NO_SIGNERS" }')
[void]$lib.Add('  $rows = New-Object System.Collections.Generic.List[string]')
[void]$lib.Add('  foreach($e in $entriesA){')
[void]$lib.Add('    $principal = [string]$e.principal')
[void]$lib.Add('    $pub = [string]$e.pubkey')
[void]$lib.Add('    $kid = [string]$e.key_id')
[void]$lib.Add('    $ns = @(@($e.namespaces) | ForEach-Object { [string]$_ } | Sort-Object)')
[void]$lib.Add('    $nsCsv = (@($ns) -join ",")')
[void]$lib.Add('    if([string]::IsNullOrWhiteSpace($principal)){ NL-Die "SIGNER_MISSING_PRINCIPAL" }')
[void]$lib.Add('    if([string]::IsNullOrWhiteSpace($pub)){ NL-Die ("SIGNER_MISSING_PUBKEY principal=" + $principal) }')
[void]$lib.Add('    if([string]::IsNullOrWhiteSpace($nsCsv)){ NL-Die ("SIGNER_MISSING_NAMESPACES principal=" + $principal) }')
[void]$lib.Add('    $opt = ("namespaces=" + $nsCsv)')
[void]$lib.Add('    $line = $principal + " " + $opt + " " + $pub')
[void]$lib.Add('    if(-not [string]::IsNullOrWhiteSpace($kid)){ $line = $line + " " + $kid }')
[void]$lib.Add('    [void]$rows.Add($line)')
[void]$lib.Add('  }')
[void]$lib.Add('  $rows2 = @(@($rows.ToArray()) | Sort-Object)')
[void]$lib.Add('  $asPath = Join-Path $RepoRoot "proofs\trust\allowed_signers"')
[void]$lib.Add('  NL-WriteUtf8NoBomLf $asPath ((@($rows2) -join "`n") + "`n")')
[void]$lib.Add('  NL-AppendReceipt $RepoRoot "neverlost.allowed_signers.write.v1" @{ allowed_signers=$asPath; allowed_signers_sha256=(NL-Sha256HexFile $asPath); trust_bundle_sha256=(NL-Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($tbInfo.Raw))) } | Out-Null')
[void]$lib.Add('  return $asPath')
[void]$lib.Add('}')

Write-Utf8NoBomLf $libPath ((@($lib.ToArray()) -join "`n") + "`n")
Parse-GatePs1 $libPath

# ---------------- scripts/make_allowed_signers_v1.ps1 ----------------
$masPath = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$mas = New-Object System.Collections.Generic.List[string]
[void]$mas.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot)')
[void]$mas.Add('$ErrorActionPreference="Stop"')
[void]$mas.Add('Set-StrictMode -Version Latest')
[void]$mas.Add('$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$mas.Add('$ScriptsDir=Join-Path $RepoRoot "scripts"')
[void]$mas.Add('. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")')
[void]$mas.Add('$as = NL-WriteAllowedSignersFromTrust $RepoRoot')
[void]$mas.Add('Write-Host ("OK: allowed_signers written: " + $as) -ForegroundColor Green')
Write-Utf8NoBomLf $masPath ((@($mas.ToArray()) -join "`n") + "`n")
Parse-GatePs1 $masPath

# ---------------- scripts/show_identity_v1.ps1 ----------------
$sidPath = Join-Path $ScriptsDir "show_identity_v1.ps1"
$sid = New-Object System.Collections.Generic.List[string]
[void]$sid.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot)')
[void]$sid.Add('$ErrorActionPreference="Stop"')
[void]$sid.Add('Set-StrictMode -Version Latest')
[void]$sid.Add('$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$sid.Add('$ScriptsDir=Join-Path $RepoRoot "scripts"')
[void]$sid.Add('. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")')
[void]$sid.Add('$tbInfo = NL-LoadTrustBundle $RepoRoot')
[void]$sid.Add('$entries = NL-EnumerateSignerEntries $tbInfo.Tb')
[void]$sid.Add('$entriesA = @(@($entries))')
[void]$sid.Add('Write-Host ("SIGNERS: " + $entriesA.Count) -ForegroundColor Gray')
[void]$sid.Add('foreach($e in $entriesA){')
[void]$sid.Add('  $p=[string]$e.principal; $kid=[string]$e.key_id; $ns=@(@($e.namespaces) | ForEach-Object { [string]$_ } | Sort-Object)')
[void]$sid.Add('  Write-Host ("  principal=" + $p + " key_id=" + $kid + " namespaces=" + (@($ns)-join ",")) -ForegroundColor Gray')
[void]$sid.Add('}')
[void]$sid.Add('NL-AppendReceipt $RepoRoot "neverlost.identity.show.v1" @{ signers=$entriesA.Count; trust_bundle_path=$tbInfo.Path; trust_bundle_sha256=(NL-Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($tbInfo.Raw))) } | Out-Null')
[void]$sid.Add('Write-Host "OK: identity shown" -ForegroundColor Green')
Write-Utf8NoBomLf $sidPath ((@($sid.ToArray()) -join "`n") + "`n")
Parse-GatePs1 $sidPath

# ---------------- scripts/sign_file_v1.ps1 ----------------
$sfPath = Join-Path $ScriptsDir "sign_file_v1.ps1"
$sf = New-Object System.Collections.Generic.List[string]
[void]$sf.Add('param(')
[void]$sf.Add('  [Parameter(Mandatory=$true)][string]$RepoRoot,')
[void]$sf.Add('  [Parameter(Mandatory=$true)][string]$TargetPath,')
[void]$sf.Add('  [Parameter(Mandatory=$true)][string]$SigNamespace,')
[void]$sf.Add('  [Parameter(Mandatory=$true)][string]$Principal,')
[void]$sf.Add('  [Parameter(Mandatory=$true)][string]$KeyId,')
[void]$sf.Add('  [Parameter(Mandatory=$true)][string]$PrivKeyPath,')
[void]$sf.Add('  [string]$OutSigPath')
[void]$sf.Add(')')
[void]$sf.Add('$ErrorActionPreference="Stop"')
[void]$sf.Add('Set-StrictMode -Version Latest')
[void]$sf.Add('$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$sf.Add('$TargetPath=(Resolve-Path -LiteralPath $TargetPath).Path')
[void]$sf.Add('$PrivKeyPath=(Resolve-Path -LiteralPath $PrivKeyPath).Path')
[void]$sf.Add('$ScriptsDir=Join-Path $RepoRoot "scripts"')
[void]$sf.Add('. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")')
[void]$sf.Add('$ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source')
[void]$sf.Add('if([string]::IsNullOrWhiteSpace($OutSigPath)){ $OutSigPath = ($TargetPath + ".sig") }')
[void]$sf.Add('$outDir = Split-Path -Parent $OutSigPath')
[void]$sf.Add('if($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $outDir | Out-Null }')
[void]$sf.Add('$args = @("-Y","sign","-f",$PrivKeyPath,"-n",$SigNamespace,"-I",$Principal,"-O",("keyid="+$KeyId),"-s",$OutSigPath,$TargetPath)')
[void]$sf.Add('Write-Host ("SIGN_CMD: " + $ssh + " " + (@($args) -join " ")) -ForegroundColor DarkGray')
[void]$sf.Add('$out = & $ssh @args 2>&1')
[void]$sf.Add('if($LASTEXITCODE -ne 0){')
[void]$sf.Add('  NL-AppendReceipt $RepoRoot "neverlost.sig.sign.fail.v1" @{ target=$TargetPath; sig=$OutSigPath; namespace=$SigNamespace; principal=$Principal; key_id=$KeyId; exit_code=[int]$LASTEXITCODE; output=(@($out)-join "`n"); target_sha256=(NL-Sha256HexFile $TargetPath) } | Out-Null')
[void]$sf.Add('  NL-Die ("SIGN_FAILED exit=" + $LASTEXITCODE + " output=" + (@($out)-join "`n"))')
[void]$sf.Add('}')
[void]$sf.Add('NL-AppendReceipt $RepoRoot "neverlost.sig.sign.ok.v1" @{ target=$TargetPath; sig=$OutSigPath; namespace=$SigNamespace; principal=$Principal; key_id=$KeyId; target_sha256=(NL-Sha256HexFile $TargetPath); sig_sha256=(NL-Sha256HexFile $OutSigPath) } | Out-Null')
[void]$sf.Add('Write-Host ("OK: signed -> " + $OutSigPath) -ForegroundColor Green')
Write-Utf8NoBomLf $sfPath ((@($sf.ToArray()) -join "`n") + "`n")
Parse-GatePs1 $sfPath

# ---------------- scripts/verify_sig_v1.ps1 ----------------
$vfPath = Join-Path $ScriptsDir "verify_sig_v1.ps1"
$vf = New-Object System.Collections.Generic.List[string]
[void]$vf.Add('param(')
[void]$vf.Add('  [Parameter(Mandatory=$true)][string]$RepoRoot,')
[void]$vf.Add('  [Parameter(Mandatory=$true)][string]$TargetPath,')
[void]$vf.Add('  [Parameter(Mandatory=$true)][string]$SigPath,')
[void]$vf.Add('  [Parameter(Mandatory=$true)][string]$SigNamespace,')
[void]$vf.Add('  [Parameter(Mandatory=$true)][string]$Principal,')
[void]$vf.Add('  [int]$TimeoutSec = 30')
[void]$vf.Add(')')
[void]$vf.Add('$ErrorActionPreference="Stop"')
[void]$vf.Add('Set-StrictMode -Version Latest')
[void]$vf.Add('$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$vf.Add('$TargetPath=(Resolve-Path -LiteralPath $TargetPath).Path')
[void]$vf.Add('$SigPath=(Resolve-Path -LiteralPath $SigPath).Path')
[void]$vf.Add('$ScriptsDir=Join-Path $RepoRoot "scripts"')
[void]$vf.Add('. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")')
[void]$vf.Add('$ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source')
[void]$vf.Add('$asPath = Join-Path $RepoRoot "proofs\trust\allowed_signers"')
[void]$vf.Add('if (-not (Test-Path -LiteralPath $asPath -PathType Leaf)) { NL-Die ("MISSING_ALLOWED_SIGNERS: " + $asPath + " (run make_allowed_signers_v1.ps1)") }')
[void]$vf.Add('$psi = New-Object System.Diagnostics.ProcessStartInfo')
[void]$vf.Add('$psi.FileName = $ssh')
[void]$vf.Add('$psi.Arguments = ("-Y verify -f `"" + $asPath + "`" -I `"" + $Principal + "`" -n `"" + $SigNamespace + "`" -s `"" + $SigPath + "`"")')
[void]$vf.Add('$psi.UseShellExecute = $false')
[void]$vf.Add('$psi.RedirectStandardInput = $true')
[void]$vf.Add('$psi.RedirectStandardOutput = $true')
[void]$vf.Add('$psi.RedirectStandardError = $true')
[void]$vf.Add('Write-Host ("VERIFY_CMD: " + $ssh + " " + $psi.Arguments) -ForegroundColor DarkGray')
[void]$vf.Add('$p = New-Object System.Diagnostics.Process')
[void]$vf.Add('$p.StartInfo = $psi')
[void]$vf.Add('[void]$p.Start()')
[void]$vf.Add('$bytes = [System.IO.File]::ReadAllBytes($TargetPath)')
[void]$vf.Add('$p.StandardInput.BaseStream.Write($bytes,0,$bytes.Length)')
[void]$vf.Add('$p.StandardInput.Close()')
[void]$vf.Add('if(-not $p.WaitForExit($TimeoutSec*1000)){ try{ $p.Kill() } catch { }; NL-AppendReceipt $RepoRoot "neverlost.sig.verify.timeout.v1" @{ target=$TargetPath; sig=$SigPath; namespace=$SigNamespace; principal=$Principal; timeout_sec=$TimeoutSec; target_sha256=(NL-Sha256HexFile $TargetPath); sig_sha256=(NL-Sha256HexFile $SigPath) } | Out-Null; NL-Die ("VERIFY_TIMEOUT sec=" + $TimeoutSec) }')
[void]$vf.Add('$out = $p.StandardOutput.ReadToEnd()')
[void]$vf.Add('$err = $p.StandardError.ReadToEnd()')
[void]$vf.Add('$code = [int]$p.ExitCode')
[void]$vf.Add('if ($code -ne 0) { NL-AppendReceipt $RepoRoot "neverlost.sig.verify.fail.v1" @{ target=$TargetPath; sig=$SigPath; namespace=$SigNamespace; principal=$Principal; exit_code=$code; stdout=$out; stderr=$err; target_sha256=(NL-Sha256HexFile $TargetPath); sig_sha256=(NL-Sha256HexFile $SigPath); allowed_signers_sha256=(NL-Sha256HexFile $asPath) } | Out-Null; NL-Die ("VERIFY_FAILED exit=" + $code + " stderr=" + $err) }')
[void]$vf.Add('NL-AppendReceipt $RepoRoot "neverlost.sig.verify.ok.v1" @{ target=$TargetPath; sig=$SigPath; namespace=$SigNamespace; principal=$Principal; stdout=$out; stderr=$err; target_sha256=(NL-Sha256HexFile $TargetPath); sig_sha256=(NL-Sha256HexFile $SigPath); allowed_signers_sha256=(NL-Sha256HexFile $asPath) } | Out-Null')
[void]$vf.Add('Write-Host "OK: verify PASS" -ForegroundColor Green')
Write-Utf8NoBomLf $vfPath ((@($vf.ToArray()) -join "`n") + "`n")
Parse-GatePs1 $vfPath

Write-Host ("WROTE+PARSE_OK: " + $libPath) -ForegroundColor Green
Write-Host ("WROTE+PARSE_OK: " + $masPath) -ForegroundColor Green
Write-Host ("WROTE+PARSE_OK: " + $sidPath) -ForegroundColor Green
Write-Host ("WROTE+PARSE_OK: " + $sfPath) -ForegroundColor Green
Write-Host ("WROTE+PARSE_OK: " + $vfPath) -ForegroundColor Green
