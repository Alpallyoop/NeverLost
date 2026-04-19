param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$EndTimeUtc = "",
  [string]$Note = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ Die "EnsureDir: empty path" }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function ReadUtf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

function EscapeJson([string]$s){
  if($null -eq $s){ return "" }
  $x = $s.Replace('\','\\')
  $x = $x.Replace('"','\"')
  $x = $x.Replace("`r","\r")
  $x = $x.Replace("`n","\n")
  $x = $x.Replace("`t","\t")
  return $x
}

function To-CanonJson-Flat([hashtable]$h){
  $keys = @($h.Keys | Sort-Object)
  $parts = New-Object System.Collections.Generic.List[string]
  foreach($k in $keys){
    $v = $h[$k]
    if($v -is [bool]){
      $val = $(if($v){ "true" } else { "false" })
    } elseif($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]){
      $val = [string]$v
    } else {
      $val = '"' + (EscapeJson ([string]$v)) + '"'
    }
    [void]$parts.Add('"' + (EscapeJson $k) + '":' + $val)
  }
  return '{' + ($parts -join ',') + '}'
}

function AppendLineUtf8NoBomLf([string]$Path,[string]$Line){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes((($Line -replace "`r`n","`n") -replace "`r","`n") + "`n")
  $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
  try {
    $fs.Write($bytes,0,$bytes.Length)
  } finally {
    $fs.Dispose()
  }
}

function Sha256HexFile([string]$Path){
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TrustDir = Join-Path $RepoRoot "proofs\trust"
$ReceiptDir = Join-Path $RepoRoot "proofs\receipts"
$LedgerPath = Join-Path $ReceiptDir "neverlost.ndjson"
$SessionPath = Join-Path $ReceiptDir "active_authority_session.json"

if(-not (Test-Path -LiteralPath $SessionPath -PathType Leaf)){ Die "NO_ACTIVE_SESSION" }

$sessionObj = ConvertFrom-Json (ReadUtf8 $SessionPath)
if(-not $sessionObj.active){ Die "SESSION_NOT_ACTIVE" }

$trustSha = Sha256HexFile (Join-Path $TrustDir "trust_bundle.json")
$allowedSha = Sha256HexFile (Join-Path $TrustDir "allowed_signers")
if([string]::IsNullOrWhiteSpace($EndTimeUtc)){
  $EndTimeUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

$receipt = [ordered]@{
  action = "authority.ended"
  allowed_signers_sha256 = $allowedSha
  authority_state = "inactive"
  note = $Note
  ok = $true
  principal = [string]$sessionObj.principal
  schema = "neverlost.operator.authority.ended.v1"
  session_id = [string]$sessionObj.session_id
  time_utc = $EndTimeUtc
  trust_bundle_sha256 = $trustSha
}
AppendLineUtf8NoBomLf $LedgerPath (To-CanonJson-Flat $receipt)

$inactive = [ordered]@{
  active = $false
  ended_utc = $EndTimeUtc
  principal = [string]$sessionObj.principal
  session_id = [string]$sessionObj.session_id
  started_utc = [string]$sessionObj.started_utc
}
[System.IO.File]::WriteAllText($SessionPath, (To-CanonJson-Flat $inactive) + "`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Host "AUTHORITY_ENDED_OK" -ForegroundColor Green
Write-Host ("SESSION_ID=" + [string]$sessionObj.session_id) -ForegroundColor Green
