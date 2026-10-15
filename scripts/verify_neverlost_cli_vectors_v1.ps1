param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

# NeverLost CLI vectors (test_vectors/neverlost_cli_v1, schema neverlost.cli.vector.v1).
# Each vector runs in its own fresh sandbox copy of the instrument (.scratch/sandbox), so vectors are
# clean-state, independent of the operator's live authority session, and never append test receipts
# to the live ledger. Stdout is deterministic for the freeze lane.
#
# Vector kinds:
#   positive_lifecycle  steps[] that must all succeed, then status must be INACTIVE
#   negative_single     one area/action with expect_exit and expect_contains (stdout+stderr)
#   sequence            optional setup, then steps[] each with expect_exit and expect_contains
# Setup operations (sequence only): write_files { "<repo-relative path>": "<text>" }, remove_files [paths]

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

function Invoke-CLI-Process {
  param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Area,
    [Parameter(Mandatory=$true)][string]$Action
  )
  $CliPath = Join-Path (Join-Path $Root "scripts") "neverlost_cli_v1.ps1"
  $tmp = Join-Path $Root "io"
  $id = [Guid]::NewGuid().ToString("N")
  return NL-InvokePsFile -File $CliPath -PsHost $PSExe -Arguments @("-RepoRoot",$Root,"-Area",$Area,"-Action",$Action) -StdoutPath (Join-Path $tmp ($id + ".stdout.txt")) -StderrPath (Join-Path $tmp ($id + ".stderr.txt"))
}

function Assert-Contains {
  param(
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory=$true)][string]$Needle,
    [Parameter(Mandatory=$true)][string]$FailCode
  )
  if($Text.IndexOf($Needle,[System.StringComparison]::Ordinal) -lt 0){
    Die $FailCode
  }
}

function Get-Prop([object]$o,[string]$n){
  if($null -eq $o){ return $null }
  $p = $o.PSObject.Properties[$n]
  if($null -eq $p){ return $null }
  return $p.Value
}

function Apply-Setup([string]$Root,[object]$Setup){
  if($null -eq $Setup){ return }
  $wf = Get-Prop $Setup "write_files"
  if($null -ne $wf){
    foreach($prop in $wf.PSObject.Properties){
      $rel = [string]$prop.Name
      if($rel -match '\.\.' -or $rel -match '^[\\/]' -or $rel -match '^[A-Za-z]:'){ Die ("VECTOR_SETUP_PATH_REFUSED: " + $rel) }
      $target = $Root
      foreach($seg in ($rel -split '[\\/]')){ if($seg.Length -gt 0){ $target = Join-Path $target $seg } }
      $d = Split-Path -Parent $target
      if($d -and -not (Test-Path -LiteralPath $d -PathType Container)){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
      if(Test-Path -LiteralPath $target -PathType Leaf){ Remove-Item -LiteralPath $target -Force }
      [System.IO.File]::WriteAllBytes($target,(New-Object System.Text.UTF8Encoding($false)).GetBytes([string]$prop.Value))
    }
  }
  $rf = Get-Prop $Setup "remove_files"
  if($null -ne $rf){
    foreach($rel in @($rf)){
      $r = [string]$rel
      if($r -match '\.\.' -or $r -match '^[\\/]' -or $r -match '^[A-Za-z]:'){ Die ("VECTOR_SETUP_PATH_REFUSED: " + $r) }
      $target = $Root
      foreach($seg in ($r -split '[\\/]')){ if($seg.Length -gt 0){ $target = Join-Path $target $seg } }
      if(Test-Path -LiteralPath $target -PathType Leaf){ Remove-Item -LiteralPath $target -Force }
    }
  }
}

$VectorsRoot = Join-Path (Join-Path $RepoRoot "test_vectors") "neverlost_cli_v1"
if(-not (Test-Path -LiteralPath $VectorsRoot -PathType Container)){
  Die "MISSING_VECTORS_ROOT"
}

$vectorFiles = @(Get-ChildItem -LiteralPath $VectorsRoot -Filter *.json | Sort-Object Name)
if($vectorFiles.Count -lt 1){
  Die "NO_VECTOR_FILES_FOUND"
}

foreach($vf in $vectorFiles){
  $raw = [System.IO.File]::ReadAllText($vf.FullName,(New-Object System.Text.UTF8Encoding($false)))
  $vector = $raw | ConvertFrom-Json
  if([string](Get-Prop $vector "schema") -cne "neverlost.cli.vector.v1"){ Die ("VECTOR_SCHEMA_INVALID: " + $vf.Name) }
  $name = [string]$vector.name
  $kind = [string]$vector.kind

  $sb = NL-NewSandboxRepo -RepoRoot $RepoRoot -Label ("cli_vector_" + $name)
  try {
    if($kind -eq "positive_lifecycle"){
      $statusBefore = Invoke-CLI-Process -Root $sb -Area "authority" -Action "status"
      if($statusBefore.ExitCode -ne 0){ Die ("VECTOR_FAIL:" + $name + ":STATUS_BEFORE") }
      if($statusBefore.Stdout -match 'AUTHORITY_STATUS=ACTIVE'){ Die ("VECTOR_FAIL:" + $name + ":REQUIRES_INACTIVE") }

      foreach($step in $vector.steps){
        $result = Invoke-CLI-Process -Root $sb -Area ([string]$step.area) -Action ([string]$step.action)
        if([int]$step.expect_exit -ne $result.ExitCode){ Die ("VECTOR_FAIL:" + $name + ":EXIT:" + [string]$step.action + " actual=" + $result.ExitCode + " stderr=" + $result.Stderr) }
        Assert-Contains -Text $result.Stdout -Needle ([string]$step.expect_stdout_contains) -FailCode ("VECTOR_FAIL:" + $name + ":STDOUT:" + [string]$step.action)
      }

      $statusAfter = Invoke-CLI-Process -Root $sb -Area "authority" -Action "status"
      if($statusAfter.ExitCode -ne 0){ Die ("VECTOR_FAIL:" + $name + ":STATUS_AFTER") }
      Assert-Contains -Text $statusAfter.Stdout -Needle "AUTHORITY_STATUS=INACTIVE" -FailCode ("VECTOR_FAIL:" + $name + ":STATUS_AFTER_INACTIVE")
    }
    elseif($kind -eq "negative_single"){
      $result = Invoke-CLI-Process -Root $sb -Area ([string]$vector.area) -Action ([string]$vector.action)
      if([int]$vector.expect_exit -ne $result.ExitCode){ Die ("VECTOR_FAIL:" + $name + ":EXIT actual=" + $result.ExitCode) }
      Assert-Contains -Text ($result.Stdout + "`n" + $result.Stderr) -Needle ([string]$vector.expect_contains) -FailCode ("VECTOR_FAIL:" + $name + ":CONTAINS")
    }
    elseif($kind -eq "sequence"){
      Apply-Setup $sb (Get-Prop $vector "setup")
      $i = 0
      foreach($step in $vector.steps){
        $result = Invoke-CLI-Process -Root $sb -Area ([string]$step.area) -Action ([string]$step.action)
        if([int]$step.expect_exit -ne $result.ExitCode){ Die ("VECTOR_FAIL:" + $name + ":STEP" + $i + ":EXIT actual=" + $result.ExitCode + " stderr=" + $result.Stderr) }
        Assert-Contains -Text ($result.Stdout + "`n" + $result.Stderr) -Needle ([string]$step.expect_contains) -FailCode ("VECTOR_FAIL:" + $name + ":STEP" + $i + ":CONTAINS")
        $i++
      }
    }
    else {
      Die ("UNKNOWN_VECTOR_KIND: " + $kind)
    }
  }
  finally {
    NL-RemoveSandboxRepo $sb
  }
  Write-Output ("VECTOR_OK=" + $name)
}

Write-Host "NEVERLOST_CLI_VECTORS_OK" -ForegroundColor Green
