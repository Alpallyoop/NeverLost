param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Area,
  [Parameter(Mandatory=$true)][string]$Action
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# NEVERLOST_ACTIVE_START_GUARD_V1
$__nlRepo = (Resolve-Path -LiteralPath $RepoRoot).Path
$__nlStatePath = Join-Path $__nlRepo "proofs\receipts\active_authority_session.json"

if($Area -eq "authority" -and $Action -eq "start" -and (Test-Path -LiteralPath $__nlStatePath -PathType Leaf)){
  try {
    $__state = Get-Content -Raw -LiteralPath $__nlStatePath -Encoding UTF8 | ConvertFrom-Json
    $__sid = ""
    $__ended = ""
    $__activeBool = $false

    if($__state.PSObject.Properties.Name -contains "session_id"){ $__sid = [string]$__state.session_id }
    if($__state.PSObject.Properties.Name -contains "ended_utc"){ $__ended = [string]$__state.ended_utc }
    if($__state.PSObject.Properties.Name -contains "active"){ $__activeBool = [bool]$__state.active }

    $__active = $__activeBool -or ((-not [string]::IsNullOrWhiteSpace($__sid)) -and [string]::IsNullOrWhiteSpace($__ended))

    if($__active){
      Write-Host "AUTHORITY_START_DENIED_ALREADY_ACTIVE"
      Write-Host ("SESSION_ID=" + $__sid)
      exit 2
    }
  } catch {
    throw ("AUTHORITY_START_GUARD_FAILED: " + $_.Exception.Message)
  }
}
# NEVERLOST_ACTIVE_START_GUARD_V1_END


function Die([string]$m){ throw $m }

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die "REPOROOT_MISSING" }

if($Area -ne "authority"){ Die ("UNKNOWN_AREA: " + $Area) }
if(@("start","confirm","end","status") -notcontains $Action){ Die ("UNKNOWN_ACTION: " + $Action) }

. (Join-Path (Join-Path $RepoRoot "scripts") "_lib_neverlost_host_v1.ps1")
$PSExe = $null
if($Action -ne "status"){ $PSExe = NL-ResolvePsHost }

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
    # PowerShell 7 turns ISO timestamps into DateTime; print them back in the canonical UTC form.
    foreach($tp in @("started_utc","ended_utc")){
      $pp = $obj.PSObject.Properties[$tp]
      if($null -ne $pp -and $pp.Value -is [datetime]){ $pp.Value = $pp.Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
    }

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