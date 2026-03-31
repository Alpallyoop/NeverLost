param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$StartTimeUtc = "",
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

function Sha256HexString([string]$Text){
  $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }
  return ([System.BitConverter]::ToString($hash)).Replace('-','').ToLowerInvariant()
}

function Sha256HexFile([string]$Path){
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TrustDir = Join-Path $RepoRoot "proofs\trust"
$ReceiptDir = Join-Path $RepoRoot "proofs\receipts"
$LedgerPath = Join-Path $ReceiptDir "neverlost.ndjson"
$SessionPath = Join-Path $ReceiptDir "active_authority_session.json"

$PrincipalPath = Join-Path $TrustDir "expected_principal0.txt"
$AllowedPath   = Join-Path $TrustDir "allowed_signers"
$TrustPath     = Join-Path $TrustDir "trust_bundle.json"

$principal = ((ReadUtf8 $PrincipalPath).Split("`n")[0] + "").Trim()
if([string]::IsNullOrWhiteSpace($principal)){ Die "EMPTY_PRINCIPAL" }

$trustSha = Sha256HexFile $TrustPath
$allowedSha = Sha256HexFile $AllowedPath

if([string]::IsNullOrWhiteSpace($StartTimeUtc)){
  $StartTimeUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

$sessionId = Sha256HexString($principal + $StartTimeUtc)

$receipt = [ordered]@{
  action = "authority.started"
  allowed_signers_sha256 = $allowedSha
  authority_state = "active"
  note = $Note
  ok = $true
  principal = $principal
  schema = "neverlost.operator.authority.started.v1"
  session_id = $sessionId
  time_utc = $StartTimeUtc
  trust_bundle_sha256 = $trustSha
}
$canon = To-CanonJson-Flat $receipt
AppendLineUtf8NoBomLf $LedgerPath $canon

$session = [ordered]@{
  active = $true
  principal = $principal
  session_id = $sessionId
  started_utc = $StartTimeUtc
}
[System.IO.File]::WriteAllText($SessionPath, (To-CanonJson-Flat $session) + "`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Host "AUTHORITY_STARTED_OK" -ForegroundColor Green
Write-Host ("SESSION_ID=" + $sessionId) -ForegroundColor Green
