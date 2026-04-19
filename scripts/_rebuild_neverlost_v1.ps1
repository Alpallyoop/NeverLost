$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$RepoRoot = "C:\dev\neverlost"

function Write-Utf8NoBom([string]$Path,[string[]]$Lines){
  $enc = [System.Text.UTF8Encoding]::new($false)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $text = ($Lines -join "`n") + "`n"
  [System.IO.File]::WriteAllBytes($Path, $enc.GetBytes($text))
}

# --- rewrite lib ---
$libPath = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
Write-Utf8NoBom $libPath @(
  '$ErrorActionPreference="Stop"'
  'Set-StrictMode -Version Latest'
  ''
  'function NL-GetUtf8NoBomEncoding(){ [System.Text.UTF8Encoding]::new($false) }'
  ''
  'function Sha256HexBytes([byte[]]$Bytes){'
  '  $sha = [System.Security.Cryptography.SHA256]::Create()'
  '  try {'
  '    $h = $sha.ComputeHash($Bytes)'
  '    return ([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant()'
  '  } finally { $sha.Dispose() }'
  '}'
  ''
  'function Sha256HexPath([string]$Path){'
  '  if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found for sha256: $Path" }'
  '  $rp = (Resolve-Path -LiteralPath $Path).Path'
  '  $bytes = [System.IO.File]::ReadAllBytes($rp)'
  '  return Sha256HexBytes $bytes'
  '}'
  ''
  'function Read-Utf8([string]$Path){'
  '  $enc = NL-GetUtf8NoBomEncoding'
  '  $rp = (Resolve-Path -LiteralPath $Path).Path'
  '  $bytes = [System.IO.File]::ReadAllBytes($rp)'
  '  return $enc.GetString($bytes)'
  '}'
)

# --- rewrite entry script with param FIRST TOKEN (line 1) ---
$showPath = Join-Path $RepoRoot "scripts\show_identity_v1.ps1"
Write-Utf8NoBom $showPath @(
  'param([Parameter(Mandatory=$true)][string]$RepoRoot)'
  '$ErrorActionPreference="Stop"'
  'Set-StrictMode -Version Latest'
  '$here = Split-Path -Parent $MyInvocation.MyCommand.Path'
  '. (Join-Path $here "_lib_neverlost_v1.ps1")'
  '$pub = Join-Path $RepoRoot "proofs\keys\neverlost_authority_ed25519.pub"'
  'Write-Host ("pubkey_sha256 : " + (Sha256HexPath $pub))'
)

Write-Host ("OK: rebuilt NeverLost at " + $RepoRoot) -ForegroundColor Green
