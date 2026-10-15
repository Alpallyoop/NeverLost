param(
  [Parameter(Mandatory=$false)]
  [string]$RepoRoot = "C:\dev\neverlost",

  [Parameter(Mandatory=$true)]
  [ValidateSet("status","confirm","help")]
  [string]$Action,

  [Parameter(Mandatory=$false)]
  [string]$NodeId = "local-node",

  [Parameter(Mandatory=$false)]
  [string]$AdminId = $env:USERNAME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die {
  param([Parameter(Mandatory=$true)][string]$Message)
  Write-Host $Message -ForegroundColor Red
  exit 1
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
  [System.IO.File]::WriteAllText($Path,$normalized,(New-Object System.Text.UTF8Encoding($false)))
}

function Append-Ndjson {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][object]$Object
  )
  $line = ($Object | ConvertTo-Json -Depth 20 -Compress)
  $parent = Split-Path -Parent $Path
  Ensure-Dir -Path $parent
  [System.IO.File]::AppendAllText($Path,$line + "`n",(New-Object System.Text.UTF8Encoding($false)))
}

function Read-JsonFile {
  param([Parameter(Mandatory=$true)][string]$Path)
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    return $null
  }
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  if([string]::IsNullOrWhiteSpace($raw)){
    return $null
  }
  return ($raw | ConvertFrom-Json)
}

function Get-WorkbenchMode {
  param([Parameter(Mandatory=$true)][string]$Root)

  $modePath = Join-Path $Root "proofs\receipts\workbench_mode.json"
  $modeObj = Read-JsonFile -Path $modePath

  if($null -eq $modeObj){
    return "local"
  }

  $mode = [string]$modeObj.mode
  if($mode -eq "managed"){
    return "managed"
  }

  return "local"
}

function Get-JsonPropString {
  param(
    [Parameter(Mandatory=$true)][object]$Object,
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$false)][string]$Default = ""
  )

  if($null -eq $Object){ return $Default }
  if($Object.PSObject.Properties.Name -contains $Name){
    $v = $Object.$Name
    if($null -eq $v){ return $Default }
    return [string]$v
  }

  return $Default
}

function Get-JsonPropBool {
  param(
    [Parameter(Mandatory=$true)][object]$Object,
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$false)][bool]$Default = $false
  )

  if($null -eq $Object){ return $Default }
  if($Object.PSObject.Properties.Name -contains $Name){
    $v = $Object.$Name
    if($null -eq $v){ return $Default }
    return [bool]$v
  }

  return $Default
}

function Get-AuthorityState {
  param([Parameter(Mandatory=$true)][string]$Root)

  $statePath = Join-Path $Root "proofs\receipts\active_authority_session.json"
  $state = Read-JsonFile -Path $statePath

  if($null -eq $state){
    return [pscustomobject]@{
      active = $false
      principal = ""
      session_id = ""
      started_utc = ""
      ended_utc = ""
    }
  }

  $ended = Get-JsonPropString -Object $state -Name "ended_utc"
  $sid = Get-JsonPropString -Object $state -Name "session_id"
  $explicitActive = $false

  $explicitActive = Get-JsonPropBool -Object $state -Name "active" -Default $false

  $inferredActive = (-not [string]::IsNullOrWhiteSpace($sid)) -and [string]::IsNullOrWhiteSpace($ended)

  return [pscustomobject]@{
    active = ($explicitActive -or $inferredActive)
    principal = Get-JsonPropString -Object $state -Name "principal"
    session_id = $sid
    started_utc = Get-JsonPropString -Object $state -Name "started_utc"
    ended_utc = $ended
  }
}

function New-AdminReceipt {
  param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$NodeId,
    [Parameter(Mandatory=$true)][string]$AdminId,
    [Parameter(Mandatory=$true)][string]$Mode,
    [Parameter(Mandatory=$true)][object]$Authority,
    [Parameter(Mandatory=$true)][bool]$Ok,
    [Parameter(Mandatory=$true)][string]$Decision,
    [Parameter(Mandatory=$true)][string]$Reason
  )

  $receipt = [ordered]@{
    schema = "neverlost.admin_plugin.confirm.v1"
    time_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    node_id = $NodeId
    admin_id = $AdminId
    actor_role = "admin"
    source = "admin_plugin"
    source_detail = "admin_plugin.authority.confirm"
    mode = $Mode
    ok = $Ok
    decision = $Decision
    reason = $Reason
    authority_active = [bool]$Authority.active
    principal = [string]$Authority.principal
    session_id = [string]$Authority.session_id
    started_utc = [string]$Authority.started_utc
    ended_utc = [string]$Authority.ended_utc
  }

  $path = Join-Path $Root "proofs\receipts\admin_plugin\admin_confirm.ndjson"
  Append-Ndjson -Path $path -Object $receipt

  return $receipt
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$mode = Get-WorkbenchMode -Root $RepoRoot
$authority = Get-AuthorityState -Root $RepoRoot

if($Action -eq "help"){
  Write-Host "NeverLost Admin Plugin v1"
  Write-Host "Actions:"
  Write-Host "  status  - show managed/local mode and authority state"
  Write-Host "  confirm - managed-mode-only admin confirmation receipt"
  Write-Host ""
  Write-Host "Example:"
  Write-Host ".\scripts\neverlost_admin_plugin_v1.ps1 -RepoRoot C:\dev\neverlost -Action status"
  exit 0
}

if($Action -eq "status"){
  Write-Host ("NODE_ID=" + $NodeId)
  Write-Host ("MODE=" + $mode.ToUpperInvariant())
  Write-Host ("AUTHORITY_ACTIVE=" + $authority.active)
  Write-Host ("PRINCIPAL=" + $authority.principal)
  Write-Host ("SESSION_ID=" + $authority.session_id)
  Write-Host ("STARTED_UTC=" + $authority.started_utc)
  Write-Host ("ENDED_UTC=" + $authority.ended_utc)
  Write-Host "NEVERLOST_ADMIN_PLUGIN_STATUS_OK" -ForegroundColor Green
  exit 0
}

if($Action -eq "confirm"){
  if($mode -ne "managed"){
    $r = New-AdminReceipt -Root $RepoRoot -NodeId $NodeId -AdminId $AdminId -Mode $mode -Authority $authority -Ok $false -Decision "deny" -Reason "ADMIN_REQUIRES_MANAGED_MODE"
    Write-Host "ADMIN_CONFIRM_DENIED:ADMIN_REQUIRES_MANAGED_MODE" -ForegroundColor Yellow
    Write-Host ("SESSION_ID=" + $r.session_id)
    exit 0
  }

  if(-not $authority.active){
    $r = New-AdminReceipt -Root $RepoRoot -NodeId $NodeId -AdminId $AdminId -Mode $mode -Authority $authority -Ok $false -Decision "deny" -Reason "NO_ACTIVE_SESSION"
    Write-Host "ADMIN_CONFIRM_DENIED:NO_ACTIVE_SESSION" -ForegroundColor Yellow
    Write-Host ("SESSION_ID=" + $r.session_id)
    exit 0
  }

  $receipt = New-AdminReceipt -Root $RepoRoot -NodeId $NodeId -AdminId $AdminId -Mode $mode -Authority $authority -Ok $true -Decision "allow" -Reason "ADMIN_CONFIRMED_ACTIVE_MANAGED_SESSION"
  Write-Host "ADMIN_CONFIRM_OK" -ForegroundColor Green
  Write-Host ("NODE_ID=" + $receipt.node_id)
  Write-Host ("ADMIN_ID=" + $receipt.admin_id)
  Write-Host ("SESSION_ID=" + $receipt.session_id)
  exit 0
}

Die ("UNKNOWN_ACTION: " + $Action)