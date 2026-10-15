param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $PSScriptRoot "_lib_neverlost_host_v1.ps1")
# The release package is a Windows MSI; this lane only runs on Windows.
if(-not (NL-IsWindowsHost)){ throw "RELEASE_SMOKE_WINDOWS_ONLY" }
$PSExe = NL-ResolvePsHost
$RunId = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$RunRoot = Join-Path $RepoRoot ("proofs\receipts\release_package_smoke\" + $RunId)

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
  if($parent){ Ensure-Dir -Path $parent }
  $normalized = $Text -replace "`r`n","`n"
  $normalized = $normalized -replace "`r","`n"
  if(-not $normalized.EndsWith("`n")){ $normalized += "`n" }
  [System.IO.File]::WriteAllText($Path,$normalized,(New-Object System.Text.UTF8Encoding($false)))
}

function Parse-GatePs1 {
  param([Parameter(Mandatory=$true)][string]$Path)
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
  if(@($errors).Count -gt 0){
    $msg = (@($errors) | ForEach-Object { $_.Message }) -join " | "
    throw ("PARSE_FAILED: " + $Path + " :: " + $msg)
  }
  Write-Host ("PARSE_OK: " + $Path) -ForegroundColor Green
}

function Run-Capture {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$true)][string[]]$Arguments,
    [int]$TimeoutSeconds = 300
  )

  $stdout = Join-Path $RunRoot ($Name + ".stdout.txt")
  $stderr = Join-Path $RunRoot ($Name + ".stderr.txt")

  $p = Start-Process -FilePath $FilePath `
    -ArgumentList $Arguments `
    -Wait `
    -PassThru `
    -NoNewWindow `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr

  Write-Host ($Name + "_EXIT=" + $p.ExitCode)
  if($p.ExitCode -ne 0){
    Get-Content $stdout -ErrorAction SilentlyContinue | Out-Host
    Get-Content $stderr -ErrorAction SilentlyContinue | Out-Host
    throw ($Name + "_FAILED")
  }
}

Ensure-Dir $RunRoot
Set-Location $RepoRoot

Write-Host "NEVERLOST_RELEASE_PACKAGE_SMOKE_START" -ForegroundColor Cyan
Write-Host ("RUN_ROOT=" + $RunRoot)

# 1) Parse gates.
Parse-GatePs1 (Join-Path $RepoRoot "scripts\neverlost_cli_v1.ps1")
Parse-GatePs1 (Join-Path $RepoRoot "scripts\neverlost_admin_plugin_minimal_v1.ps1")
Parse-GatePs1 (Join-Path $RepoRoot "scripts\nl-admin.ps1")

# 2) Frontend build.
Run-Capture -Name "npm_build" -FilePath "cmd.exe" -Arguments @("/c","npm run build") -TimeoutSeconds 300

# 3) Tauri release package.
Run-Capture -Name "tauri_build" -FilePath "cmd.exe" -Arguments @("/c","npm run tauri build") -TimeoutSeconds 900

# 4) Locate release exe and installers.
$ReleaseExe = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "src-tauri\target\release") -Filter "*.exe" -File -ErrorAction Stop |
  Where-Object { $_.Name -match "neverlost|workbench" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if($null -eq $ReleaseExe){
  throw "RELEASE_EXE_NOT_FOUND"
}

$Bundles = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "src-tauri\target\release\bundle") -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -in @(".msi",".exe") } |
  Sort-Object LastWriteTime -Descending)

$bundleLines = @()
foreach($b in $Bundles){
  $bundleLines += ($b.FullName)
}

Write-Utf8NoBomLf (Join-Path $RunRoot "release_exe.txt") $ReleaseExe.FullName
Write-Utf8NoBomLf (Join-Path $RunRoot "bundles.txt") (($bundleLines -join "`n"))

Write-Host ("RELEASE_EXE=" + $ReleaseExe.FullName) -ForegroundColor Green
foreach($b in $Bundles){ Write-Host ("BUNDLE=" + $b.FullName) -ForegroundColor Green }

# 5) Launch packaged exe smoke.
Get-Process neverlost_workbench -ErrorAction SilentlyContinue | Stop-Process -Force

$p = Start-Process -FilePath $ReleaseExe.FullName -PassThru
Start-Sleep -Seconds 8

$running = Get-Process neverlost_workbench -ErrorAction SilentlyContinue
if($null -eq $running){
  throw "PACKAGED_EXE_DID_NOT_STAY_RUNNING"
}

Write-Host "PACKAGED_EXE_LAUNCH_OK" -ForegroundColor Green

# Do not leave it running during CLI proof.
Get-Process neverlost_workbench -ErrorAction SilentlyContinue | Stop-Process -Force

# 6) CLI start guard + admin plugin proof.
$CoreCli = Join-Path $RepoRoot "scripts\neverlost_cli_v1.ps1"
$AdminWrapper = Join-Path $RepoRoot "scripts\nl-admin.ps1"

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $CoreCli -RepoRoot $RepoRoot -Area authority -Action end | Out-Host

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $CoreCli -RepoRoot $RepoRoot -Area authority -Action start | Out-Host
if($LASTEXITCODE -ne 0){ throw "CORE_START_FAILED" }

# Starting again must deny while active.
$denyOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $CoreCli -RepoRoot $RepoRoot -Area authority -Action start 2>&1
$denyText = ($denyOut | Out-String)
Write-Utf8NoBomLf (Join-Path $RunRoot "active_start_deny.txt") $denyText

if($denyText -notmatch "AUTHORITY_START_DENIED_ALREADY_ACTIVE"){
  throw "ACTIVE_START_GUARD_DID_NOT_DENY"
}

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AdminWrapper status | Out-Host
if($LASTEXITCODE -ne 0){ throw "NL_ADMIN_STATUS_FAILED" }

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AdminWrapper confirm | Out-Host
if($LASTEXITCODE -ne 0){ throw "NL_ADMIN_CONFIRM_FAILED" }

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $CoreCli -RepoRoot $RepoRoot -Area authority -Action end | Out-Host
if($LASTEXITCODE -ne 0){ throw "CORE_END_FAILED" }

# 7) Startup note: installed startup must be validated after installer run.
$startupNote = @(
  "Startup validation is not complete from tauri dev.",
  "Use the packaged exe / installed app only.",
  "Expected startup behavior:",
  "- no blank PowerShell/CMD window",
  "- workbench shell opens or launches hidden based on setting",
  "- no managed/local mode drift from Settings",
  "- admin confirm remains CLI/plugin-only"
) -join "`n"

Write-Utf8NoBomLf (Join-Path $RunRoot "startup_validation_next.txt") $startupNote

# 8) Summary.
$summary = @(
  "schema=neverlost.release_package_smoke.v1",
  "run_id=" + $RunId,
  "release_exe=" + $ReleaseExe.FullName,
  "build=ok",
  "tauri_build=ok",
  "packaged_exe_launch=ok",
  "active_start_guard=ok",
  "nl_admin_status=ok",
  "nl_admin_confirm=ok",
  "startup_installed_validation=pending"
) -join "`n"

Write-Utf8NoBomLf (Join-Path $RunRoot "SUMMARY.txt") $summary

Write-Host "NEVERLOST_RELEASE_PACKAGE_SMOKE_GREEN" -ForegroundColor Green
Write-Host ("RUN_ROOT=" + $RunRoot) -ForegroundColor Green