param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-Gate([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("Parse-Gate missing file: " + $Path) }
  [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path -Encoding UTF8)) | Out-Null
}

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("RepoRoot not found: " + $RepoRoot) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("Missing scripts dir: " + $ScriptsDir) }

$Lib  = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$Make = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$Diag = Join-Path $ScriptsDir "_DIAG_sshkeygen_y_support_v2.ps1"

foreach($p in @($Lib,$Make)){
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Die ("Missing required file: " + $p) }
}

# ---- backup ----
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_fix_lib_allowed_signers_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Lib  -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Lib ) + ".pre")) -Force
Copy-Item -LiteralPath $Make -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Make) + ".pre")) -Force

# =========================================================
# 1) Patch _lib_neverlost_v1.ps1 by APPENDING safe overrides
# =========================================================
$libText = Get-Content -Raw -LiteralPath $Lib -Encoding UTF8
if (-not $libText.EndsWith("`n")) { $libText += "`n" }

$append = @'
# ==========================================================
# NeverLost Patch v1 (APPENDED):
# - Fix ssh-keygen -Y detection (NO prompts)
# - Provide NL-ResolveSshKeygen + NL-InvokeProc if missing
# - Uses: ssh-keygen.exe -Y help probe (safe, non-interactive)
# ==========================================================

if (-not (Get-Command NL-InvokeProc -ErrorAction SilentlyContinue)) {
  function NL-InvokeProc([string]$Exe,[string]$Args,[int]$TimeoutMs){
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $Args
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.RedirectStandardInput  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    try { $p.StandardInput.Close() } catch { }

    if (-not $p.WaitForExit($TimeoutMs)) {
      try { $p.Kill() } catch { }
      $o=""; $e=""
      try { $o = $p.StandardOutput.ReadToEnd() } catch { }
      try { $e = $p.StandardError.ReadToEnd() } catch { }
      return [pscustomobject]@{ TimedOut=$true; ExitCode=-1; Stdout=$o; Stderr=$e }
    }

    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    return [pscustomobject]@{ TimedOut=$false; ExitCode=[int]$p.ExitCode; Stdout=[string]$out; Stderr=[string]$err }
  }
}

function NL-TestSshKeygenY([string]$Exe){
  if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return $false }
  $r = NL-InvokeProc $Exe "-Y help" 3000
  if ($r.TimedOut) { return $false }
  $txt = (($r.Stdout + "`n" + $r.Stderr) -replace "`r`n","`n")
  return ($txt -match 'find-principals' -and $txt -match '\bverify\b' -and $txt -match '\bsign\b')
}

function NL-ResolveSshKeygen {
  $win = $env:WINDIR
  $sys = $null
  if ($win) { $sys = Join-Path $win "System32\OpenSSH\ssh-keygen.exe" }
  if ($sys -and (NL-TestSshKeygenY $sys)) { return $sys }

  $cands = New-Object System.Collections.Generic.List[string]

  try {
    $cmds = @(Get-Command ssh-keygen.exe -All -ErrorAction SilentlyContinue)
    foreach($c in $cmds){
      if ($c -and $c.CommandType -eq 'Application' -and $c.Source) { [void]$cands.Add([string]$c.Source) }
    }
  } catch { }

  try {
    $w = & where.exe ssh-keygen.exe 2>$null
    foreach($p in @($w)){
      if (-not [string]::IsNullOrWhiteSpace($p)) { [void]$cands.Add($p.Trim()) }
    }
  } catch { }

  $uniq = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
  foreach($p in $cands){
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $pp = $p.Trim()
    if (-not (Test-Path -LiteralPath $pp -PathType Leaf)) { continue }
    if (-not $uniq.Add($pp)) { continue }
    if (NL-TestSshKeygenY $pp) { return $pp }
  }

  throw "NL-ResolveSshKeygen: No ssh-keygen.exe with '-Y' support found. Install/enable Windows OpenSSH Client (System32) or update Git/OpenSSH."
}
