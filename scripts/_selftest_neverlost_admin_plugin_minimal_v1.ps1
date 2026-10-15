param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

# Selftest for the minimal admin plugin (docs/ADMIN_PLUGIN_MINIMAL_v1.md), run in a sandbox copy so the
# live session and receipts are untouched. Covers: status, deny outside managed mode, deny without an
# active session, allowed confirm of an active session, and that every admin receipt line is valid JSON
# (CLI output with newlines must be escaped).

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw ("ADMIN_PLUGIN_SELFTEST_FAIL: " + $m) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path (Join-Path $RepoRoot "scripts") "_lib_neverlost_host_v1.ps1")
$PSExe = NL-ResolvePsHost

$sb = NL-NewSandboxRepo -RepoRoot $RepoRoot -Label "admin_plugin_selftest"
try {
  $plugin = Join-Path (Join-Path $sb "scripts") "neverlost_admin_plugin_minimal_v1.ps1"
  $cli = Join-Path (Join-Path $sb "scripts") "neverlost_cli_v1.ps1"
  $io = Join-Path $sb "io"
  function Run([string]$File,[string[]]$A,[string]$Label){
    return NL-InvokePsFile -File $File -PsHost $PSExe -Arguments $A -StdoutPath (Join-Path $io ($Label + ".out")) -StderrPath (Join-Path $io ($Label + ".err"))
  }

  $r = Run $plugin @("-RepoRoot",$sb,"-Action","status","-AdminActor","selftest") "status"
  if($r.ExitCode -ne 0 -or $r.Stdout -notmatch 'ADMIN_PLUGIN_STATUS_OK' -or $r.Stdout -notmatch 'ACTIVE=FALSE'){ Die ("STATUS " + $r.Stderr) }

  $r = Run $plugin @("-RepoRoot",$sb,"-Action","confirm","-TargetMode","local","-AdminActor","selftest") "deny_local"
  if($r.Stdout -notmatch 'ADMIN_PLUGIN_CONFIRM_DENIED' -or $r.Stdout -notmatch 'REASON=ADMIN_PLUGIN_REQUIRES_MANAGED_MODE'){ Die "DENY_LOCAL" }

  $r = Run $plugin @("-RepoRoot",$sb,"-Action","confirm","-TargetMode","managed","-AdminActor","selftest") "deny_inactive"
  if($r.Stdout -notmatch 'REASON=NO_ACTIVE_SESSION'){ Die "DENY_INACTIVE" }

  $r = Run $cli @("-RepoRoot",$sb,"-Area","authority","-Action","start") "start"
  if($r.ExitCode -ne 0){ Die ("START " + $r.Stderr) }

  $r = Run $plugin @("-RepoRoot",$sb,"-Action","confirm","-TargetMode","managed","-AdminActor","selftest") "confirm"
  if($r.ExitCode -ne 0 -or $r.Stdout -notmatch 'ADMIN_PLUGIN_CONFIRM_OK'){ Die ("CONFIRM " + $r.Stdout + " " + $r.Stderr) }

  $receipts = Join-Path (Join-Path (Join-Path (Join-Path $sb "proofs") "receipts") "admin_plugin") "admin_actions.ndjson"
  if(-not (Test-Path -LiteralPath $receipts -PathType Leaf)){ Die "RECEIPTS_MISSING" }
  $text = (New-Object System.Text.UTF8Encoding($false)).GetString([System.IO.File]::ReadAllBytes($receipts))
  $lines = @($text.TrimEnd("`n").Split("`n"))
  if($lines.Count -ne 4){ Die ("RECEIPT_COUNT actual=" + $lines.Count) }
  $decisions = @()
  foreach($l in $lines){
    try { $o = $l | ConvertFrom-Json -ErrorAction Stop } catch { Die ("RECEIPT_NOT_JSON " + $l) }
    if([string]$o.schema -cne "neverlost.admin_plugin.action.v1"){ Die "RECEIPT_SCHEMA" }
    $decisions += [string]$o.decision
  }
  if(($decisions -join ",") -cne "inactive,deny,deny,allow"){ Die ("RECEIPT_DECISIONS " + ($decisions -join ",")) }
  $last = $lines[3] | ConvertFrom-Json
  if(([string]$last.cli_stdout).IndexOf("AUTHORITY_CONFIRMED_OK",[System.StringComparison]::Ordinal) -lt 0){ Die "RECEIPT_CLI_STDOUT" }
}
finally {
  NL-RemoveSandboxRepo $sb
}

Write-Host "NEVERLOST_ADMIN_PLUGIN_SELFTEST_OK" -ForegroundColor Green
