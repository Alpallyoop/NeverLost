param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Parse-GatePs1([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSE_GATE_MISSING: " + $Path) }
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  $errs = @(@($err))
  if($errs.Count -gt 0){
    $e = $errs[0]
    Die ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message)
  }
}

function ReadUtf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-LedgerCount([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return 0 }
  $lines = @((Get-Content -LiteralPath $Path -Encoding UTF8) | Where-Object { $_.Trim().Length -gt 0 })
  return $lines.Count
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$ReceiptDir = Join-Path $RepoRoot "proofs\receipts"
$LedgerPath = Join-Path $ReceiptDir "neverlost.ndjson"
$SessionPath = Join-Path $ReceiptDir "active_authority_session.json"

$StartPath   = Join-Path $ScriptsDir "start_authority_v1.ps1"
$ConfirmPath = Join-Path $ScriptsDir "confirm_authority_v1.ps1"
$EndPath     = Join-Path $ScriptsDir "end_authority_v1.ps1"

Parse-GatePs1 $StartPath
Parse-GatePs1 $ConfirmPath
Parse-GatePs1 $EndPath

$PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){ Die ("MISSING_POWERSHELL_EXE: " + $PSExe) }

$fixedStart = "2026-03-28T00:00:00Z"
$fixedConfirm = "2026-03-28T00:05:00Z"
$fixedEnd = "2026-03-28T00:10:00Z"

$before = Get-LedgerCount $LedgerPath

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $StartPath -RepoRoot $RepoRoot -StartTimeUtc $fixedStart -Note "authority lifecycle selftest" | Out-Host
if($LASTEXITCODE -ne 0){ Die ("START_CHILD_FAILED: " + $LASTEXITCODE) }

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ConfirmPath -RepoRoot $RepoRoot -ConfirmTimeUtc $fixedConfirm | Out-Host
if($LASTEXITCODE -ne 0){ Die ("CONFIRM_CHILD_FAILED: " + $LASTEXITCODE) }

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $EndPath -RepoRoot $RepoRoot -EndTimeUtc $fixedEnd -Note "authority lifecycle selftest complete" | Out-Host
if($LASTEXITCODE -ne 0){ Die ("END_CHILD_FAILED: " + $LASTEXITCODE) }

$after = Get-LedgerCount $LedgerPath
if(($after - $before) -lt 3){ Die "LEDGER_APPEND_COUNT_LT_3" }

$sessionText = ReadUtf8 $SessionPath
if($sessionText.IndexOf('"active":false',[System.StringComparison]::Ordinal) -lt 0){ Die "SESSION_NOT_ENDED" }

$ledgerLines = @((Get-Content -LiteralPath $LedgerPath -Encoding UTF8) | Where-Object { $_.Trim().Length -gt 0 })
$tail = @($ledgerLines | Select-Object -Last 3)
if($tail.Count -ne 3){ Die "LEDGER_TAIL_COUNT_NE_3" }

if($tail[0].IndexOf('"schema":"neverlost.operator.authority.started.v1"',[System.StringComparison]::Ordinal) -lt 0){ Die "MISSING_STARTED_RECEIPT" }
if($tail[1].IndexOf('"schema":"neverlost.operator.authority.confirmed.v1"',[System.StringComparison]::Ordinal) -lt 0){ Die "MISSING_CONFIRMED_RECEIPT" }
if($tail[2].IndexOf('"schema":"neverlost.operator.authority.ended.v1"',[System.StringComparison]::Ordinal) -lt 0){ Die "MISSING_ENDED_RECEIPT" }

$sessionIds = @()
foreach($line in $tail){
  $m = [regex]::Match($line, '"session_id":"([^"]+)"')
  if(-not $m.Success){ Die "SESSION_ID_MISSING_IN_RECEIPT" }
  $sessionIds += $m.Groups[1].Value
}

$uniqueSessionIds = @($sessionIds | Select-Object -Unique)
if($uniqueSessionIds.Count -ne 1){ Die "SESSION_ID_NOT_STABLE" }

Write-Host "NEVERLOST_AUTHORITY_TIER0_ALL_GREEN" -ForegroundColor Green
Write-Host ("SESSION_ID=" + $uniqueSessionIds[0]) -ForegroundColor Green
