param([Parameter(Mandatory=$true)][string]$RepoRoot)

# One entry point for every portable proof lane (Windows PowerShell 5.1, PowerShell 7 on Windows,
# Linux and macOS). Lanes run in sandbox copies (.scratch/sandbox) and do not write to the live trust
# directory or the live receipt ledger. Evidence-writing lanes (tier0 full green, freeze, trust pipeline
# evidence) and the Windows MSI smoke stay separate.
#
# Trust under test: NEVERLOST_TRUST_SOURCE=live (default, this checkout's proofs/trust) or fixture
# (test_vectors/fixtures/trust_root_v1, for clean clones and CI).

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
. (Join-Path $ScriptsDir "_lib_neverlost_host_v1.ps1")
$PSExe = NL-ResolvePsHost
$trustSource = NL-TrustSource

# Parse gate: every top-level script must parse.
foreach($f in @(Get-ChildItem -LiteralPath $ScriptsDir -File -Filter *.ps1 | Sort-Object Name)){
  $tok = $null; $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tok,[ref]$err)
  if($err -and @($err).Count -gt 0){ $e = @($err)[0]; Die ("PARSE_GATE_FAIL: " + $f.Name + ":" + $e.Extent.StartLineNumber + ": " + $e.Message) }
}
Write-Output "LANE parse_gate OK"

$io = Join-Path (Join-Path $RepoRoot ".scratch") ("ci_" + [Guid]::NewGuid().ToString("N"))
function Lane([string]$Name,[string]$Script,[string[]]$LaneArgs,[string]$Token){
  $r = NL-InvokePsFile -File (Join-Path $ScriptsDir $Script) -PsHost $PSExe -Arguments $LaneArgs -StdoutPath (Join-Path $io ($Name + ".out")) -StderrPath (Join-Path $io ($Name + ".err"))
  if($r.ExitCode -ne 0 -or $r.Stdout.IndexOf($Token,[System.StringComparison]::Ordinal) -lt 0){
    Write-Output $r.Stdout
    Write-Output $r.Stderr
    Die ("CI_LANE_FAILED: " + $Name + " exit=" + $r.ExitCode)
  }
  Write-Output ("LANE " + $Name + " OK")
}

try {
  $sb = NL-NewSandboxRepo -RepoRoot $RepoRoot -Label "ci_trust"
  try {
    Lane "trust_bundle_verify" "verify_trust_bundle_v1.ps1" @("-RepoRoot",$sb,"-UseExpectedFiles") "TRUST_BUNDLE_VERIFY_OK"
  } finally { NL-RemoveSandboxRepo $sb }

  $liveLedger = Join-Path (Join-Path (Join-Path $RepoRoot "proofs") "receipts") "neverlost.ndjson"
  if($trustSource -eq "live" -and (Test-Path -LiteralPath $liveLedger -PathType Leaf)){
    Lane "receipt_ledger_verify" "verify_receipt_ledger_v1.ps1" @("-RepoRoot",$RepoRoot) "RECEIPT_LEDGER_VERIFY_OK"
  } else {
    Write-Output "LANE receipt_ledger_verify SKIPPED (no live ledger in this checkout)"
  }

  Lane "cli_selftest" "_selftest_neverlost_cli_v1.ps1" @("-RepoRoot",$RepoRoot) "NEVERLOST_CLI_SELFTEST_OK"
  Lane "cli_vectors" "verify_neverlost_cli_vectors_v1.ps1" @("-RepoRoot",$RepoRoot) "NEVERLOST_CLI_VECTORS_OK"
  Lane "trust_signature_vectors" "_RUN_neverlost_vectors_v3.ps1" @("-RepoRoot",$RepoRoot) "NEVERLOST_VECTORS_FULL_GREEN"
  Lane "authority_lifecycle" "_RUN_neverlost_authority_full_green_v1.ps1" @("-RepoRoot",$RepoRoot) "NEVERLOST_AUTHORITY_TIER0_ALL_GREEN"
  Lane "admin_plugin_selftest" "_selftest_neverlost_admin_plugin_minimal_v1.ps1" @("-RepoRoot",$RepoRoot) "NEVERLOST_ADMIN_PLUGIN_SELFTEST_OK"
}
finally {
  NL-RemoveScratchTree $io
}

Write-Output ("TRUST_SOURCE=" + $trustSource)
Write-Output "NEVERLOST_CI_GREEN"
