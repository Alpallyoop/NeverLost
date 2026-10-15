param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [ValidateSet("status","confirm")]
  [string]$Action = "status",
  [ValidateSet("local","managed")]
  [string]$TargetMode = "managed",
  [string]$NodeId = "local-loopback",
  [string]$AdminActor = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Message){ throw $Message }

function Ensure-Dir([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function JsonEscape([AllowNull()][string]$Value){
  # RFC 8259 string escaping: backslash, quote and every control character (CR/LF in captured CLI
  # output previously produced invalid NDJSON lines).
  if($null -eq $Value){ return "" }
  $sb = New-Object System.Text.StringBuilder
  foreach($ch in $Value.ToCharArray()){
    $code = [int][char]$ch
    if($ch -eq '"'){ [void]$sb.Append('\"'); continue }
    if($ch -eq '\'){ [void]$sb.Append('\\'); continue }
    if($code -eq 10){ [void]$sb.Append('\n'); continue }
    if($code -eq 13){ [void]$sb.Append('\r'); continue }
    if($code -eq 9){ [void]$sb.Append('\t'); continue }
    if($code -lt 32){ [void]$sb.Append('\u' + $code.ToString("x4")); continue }
    [void]$sb.Append($ch)
  }
  return $sb.ToString()
}

function Append-Receipt {
  param(
    [string]$Action,
    [bool]$Ok,
    [string]$Decision,
    [string]$Reason,
    [string]$NodeId,
    [string]$TargetMode,
    [string]$Principal,
    [string]$SessionId,
    [string]$AdminActor,
    [int]$ExitCode,
    [string]$Stdout,
    [string]$Stderr
  )

  $okText = if($Ok){ "true" } else { "false" }
  $timeUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  $json = '{"action":"' + (JsonEscape $Action) + '","admin_actor":"' + (JsonEscape $AdminActor) + '","cli_exit_code":' + $ExitCode + ',"cli_stderr":"' + (JsonEscape $Stderr) + '","cli_stdout":"' + (JsonEscape $Stdout) + '","decision":"' + (JsonEscape $Decision) + '","node_id":"' + (JsonEscape $NodeId) + '","ok":' + $okText + ',"principal":"' + (JsonEscape $Principal) + '","reason":"' + (JsonEscape $Reason) + '","schema":"neverlost.admin_plugin.action.v1","session_id":"' + (JsonEscape $SessionId) + '","target_mode":"' + (JsonEscape $TargetMode) + '","time_utc":"' + $timeUtc + '"}'

  $receiptPath = Join-Path $RepoRoot "proofs\receipts\admin_plugin\admin_actions.ndjson"
  Ensure-Dir (Split-Path -Parent $receiptPath)
  [System.IO.File]::AppendAllText($receiptPath, ($json + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

$RepoRoot = (Resolve-Path $RepoRoot).Path
$TargetMode = $TargetMode.ToLowerInvariant()
if([string]::IsNullOrWhiteSpace($AdminActor)){
  $AdminActor = $env:USERNAME
  if([string]::IsNullOrWhiteSpace($AdminActor)){ $AdminActor = "admin-operator" }
}

$StatePath = Join-Path $RepoRoot "proofs\receipts\active_authority_session.json"
$CoreCli = Join-Path $RepoRoot "scripts\neverlost_cli_v1.ps1"
. (Join-Path $PSScriptRoot "_lib_neverlost_host_v1.ps1")
$PSExe = NL-ResolvePsHost

if(-not (Test-Path -LiteralPath $CoreCli -PathType Leaf)){ Die ("ADMIN_PLUGIN_FAIL:MISSING_CORE_CLI:" + $CoreCli) }

$principal = ""
$sessionId = ""
$active = $false

if(Test-Path -LiteralPath $StatePath -PathType Leaf){
  $state = Get-Content -Raw -LiteralPath $StatePath -Encoding UTF8 | ConvertFrom-Json
  $principal = [string]$state.principal
  $sessionId = [string]$state.session_id
  $endedUtc = ""
  if($state.PSObject.Properties.Name -contains "ended_utc"){
    $endedUtc = [string]$state.ended_utc
  }
  $active = (-not [string]::IsNullOrWhiteSpace($sessionId)) -and [string]::IsNullOrWhiteSpace($endedUtc)
}

if($Action -eq "status"){
  $decision = if($active){ "active" } else { "inactive" }
  Append-Receipt -Action "status" -Ok $true -Decision $decision -Reason "" -NodeId $NodeId -TargetMode $TargetMode -Principal $principal -SessionId $sessionId -AdminActor $AdminActor -ExitCode 0 -Stdout "" -Stderr ""
  Write-Host "ADMIN_PLUGIN_STATUS_OK"
  Write-Host ("NODE_ID=" + $NodeId)
  Write-Host ("TARGET_MODE=" + $TargetMode)
  Write-Host ("ACTIVE=" + $active.ToString().ToUpperInvariant())
  Write-Host ("SESSION_ID=" + $sessionId)
  exit 0
}

if($Action -eq "confirm"){
  if($TargetMode -ne "managed"){
    Append-Receipt -Action "confirm" -Ok $false -Decision "deny" -Reason "ADMIN_PLUGIN_REQUIRES_MANAGED_MODE" -NodeId $NodeId -TargetMode $TargetMode -Principal $principal -SessionId $sessionId -AdminActor $AdminActor -ExitCode 403 -Stdout "" -Stderr "ADMIN_PLUGIN_REQUIRES_MANAGED_MODE"
    Write-Host "ADMIN_PLUGIN_CONFIRM_DENIED"
    Write-Host "REASON=ADMIN_PLUGIN_REQUIRES_MANAGED_MODE"
    exit 0
  }

  if(-not $active){
    Append-Receipt -Action "confirm" -Ok $false -Decision "deny" -Reason "NO_ACTIVE_SESSION" -NodeId $NodeId -TargetMode $TargetMode -Principal $principal -SessionId $sessionId -AdminActor $AdminActor -ExitCode 409 -Stdout "" -Stderr "NO_ACTIVE_SESSION"
    Write-Host "ADMIN_PLUGIN_CONFIRM_DENIED"
    Write-Host "REASON=NO_ACTIVE_SESSION"
    exit 0
  }

  $outDir = Join-Path $RepoRoot "proofs\receipts\admin_plugin"
  Ensure-Dir $outDir
  $stdoutPath = Join-Path $outDir "confirm_stdout.tmp.txt"
  $stderrPath = Join-Path $outDir "confirm_stderr.tmp.txt"

  $p = Start-Process -FilePath $PSExe -ArgumentList @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$CoreCli,"-RepoRoot",$RepoRoot,"-Area","authority","-Action","confirm") -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

  $cliStdout = ""
  $cliStderr = ""
  if(Test-Path -LiteralPath $stdoutPath){ $cliStdout = Get-Content -Raw -LiteralPath $stdoutPath -Encoding UTF8 }
  if(Test-Path -LiteralPath $stderrPath){ $cliStderr = Get-Content -Raw -LiteralPath $stderrPath -Encoding UTF8 }

  $ok = ($p.ExitCode -eq 0)
  $decision = if($ok){ "allow" } else { "deny" }
  $reason = if($ok){ "" } else { "CORE_CONFIRM_FAILED" }
  Append-Receipt -Action "confirm" -Ok $ok -Decision $decision -Reason $reason -NodeId $NodeId -TargetMode $TargetMode -Principal $principal -SessionId $sessionId -AdminActor $AdminActor -ExitCode $p.ExitCode -Stdout $cliStdout -Stderr $cliStderr

  if($ok){
    Write-Host "ADMIN_PLUGIN_CONFIRM_OK"
    Write-Host ("NODE_ID=" + $NodeId)
    Write-Host ("SESSION_ID=" + $sessionId)
    exit 0
  }

  Write-Host "ADMIN_PLUGIN_CONFIRM_FAILED"
  Write-Host ("EXIT_CODE=" + $p.ExitCode)
  exit 1
}

Die ("ADMIN_PLUGIN_FAIL:UNKNOWN_ACTION:" + $Action)
