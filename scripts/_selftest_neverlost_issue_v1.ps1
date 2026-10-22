param([Parameter(Mandatory=$true)][string]$RepoRoot)

# Selftest for identity issuance, rotation, revocation and the issuance plan
# (scripts/issue_identity_v1.ps1, revoke_identity_v1.ps1, issue_plan_v1.ps1). Runs in a sandbox copy,
# so the live trust root, keys and ledger are never touched. Every negative requires its exact code and
# leaves the bundle bytes unchanged. Stdout is deterministic.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw ("ISSUE_SELFTEST_FAIL: " + $m) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path (Join-Path $RepoRoot "scripts") "_lib_neverlost_v1.ps1")
. (Join-Path (Join-Path $RepoRoot "scripts") "_lib_neverlost_host_v1.ps1")
$PSExe = NL-ResolvePsHost
$ssh = NL-ResolveSshKeygen

$sb = NL-NewSandboxRepo -RepoRoot $RepoRoot -Label "issue_selftest"
try {
  $sc = Join-Path $sb "scripts"
  $io = Join-Path $sb "io"
  $tb = Join-Path (Join-Path (Join-Path $sb "proofs") "trust") "trust_bundle.json"
  $ledger = Join-Path (Join-Path (Join-Path $sb "proofs") "receipts") "neverlost.ndjson"
  $script:n = 0
  function Run([string]$Script,[string[]]$A){
    $script:n++
    return NL-InvokePsFile -File (Join-Path $sc $Script) -PsHost $PSExe -Arguments $A -StdoutPath (Join-Path $io ([string]$script:n + ".out")) -StderrPath (Join-Path $io ([string]$script:n + ".err"))
  }
  function Issue([string[]]$A){ return Run "issue_identity_v1.ps1" (@("-RepoRoot",$sb) + $A) }
  function Expect-Ok($r,[string]$Token,[string]$Name){ if($r.ExitCode -ne 0 -or $r.Stdout.IndexOf($Token,[System.StringComparison]::Ordinal) -lt 0){ Die ($Name + " exit=" + $r.ExitCode + " " + $r.Stderr) } }
  function Expect-Refused($r,[string]$Code,[string]$Name){
    $before = $script:bundleSha
    if($r.ExitCode -eq 0){ Die ($Name + ": DID_NOT_FAIL") }
    if(($r.Stdout + "`n" + $r.Stderr).IndexOf($Code,[System.StringComparison]::Ordinal) -lt 0){ Die ($Name + ": WRONG_CODE expected=" + $Code + " got=" + $r.Stderr) }
    if((NL-Sha256HexFile $tb) -cne $before){ Die ($Name + ": BUNDLE_CHANGED_ON_REFUSAL") }
  }
  function Sync-Sha(){ $script:bundleSha = NL-Sha256HexFile $tb }

  # 1. The writer reproduces the bundle byte for byte.
  $m = NL-ReadTrustBundleModelV1 $sb $tb
  if((NL-TrustBundleJsonV1 $m) -cne $m.Raw){ Die "ROUNDTRIP_NOT_IDENTICAL" }
  $principal0 = [string]$m.Principals[0].principal
  Write-Output "ISSUE_VECTOR_ROUNDTRIP_OK"

  # 2. Issue with a NeverLost-generated key, then use it.
  Sync-Sha
  $p1 = "single-tenant/device_agent/selftest-svc"
  $r = Issue @("-Id","selftest-svc","-Principal",$p1,"-Namespaces","selftest/b,selftest/a","-Generate","-Consumer","selftest-consumer")
  Expect-Ok $r "IDENTITY_ISSUED_OK" "issue_generate"
  $entries = NL-AssertTrustBundleV1 -RepoRoot $sb
  NL-AssertAllowedSignersCurrentV1 $sb $entries
  if([string]$entries[0].principal -cne $principal0){ Die "PRINCIPAL0_MOVED" }
  $e1 = @($entries | Where-Object { [string]$_.principal -ceq $p1 })
  if($e1.Count -ne 1 -or ((@($e1[0].namespaces)) -join ",") -cne "selftest/a,selftest/b"){ Die "ISSUED_ENTRY_WRONG" }
  $priv = Join-Path (Join-Path (Join-Path $sb "proofs") "keys") "selftest-svc_ed25519"
  if(-not (Test-Path -LiteralPath $priv -PathType Leaf)){ Die "PRIVATE_KEY_MISSING" }
  $pubText = [System.IO.File]::ReadAllText($priv + ".pub")
  if($pubText.Contains("`r") -or -not $pubText.EndsWith("`n") -or @($pubText.TrimEnd("`n").Split("`n")).Count -ne 1){ Die "PUBKEY_NOT_ONE_LF_LINE" }
  $pubDir = Join-Path (Join-Path $sb "proofs") "published"
  $shaLine = [System.IO.File]::ReadAllText((Join-Path $pubDir "trust_bundle.sha256"))
  if(-not $shaLine.StartsWith((NL-Sha256HexFile $tb) + "  trust_bundle.json")){ Die "PUBLISHED_SHA_WRONG" }
  $cAs = [System.IO.File]::ReadAllText((Join-Path (Join-Path $pubDir "selftest-consumer") "allowed_signers"))
  if(@($cAs.TrimEnd("`n").Split("`n")).Count -ne 1 -or -not $cAs.StartsWith($p1 + " ")){ Die "CONSUMER_SIGNERS_WRONG" }
  if(-not (Test-Path -LiteralPath (Join-Path (Join-Path $pubDir "selftest-consumer") "HANDOFF.md") -PathType Leaf)){ Die "HANDOFF_MISSING" }
  if([System.IO.File]::ReadAllText($ledger).IndexOf('"event_type":"neverlost.trust.issue.v1"',[System.StringComparison]::Ordinal) -lt 0){ Die "ISSUE_RECEIPT_MISSING" }
  $payload = Join-Path $io "payload.txt"
  [System.IO.File]::WriteAllBytes($payload,(New-Object System.Text.UTF8Encoding($false)).GetBytes("issued identity payload`n"))
  Expect-Ok (Run "sign_file_v1.ps1" @("-RepoRoot",$sb,"-TargetPath",$payload,"-SigNamespace","selftest/a","-Principal",$p1,"-KeyId","selftest-svc-ed25519","-PrivKeyPath",$priv)) "OK: signed" "sign_with_issued"
  Expect-Ok (Run "verify_sig_v1.ps1" @("-RepoRoot",$sb,"-TargetPath",$payload,"-SigPath",($payload + ".sig"),"-SigNamespace","selftest/a","-Principal",$p1)) "OK: verify PASS" "verify_issued"
  Write-Output "ISSUE_VECTOR_GENERATE_OK"

  # 3. Refusals leave the bundle unchanged.
  Sync-Sha
  Expect-Refused (Issue @("-Id","selftest-svc2","-Principal",$p1,"-Namespaces","selftest/a","-Generate")) "ISSUE_PRINCIPAL_EXISTS" "duplicate_principal"
  Expect-Refused (Issue @("-Id","bad-role","-Principal","single-tenant/root/x","-Namespaces","selftest/a","-Generate")) "ISSUE_PRINCIPAL_FORMAT" "bad_role"
  Expect-Refused (Issue @("-Id","bad-ns","-Principal","single-tenant/device_agent/bad-ns","-Namespaces","bad ns","-Generate")) "ISSUE_NAMESPACE_FORMAT" "bad_namespace"
  Expect-Refused (Issue @("-Id","Bad_Id","-Principal","single-tenant/device_agent/bad-id","-Namespaces","selftest/a","-Generate")) "ISSUE_ID_FORMAT" "bad_id"
  Expect-Refused (Issue @("-Id","both","-Principal","single-tenant/device_agent/both","-Namespaces","selftest/a","-Generate","-PubkeyPath",($priv + ".pub"))) "ISSUE_KEY_SOURCE_AMBIGUOUS" "two_key_sources"
  Expect-Refused (Issue @("-Id","none","-Principal","single-tenant/device_agent/none","-Namespaces","selftest/a")) "ISSUE_KEY_SOURCE_MISSING" "no_key_source"
  Expect-Refused (Issue @("-Id","reuse","-Principal","single-tenant/device_agent/reuse","-Namespaces","selftest/a","-PubkeyPath",($priv + ".pub"))) "ISSUE_KEY_ALREADY_TRUSTED" "same_key_two_principals"
  Expect-Refused (Issue @("-Id","selftest-svc","-Principal","single-tenant/device_agent/other","-Namespaces","selftest/a","-Generate")) "ISSUE_KEY_ID_EXISTS" "key_id_taken"
  Expect-Refused (Issue @("-Id","ghost","-Principal","single-tenant/device_agent/ghost","-Namespaces","selftest/a","-Generate","-Replace")) "ISSUE_REPLACE_UNKNOWN_PRINCIPAL" "replace_unknown"
  # A broken trust root is never extended.
  $good = [System.IO.File]::ReadAllBytes($tb)
  Remove-Item -LiteralPath $tb -Force
  [System.IO.File]::WriteAllBytes($tb,(New-Object System.Text.UTF8Encoding($false)).GetBytes('{"schema":"neverlost.trust_bundle.v1","principals":"not-an-array"}'))
  Sync-Sha
  Expect-Refused (Issue @("-Id","on-broken","-Principal","single-tenant/device_agent/on-broken","-Namespaces","selftest/a","-Generate")) "TRUST_BUNDLE_INVALID:PRINCIPALS_NOT_ARRAY" "broken_bundle"
  if(Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $sb "proofs") "keys") "on-broken_ed25519")){ Die "KEY_CREATED_FOR_BROKEN_BUNDLE" }
  Remove-Item -LiteralPath $tb -Force
  [System.IO.File]::WriteAllBytes($tb,$good)
  Write-Output "ISSUE_VECTOR_REFUSALS_OK"

  # 4. Consumer-held key: enroll a public key the service created.
  $ext = Join-Path $io "consumer_key"
  $kg = NL-InvokeNative -Exe $ssh -Arguments @("-q","-t","ed25519","-N","","-C","consumer","-f",$ext) -NullStdin
  if($kg.Code -ne 0){ Die ("KEYGEN " + $kg.Output) }
  $p2 = "single-tenant/device_agent/selftest-consumer"
  $r = Issue @("-Id","selftest-consumer","-Principal",$p2,"-Namespaces","selftest/c","-KeyId","consumer-chosen-id","-PubkeyPath",($ext + ".pub"))
  Expect-Ok $r "CUSTODY=consumer" "enroll_consumer_key"
  if(Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $sb "proofs") "keys") "selftest-consumer_ed25519")){ Die "PRIVATE_KEY_FOR_CONSUMER_CUSTODY" }
  $allE = NL-AssertTrustBundleV1 -RepoRoot $sb
  if(@($allE | Where-Object { [string]$_.key_id -ceq "consumer-chosen-id" }).Count -ne 1){ Die "CONSUMER_KEY_ID_NOT_KEPT" }
  Write-Output "ISSUE_VECTOR_ENROLL_OK"

  # 5. Rotation: new key verifies, the old key's signature no longer does, old files retired.
  $r = Issue @("-Id","selftest-svc","-Principal",$p1,"-Namespaces","selftest/a,selftest/b","-Generate","-Replace")
  Expect-Ok $r "IDENTITY_ISSUED_OK" "rotate"
  if(@(Get-ChildItem -LiteralPath (Join-Path (Join-Path (Join-Path $sb "proofs") "keys") "retired") -File).Count -ne 2){ Die "ROTATE_NOT_RETIRED" }
  $v = Run "verify_sig_v1.ps1" @("-RepoRoot",$sb,"-TargetPath",$payload,"-SigPath",($payload + ".sig"),"-SigNamespace","selftest/a","-Principal",$p1)
  if($v.ExitCode -eq 0){ Die "OLD_SIGNATURE_STILL_VALID_AFTER_ROTATE" }
  $payload2 = Join-Path $io "payload2.txt"
  [System.IO.File]::WriteAllBytes($payload2,(New-Object System.Text.UTF8Encoding($false)).GetBytes("after rotation`n"))
  Expect-Ok (Run "sign_file_v1.ps1" @("-RepoRoot",$sb,"-TargetPath",$payload2,"-SigNamespace","selftest/b","-Principal",$p1,"-KeyId","selftest-svc-ed25519","-PrivKeyPath",$priv)) "OK: signed" "sign_after_rotate"
  Write-Output "ISSUE_VECTOR_ROTATE_OK"

  # 6. Revocation.
  Sync-Sha
  Expect-Refused (Run "revoke_identity_v1.ps1" @("-RepoRoot",$sb,"-Principal",$principal0)) "REVOKE_REFUSED_EXPECTED_PRINCIPAL" "revoke_expected"
  Expect-Refused (Run "revoke_identity_v1.ps1" @("-RepoRoot",$sb,"-Principal","single-tenant/device_agent/nobody")) "REVOKE_UNKNOWN_PRINCIPAL" "revoke_unknown"
  Expect-Ok (Run "revoke_identity_v1.ps1" @("-RepoRoot",$sb,"-Principal",$p1)) "IDENTITY_REVOKED_OK" "revoke"
  $entries = NL-AssertTrustBundleV1 -RepoRoot $sb
  NL-AssertAllowedSignersCurrentV1 $sb $entries
  if(@($entries | Where-Object { [string]$_.principal -ceq $p1 }).Count){ Die "REVOKED_PRINCIPAL_STILL_TRUSTED" }
  $v = Run "verify_sig_v1.ps1" @("-RepoRoot",$sb,"-TargetPath",$payload2,"-SigPath",($payload2 + ".sig"),"-SigNamespace","selftest/b","-Principal",$p1)
  if($v.ExitCode -eq 0){ Die "SIGNATURE_VALID_AFTER_REVOKE" }
  if(Test-Path -LiteralPath $priv){ Die "REVOKED_KEY_NOT_RETIRED" }
  Write-Output "ISSUE_VECTOR_REVOKE_OK"

  # 7. The plan: states, apply, idempotence. A fake dev root holds a consumer's public key.
  $dev = Join-Path $io "devroot"
  $svcKeys = Join-Path (Join-Path (Join-Path (Join-Path $dev "_Family") "planconsumer") "proofs") "keys"
  New-Item -ItemType Directory -Force -Path $svcKeys | Out-Null
  $kg = NL-InvokeNative -Exe $ssh -Arguments @("-q","-t","ed25519","-N","","-C","planconsumer","-f",(Join-Path $svcKeys "planconsumer_ed25519")) -NullStdin
  if($kg.Code -ne 0){ Die ("KEYGEN2 " + $kg.Output) }
  $planPath = Join-Path $io "plan.json"
  $planJson = '{"schema":"neverlost.issuance_plan.v1","identities":[' +
    '{"id":"plan-gen","principal":"single-tenant/device_agent/plan-gen","namespaces":["plan/gen"],"custody":"neverlost","consumer":"plan-gen"},' +
    '{"id":"plan-consumer","principal":"single-tenant/device_agent/plan-consumer","namespaces":["plan/consumer"],"custody":"consumer","consumer":"planconsumer","pubkey":{"service":"planconsumer","path":"proofs/keys/planconsumer_ed25519.pub"}},' +
    '{"id":"plan-missing","principal":"single-tenant/device_agent/plan-missing","namespaces":["plan/missing"],"custody":"consumer","consumer":"absent","pubkey":{"service":"absent","path":"proofs/keys/absent.pub"}},' +
    '{"id":"plan-needs","principal":"single-tenant/device_agent/plan/<id>","namespaces":["plan/needs"],"custody":"neverlost","consumer":"x","needs":"ids"},' +
    '{"id":"plan-existing","principal":"' + $p2 + '","namespaces":["selftest/c"],"custody":"neverlost","consumer":"x"}]}'
  [System.IO.File]::WriteAllBytes($planPath,(New-Object System.Text.UTF8Encoding($false)).GetBytes($planJson))
  $show = Run "issue_plan_v1.ps1" @("-RepoRoot",$sb,"-PlanPath",$planPath,"-DevRoot",$dev)
  Expect-Ok $show "SUMMARY issued=1 ready=2 waiting=2" "plan_show"
  Sync-Sha
  if((NL-Sha256HexFile $tb) -cne $script:bundleSha){ Die "PLAN_SHOW_CHANGED_BUNDLE" }
  Expect-Ok (Run "issue_plan_v1.ps1" @("-RepoRoot",$sb,"-PlanPath",$planPath,"-DevRoot",$dev,"-Apply")) "ISSUE_PLAN_APPLIED" "plan_apply"
  $entries = NL-AssertTrustBundleV1 -RepoRoot $sb
  foreach($want in @("single-tenant/device_agent/plan-gen","single-tenant/device_agent/plan-consumer")){ if(@($entries | Where-Object { [string]$_.principal -ceq $want }).Count -ne 1){ Die ("PLAN_DID_NOT_ISSUE " + $want) } }
  if(@($entries | Where-Object { [string]$_.principal -like "*plan-missing*" -or [string]$_.principal -like "*<id>*" }).Count){ Die "PLAN_ISSUED_WAITING_ITEM" }
  Expect-Ok (Run "issue_plan_v1.ps1" @("-RepoRoot",$sb,"-PlanPath",$planPath,"-DevRoot",$dev,"-Apply")) "ISSUE_PLAN_NOTHING_TO_DO" "plan_idempotent"
  # The shipped plan parses and only names valid principals or waiting templates.
  $shipped = Run "issue_plan_v1.ps1" @("-RepoRoot",$sb,"-PlanPath",(Join-Path (Join-Path $RepoRoot "config") "issuance_plan.v1.json"),"-DevRoot",(Join-Path $io "no-devroot"))
  Expect-Ok $shipped "ISSUE_PLAN_SHOWN" "shipped_plan"
  Write-Output "ISSUE_VECTOR_PLAN_OK"

  # 8. Every receipt line written above is valid.
  Expect-Ok (Run "verify_receipt_ledger_v1.ps1" @("-RepoRoot",$sb,"-Strict")) "RECEIPT_LEDGER_VERIFY_OK" "ledger"
  Write-Output "ISSUE_VECTOR_LEDGER_OK"
}
finally {
  NL-RemoveSandboxRepo $sb
}

Write-Output "NEVERLOST_ISSUE_SELFTEST_OK"
