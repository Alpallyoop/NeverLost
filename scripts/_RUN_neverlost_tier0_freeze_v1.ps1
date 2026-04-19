param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die {
  param([Parameter(Mandatory=$true)][string]$Message)
  throw $Message
}

function Invoke-AllGreen {
  param([Parameter(Mandatory=$true)][string]$RepoRoot)

  $PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  $Script = Join-Path $RepoRoot "scripts\_RUN_neverlost_tier0_all_green_v1.ps1"

  $tmp = Join-Path $RepoRoot "proofs\receipts\freeze_tmp"
  if(-not (Test-Path -LiteralPath $tmp -PathType Container)){
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  }

  $id = [Guid]::NewGuid().ToString("N")
  $stdoutPath = Join-Path $tmp ($id + ".stdout.txt")
  $stderrPath = Join-Path $tmp ($id + ".stderr.txt")

  $argLine = @(
    '-NoProfile'
    '-NonInteractive'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    ('"' + $Script + '"')
    '-RepoRoot'
    ('"' + $RepoRoot + '"')
  ) -join ' '

  $proc = Start-Process `
    -FilePath $PSExe `
    -ArgumentList $argLine `
    -Wait `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

  $stdout = ""
  if(Test-Path -LiteralPath $stdoutPath -PathType Leaf){
    $stdout = Get-Content -Raw -LiteralPath $stdoutPath -Encoding UTF8
  }

  $stderr = ""
  if(Test-Path -LiteralPath $stderrPath -PathType Leaf){
    $stderr = Get-Content -Raw -LiteralPath $stderrPath -Encoding UTF8
  }

  if($proc.ExitCode -ne 0){
    Die "FREEZE_RUNNER_FAILED"
  }
  if($stdout -notmatch 'NEVERLOST_TIER0_ALL_GREEN'){
    Die "FREEZE_RUNNER_TOKEN_MISSING"
  }

  $runRoot = $null
  foreach($line in ($stdout -split "`r?`n")){
    if($line -match '^RUN_ROOT=(.+)$'){
      $runRoot = $matches[1]
    }
  }
  if([string]::IsNullOrWhiteSpace($runRoot)){
    Die "FREEZE_RUN_ROOT_MISSING"
  }

  return [pscustomobject]@{
    Stdout = $stdout
    Stderr = $stderr
    RunRoot = $runRoot
  }
}

function Normalize-FileText {
  param([Parameter(Mandatory=$true)][string]$Text)

  $t = $Text -replace "`r`n","`n"
  $t = $t -replace "`r","`n"

  # Remove volatile lines if they ever appear in stdout captures later
  $lines = @()
  foreach($line in ($t -split "`n")){
    if($line -match '^RUN_ID='){ continue }
    if($line -match '^RUN_ROOT='){ continue }
    if($line -match '^[A-Z]:\\'){ continue }
    $lines += $line.TrimEnd()
  }

  return (($lines -join "`n").Trim() + "`n")
}

function Get-StableManifest {
  param([Parameter(Mandatory=$true)][string]$RunRoot)

  $parsePath    = Join-Path $RunRoot "parse_gate.ok.txt"
  $selftestPath = Join-Path $RunRoot "selftest.stdout.txt"
  $vectorsPath  = Join-Path $RunRoot "vectors.stdout.txt"

  foreach($p in @($parsePath,$selftestPath,$vectorsPath)){
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
      Die ("FREEZE_STABLE_ARTIFACT_MISSING: " + $p)
    }
  }

  $parse    = Get-Content -Raw -LiteralPath $parsePath -Encoding UTF8
  $selftest = Get-Content -Raw -LiteralPath $selftestPath -Encoding UTF8
  $vectors  = Get-Content -Raw -LiteralPath $vectorsPath -Encoding UTF8

  $parseN    = Normalize-FileText -Text $parse
  $selftestN = Normalize-FileText -Text $selftest
  $vectorsN  = Normalize-FileText -Text $vectors

  if($parseN -notmatch 'PARSE_GATE_OK'){
    Die "FREEZE_PARSE_TOKEN_MISSING"
  }
  if($selftestN -notmatch 'NEVERLOST_CLI_SELFTEST_OK'){
    Die "FREEZE_SELFTEST_TOKEN_MISSING"
  }
  if($vectorsN -notmatch 'NEVERLOST_CLI_VECTORS_OK'){
    Die "FREEZE_VECTORS_TOKEN_MISSING"
  }

  return @(
    "parse_gate.ok.txt::" + $parseN.Trim()
    "selftest.stdout.txt::" + $selftestN.Trim()
    "vectors.stdout.txt::" + $vectorsN.Trim()
  ) -join "`n"
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  Die ("MISSING_REPOROOT: " + $RepoRoot)
}

$run1 = Invoke-AllGreen -RepoRoot $RepoRoot
$run2 = Invoke-AllGreen -RepoRoot $RepoRoot

$manifest1 = Get-StableManifest -RunRoot $run1.RunRoot
$manifest2 = Get-StableManifest -RunRoot $run2.RunRoot

if($manifest1 -ne $manifest2){
  $out1 = Join-Path $RepoRoot "proofs\receipts\freeze_tmp\stable_manifest_run1.txt"
  $out2 = Join-Path $RepoRoot "proofs\receipts\freeze_tmp\stable_manifest_run2.txt"
  Set-Content -LiteralPath $out1 -Value $manifest1 -Encoding UTF8
  Set-Content -LiteralPath $out2 -Value $manifest2 -Encoding UTF8
  Die "DOUBLE_RUN_MISMATCH"
}

Write-Host "DOUBLE_RUN_MATCH" -ForegroundColor Green
Write-Host ("RUN1=" + $run1.RunRoot) -ForegroundColor Green
Write-Host ("RUN2=" + $run2.RunRoot) -ForegroundColor Green
Write-Host "NEVERLOST_TIER0_FREEZE_OK" -ForegroundColor Green
