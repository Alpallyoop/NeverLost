param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die {
  param([Parameter(Mandatory=$true)][string]$Message)
  throw $Message
}

function Invoke-CLI-Process {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$Area,
    [Parameter(Mandatory=$true)][string]$Action
  )

  $PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  $CliPath = Join-Path $RepoRoot "scripts\neverlost_cli_v1.ps1"

  $tmp = Join-Path $RepoRoot "proofs\receipts\vector_cli_tmp"
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

function Assert-Contains {
  param(
    [Parameter(Mandatory=$true)][string]$Text,
    [Parameter(Mandatory=$true)][string]$Needle,
    [Parameter(Mandatory=$true)][string]$FailCode
  )

  if($Text -notmatch [regex]::Escape($Needle)){
    Die $FailCode
  }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  Die ("MISSING_REPOROOT: " + $RepoRoot)
}

$VectorsRoot = Join-Path $RepoRoot "test_vectors\neverlost_cli_v1"
if(-not (Test-Path -LiteralPath $VectorsRoot -PathType Container)){
  Die "MISSING_VECTORS_ROOT"
}

$vectorFiles = Get-ChildItem -LiteralPath $VectorsRoot -Filter *.json | Sort-Object Name
if($vectorFiles.Count -lt 1){
  Die "NO_VECTOR_FILES_FOUND"
}

foreach($vf in $vectorFiles){
  $raw = Get-Content -Raw -LiteralPath $vf.FullName -Encoding UTF8
  $vector = $raw | ConvertFrom-Json

  if([string]$vector.kind -eq "positive_lifecycle"){
    $statusBefore = Invoke-CLI-Process -RepoRoot $RepoRoot -Area "authority" -Action "status"
    if($statusBefore.ExitCode -ne 0){
      Die ("VECTOR_FAIL:" + $vector.name + ":STATUS_BEFORE")
    }
    if($statusBefore.Stdout -match 'AUTHORITY_STATUS=ACTIVE'){
      Die ("VECTOR_FAIL:" + $vector.name + ":REQUIRES_INACTIVE")
    }

    foreach($step in $vector.steps){
      $result = Invoke-CLI-Process -RepoRoot $RepoRoot -Area ([string]$step.area) -Action ([string]$step.action)

      if([int]$step.expect_exit -ne $result.ExitCode){
        Die ("VECTOR_FAIL:" + $vector.name + ":EXIT:" + [string]$step.action)
      }

      Assert-Contains -Text $result.Stdout -Needle ([string]$step.expect_stdout_contains) -FailCode ("VECTOR_FAIL:" + $vector.name + ":STDOUT:" + [string]$step.action)
    }

    $statusAfter = Invoke-CLI-Process -RepoRoot $RepoRoot -Area "authority" -Action "status"
    if($statusAfter.ExitCode -ne 0){
      Die ("VECTOR_FAIL:" + $vector.name + ":STATUS_AFTER")
    }
    Assert-Contains -Text $statusAfter.Stdout -Needle "AUTHORITY_STATUS=INACTIVE" -FailCode ("VECTOR_FAIL:" + $vector.name + ":STATUS_AFTER_INACTIVE")
  }
  elseif([string]$vector.kind -eq "negative_single"){
    $result = Invoke-CLI-Process -RepoRoot $RepoRoot -Area ([string]$vector.area) -Action ([string]$vector.action)

    if([int]$vector.expect_exit -eq $result.ExitCode){
      # exact match OK
    } else {
      Die ("VECTOR_FAIL:" + $vector.name + ":EXIT")
    }

    $combined = ($result.Stdout + "`n" + $result.Stderr)
    Assert-Contains -Text $combined -Needle ([string]$vector.expect_contains) -FailCode ("VECTOR_FAIL:" + $vector.name + ":CONTAINS")
  }
  else {
    Die ("UNKNOWN_VECTOR_KIND: " + [string]$vector.kind)
  }
}

Write-Host "NEVERLOST_CLI_VECTORS_OK" -ForegroundColor Green
