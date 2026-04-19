param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die {
  param([Parameter(Mandatory=$true)][string]$Message)
  throw $Message
}

function Invoke-CLI {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$Area,
    [Parameter(Mandatory=$true)][string]$Action
  )

  $PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  $CliPath = Join-Path $RepoRoot "scripts\neverlost_cli_v1.ps1"

  $tmp = Join-Path $RepoRoot "proofs\receipts\selftest_cli_tmp"
  if(Test-Path -LiteralPath $tmp -PathType Container){
    Remove-Item -LiteralPath $tmp -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null

  $stdoutPath = Join-Path $tmp ($Action + ".stdout.txt")
  $stderrPath = Join-Path $tmp ($Action + ".stderr.txt")

  $argLine = @(
    '-NoProfile'
    '-NonInteractive'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    ('"' + $CliPath + '"')
    '-RepoRoot'
    ('"' + $RepoRoot + '"')
    '-Area'
    $Area
    '-Action'
    $Action
  ) -join ' '

  $proc = Start-Process -FilePath $PSExe -ArgumentList $argLine -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

  $stdout = ""
  if(Test-Path -LiteralPath $stdoutPath -PathType Leaf){
    $stdout = Get-Content -Raw -LiteralPath $stdoutPath -Encoding UTF8
  }

  $stderr = ""
  if(Test-Path -LiteralPath $stderrPath -PathType Leaf){
    $stderr = Get-Content -Raw -LiteralPath $stderrPath -Encoding UTF8
  }

  return [pscustomobject]@{
    ExitCode = [int]$proc.ExitCode
    Stdout   = [string]$stdout
    Stderr   = [string]$stderr
  }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  Die ("MISSING_REPOROOT: " + $RepoRoot)
}

$statusBefore = Invoke-CLI -RepoRoot $RepoRoot -Area "authority" -Action "status"
if($statusBefore.ExitCode -ne 0){
  Die "SELFTEST_STATUS_BEFORE_FAILED"
}

if($statusBefore.Stdout -match 'AUTHORITY_STATUS=ACTIVE'){
  Die "SELFTEST_REQUIRES_INACTIVE_STATE"
}

$start = Invoke-CLI -RepoRoot $RepoRoot -Area "authority" -Action "start"
if($start.ExitCode -ne 0){
  Die "SELFTEST_START_FAILED"
}
if($start.Stdout -notmatch 'AUTHORITY_STARTED_OK'){
  Die "SELFTEST_START_TOKEN_MISSING"
}

$confirm = Invoke-CLI -RepoRoot $RepoRoot -Area "authority" -Action "confirm"
if($confirm.ExitCode -ne 0){
  Die "SELFTEST_CONFIRM_FAILED"
}
if($confirm.Stdout -notmatch 'AUTHORITY_CONFIRMED_OK'){
  Die "SELFTEST_CONFIRM_TOKEN_MISSING"
}

$end = Invoke-CLI -RepoRoot $RepoRoot -Area "authority" -Action "end"
if($end.ExitCode -ne 0){
  Die "SELFTEST_END_FAILED"
}
if($end.Stdout -notmatch 'AUTHORITY_ENDED_OK'){
  Die "SELFTEST_END_TOKEN_MISSING"
}

$statusAfter = Invoke-CLI -RepoRoot $RepoRoot -Area "authority" -Action "status"
if($statusAfter.ExitCode -ne 0){
  Die "SELFTEST_STATUS_AFTER_FAILED"
}
if($statusAfter.Stdout -notmatch 'AUTHORITY_STATUS=INACTIVE'){
  Die "SELFTEST_STATUS_AFTER_NOT_INACTIVE"
}

Write-Host "NEVERLOST_CLI_SELFTEST_OK" -ForegroundColor Green
