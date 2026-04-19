param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ Die "EnsureDir: empty path" }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path,$enc.GetBytes($t))
}

function Parse-GatePs1([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("PARSE_GATE_MISSING: " + $Path)
  }
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message)
  }
}

function Get-FileSha256([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("SHA256_MISSING_FILE: " + $Path)
  }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Escape-Json([string]$s){
  if($null -eq $s){ return "" }
  $x = $s.Replace('\','\\')
  $x = $x.Replace('"','\"')
  $x = $x.Replace("`r","\r")
  $x = $x.Replace("`n","\n")
  $x = $x.Replace("`t","\t")
  return $x
}

function To-CanonJson-Flat([hashtable]$h){
  $keys = @($h.Keys | Sort-Object)
  $parts = New-Object System.Collections.Generic.List[string]
  foreach($k in $keys){
    $v = $h[$k]
    if($v -is [bool]){
      $val = $(if($v){ "true" } else { "false" })
    } elseif($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]){
      $val = [string]$v
    } else {
      $val = '"' + (Escape-Json ([string]$v)) + '"'
    }
    [void]$parts.Add('"' + (Escape-Json $k) + '":' + $val)
  }
  return '{' + ($parts -join ',') + '}'
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$ReceiptsDir = Join-Path $RepoRoot "proofs\receipts"
$LedgerPath = Join-Path $ReceiptsDir "neverlost.ndjson"

$AclPath = Join-Path $ScriptsDir "enforce_trust_acl_v1.ps1"
$SelftestPath = Join-Path $ScriptsDir "selftest_neverlost_trustbundle_v2.ps1"
$TrustRunnerPath = Join-Path $ScriptsDir "_RUN_neverlost_trust_pipeline_full_green_v1.ps1"
$EvidenceRunnerPath = Join-Path $ScriptsDir "_RUN_neverlost_trust_pipeline_evidence_v1.ps1"
$VectorRunnerPath = Join-Path $ScriptsDir "_RUN_neverlost_vectors_v3.ps1"

Parse-GatePs1 $AclPath
Parse-GatePs1 $SelftestPath
Parse-GatePs1 $TrustRunnerPath
Parse-GatePs1 $EvidenceRunnerPath
Parse-GatePs1 $VectorRunnerPath

EnsureDir $ReceiptsDir

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$startedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){
  Die ("MISSING_POWERSHELL_EXE: " + $PSExe)
}

$tmpRoot = Join-Path $ReceiptsDir "_tmp_neverlost_tier0"
EnsureDir $tmpRoot

$evidenceStdout = Join-Path $tmpRoot ("neverlost_tier0_evidence_stdout_" + $runId + ".txt")
$evidenceStderr = Join-Path $tmpRoot ("neverlost_tier0_evidence_stderr_" + $runId + ".txt")
$vectorStdout   = Join-Path $tmpRoot ("neverlost_tier0_vectors_stdout_" + $runId + ".txt")
$vectorStderr   = Join-Path $tmpRoot ("neverlost_tier0_vectors_stderr_" + $runId + ".txt")

$pEvidence = Start-Process `
  -FilePath $PSExe `
  -ArgumentList @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$EvidenceRunnerPath,
    "-RepoRoot",$RepoRoot
  ) `
  -Wait `
  -PassThru `
  -RedirectStandardOutput $evidenceStdout `
  -RedirectStandardError $evidenceStderr

if($pEvidence.ExitCode -ne 0){
  Write-Host ("EVIDENCE_STDOUT=" + $evidenceStdout) -ForegroundColor Yellow
  Write-Host ("EVIDENCE_STDERR=" + $evidenceStderr) -ForegroundColor Yellow
  throw ("NEVERLOST_TIER0_EVIDENCE_CHILD_FAILED: " + $pEvidence.ExitCode)
}

$evidenceText = Get-Content -Raw -LiteralPath $evidenceStdout -Encoding UTF8
if($evidenceText.IndexOf("NEVERLOST_TRUST_EVIDENCE_OK",[System.StringComparison]::Ordinal) -lt 0){
  throw "NEVERLOST_TIER0_MISSING_EVIDENCE_TOKEN"
}

$pVector = Start-Process `
  -FilePath $PSExe `
  -ArgumentList @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$VectorRunnerPath,
    "-RepoRoot",$RepoRoot
  ) `
  -Wait `
  -PassThru `
  -RedirectStandardOutput $vectorStdout `
  -RedirectStandardError $vectorStderr

if($pVector.ExitCode -ne 0){
  Write-Host ("VECTOR_STDOUT=" + $vectorStdout) -ForegroundColor Yellow
  Write-Host ("VECTOR_STDERR=" + $vectorStderr) -ForegroundColor Yellow
  throw ("NEVERLOST_TIER0_VECTOR_CHILD_FAILED: " + $pVector.ExitCode)
}

$vectorText = Get-Content -Raw -LiteralPath $vectorStdout -Encoding UTF8
if($vectorText.IndexOf("NEVERLOST_VECTORS_FULL_GREEN",[System.StringComparison]::Ordinal) -lt 0){
  throw "NEVERLOST_TIER0_MISSING_VECTOR_TOKEN"
}
if($vectorText.IndexOf("NEVERLOST_VECTOR_NEGATIVE_WRONG_PRINCIPAL_OK",[System.StringComparison]::Ordinal) -lt 0){
  throw "NEVERLOST_TIER0_MISSING_WRONG_PRINCIPAL_TOKEN"
}
if($vectorText.IndexOf("NEVERLOST_VECTOR_NEGATIVE_NAMESPACE_OK",[System.StringComparison]::Ordinal) -lt 0){
  throw "NEVERLOST_TIER0_MISSING_NAMESPACE_TOKEN"
}
if($vectorText.IndexOf("NEVERLOST_VECTOR_NEGATIVE_MALFORMED_SHAPE_OK",[System.StringComparison]::Ordinal) -lt 0){
  throw "NEVERLOST_TIER0_MISSING_MALFORMED_SHAPE_TOKEN"
}

$finishedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$receipt = [ordered]@{
  acl_sha256 = (Get-FileSha256 $AclPath)
  event_type = "neverlost/tier0-full-green"
  evidence_runner_sha256 = (Get-FileSha256 $EvidenceRunnerPath)
  evidence_stderr_sha256 = (Get-FileSha256 $evidenceStderr)
  evidence_stdout_sha256 = (Get-FileSha256 $evidenceStdout)
  finished_utc = $finishedUtc
  ok = $true
  repo_root = $RepoRoot
  run_id = $runId
  selftest_sha256 = (Get-FileSha256 $SelftestPath)
  started_utc = $startedUtc
  trust_runner_sha256 = (Get-FileSha256 $TrustRunnerPath)
  vector_runner_sha256 = (Get-FileSha256 $VectorRunnerPath)
  vector_stderr_sha256 = (Get-FileSha256 $vectorStderr)
  vector_stdout_sha256 = (Get-FileSha256 $vectorStdout)
}
Add-Content -LiteralPath $LedgerPath -Value (To-CanonJson-Flat $receipt)

Write-Host "NEVERLOST_TIER0_FULL_GREEN" -ForegroundColor Green
Write-Host ("LEDGER=" + $LedgerPath) -ForegroundColor Green
Write-Host ("EVIDENCE_STDOUT=" + $evidenceStdout) -ForegroundColor Green
Write-Host ("EVIDENCE_STDERR=" + $evidenceStderr) -ForegroundColor Green
Write-Host ("VECTOR_STDOUT=" + $vectorStdout) -ForegroundColor Green
Write-Host ("VECTOR_STDERR=" + $vectorStderr) -ForegroundColor Green
