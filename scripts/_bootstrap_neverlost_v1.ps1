$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

param(
  [Parameter(Mandatory=$false)][string]$RepoRoot = (Get-Location).Path,
  [Parameter(Mandatory=$false)][switch]$Force,
  [Parameter(Mandatory=$false)][switch]$DoSelfTest
)

if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "Repo root not found: $RepoRoot" }

$enc = [System.Text.UTF8Encoding]::new($false)
function Write-Utf8NoBomFile([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllBytes($Path, $enc.GetBytes($Text.Replace("`r`n","`n")))
}

function Ensure-Dir([string]$p){ if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }

$proofs   = Join-Path $RepoRoot "proofs"
$keysDir  = Join-Path $proofs "keys"
$trustDir = Join-Path $proofs "trust"
$rcptDir  = Join-Path $proofs "receipts"
$scrDir   = Join-Path $RepoRoot "scripts"

Ensure-Dir $keysDir
Ensure-Dir $trustDir
Ensure-Dir $rcptDir
Ensure-Dir $scrDir

$trustBundlePath  = Join-Path $trustDir "trust_bundle.json"
$allowedSigners   = Join-Path $trustDir "allowed_signers"
$receiptsPath     = Join-Path $rcptDir "neverlost.ndjson"

if (-not (Test-Path -LiteralPath $receiptsPath)) { Write-Utf8NoBomFile $receiptsPath "" }

# ------------------------------
# scripts/_lib_neverlost_v1.ps1
# ------------------------------
$libPath = Join-Path $scrDir "_lib_neverlost_v1.ps1"
if ($Force -or -not (Test-Path -LiteralPath $libPath)) {
  $lib = @()
  $lib += '$ErrorActionPreference="Stop"'
  $lib += 'Set-StrictMode -Version Latest'
  $lib += ''
  $lib += '# NeverLost v1 — canonical identity substrate (PowerShell)'
  $lib += '# Deterministic IO + hashing + canonical JSON + ssh-keygen -Y wrappers + receipts'
  $lib += ''
  $lib += 'function NL-GetUtf8NoBomEncoding(){ [System.Text.UTF8Encoding]::new($false) }'
  $lib += 'function Write-Utf8NoBom([string]$Path,[string]$Text){'
  $lib += '  $enc = NL-GetUtf8NoBomEncoding'
  $lib += '  $dir = Split-Path -Parent $Path'
  $lib += '  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }'
  $lib += '  [System.IO.File]::WriteAllBytes($Path, $enc.GetBytes($Text.Replace("`r`n","`n")))'
  $lib += '}'
  $lib += 'function Read-Utf8([string]$Path){'
  $lib += '  $enc = NL-GetUtf8NoBomEncoding'
  $lib += '  $bytes = [System.IO.File]::ReadAllBytes($Path)'
  $lib += '  return $enc.GetString($bytes)'
  $lib += '}'
  $lib += ''
  $lib += 'function Sha256HexBytes([byte[]]$Bytes){'
  $lib += '  $sha = [System.Security.Cryptography.SHA256]::Create()'
  $lib += '  try {'
  $lib += '    $h = $sha.ComputeHash($Bytes)'
  $lib += '    return ([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant()'
  $lib += '  } finally { $sha.Dispose() }'
  $lib += '}'
  $lib += 'function Sha256HexPath([string]$Path){'
  $lib += '  $bytes = [System.IO.File]::ReadAllBytes($Path)'
  $lib += '  return Sha256HexBytes $bytes'
  $lib += '}'
  $lib += ''
  $lib += 'function ResolveRealPath([string]$Path){'
  $lib += '  return (Resolve-Path -LiteralPath $Path).Path'
  $lib += '}'
  $lib += 'function RelPathUnix([string]$Root,[string]$Path){'
  $lib += '  $r = (ResolveRealPath $Root).TrimEnd("\")'
  $lib += '  $p = (ResolveRealPath $Path)'
  $lib += '  if (-not $p.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) { return ($p -replace "\\","/") }'
  $lib += '  $rel = $p.Substring($r.Length).TrimStart("\")'
  $lib += '  return ($rel -replace "\\","/")'
  $lib += '}'
  $lib += ''
  $lib += 'function AssertPrincipalFormat([string]$Principal){'
  $lib += '  if ([string]::IsNullOrWhiteSpace($Principal)) { throw "Principal is required." }'
  $lib += '  if ($Principal.Length -gt 128) { throw "Principal too long (>128): $Principal" }'
  $lib += '  if ($Principal -cne $Principal.ToLowerInvariant()) { throw "Principal must be lowercase: $Principal" }'
  $lib += '  if ($Principal -match "\s") { throw "Principal must not contain spaces: $Principal" }'
  $lib += '  $re = "^single-tenant\/[a-z0-9_]+\/authority\/[a-z0-9_]+$"'
  $lib += '  if ($Principal -notmatch $re) { throw "Principal format invalid: $Principal" }'
  $lib += '}'
  $lib += 'function AssertKeyIdFormat([string]$KeyId){'
  $lib += '  if ([string]::IsNullOrWhiteSpace($KeyId)) { throw "KeyId is required." }'
  $lib += '  if ($KeyId.Length -gt 128) { throw "KeyId too long (>128): $KeyId" }'
  $lib += '  if ($KeyId -match "\s") { throw "KeyId must not contain spaces: $KeyId" }'
  $lib += '  $re = "^[a-z0-9][a-z0-9\-]*[a-z0-9]$"'
  $lib += '  if ($KeyId -notmatch $re) { throw "KeyId format invalid: $KeyId" }'
  $lib += '}'
  $lib += ''
  $lib += 'function NL-ConvertToOrdered($obj){'
  $lib += '  if ($null -eq $obj) { return $null }'
  $lib += '  if ($obj -is [System.Collections.IDictionary]) {'
  $lib += '    $keys = @($obj.Keys) | Sort-Object'
  $lib += '    $o = [ordered]@{}'
  $lib += '    foreach ($k in $keys) { $o[$k] = NL-ConvertToOrdered $obj[$k] }'
  $lib += '    return $o'
  $lib += '  }'
  $lib += '  if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {'
  $lib += '    $arr = @()'
  $lib += '    foreach ($x in $obj) { $arr += ,(NL-ConvertToOrdered $x) }'
  $lib += '    return $arr'
  $lib += '  }'
  $lib += '  return $obj'
  $lib += '}'
  $lib += 'function To-CanonJson($obj,[int]$Depth=64){'
  $lib += '  $ordered = NL-ConvertToOrdered $obj'
  $lib += '  $json = $ordered | ConvertTo-Json -Depth $Depth -Compress'
  $lib += '  return $json'
  $lib += '}'
  $lib += ''
  $lib += 'function Load-TrustBundle([string]$TrustBundlePath){'
  $lib += '  if (-not (Test-Path -LiteralPath $TrustBundlePath)) { throw "Trust bundle not found: $TrustBundlePath" }'
  $lib += '  $txt = Read-Utf8 $TrustBundlePath'
  $lib += '  $obj = $txt | ConvertFrom-Json -Depth 64'
  $lib += '  if ($obj.version -ne 1) { throw "trust_bundle.json version must be 1." }'
  $lib += '  if (-not $obj.authorities) { throw "trust_bundle.json missing authorities." }'
  $lib += '  foreach ($a in $obj.authorities) {'
  $lib += '    AssertPrincipalFormat $a.principal'
  $lib += '    AssertKeyIdFormat $a.key_id'
  $lib += '    if (-not $a.pubkey_path) { throw "authority missing pubkey_path for $($a.principal)" }'
  $lib += '    if (-not $a.pubkey_sha256) { throw "authority missing pubkey_sha256 for $($a.principal)" }'
  $lib += '    if (-not $a.allowed_namespaces) { throw "authority missing allowed_namespaces for $($a.principal)" }'
  $lib += '  }'
  $lib += '  return $obj'
  $lib += '}'
  $lib += ''
  $lib += 'function MakeAllowedSignersLine([string]$Principal,[string[]]$Namespaces,[string]$PublicKeyLine){'
  $lib += '  AssertPrincipalFormat $Principal'
  $lib += '  if (-not $PublicKeyLine) { throw "PublicKeyLine is required." }'
  $lib += '  # PublicKeyLine is the standard ssh public key line: "ssh-ed25519 AAAA... comment"'
  $lib += '  $ns = ($Namespaces | Sort-Object) -join ","'
  $lib += '  return ("{0} namespaces=`"{1}`" {2}" -f $Principal, $ns, $PublicKeyLine.Trim())'
  $lib += '}'
  $lib += 'function WriteAllowedSignersFile([string]$TrustBundlePath,[string]$RepoRoot,[string]$OutPath){'
  $lib += '  $tb = Load-TrustBundle $TrustBundlePath'
  $lib += '  $lines = @()'
  $lib += '  foreach ($a in ($tb.authorities | Sort-Object principal)) {'
  $lib += '    $pubPath = Join-Path $RepoRoot $a.pubkey_path'
  $lib += '    if (-not (Test-Path -LiteralPath $pubPath)) { throw "pubkey not found: $pubPath" }'
  $lib += '    $pubLine = (Read-Utf8 $pubPath).Trim()'
  $lib += '    $pubHash = Sha256HexPath $pubPath'
  $lib += '    if ($pubHash -ne $a.pubkey_sha256) { throw "pubkey_sha256 mismatch for $($a.principal). expected=$($a.pubkey_sha256) actual=$pubHash" }'
  $lib += '    $lines += (MakeAllowedSignersLine $a.principal $a.allowed_namespaces $pubLine)'
  $lib += '  }'
  $lib += '  $out = ($lines -join "`n") + "`n"'
  $lib += '  Write-Utf8NoBom $OutPath $out'
  $lib += '  return $true'
  $lib += '}'
  $lib += ''
  $lib += 'function Write-NeverLostReceipt([string]$ReceiptsPath, $Obj){'
  $lib += '  $line = (To-CanonJson $Obj)'
  $lib += '  # append-only'
  $lib += '  $enc = NL-GetUtf8NoBomEncoding'
  $lib += '  $bytes = $enc.GetBytes($line + "`n")'
  $lib += '  $fs = [System.IO.File]::Open($ReceiptsPath,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)'
  $lib += '  try { $fs.Write($bytes,0,$bytes.Length) } finally { $fs.Dispose() }'
  $lib += '}'
  $lib += ''
  $lib += 'function NL-InvokeExeWithStdinBytes([string]$Exe,[string[]]$Args,[byte[]]$StdinBytes){'
  $lib += '  $psi = [System.Diagnostics.ProcessStartInfo]::new()'
  $lib += '  $psi.FileName = $Exe'
  $lib += '  foreach($a in $Args){ [void]$psi.ArgumentList.Add($a) }'
  $lib += '  $psi.RedirectStandardInput = $true'
  $lib += '  $psi.RedirectStandardOutput = $true'
  $lib += '  $psi.RedirectStandardError = $true'
  $lib += '  $psi.UseShellExecute = $false'
  $lib += '  $p = [System.Diagnostics.Process]::new()'
  $lib += '  $p.StartInfo = $psi'
  $lib += '  if (-not $p.Start()) { throw "Failed to start: $Exe" }'
  $lib += '  if ($StdinBytes) {'
  $lib += '    $p.StandardInput.BaseStream.Write($StdinBytes,0,$StdinBytes.Length)'
  $lib += '  }'
  $lib += '  $p.StandardInput.Close()'
  $lib += '  $stdout = $p.StandardOutput.ReadToEnd()'
  $lib += '  $stderr = $p.StandardError.ReadToEnd()'
  $lib += '  $p.WaitForExit()'
  $lib += '  return [pscustomobject]@{ ExitCode=$p.ExitCode; StdOut=$stdout; StdErr=$stderr }'
  $lib += '}'
  $lib += ''
  $lib += 'function SshYSignFile([string]$PrivateKeyPath,[string]$Namespace,[string]$FilePath,[string]$SigPath){'
  $lib += '  if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) { throw "ssh-keygen not found in PATH (OpenSSH required)." }'
  $lib += '  if (-not (Test-Path -LiteralPath $PrivateKeyPath)) { throw "Private key not found: $PrivateKeyPath" }'
  $lib += '  if (-not (Test-Path -LiteralPath $FilePath)) { throw "File not found: $FilePath" }'
  $lib += '  $args = @("-Y","sign","-f",$PrivateKeyPath,"-n",$Namespace,$FilePath)'
  $lib += '  $p = Start-Process -FilePath "ssh-keygen" -ArgumentList $args -NoNewWindow -Wait -PassThru'
  $lib += '  if ($p.ExitCode -ne 0) { throw "ssh-keygen sign failed (exit $($p.ExitCode))." }'
  $lib += '  $autoSig = "$FilePath.sig"'
  $lib += '  if (-not (Test-Path -LiteralPath $autoSig)) { throw "Expected signature not found: $autoSig" }'
  $lib += '  Move-Item -Force -LiteralPath $autoSig -Destination $SigPath'
  $lib += '}'
  $lib += 'function SshYVerifyFile([string]$AllowedSignersPath,[string]$Principal,[string]$Namespace,[string]$FilePath,[string]$SigPath){'
  $lib += '  if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) { throw "ssh-keygen not found in PATH (OpenSSH required)." }'
  $lib += '  AssertPrincipalFormat $Principal'
  $lib += '  if (-not (Test-Path -LiteralPath $AllowedSignersPath)) { throw "allowed_signers not found: $AllowedSignersPath" }'
  $lib += '  if (-not (Test-Path -LiteralPath $FilePath)) { throw "File not found: $FilePath" }'
  $lib += '  if (-not (Test-Path -LiteralPath $SigPath)) { throw "Signature not found: $SigPath" }'
  $lib += '  $bytes = [System.IO.File]::ReadAllBytes($FilePath)'
  $lib += '  $args = @("-Y","verify","-f",$AllowedSignersPath,"-I",$Principal,"-n",$Namespace,"-s",$SigPath)'
  $lib += '  $r = NL-InvokeExeWithStdinBytes "ssh-keygen" $args $bytes'
  $lib += '  return $r'
  $lib += '}'

  Write-Utf8NoBomFile $libPath (($lib -join "`n") + "`n")
}

# ------------------------------
# scripts/make_allowed_signers_v1.ps1
# ------------------------------
$mk = Join-Path $scrDir "make_allowed_signers_v1.ps1"
if ($Force -or -not (Test-Path -LiteralPath $mk)) {
  $t = @()
  $t += '$ErrorActionPreference="Stop"'
  $t += 'Set-StrictMode -Version Latest'
  $t += 'param([string]$RepoRoot=(Get-Location).Path)'
  $t += '$here = Split-Path -Parent $MyInvocation.MyCommand.Path'
  $t += '. (Join-Path $here "_lib_neverlost_v1.ps1")'
  $t += '$trust = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"'
  $t += '$out   = Join-Path $RepoRoot "proofs\trust\allowed_signers"'
  $t += '[void](WriteAllowedSignersFile $trust $RepoRoot $out)'
  $t += '$rcpt = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"'
  $t += '$tbHash = Sha256HexPath $trust'
  $t += '$asHash = Sha256HexPath $out'
  $t += 'Write-NeverLostReceipt $rcpt ([ordered]@{ts_utc=(Get-Date).ToUniversalTime().ToString("o");action="make_allowed_signers";trust_bundle_sha256=$tbHash;allowed_signers_sha256=$asHash;ok=$true})'
  Write-Utf8NoBomFile $mk (($t -join "`n") + "`n")
}

# ------------------------------
# scripts/show_identity_v1.ps1
# ------------------------------
$show = Join-Path $scrDir "show_identity_v1.ps1"
if ($Force -or -not (Test-Path -LiteralPath $show)) {
  $t = @()
  $t += '$ErrorActionPreference="Stop"'
  $t += 'Set-StrictMode -Version Latest'
  $t += 'param([string]$RepoRoot=(Get-Location).Path)'
  $t += '$here = Split-Path -Parent $MyInvocation.MyCommand.Path'
  $t += '. (Join-Path $here "_lib_neverlost_v1.ps1")'
  $t += '$trust = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"'
  $t += '$as    = Join-Path $RepoRoot "proofs\trust\allowed_signers"'
  $t += '$rcpt  = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"'
  $t += '$tb = Load-TrustBundle $trust'
  $t += '$tbHash = Sha256HexPath $trust'
  $t += '$asHash = if (Test-Path -LiteralPath $as) { Sha256HexPath $as } else { "" }'
  $t += 'Write-Host ("NeverLost v1")'
  $t += 'Write-Host ("trust_bundle_sha256 : " + $tbHash)'
  $t += 'Write-Host ("allowed_signers_sha256: " + $asHash)'
  $t += 'Write-Host ""'
  $t += 'foreach($a in ($tb.authorities | Sort-Object principal)) {'
  $t += '  Write-Host ("principal : " + $a.principal)'
  $t += '  Write-Host ("key_id     : " + $a.key_id)'
  $t += '  Write-Host ("pubkey_path: " + $a.pubkey_path)'
  $t += '  Write-Host ("pubkey_sha256: " + $a.pubkey_sha256)'
  $t += '  Write-Host ("allowed_namespaces: " + (($a.allowed_namespaces | Sort-Object) -join ", "))'
  $t += '  Write-Host ""'
  $t += '}'
  $t += 'Write-NeverLostReceipt $rcpt ([ordered]@{ts_utc=(Get-Date).ToUniversalTime().ToString("o");action="show_identity";trust_bundle_sha256=$tbHash;allowed_signers_sha256=$asHash;ok=$true})'
  Write-Utf8NoBomFile $show (($t -join "`n") + "`n")
}

# ------------------------------
# scripts/sign_file_v1.ps1
# ------------------------------
$sign = Join-Path $scrDir "sign_file_v1.ps1"
if ($Force -or -not (Test-Path -LiteralPath $sign)) {
  $t = @()
  $t += '$ErrorActionPreference="Stop"'
  $t += 'Set-StrictMode -Version Latest'
  $t += 'param(
  $t += '  [Parameter(Mandatory=$true)][string]$RepoRoot,'
  $t += '  [Parameter(Mandatory=$true)][string]$Principal,'
  $t += '  [Parameter(Mandatory=$true)][string]$KeyId,'
  $t += '  [Parameter(Mandatory=$true)][string]$Namespace,'
  $t += '  [Parameter(Mandatory=$true)][string]$FilePath,'
  $t += '  [Parameter(Mandatory=$true)][string]$PrivateKeyPath,'
  $t += '  [Parameter(Mandatory=$false)][string]$SigPath = ($FilePath + ".sig")'
  $t += ' )'
  $t += '$here = Split-Path -Parent $MyInvocation.MyCommand.Path'
  $t += '. (Join-Path $here "_lib_neverlost_v1.ps1")'
  $t += 'AssertPrincipalFormat $Principal'
  $t += 'AssertKeyIdFormat $KeyId'
  $t += '$rcpt = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"'
  $t += '$trust = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"'
  $t += '$tbHash = Sha256HexPath $trust'
  $t += 'SshYSignFile $PrivateKeyPath $Namespace $FilePath $SigPath'
  $t += '$fHash = Sha256HexPath $FilePath'
  $t += '$sHash = Sha256HexPath $SigPath'
  $t += 'Write-NeverLostReceipt $rcpt ([ordered]@{ts_utc=(Get-Date).ToUniversalTime().ToString("o");action="sign";principal=$Principal;key_id=$KeyId;namespace=$Namespace;target_path=(RelPathUnix $RepoRoot $FilePath);target_sha256=$fHash;signature_path=(RelPathUnix $RepoRoot $SigPath);signature_sha256=$sHash;trust_bundle_sha256=$tbHash;ok=$true})'
  Write-Utf8NoBomFile $sign (($t -join "`n") + "`n")
}

# ------------------------------
# scripts/verify_sig_v1.ps1
# ------------------------------
$ver = Join-Path $scrDir "verify_sig_v1.ps1"
if ($Force -or -not (Test-Path -LiteralPath $ver)) {
  $t = @()
  $t += '$ErrorActionPreference="Stop"'
  $t += 'Set-StrictMode -Version Latest'
  $t += 'param(
  $t += '  [Parameter(Mandatory=$true)][string]$RepoRoot,'
  $t += '  [Parameter(Mandatory=$true)][string]$Principal,'
  $t += '  [Parameter(Mandatory=$true)][string]$Namespace,'
  $t += '  [Parameter(Mandatory=$true)][string]$FilePath,'
  $t += '  [Parameter(Mandatory=$true)][string]$SigPath'
  $t += ' )'
  $t += '$here = Split-Path -Parent $MyInvocation.MyCommand.Path'
  $t += '. (Join-Path $here "_lib_neverlost_v1.ps1")'
  $t += 'AssertPrincipalFormat $Principal'
  $t += '$allowed = Join-Path $RepoRoot "proofs\trust\allowed_signers"'
  $t += '$trust   = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"'
  $t += '$rcpt    = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"'
  $t += '$tb = Load-TrustBundle $trust'
  $t += '$auth = $tb.authorities | Where-Object { $_.principal -eq $Principal } | Select-Object -First 1'
  $t += 'if (-not $auth) { throw "Principal not trusted by bundle: $Principal" }'
  $t += '$nsAllowed = @($auth.allowed_namespaces)'
  $t += 'if ($nsAllowed -notcontains $Namespace) { throw "Namespace not allowed for principal. principal=$Principal namespace=$Namespace" }'
  $t += '$r = SshYVerifyFile $allowed $Principal $Namespace $FilePath $SigPath'
  $t += '$ok = ($r.ExitCode -eq 0)'
  $t += '$fHash = Sha256HexPath $FilePath'
  $t += '$sHash = Sha256HexPath $SigPath'
  $t += '$tbHash = Sha256HexPath $trust'
  $t += 'Write-NeverLostReceipt $rcpt ([ordered]@{ts_utc=(Get-Date).ToUniversalTime().ToString("o");action="verify_sig";principal=$Principal;namespace=$Namespace;target_path=(RelPathUnix $RepoRoot $FilePath);target_sha256=$fHash;signature_path=(RelPathUnix $RepoRoot $SigPath);signature_sha256=$sHash;trust_bundle_sha256=$tbHash;ok=$ok;exit_code=$r.ExitCode;stderr=$r.StdErr})'
  $t += 'if (-not $ok) { throw ("Signature verification failed. exit={0} err={1}" -f $r.ExitCode, $r.StdErr) }'
  Write-Utf8NoBomFile $ver (($t -join "`n") + "`n")
}

# ------------------------------
# proofs/trust/trust_bundle.json (template if missing)
# ------------------------------
if (-not (Test-Path -LiteralPath $trustBundlePath)) {
  $repoName = Split-Path -Leaf $RepoRoot
  $bundle = [ordered]@{
    version = 1
    bundle_id = ("{0}-trust-v1" -f $repoName)
    created_utc = (Get-Date).ToUniversalTime().ToString("o")
    authorities = @(
      [ordered]@{
        principal = "single-tenant/REPLACE_TENANT/authority/REPLACE_PRODUCER"
        key_id = "replace-authority-ed25519"
        pubkey_sha256 = "REPLACE_WITH_SHA256_OF_PUBKEY_FILE"
        pubkey_path = "proofs/keys/REPLACE_authority_ed25519.pub"
        allowed_namespaces = @("neverlost/*")
      }
    )
  }
  Write-Utf8NoBomFile $trustBundlePath ((To-CanonJson $bundle) + "`n")
}

# Generate allowed_signers deterministically (will fail until pubkey exists and sha256 matches)
try {
  . (Join-Path $scrDir "_lib_neverlost_v1.ps1")
  if (Test-Path -LiteralPath $trustBundlePath) {
    # only attempt if pubkey_path exists
    $tbTry = (Read-Utf8 $trustBundlePath) | ConvertFrom-Json -Depth 64
    $pp = $tbTry.authorities[0].pubkey_path
    if ($pp) {
      $pubTry = Join-Path $RepoRoot $pp
      if (Test-Path -LiteralPath $pubTry) {
        WriteAllowedSignersFile $trustBundlePath $RepoRoot $allowedSigners | Out-Null
      }
    }
  }
} catch { }

# Optional self-test (only runs if we have a private key and trust is configured)
if ($DoSelfTest) {
  try {
    . (Join-Path $scrDir "_lib_neverlost_v1.ps1")
    $tb = Load-TrustBundle $trustBundlePath
    $a = $tb.authorities[0]
    $privGuess = Join-Path $RepoRoot ($a.pubkey_path -replace "\.pub$","")
    $pubPath = Join-Path $RepoRoot $a.pubkey_path
    if ((Test-Path -LiteralPath $privGuess) -and (Test-Path -LiteralPath $pubPath)) {
      WriteAllowedSignersFile $trustBundlePath $RepoRoot $allowedSigners | Out-Null
      $testFile = Join-Path $RepoRoot "proofs\receipts\_neverlost_selftest.txt"
      Write-Utf8NoBom $testFile ("neverlost-selftest " + (Get-Date).ToUniversalTime().ToString("o"))
      $sig = $testFile + ".sig"
      SshYSignFile $privGuess "neverlost/selftest" $testFile $sig
      $r = SshYVerifyFile $allowedSigners $a.principal "neverlost/selftest" $testFile $sig
      if ($r.ExitCode -ne 0) { throw "Self-test verify failed: $($r.StdErr)" }
    }
  } catch { }
}

Write-Host "NeverLost v1 installed: $RepoRoot" -ForegroundColor Green
Write-Host "Next:" -ForegroundColor Cyan
Write-Host "  1) Put pubkey in proofs/keys and update trust_bundle.json pubkey_path + pubkey_sha256"
Write-Host "  2) Run: pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\make_allowed_signers_v1.ps1 -RepoRoot `"$RepoRoot`""
Write-Host "  3) Run: pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\show_identity_v1.ps1 -RepoRoot `"$RepoRoot`""

exit 0
