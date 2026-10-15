param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$LedgerPath = "",
  [switch]$Strict
)
# Non-mutating verifier for the NeverLost receipt ledger (contract neverlost.receipt.v1,
# schemas/neverlost_receipt_v1.schema.json). Recomputes, never trusts:
#   - encoding: UTF-8 without BOM, LF line ends, final LF, no empty lines (historic CRLF lines are anomalies)
#   - every line is a JSON object identified by "schema" or "event_type" in the neverlost family
#   - authority lifecycle receipts: exact field set, sha256 formats, action/state/schema agreement
#   - provenance chain: confirmed/ended only for a started session; no confirm after end; no double end
# Format defects always fail. Lifecycle anomalies and historic CRLF lines are listed; they fail only with -Strict
# (historic ledgers can contain anomalies written by the pre-2026-10 test lanes).
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if([string]::IsNullOrWhiteSpace($LedgerPath)){ $LedgerPath = Join-Path (Join-Path (Join-Path $RepoRoot "proofs") "receipts") "neverlost.ndjson" }
if(-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)){ throw ("LEDGER_MISSING: " + $LedgerPath) }

function Fail([string]$Code,[int]$Line,[string]$Detail){ throw ("LEDGER_INVALID:" + $Code + " line=" + $Line + " " + $Detail) }
function Prop([object]$o,[string]$n){ $p = $o.PSObject.Properties[$n]; if($null -eq $p){ return $null }; return $p.Value }

$bytes = [System.IO.File]::ReadAllBytes($LedgerPath)
if($bytes.Length -eq 0){ Write-Output "LEDGER_LINES=0"; Write-Output "RECEIPT_LEDGER_VERIFY_OK"; exit 0 }
if($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){ Fail "UTF8_BOM" 1 "" }
try { $text = (New-Object System.Text.UTF8Encoding($false,$true)).GetString($bytes) } catch { Fail "UTF8_DECODE" 0 $_.Exception.Message }
if(-not $text.EndsWith("`n")){ Fail "NO_FINAL_LF" 0 "" }

$sha = '^[a-f0-9]{64}$'
$utc = '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$'
$authority = @{
  "neverlost.operator.authority.started.v1"   = @{ action="authority.started";   state="active";   fields=@("action","allowed_signers_sha256","authority_state","note","ok","principal","schema","session_id","time_utc","trust_bundle_sha256") }
  "neverlost.operator.authority.confirmed.v1" = @{ action="authority.confirmed"; state="active";   fields=@("action","allowed_signers_sha256","authority_state","ok","principal","schema","session_id","time_utc","trust_bundle_sha256") }
  "neverlost.operator.authority.ended.v1"     = @{ action="authority.ended";     state="inactive"; fields=@("action","allowed_signers_sha256","authority_state","note","ok","principal","schema","session_id","time_utc","trust_bundle_sha256") }
}

$lines = $text.Substring(0, $text.Length - 1).Split("`n")
$families = @{}
$started = @{}
$ended = @{}
$anomalies = New-Object System.Collections.Generic.List[string]
$n = 0
foreach($rawLine in $lines){
  $n++
  $raw = $rawLine
  if($raw.EndsWith("`r")){
    # Historic defect: Windows PowerShell Add-Content wrote CRLF for tier0 run receipts (fixed 2026-10-15).
    [void]$anomalies.Add("line=" + $n + " LEGACY_CRLF_LINE")
    $raw = $raw.Substring(0, $raw.Length - 1)
  }
  if($raw.Contains("`r")){ Fail "CR_PRESENT" $n "" }
  if($raw.Length -eq 0){ Fail "EMPTY_LINE" $n "" }
  try { $o = $raw | ConvertFrom-Json -ErrorAction Stop } catch { Fail "JSON_PARSE" $n $_.Exception.Message }
  if(-not ($o -is [System.Management.Automation.PSCustomObject])){ Fail "NOT_OBJECT" $n "" }
  $schema = Prop $o "schema"
  $event = Prop $o "event_type"
  $id = $null
  if($null -ne $schema){ $id = [string]$schema } elseif($null -ne $event){ $id = [string]$event }
  if([string]::IsNullOrWhiteSpace($id)){ Fail "UNIDENTIFIED" $n "" }
  if($id -cnotmatch '^neverlost[./]'){ Fail "FOREIGN_FAMILY" $n $id }
  if($families.ContainsKey($id)){ $families[$id]++ } else { $families[$id] = 1 }

  if($authority.ContainsKey($id)){
    $spec = $authority[$id]
    $names = @($o.PSObject.Properties.Name)
    foreach($f in $spec.fields){ if($names -notcontains $f){ Fail "AUTHORITY_FIELD_MISSING" $n $f } }
    foreach($f in $names){ if(@($spec.fields) -notcontains $f){ Fail "AUTHORITY_FIELD_UNKNOWN" $n $f } }
    if([string](Prop $o "action") -cne $spec.action){ Fail "AUTHORITY_ACTION" $n "" }
    if([string](Prop $o "authority_state") -cne $spec.state){ Fail "AUTHORITY_STATE" $n "" }
    if((Prop $o "ok") -ne $true){ Fail "AUTHORITY_OK" $n "" }
    foreach($f in @("allowed_signers_sha256","session_id","trust_bundle_sha256")){ if([string](Prop $o $f) -cnotmatch $sha){ Fail "AUTHORITY_SHA256_FORMAT" $n $f } }
    $t = Prop $o "time_utc"
    if($t -is [datetime]){ $t = $t.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
    if([string]$t -cnotmatch $utc){ Fail "AUTHORITY_TIME_FORMAT" $n "" }
    if([string]::IsNullOrWhiteSpace([string](Prop $o "principal"))){ Fail "AUTHORITY_PRINCIPAL_EMPTY" $n "" }

    $sid = [string](Prop $o "session_id")
    switch($spec.action){
      "authority.started"   { if($started.ContainsKey($sid)){ [void]$anomalies.Add("line=" + $n + " DUPLICATE_START session=" + $sid) }; $started[$sid] = $n }
      "authority.confirmed" { if(-not $started.ContainsKey($sid)){ [void]$anomalies.Add("line=" + $n + " CONFIRM_WITHOUT_START session=" + $sid) } elseif($ended.ContainsKey($sid)){ [void]$anomalies.Add("line=" + $n + " CONFIRM_AFTER_END session=" + $sid) } }
      "authority.ended"     { if(-not $started.ContainsKey($sid)){ [void]$anomalies.Add("line=" + $n + " END_WITHOUT_START session=" + $sid) } elseif($ended.ContainsKey($sid)){ [void]$anomalies.Add("line=" + $n + " DOUBLE_END session=" + $sid) }; $ended[$sid] = $n }
    }
  }
}

Write-Output ("LEDGER_SHA256=" + (([System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create()).ComputeHash($bytes))).Replace("-","").ToLowerInvariant()))
Write-Output ("LEDGER_LINES=" + $n)
$keys = [string[]]@($families.Keys); [System.Array]::Sort($keys,[System.StringComparer]::Ordinal)
foreach($k in $keys){ Write-Output ("FAMILY " + $k + "=" + $families[$k]) }
foreach($a in $anomalies){ Write-Output ("ANOMALY " + $a) }
if($anomalies.Count -gt 0){
  if($Strict){ throw ("LEDGER_ANOMALIES count=" + $anomalies.Count) }
  Write-Output ("ANOMALIES=" + $anomalies.Count)
}
Write-Output "RECEIPT_LEDGER_VERIFY_OK"
