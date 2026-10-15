param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Invoke-Proc([string]$Exe, [string]$Args, [int]$TimeoutMs){
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

  # close stdin immediately (prevents OpenSSH console read hangs)
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

function Is-KeygenPrompt([string]$s){
  if ([string]::IsNullOrWhiteSpace($s)) { return $false }
  return ($s -match 'Generating public/private ed25519 key pair' -or $s -match 'Enter file in which to save the key')
}

# ---- collect candidates deterministically ----
$candidates = New-Object System.Collections.Generic.List[string]

# Get-Command -All
try {
  $cmds = @(Get-Command ssh-keygen -All -ErrorAction SilentlyContinue)
  foreach($c in $cmds){
    if ($c -and $c.CommandType -eq 'Application' -and $c.Source) { [void]$candidates.Add($c.Source) }
  }
} catch { }

# where.exe
try {
  $where = & where.exe ssh-keygen 2>$null
  foreach($w in @($where)){
    if (-not [string]::IsNullOrWhiteSpace($w)) { [void]$candidates.Add($w.Trim()) }
  }
} catch { }

# canonical locations
$win = $env:WINDIR
$pf  = $env:ProgramFiles
$pf86 = ${env:ProgramFiles(x86)}
$la  = $env:LOCALAPPDATA

if ($win) { [void]$candidates.Add((Join-Path $win "System32\OpenSSH\ssh-keygen.exe")) }
if ($pf)  { [void]$candidates.Add((Join-Path $pf  "OpenSSH-Win64\ssh-keygen.exe")) }
if ($pf)  { [void]$candidates.Add((Join-Path $pf  "Git\usr\bin\ssh-keygen.exe")) }
if ($pf)  { [void]$candidates.Add((Join-Path $pf  "Git\bin\ssh-keygen.exe")) }
if ($pf86){ [void]$candidates.Add((Join-Path $pf86 "Git\usr\bin\ssh-keygen.exe")) }
if ($pf86){ [void]$candidates.Add((Join-Path $pf86 "Git\bin\ssh-keygen.exe")) }
if ($la)  { [void]$candidates.Add((Join-Path $la "Programs\Git\usr\bin\ssh-keygen.exe")) }
if ($la)  { [void]$candidates.Add((Join-Path $la "Programs\Git\bin\ssh-keygen.exe")) }

# de-dupe + only existing
$uniq = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
$final = New-Object System.Collections.Generic.List[string]
foreach($p in $candidates){
  if ([string]::IsNullOrWhiteSpace($p)) { continue }
  $pp = $p.Trim()
  if (-not (Test-Path -LiteralPath $pp -PathType Leaf)) { continue }
  if ($uniq.Add($pp)) { [void]$final.Add($pp) }
}

Write-Host "=== OpenSSH.Client Windows capability (if available) ===" -ForegroundColor Cyan
try {
  $caps = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "OpenSSH.Client*" })
  if ($caps.Count -gt 0) {
    $caps | Select-Object Name, State | Format-Table -AutoSize | Out-String | Write-Host
  } else {
    Write-Host "(Get-WindowsCapability not available or no OpenSSH.Client capability found.)"
  }
} catch {
  Write-Host "(Get-WindowsCapability failed: $($_.Exception.Message))"
}
Write-Host ""

if ($final.Count -eq 0) {
  Write-Host "NO ssh-keygen.exe candidates found at all." -ForegroundColor Red
  throw "ssh-keygen.exe not found"
}

Write-Host "=== ssh-keygen candidates + '-Y sign' probe ===" -ForegroundColor Cyan

$rows = @()
foreach($exe in $final){
  $r = Invoke-Proc $exe "-Y sign" 2000
  $combo = ($r.Stdout + "`n" + $r.Stderr)
  $keygenPrompt = Is-KeygenPrompt $combo
  $supportsY = (-not $r.TimedOut) -and (-not $keygenPrompt)

  $rows += [pscustomobject]@{
    path=$exe
    supports_Y=$supportsY
    timed_out=$r.TimedOut
    exit_code=$r.ExitCode
    looks_like_keygen_prompt=$keygenPrompt
    stdout=($r.Stdout -replace "`r`n","`n")
    stderr=($r.Stderr -replace "`r`n","`n")
  }
}

$rows | Select-Object path,supports_Y,timed_out,exit_code,looks_like_keygen_prompt | Format-Table -AutoSize | Out-String | Write-Host
Write-Host ""

$good = @($rows | Where-Object { $_.supports_Y })
if ($good.Count -gt 0) {
  Write-Host "=== RESULT: FOUND ssh-keygen with -Y support ===" -ForegroundColor Green
  $good | Select-Object path,exit_code | Format-Table -AutoSize | Out-String | Write-Host
  Write-Host "Use the first 'path' above as canonical ssh-keygen for NeverLost."
} else {
  Write-Host "=== RESULT: NO ssh-keygen with -Y support found ===" -ForegroundColor Red
  Write-Host "You must install/update an OpenSSH that supports: ssh-keygen -Y sign|verify|find-principals"
  Write-Host ""
  Write-Host "FASTEST FIX on Windows (admin):" -ForegroundColor Yellow
  Write-Host "  Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
  Write-Host ""
  Write-Host "Then verify this exists:" -ForegroundColor Yellow
  Write-Host "  C:\Windows\System32\OpenSSH\ssh-keygen.exe"
  Write-Host ""
  Write-Host "If you rely on Git's ssh-keygen, update Git for Windows to a recent version (older Git builds may lack -Y)." -ForegroundColor Yellow
  throw "NO_SSHKEYGEN_Y_SUPPORT"
}

Write-Host ""
Write-Host "OK: DIAG complete" -ForegroundColor Green
