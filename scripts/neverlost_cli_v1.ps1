param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Area,
  [Parameter(Mandatory=$true)][string]$Action
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

$PSExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die "REPOROOT_MISSING" }

if($Area -ne "authority"){ Die ("UNKNOWN_AREA: " + $Area) }

switch($Action){
  "start" {
    & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\start_authority_v1.ps1") `
      -RepoRoot $RepoRoot
    exit $LASTEXITCODE
  }

  "confirm" {
    & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\confirm_authority_v1.ps1") `
      -RepoRoot $RepoRoot
    exit $LASTEXITCODE
  }

  "end" {
    & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
      -File (Join-Path $RepoRoot "scripts\end_authority_v1.ps1") `
      -RepoRoot $RepoRoot
    exit $LASTEXITCODE
  }

  "status" {
    $ActivePath = Join-Path $RepoRoot "proofs\receipts\active_authority_session.json"
    if(-not (Test-Path -LiteralPath $ActivePath -PathType Leaf)){
      Write-Host "AUTHORITY_STATUS=NONE"
      exit 0
    }

    $raw = Get-Content -Raw -LiteralPath $ActivePath -Encoding UTF8
    if([string]::IsNullOrWhiteSpace($raw)){
      Write-Host "AUTHORITY_STATUS=NONE"
      exit 0
    }

    $obj = $raw | ConvertFrom-Json

    $active = $false
    if($obj.PSObject.Properties.Name -contains "active"){
      $active = [bool]$obj.active
    }

    Write-Host ("AUTHORITY_STATUS=" + ($(if($active){"ACTIVE"}else{"INACTIVE"})))
    if($obj.PSObject.Properties.Name -contains "principal"){
      Write-Host ("PRINCIPAL=" + [string]$obj.principal)
    }
    if($obj.PSObject.Properties.Name -contains "session_id"){
      Write-Host ("SESSION_ID=" + [string]$obj.session_id)
    }
    if($obj.PSObject.Properties.Name -contains "started_utc"){
      Write-Host ("STARTED_UTC=" + [string]$obj.started_utc)
    }
    if($obj.PSObject.Properties.Name -contains "ended_utc"){
      Write-Host ("ENDED_UTC=" + [string]$obj.ended_utc)
    }
    exit 0
  }

  default {
    Die ("UNKNOWN_ACTION: " + $Action)
  }
}