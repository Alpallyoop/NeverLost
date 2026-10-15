param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

# NeverLost CLI lifecycle selftest: status -> start -> confirm -> end -> status, run in a fresh sandbox
# copy of the instrument (.scratch/sandbox) so it never depends on, or writes to, the live authority
# session and receipt ledger. Also checks the receipts the lifecycle appended in the sandbox ledger.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die {
  param([Parameter(Mandatory=$true)][string]$Message)
  throw $Message
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  Die ("MISSING_REPOROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path (Join-Path $RepoRoot "scripts") "_lib_neverlost_host_v1.ps1")
$PSExe = NL-ResolvePsHost

function Invoke-CLI {
  param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Area,
    [Parameter(Mandatory=$true)][string]$Action
  )
  $CliPath = Join-Path (Join-Path $Root "scripts") "neverlost_cli_v1.ps1"
  $tmp = Join-Path $Root "io"
  return NL-InvokePsFile -File $CliPath -PsHost $PSExe -Arguments @("-RepoRoot",$Root,"-Area",$Area,"-Action",$Action) -StdoutPath (Join-Path $tmp ($Action + "." + [Guid]::NewGuid().ToString("N") + ".stdout.txt")) -StderrPath (Join-Path $tmp ($Action + "." + [Guid]::NewGuid().ToString("N") + ".stderr.txt"))
}

$sb = NL-NewSandboxRepo -RepoRoot $RepoRoot -Label "cli_selftest"
try {
  $statusBefore = Invoke-CLI -Root $sb -Area "authority" -Action "status"
  if($statusBefore.ExitCode -ne 0){ Die "SELFTEST_STATUS_BEFORE_FAILED" }
  if($statusBefore.Stdout -match 'AUTHORITY_STATUS=ACTIVE'){ Die "SELFTEST_REQUIRES_INACTIVE_STATE" }

  $start = Invoke-CLI -Root $sb -Area "authority" -Action "start"
  if($start.ExitCode -ne 0){ Die ("SELFTEST_START_FAILED: " + $start.Stderr) }
  if($start.Stdout -notmatch 'AUTHORITY_STARTED_OK'){ Die "SELFTEST_START_TOKEN_MISSING" }

  $confirm = Invoke-CLI -Root $sb -Area "authority" -Action "confirm"
  if($confirm.ExitCode -ne 0){ Die ("SELFTEST_CONFIRM_FAILED: " + $confirm.Stderr) }
  if($confirm.Stdout -notmatch 'AUTHORITY_CONFIRMED_OK'){ Die "SELFTEST_CONFIRM_TOKEN_MISSING" }

  $end = Invoke-CLI -Root $sb -Area "authority" -Action "end"
  if($end.ExitCode -ne 0){ Die ("SELFTEST_END_FAILED: " + $end.Stderr) }
  if($end.Stdout -notmatch 'AUTHORITY_ENDED_OK'){ Die "SELFTEST_END_TOKEN_MISSING" }

  $statusAfter = Invoke-CLI -Root $sb -Area "authority" -Action "status"
  if($statusAfter.ExitCode -ne 0){ Die "SELFTEST_STATUS_AFTER_FAILED" }
  if($statusAfter.Stdout -notmatch 'AUTHORITY_STATUS=INACTIVE'){ Die "SELFTEST_STATUS_AFTER_NOT_INACTIVE" }

  # Receipt checks: exactly started -> confirmed -> ended for one session id, each a canonical line.
  $ledger = Join-Path (Join-Path (Join-Path $sb "proofs") "receipts") "neverlost.ndjson"
  if(-not (Test-Path -LiteralPath $ledger -PathType Leaf)){ Die "SELFTEST_LEDGER_MISSING" }
  $bytes = [System.IO.File]::ReadAllBytes($ledger)
  if($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){ Die "SELFTEST_LEDGER_BOM" }
  $text = (New-Object System.Text.UTF8Encoding($false)).GetString($bytes)
  if($text.Contains("`r")){ Die "SELFTEST_LEDGER_CR" }
  $lines = @($text.TrimEnd("`n").Split("`n"))
  if($lines.Count -ne 3){ Die ("SELFTEST_LEDGER_LINE_COUNT actual=" + $lines.Count) }
  $want = @("neverlost.operator.authority.started.v1","neverlost.operator.authority.confirmed.v1","neverlost.operator.authority.ended.v1")
  $sid = $null
  for($i = 0; $i -lt 3; $i++){
    $o = $lines[$i] | ConvertFrom-Json
    if([string]$o.schema -cne $want[$i]){ Die ("SELFTEST_LEDGER_SCHEMA idx=" + $i + " actual=" + [string]$o.schema) }
    if(-not [bool]$o.ok){ Die ("SELFTEST_LEDGER_NOT_OK idx=" + $i) }
    if($null -eq $sid){ $sid = [string]$o.session_id }
    if([string]$o.session_id -cne $sid){ Die "SELFTEST_LEDGER_SESSION_MISMATCH" }
    if([string]$o.trust_bundle_sha256 -cnotmatch '^[a-f0-9]{64}$'){ Die "SELFTEST_LEDGER_TRUST_HASH" }
  }
}
finally {
  NL-RemoveSandboxRepo $sb
}

Write-Host "NEVERLOST_CLI_SELFTEST_OK" -ForegroundColor Green
