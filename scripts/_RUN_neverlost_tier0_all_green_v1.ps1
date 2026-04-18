param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die {
  param([Parameter(Mandatory=$true)][string]$Message)
  throw $Message
}

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Text
  )
  $parent = Split-Path -Parent $Path
  if(-not [string]::IsNullOrWhiteSpace($parent)){
    Ensure-Dir -Path $parent
  }
  $normalized = $Text -replace "`r`n","`n"
  $normalized = $normalized -replace "`r","`n"
  if(-not $normalized.EndsWith("`n")){
    $normalized += "`n"
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $normalized, $enc)
}

function Parse-GatePs1 {
  param([Parameter(Mandatory=$true)][string]$Path)

  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("MISSING_SCRIPT: " + $Path)
  }

  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
  if($errors -and $errors.Count -gt 0){
    $msg = ($errors | ForEach-Object { $_.Message }) -join " | "
    Die ("PARSE_GATE_FAILED: " + $Path + " :: " + $msg)
  }
}

function Invoke-PSFileCapture {
  param(
    [Parameter(Mandatory=$true)][string]$PSExe,
    [Parameter(Mandatory=$true)][string]$File,
    [Parameter(Mandatory=$true)][string[]]$Args,
    [Parameter(Mandatory=$true)][string]$StdoutPath,
    [Parameter(Mandatory=$true)][string]$StderrPath
  )

  $argLineParts = @(
    '-NoProfile'
    '-NonInteractive'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    ('"' + $File + '"')
  ) + $Args

  $argLine = $argLineParts -join ' '

  $proc = Start-Process `
    -FilePath $PSExe `
    -ArgumentList $argLine `
    -Wait `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $StdoutPath `
    -RedirectStandardError $StderrPath

  $stdout = ""
  if(Test-Path -LiteralPath $StdoutPath -PathType Leaf){
    $stdout = Get-Content -Raw -LiteralPath $StdoutPath -Encoding UTF8
  }

  $stderr = ""
  if(Test-Path -LiteralPath $StderrPath -PathType Leaf){
    $stderr = Get-Content -Raw -LiteralPath $StderrPath -Encoding UTF8
  }

  return [pscustomobject]@{
    ExitCode = [int]$proc.ExitCode
    Stdout   = [string]$stdout
    Stderr   = [string]$stderr
  }
}

function Write-Sha256Sums {
  param(
    [Parameter(Mandatory=$true)][string]$RootDir,
    [Parameter(Mandatory=$true)][string]$OutPath
  )

  $files = Get-ChildItem -LiteralPath $RootDir -Recurse -File | Sort-Object FullName
  $lines = New-Object System.Collections.Generic.List[string]

  foreach($f in $files){
    if($f.FullName -eq $OutPath){ continue }
    $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $rel  = $f.FullName.Substring($RootDir.Length).TrimStart('\') -replace '\\','/'
    [void]$lines.Add(($hash + "  " + $rel))
  }

  Write-Utf8NoBomLf -Path $OutPath -Text ($lines -join "`n")
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  Die ("MISSING_REPOROOT: " + $RepoRoot)
}

$PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$RunRoot = Join-Path $RepoRoot ("proofs\receipts\full_green\" + $RunId)
Ensure-Dir -Path $RunRoot

$ParseGateList = @(
  (Join-Path $RepoRoot "scripts\neverlost_cli_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_selftest_neverlost_cli_v1.ps1"),
  (Join-Path $RepoRoot "scripts\verify_neverlost_cli_vectors_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_neverlost_tier0_all_green_v1.ps1"),
  (Join-Path $RepoRoot "scripts\start_authority_v1.ps1"),
  (Join-Path $RepoRoot "scripts\confirm_authority_v1.ps1"),
  (Join-Path $RepoRoot "scripts\end_authority_v1.ps1")
)

foreach($p in $ParseGateList){
  Parse-GatePs1 -Path $p
}

$parseReceipt = Join-Path $RunRoot "parse_gate.ok.txt"
Write-Utf8NoBomLf -Path $parseReceipt -Text "PARSE_GATE_OK"

$SelftestScript = Join-Path $RepoRoot "scripts\_selftest_neverlost_cli_v1.ps1"
$SelftestStdout = Join-Path $RunRoot "selftest.stdout.txt"
$SelftestStderr = Join-Path $RunRoot "selftest.stderr.txt"
$selftest = Invoke-PSFileCapture `
  -PSExe $PSExe `
  -File $SelftestScript `
  -Args @('-RepoRoot', ('"' + $RepoRoot + '"')) `
  -StdoutPath $SelftestStdout `
  -StderrPath $SelftestStderr

if($selftest.ExitCode -ne 0){
  Die "FULL_GREEN_SELFTEST_FAILED"
}
if($selftest.Stdout -notmatch 'NEVERLOST_CLI_SELFTEST_OK'){
  Die "FULL_GREEN_SELFTEST_TOKEN_MISSING"
}

$VectorsScript = Join-Path $RepoRoot "scripts\verify_neverlost_cli_vectors_v1.ps1"
$VectorsStdout = Join-Path $RunRoot "vectors.stdout.txt"
$VectorsStderr = Join-Path $RunRoot "vectors.stderr.txt"
$vectors = Invoke-PSFileCapture `
  -PSExe $PSExe `
  -File $VectorsScript `
  -Args @('-RepoRoot', ('"' + $RepoRoot + '"')) `
  -StdoutPath $VectorsStdout `
  -StderrPath $VectorsStderr

if($vectors.ExitCode -ne 0){
  Die "FULL_GREEN_VECTORS_FAILED"
}
if($vectors.Stdout -notmatch 'NEVERLOST_CLI_VECTORS_OK'){
  Die "FULL_GREEN_VECTORS_TOKEN_MISSING"
}

$summary = @"
RUN_ID=$RunId
RUN_ROOT=$RunRoot
SELFTEST=OK
VECTORS=OK
TOKEN=NEVERLOST_TIER0_ALL_GREEN
"@
Write-Utf8NoBomLf -Path (Join-Path $RunRoot "summary.txt") -Text $summary

$shaOut = Join-Path $RunRoot "sha256sums.txt"
Write-Sha256Sums -RootDir $RunRoot -OutPath $shaOut

Write-Host "NEVERLOST_TIER0_ALL_GREEN" -ForegroundColor Green
Write-Host ("RUN_ID=" + $RunId) -ForegroundColor Green
Write-Host ("RUN_ROOT=" + $RunRoot) -ForegroundColor Green
