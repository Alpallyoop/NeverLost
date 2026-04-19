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

function Write-Sha256Sums([string]$Root,[string]$OutPath){
  $items = Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
    $_.FullName -ne $OutPath
  } | Sort-Object FullName

  $lines = New-Object System.Collections.Generic.List[string]
  foreach($f in $items){
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
    $rel = $rel.Replace('\','/')
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()
    [void]$lines.Add($sha + " *" + $rel)
  }
  Write-Utf8NoBomLf -Path $OutPath -Text ($lines -join "`n")
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$ReceiptsRoot = Join-Path $RepoRoot "proofs\receipts\neverlost_trust_pipeline_full_green"
$RunnerPath = Join-Path $ScriptsDir "_RUN_neverlost_trust_pipeline_full_green_v1.ps1"
$AclPath = Join-Path $ScriptsDir "enforce_trust_acl_v1.ps1"
$SelftestPath = Join-Path $ScriptsDir "selftest_neverlost_trustbundle_v2.ps1"
$LibPath = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"

Parse-GatePs1 $RunnerPath

if(-not (Test-Path -LiteralPath $AclPath -PathType Leaf)){ Die ("MISSING_ACL: " + $AclPath) }
if(-not (Test-Path -LiteralPath $SelftestPath -PathType Leaf)){ Die ("MISSING_SELFTEST: " + $SelftestPath) }
if(-not (Test-Path -LiteralPath $LibPath -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }

EnsureDir $ReceiptsRoot

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$runDir = Join-Path $ReceiptsRoot $runId
EnsureDir $runDir

$stdoutPath = Join-Path $runDir "stdout.txt"
$stderrPath = Join-Path $runDir "stderr.txt"
$summaryPath = Join-Path $runDir "summary.json"
$receiptPath = Join-Path $runDir "receipt.ndjson"
$shaPath = Join-Path $runDir "sha256sums.txt"

$startedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){
  Die ("MISSING_POWERSHELL_EXE: " + $PSExe)
}

$p = Start-Process `
  -FilePath $PSExe `
  -ArgumentList @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$RunnerPath,
    "-RepoRoot",$RepoRoot
  ) `
  -Wait `
  -PassThru `
  -RedirectStandardOutput $stdoutPath `
  -RedirectStandardError $stderrPath

$finishedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$stdoutSha = Get-FileSha256 $stdoutPath
$stderrSha = Get-FileSha256 $stderrPath
$runnerSha = Get-FileSha256 $RunnerPath
$aclSha = Get-FileSha256 $AclPath
$selftestSha = Get-FileSha256 $SelftestPath
$libSha = Get-FileSha256 $LibPath

$summary = [ordered]@{
  acl_path = $AclPath
  acl_sha256 = $aclSha
  event_type = "neverlost/trust-pipeline-full-green"
  finished_utc = $finishedUtc
  lib_path = $LibPath
  lib_sha256 = $libSha
  repo_root = $RepoRoot
  run_id = $runId
  run_dir = $runDir
  runner_exit_code = [int]$p.ExitCode
  runner_path = $RunnerPath
  runner_sha256 = $runnerSha
  selftest_path = $SelftestPath
  selftest_sha256 = $selftestSha
  started_utc = $startedUtc
  stderr_path = $stderrPath
  stderr_sha256 = $stderrSha
  stdout_path = $stdoutPath
  stdout_sha256 = $stdoutSha
}
Write-Utf8NoBomLf -Path $summaryPath -Text (To-CanonJson-Flat $summary)

$receipt = [ordered]@{
  acl_sha256 = $aclSha
  event_type = "neverlost/trust-pipeline-full-green"
  ok = ($p.ExitCode -eq 0)
  repo_root = $RepoRoot
  run_id = $runId
  runner_exit_code = [int]$p.ExitCode
  runner_sha256 = $runnerSha
  selftest_sha256 = $selftestSha
  stderr_sha256 = $stderrSha
  stdout_sha256 = $stdoutSha
  summary_sha256 = (Get-FileSha256 $summaryPath)
  utc = $finishedUtc
}
Write-Utf8NoBomLf -Path $receiptPath -Text (To-CanonJson-Flat $receipt)

Write-Sha256Sums -Root $runDir -OutPath $shaPath

$stdoutText = Get-Content -Raw -LiteralPath $stdoutPath -Encoding UTF8
if($p.ExitCode -ne 0){
  Write-Host ("RUN_DIR=" + $runDir) -ForegroundColor Yellow
  Write-Host ("STDOUT=" + $stdoutPath) -ForegroundColor Yellow
  Write-Host ("STDERR=" + $stderrPath) -ForegroundColor Yellow
  throw ("NEVERLOST_TRUST_EVIDENCE_CHILD_FAILED: " + $p.ExitCode)
}

if($stdoutText.IndexOf("NEVERLOST_TRUST_PIPELINE_FULL_GREEN",[System.StringComparison]::Ordinal) -lt 0){
  throw "NEVERLOST_TRUST_EVIDENCE_MISSING_GREEN_TOKEN"
}

Write-Host "NEVERLOST_TRUST_EVIDENCE_OK" -ForegroundColor Green
Write-Host ("RUN_DIR=" + $runDir) -ForegroundColor Green
Write-Host ("RECEIPT=" + $receiptPath) -ForegroundColor Green
Write-Host ("SHA256SUMS=" + $shaPath) -ForegroundColor Green
