param([Parameter(Mandatory=$true)][string]$RepoRoot)

# NeverLost trust + signature vectors (v3).
# Every negative case runs the real verifier or ssh-keygen against a real fixture and requires the
# specific failure code. Fixtures live in an isolated sandbox under .scratch/sandbox and are removed
# afterwards; the live trust directory and the live receipt ledger are never written.
# Stdout is deterministic (no paths, times or ids) so the freeze lane can compare runs.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Parse-GatePs1([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSE_GATE_MISSING: " + $Path) }
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message)
  }
}

function Write-Bytes([string]$Path,[string]$Text){
  $d = Split-Path -Parent $Path
  if($d -and -not (Test-Path -LiteralPath $d -PathType Container)){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
  if(Test-Path -LiteralPath $Path -PathType Leaf){ Remove-Item -LiteralPath $Path -Force }
  [System.IO.File]::WriteAllBytes($Path,(New-Object System.Text.UTF8Encoding($false)).GetBytes($Text))
}

# Runs a script block that must throw; the message must start with $Code.
function Expect-Fail([string]$Name,[string]$Code,[scriptblock]$Block){
  $msg = $null
  try { & $Block | Out-Null } catch { $msg = [string]$_.Exception.Message }
  if($null -eq $msg){ Die ("NEVERLOST_VECTOR_FAIL:" + $Name + ":DID_NOT_FAIL") }
  if(-not $msg.StartsWith($Code,[System.StringComparison]::Ordinal)){ Die ("NEVERLOST_VECTOR_FAIL:" + $Name + ":WRONG_CODE expected=" + $Code + " actual=" + $msg) }
}

function Bundle-Json([string]$Principal,[string]$KeyId,[string]$PubPath,[string]$PubSha,[string]$Pub,[string[]]$Ns){
  $nsJson = (@($Ns) | ForEach-Object { '"' + $_ + '"' }) -join ","
  return ('{"schema":"neverlost.trust_bundle.v1","created_utc":"2026-01-01T00:00:00Z","principals":[{"principal":"' + $Principal + '","keys":[{"key_id":"' + $KeyId + '","alg":"ssh-ed25519","pubkey_path":"' + $PubPath + '","pubkey_sha256":"' + $PubSha + '","pubkey":"' + $Pub + '","namespaces":[' + $nsJson + ']}]}]}')
}

$ExpectedPrincipalGood = "single-tenant/watchtower_authority/authority/watchtower"
$ExpectedPrincipalBad  = "single-tenant/watchtower_authority/authority/not-watchtower"
$ExpectedNamespacesGood = @("nfl/ingest-receipt","packet/envelope","watchtower","watchtower/device-pledge")
$ExpectedNamespacesBad  = @("nfl/ingest-receipt","packet/envelope","watchtower","watchtower/device-pledge-WRONG")

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$HostLibPath = Join-Path $ScriptsDir "_lib_neverlost_host_v1.ps1"
$AclPath = Join-Path $ScriptsDir "enforce_trust_acl_v1.ps1"

Parse-GatePs1 $LibPath
Parse-GatePs1 $HostLibPath
Parse-GatePs1 $AclPath
Parse-GatePs1 (Join-Path $ScriptsDir "sign_file_v1.ps1")
Parse-GatePs1 (Join-Path $ScriptsDir "verify_sig_v1.ps1")

. $LibPath
. $HostLibPath

$PSExe = NL-ResolvePsHost
$ssh = NL-ResolveSshKeygen

$sb = NL-NewSandboxRepo -RepoRoot $RepoRoot -Label "vectors_v3"
try {
  $io = Join-Path $sb "io"
  # ACL lane on the sandbox trust directory (the live trust pipeline lane covers proofs/trust itself).
  $sbAcl = Join-Path (Join-Path $sb "scripts") "enforce_trust_acl_v1.ps1"
  $aclRun = NL-InvokePsFile -File $sbAcl -Arguments @("-RepoRoot",$sb) -PsHost $PSExe -StdoutPath (Join-Path $io "acl.out") -StderrPath (Join-Path $io "acl.err")
  if($aclRun.ExitCode -ne 0){ Die ("ACL_CHILD_FAILED: " + $aclRun.ExitCode + " " + $aclRun.Stderr) }

  # --- positive: trust root under test (live by default, fixture with NEVERLOST_TRUST_SOURCE=fixture)
  $entries = NL-AssertTrustBundleV1 -RepoRoot $sb -ExpectedPrincipal $ExpectedPrincipalGood -ExpectedNamespaces $ExpectedNamespacesGood
  if(@($entries).Count -lt 1){ Die "NEVERLOST_VECTOR_POSITIVE_FAIL: NO_ENTRIES" }
  NL-AssertAllowedSignersCurrentV1 $sb $entries
  Write-Host "NEVERLOST_VECTOR_POSITIVE_OK" -ForegroundColor Green

  # --- negative: expectation mismatches against the same bundle ------------------------------
  Expect-Fail "wrong_principal" "TRUST_EXPECTED_PRINCIPAL_MISMATCH" { NL-AssertTrustBundleV1 -RepoRoot $sb -ExpectedPrincipal $ExpectedPrincipalBad }
  Write-Host "NEVERLOST_VECTOR_NEGATIVE_WRONG_PRINCIPAL_OK" -ForegroundColor Green
  Expect-Fail "namespace" "TRUST_EXPECTED_NAMESPACES_MISMATCH" { NL-AssertTrustBundleV1 -RepoRoot $sb -ExpectedPrincipal $ExpectedPrincipalGood -ExpectedNamespaces $ExpectedNamespacesBad }
  Write-Host "NEVERLOST_VECTOR_NEGATIVE_NAMESPACE_OK" -ForegroundColor Green

  $fx = Join-Path $sb "fixtures"
  New-Item -ItemType Directory -Force -Path $fx | Out-Null

  # Ephemeral signer created for this run only (private key never leaves the sandbox).
  $keyBase = Join-Path (Join-Path (Join-Path $sb "proofs") "keys") "vector_signer_ed25519"
  # Windows PowerShell 5.1 drops empty native arguments; it needs a literal "" to pass an empty passphrase.
  $emptyPass = ""
  if($PSVersionTable.PSEdition -ne 'Core'){ $emptyPass = '""' }
  $kg = $null | & $ssh -q -t ed25519 -N $emptyPass -C "neverlost-vector" -f $keyBase 2>&1
  if(-not (Test-Path -LiteralPath $keyBase -PathType Leaf)){ Die ("VECTOR_KEYGEN_FAILED: " + ((@($kg) | ForEach-Object { [string]$_ }) -join " ")) }
  NL-ProtectPrivateKey $keyBase
  $pubPath = $keyBase + ".pub"
  $pubRel = "proofs/keys/vector_signer_ed25519.pub"
  $pubSha = NL-Sha256HexFile $pubPath
  $pubCore = NL-PubkeyCore ([System.IO.File]::ReadAllText($pubPath))
  $vPrincipal = "single-tenant/operator/neverlost/vector-signer"
  $vNs = @("neverlost/vector")
  $good = Bundle-Json $vPrincipal "vector-signer-ed25519" $pubRel $pubSha $pubCore $vNs

  # --- trust bundle shape and integrity negatives ---------------------------------------------
  $cases = @(
    @{ n="malformed_shape";   c="TRUST_BUNDLE_INVALID:PRINCIPALS_NOT_ARRAY"; t='{"schema":"neverlost.trust_bundle.v1","principals":"not-an-array"}' },
    @{ n="truncated_json";    c="TRUST_BUNDLE_INVALID:JSON_PARSE";           t=$good.Substring(0, [int]($good.Length / 2)) },
    @{ n="empty_file";        c="TRUST_BUNDLE_INVALID:EMPTY";                t="" },
    @{ n="wrong_schema_id";   c="TRUST_BUNDLE_INVALID:SCHEMA_ID";            t=$good.Replace('neverlost.trust_bundle.v1','neverlost.trust_bundle.v0') },
    @{ n="empty_principals";  c="TRUST_BUNDLE_INVALID:PRINCIPALS_EMPTY";     t='{"schema":"neverlost.trust_bundle.v1","principals":[]}' },
    @{ n="unknown_role";      c="TRUST_BUNDLE_INVALID:PRINCIPAL_FORMAT";     t=$good.Replace('single-tenant/operator/','single-tenant/root/') },
    @{ n="unknown_field";     c="TRUST_BUNDLE_INVALID:UNKNOWN_FIELD";        t=$good.Replace('"alg":"ssh-ed25519"','"alg":"ssh-ed25519","extra":true') },
    @{ n="unsupported_alg";   c="TRUST_BUNDLE_INVALID:ALG_UNSUPPORTED";      t=$good.Replace('"alg":"ssh-ed25519"','"alg":"ssh-rsa"') },
    @{ n="corrupted_pub_sha"; c="TRUST_BUNDLE_INVALID:PUBKEY_SHA256_MISMATCH"; t=$good.Replace($pubSha, ("0" * 64)) },
    @{ n="pubkey_mismatch";   c="TRUST_BUNDLE_INVALID:PUBKEY_FILE_MISMATCH"; t=$good.Replace($pubCore, ([string]$entries[0].pubkey)) },
    @{ n="missing_pub_file";  c="TRUST_BUNDLE_INVALID:PUBKEY_FILE_MISSING";  t=$good.Replace($pubRel,'proofs/keys/absent.pub') },
    @{ n="path_traversal";    c="TRUST_BUNDLE_INVALID:PUBKEY_PATH_TRAVERSAL"; t=$good.Replace($pubRel,'proofs/../proofs/keys/vector_signer_ed25519.pub') },
    @{ n="no_namespaces";     c="TRUST_BUNDLE_INVALID:NAMESPACES_MISSING";   t=$good.Replace(',"namespaces":["neverlost/vector"]','') },
    @{ n="bad_namespace";     c="TRUST_BUNDLE_INVALID:NAMESPACE_FORMAT";     t=$good.Replace('"neverlost/vector"','"neverlost vector"') }
  )
  foreach($case in $cases){
    $p = Join-Path $fx ($case.n + ".json")
    Write-Bytes $p ([string]$case.t)
    Expect-Fail ([string]$case.n) ([string]$case.c) { NL-AssertTrustBundleV1 -RepoRoot $sb -TrustBundlePath $p }
  }
  $bomPath = Join-Path $fx "bom.json"
  [System.IO.File]::WriteAllBytes($bomPath, [byte[]](@(0xEF,0xBB,0xBF) + @((New-Object System.Text.UTF8Encoding($false)).GetBytes($good))))
  Expect-Fail "utf8_bom" "TRUST_BUNDLE_INVALID:UTF8_BOM" { NL-AssertTrustBundleV1 -RepoRoot $sb -TrustBundlePath $bomPath }
  Write-Host "NEVERLOST_VECTOR_NEGATIVE_MALFORMED_SHAPE_OK" -ForegroundColor Green
  Write-Host "NEVERLOST_VECTOR_NEGATIVE_INTEGRITY_OK" -ForegroundColor Green

  # --- signature lane: install the fixture bundle as the sandbox trust root --------------------
  $sbTrust = Join-Path (Join-Path $sb "proofs") "trust"
  Write-Bytes (Join-Path $sbTrust "trust_bundle.json") $good
  $sbEntries = NL-AssertTrustBundleV1 -RepoRoot $sb -ExpectedPrincipal $vPrincipal -ExpectedNamespaces $vNs
  Expect-Fail "stale_allowed_signers" "TRUST_ALLOWED_SIGNERS_STALE" { NL-AssertAllowedSignersCurrentV1 $sb $sbEntries }
  [void](NL-WriteAllowedSignersFromTrust $sb)
  NL-AssertAllowedSignersCurrentV1 $sb $sbEntries

  $payload = Join-Path $fx "payload.txt"
  Write-Bytes $payload "neverlost vector payload v1`n"
  $signScript = Join-Path (Join-Path $sb "scripts") "sign_file_v1.ps1"
  $verifyScript = Join-Path (Join-Path $sb "scripts") "verify_sig_v1.ps1"
  function Invoke-Sign([string]$Target,[string]$Ns,[string]$Principal,[string]$KeyId,[string]$Label){
    return NL-InvokePsFile -File $signScript -PsHost $PSExe -Arguments @("-RepoRoot",$sb,"-TargetPath",$Target,"-SigNamespace",$Ns,"-Principal",$Principal,"-KeyId",$KeyId,"-PrivKeyPath",$keyBase) -StdoutPath (Join-Path $io ($Label + ".out")) -StderrPath (Join-Path $io ($Label + ".err"))
  }
  function Invoke-Verify([string]$Target,[string]$Sig,[string]$Ns,[string]$Principal,[string]$Label){
    return NL-InvokePsFile -File $verifyScript -PsHost $PSExe -Arguments @("-RepoRoot",$sb,"-TargetPath",$Target,"-SigPath",$Sig,"-SigNamespace",$Ns,"-Principal",$Principal) -StdoutPath (Join-Path $io ($Label + ".out")) -StderrPath (Join-Path $io ($Label + ".err"))
  }
  function Expect-ChildFail([object]$Run,[string]$Name,[string]$Code){
    if($Run.ExitCode -eq 0){ Die ("NEVERLOST_VECTOR_FAIL:" + $Name + ":DID_NOT_FAIL") }
    if(($Run.Stdout + "`n" + $Run.Stderr).IndexOf($Code,[System.StringComparison]::Ordinal) -lt 0){ Die ("NEVERLOST_VECTOR_FAIL:" + $Name + ":WRONG_CODE expected=" + $Code + " stderr=" + $Run.Stderr) }
  }

  $s = Invoke-Sign $payload "neverlost/vector" $vPrincipal "vector-signer-ed25519" "sign_ok"
  if($s.ExitCode -ne 0 -or $s.Stdout.IndexOf("OK: signed",[System.StringComparison]::Ordinal) -lt 0){ Die ("NEVERLOST_VECTOR_FAIL:sign_ok exit=" + $s.ExitCode + " stderr=" + $s.Stderr) }
  $sig = $payload + ".sig"
  $v = Invoke-Verify $payload $sig "neverlost/vector" $vPrincipal "verify_ok"
  if($v.ExitCode -ne 0 -or $v.Stdout.IndexOf("OK: verify PASS",[System.StringComparison]::Ordinal) -lt 0){ Die ("NEVERLOST_VECTOR_FAIL:verify_ok exit=" + $v.ExitCode + " stderr=" + $v.Stderr) }
  Write-Host "NEVERLOST_VECTOR_SIGNATURE_POSITIVE_OK" -ForegroundColor Green

  Expect-ChildFail (Invoke-Sign $payload "neverlost/vector" $vPrincipal "vector-signer-ed25519" "sign_again") "sign_no_overwrite" "SIGN_OUTPUT_EXISTS"
  $payload2 = Join-Path $fx "payload2.txt"
  Write-Bytes $payload2 "neverlost vector payload v2`n"
  Expect-ChildFail (Invoke-Sign $payload2 "other/namespace" $vPrincipal "vector-signer-ed25519" "sign_ns") "sign_namespace" "SIGN_DENIED_NAMESPACE"
  Expect-ChildFail (Invoke-Sign $payload2 "neverlost/vector" "single-tenant/operator/neverlost/intruder" "vector-signer-ed25519" "sign_untrusted") "sign_untrusted" "SIGN_DENIED_UNTRUSTED_SIGNER"

  $tampered = Join-Path $fx "tampered.txt"
  Write-Bytes $tampered "neverlost vector payload v1 TAMPERED`n"
  Expect-ChildFail (Invoke-Verify $tampered $sig "neverlost/vector" $vPrincipal "verify_tampered") "verify_tampered" "VERIFY_FAILED"
  Expect-ChildFail (Invoke-Verify $payload $sig "watchtower" $vPrincipal "verify_ns") "verify_wrong_namespace" "VERIFY_FAILED"
  Expect-ChildFail (Invoke-Verify $payload $sig "neverlost/vector" "single-tenant/operator/neverlost/intruder" "verify_principal") "verify_wrong_principal" "VERIFY_FAILED"
  $corruptSig = Join-Path $fx "corrupt.sig"
  $sigText = [System.IO.File]::ReadAllText($sig)
  $lines = $sigText.Split("`n")
  $mid = [int]([Math]::Floor($lines.Count / 2))
  $ln = $lines[$mid]
  $flip = 'A'
  if($ln.Length -gt 0 -and $ln[0] -eq 'A'){ $flip = 'B' }
  if($ln.Length -gt 0){ $lines[$mid] = $flip + $ln.Substring(1) }
  Write-Bytes $corruptSig ($lines -join "`n")
  Expect-ChildFail (Invoke-Verify $payload $corruptSig "neverlost/vector" $vPrincipal "verify_corrupt") "verify_corrupt_sig" "VERIFY_FAILED"

  # Stale signer list: the trust bundle changes (namespace widened) but allowed_signers was not rebuilt.
  Write-Bytes (Join-Path $sbTrust "trust_bundle.json") (Bundle-Json $vPrincipal "vector-signer-ed25519" $pubRel $pubSha $pubCore @("neverlost/vector","neverlost/vector2"))
  Expect-ChildFail (Invoke-Verify $payload $sig "neverlost/vector" $vPrincipal "verify_stale") "verify_stale_signers" "TRUST_ALLOWED_SIGNERS_STALE"
  Write-Host "NEVERLOST_VECTOR_SIGNATURE_NEGATIVE_OK" -ForegroundColor Green

  # --- receipt ledger contract (neverlost.receipt.v1) -----------------------------------------
  $ledgerScript = Join-Path (Join-Path $sb "scripts") "verify_receipt_ledger_v1.ps1"
  $sbLedger = Join-Path (Join-Path (Join-Path $sb "proofs") "receipts") "neverlost.ndjson"
  $lv = NL-InvokePsFile -File $ledgerScript -PsHost $PSExe -Arguments @("-RepoRoot",$sb,"-Strict") -StdoutPath (Join-Path $io "ledger_ok.out") -StderrPath (Join-Path $io "ledger_ok.err")
  if($lv.ExitCode -ne 0 -or $lv.Stdout.IndexOf("RECEIPT_LEDGER_VERIFY_OK",[System.StringComparison]::Ordinal) -lt 0){ Die ("NEVERLOST_VECTOR_FAIL:ledger_ok stderr=" + $lv.Stderr) }
  if($lv.Stdout.IndexOf("FAMILY neverlost.sig.sign.ok.v1=1",[System.StringComparison]::Ordinal) -lt 0){ Die "NEVERLOST_VECTOR_FAIL:ledger_sign_receipt_missing" }
  if($lv.Stdout.IndexOf("FAMILY neverlost.sig.verify.ok.v1=1",[System.StringComparison]::Ordinal) -lt 0){ Die "NEVERLOST_VECTOR_FAIL:ledger_verify_receipt_missing" }
  $good1 = [System.IO.File]::ReadAllText($sbLedger)
  $ledgerCases = @(
    @{ n="ledger_partial_line"; c="LEDGER_INVALID:JSON_PARSE"; t=($good1 + '{"schema":"neverlost.operator.authority.started.v1","act' + "`n") },
    @{ n="ledger_foreign";      c="LEDGER_INVALID:FOREIGN_FAMILY"; t=($good1 + '{"schema":"other.receipt.v1"}' + "`n") },
    @{ n="ledger_bad_session";  c="LEDGER_INVALID:AUTHORITY_SHA256_FORMAT"; t=($good1 + '{"action":"authority.started","allowed_signers_sha256":"' + ("a" * 64) + '","authority_state":"active","note":"","ok":true,"principal":"p","schema":"neverlost.operator.authority.started.v1","session_id":"not-a-hash","time_utc":"2026-01-01T00:00:00Z","trust_bundle_sha256":"' + ("b" * 64) + '"}' + "`n") },
    @{ n="ledger_no_final_lf";  c="LEDGER_INVALID:NO_FINAL_LF"; t=$good1.TrimEnd("`n") }
  )
  foreach($lc in $ledgerCases){
    $lp = Join-Path $fx ([string]$lc.n + ".ndjson")
    Write-Bytes $lp ([string]$lc.t)
    Expect-ChildFail (NL-InvokePsFile -File $ledgerScript -PsHost $PSExe -Arguments @("-RepoRoot",$sb,"-LedgerPath",$lp) -StdoutPath (Join-Path $io ([string]$lc.n + ".out")) -StderrPath (Join-Path $io ([string]$lc.n + ".err"))) ([string]$lc.n) ([string]$lc.c)
  }
  $replay = Join-Path $fx "ledger_replay.ndjson"
  $start1 = '{"action":"authority.started","allowed_signers_sha256":"' + ("a" * 64) + '","authority_state":"active","note":"","ok":true,"principal":"p","schema":"neverlost.operator.authority.started.v1","session_id":"' + ("c" * 64) + '","time_utc":"2026-01-01T00:00:00Z","trust_bundle_sha256":"' + ("b" * 64) + '"}'
  Write-Bytes $replay ($start1 + "`n" + $start1 + "`n")
  Expect-ChildFail (NL-InvokePsFile -File $ledgerScript -PsHost $PSExe -Arguments @("-RepoRoot",$sb,"-LedgerPath",$replay,"-Strict") -StdoutPath (Join-Path $io "replay.out") -StderrPath (Join-Path $io "replay.err")) "ledger_replay" "LEDGER_ANOMALIES"
  Write-Host "NEVERLOST_VECTOR_LEDGER_OK" -ForegroundColor Green
}
finally {
  NL-RemoveSandboxRepo $sb
}

Write-Host "NEVERLOST_VECTORS_FULL_GREEN" -ForegroundColor Green
