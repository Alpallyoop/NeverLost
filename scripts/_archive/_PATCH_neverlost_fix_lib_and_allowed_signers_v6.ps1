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
function Parse-GateFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("Parse-Gate missing file: " + $Path) }
  $tk=$null; $er=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tk,[ref]$er)
  if ($er -and @($er).Count -gt 0) {
    $msg = @($er | Select-Object -First 1 | ForEach-Object { $_.Message })[0]
    Die ("Parse-Gate FAIL: " + $Path + " :: " + $msg)
  }
}
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("RepoRoot not found: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("Missing scripts dir: " + $ScriptsDir) }
$Lib  = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$Make = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
foreach($p in @($Lib,$Make)){ if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Die ("Missing required file: " + $p) } }
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_fix_lib_allowed_signers_v6_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Lib  -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Lib ) + ".pre")) -Force
Copy-Item -LiteralPath $Make -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Make) + ".pre")) -Force
$libText = Get-Content -Raw -LiteralPath $Lib -Encoding UTF8
if (-not $libText.EndsWith("`n")) { $libText += "`n" }
$marker = "# NEVERLOST_PATCH_V6_SSHKEYGEN"
if ($libText -notmatch [regex]::Escape($marker)) {
  $A = New-Object System.Collections.Generic.List[string]
  [void]$A.Add("# NEVERLOST_PATCH_V6_SSHKEYGEN")
  [void]$A.Add("# - Adds NL-InvokeProc if missing")
  [void]$A.Add("# - Adds NL-TestSshKeygenY + NL-ResolveSshKeygen")
  [void]$A.Add("# - Probe: ssh-keygen.exe -Y help (safe, non-interactive)")
  [void]$A.Add("")
  [void]$A.Add("if (-not (Get-Command NL-InvokeProc -ErrorAction SilentlyContinue)) {")
  [void]$A.Add("  function NL-InvokeProc([string]$Exe,[string]$Args,[int]$TimeoutMs){")
  [void]$A.Add("    $psi = New-Object System.Diagnostics.ProcessStartInfo")
  [void]$A.Add("    $psi.FileName = $Exe")
  [void]$A.Add("    $psi.Arguments = $Args")
  [void]$A.Add("    $psi.RedirectStandardOutput = $true")
  [void]$A.Add("    $psi.RedirectStandardError  = $true")
  [void]$A.Add("    $psi.RedirectStandardInput  = $true")
  [void]$A.Add("    $psi.UseShellExecute        = $false")
  [void]$A.Add("    $psi.CreateNoWindow         = $true")
  [void]$A.Add("    $p = New-Object System.Diagnostics.Process")
  [void]$A.Add("    $p.StartInfo = $psi")
  [void]$A.Add("    [void]$p.Start()")
  [void]$A.Add("    try { $p.StandardInput.Close() } catch { }")
  [void]$A.Add("    if (-not $p.WaitForExit($TimeoutMs)) {")
  [void]$A.Add("      try { $p.Kill() } catch { }")
  [void]$A.Add("      $o="""" ; $e=""""")
  [void]$A.Add("      try { $o = $p.StandardOutput.ReadToEnd() } catch { }")
  [void]$A.Add("      try { $e = $p.StandardError.ReadToEnd() } catch { }")
  [void]$A.Add("      return [pscustomobject]@{ TimedOut=$true; ExitCode=-1; Stdout=$o; Stderr=$e }")
  [void]$A.Add("    }")
  [void]$A.Add("    $out = $p.StandardOutput.ReadToEnd()")
  [void]$A.Add("    $err = $p.StandardError.ReadToEnd()")
  [void]$A.Add("    return [pscustomobject]@{ TimedOut=$false; ExitCode=[int]$p.ExitCode; Stdout=[string]$out; Stderr=[string]$err }")
  [void]$A.Add("  }")
  [void]$A.Add("}")
  [void]$A.Add("}")
  [void]$A.Add("")
  [void]$A.Add("function NL-TestSshKeygenY([string]$Exe){")
  [void]$A.Add("  if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return $false }")
  [void]$A.Add("  $r = NL-InvokeProc $Exe ""-Y help"" 3000")
  [void]$A.Add("  if ($r.TimedOut) { return $false }")
  [void]$A.Add("  $txt = (($r.Stdout + ""`n"" + $r.Stderr) -replace ""`r`n"",""`n"")")
  [void]$A.Add("  return ($txt -match 'find-principals' -and $txt -match '\bverify\b' -and $txt -match '\bsign\b')")
  [void]$A.Add("}")
  [void]$A.Add("")
  [void]$A.Add("function NL-ResolveSshKeygen {")
  [void]$A.Add("  $win = $env:WINDIR")
  [void]$A.Add("  $sys = $null")
  [void]$A.Add("  if ($win) { $sys = Join-Path $win ""System32\OpenSSH\ssh-keygen.exe"" }")
  [void]$A.Add("  if ($sys -and (NL-TestSshKeygenY $sys)) { return $sys }")
  [void]$A.Add("  $cands = New-Object System.Collections.Generic.List[string]")
  [void]$A.Add("  try {")
  [void]$A.Add("    $cmds = @(Get-Command ssh-keygen.exe -All -ErrorAction SilentlyContinue)")
  [void]$A.Add("    foreach($c in $cmds){ if ($c -and $c.CommandType -eq 'Application' -and $c.Source) { [void]$cands.Add([string]$c.Source) } }")
  [void]$A.Add("  } catch { }")
  [void]$A.Add("  try {")
  [void]$A.Add("    $w = & where.exe ssh-keygen.exe 2>$null")
  [void]$A.Add("    foreach($p in @($w)){ if (-not [string]::IsNullOrWhiteSpace($p)) { [void]$cands.Add($p.Trim()) } }")
  [void]$A.Add("  } catch { }")
  [void]$A.Add("  $uniq = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)")
  [void]$A.Add("  foreach($p in $cands){")
  [void]$A.Add("    if ([string]::IsNullOrWhiteSpace($p)) { continue }")
  [void]$A.Add("    $pp = $p.Trim()")
  [void]$A.Add("    if (-not (Test-Path -LiteralPath $pp -PathType Leaf)) { continue }")
  [void]$A.Add("    if (-not $uniq.Add($pp)) { continue }")
  [void]$A.Add("    if (NL-TestSshKeygenY $pp) { return $pp }")
  [void]$A.Add("  }")
  [void]$A.Add("  throw ""NL-ResolveSshKeygen: No ssh-keygen.exe with '-Y' support found. Install/enable Windows OpenSSH Client (System32) or ship a portable OpenSSH and pin to it.""")
  [void]$A.Add("}")
  $appendText = ($A.ToArray() -join "`n") + "`n"
  Write-Utf8NoBomLf $Lib ($libText + $appendText)
  Parse-GateFile $Lib
}
$M = New-Object System.Collections.Generic.List[string]
[void]$M.Add("param([Parameter(Mandatory=$true)][string]$RepoRoot)")
[void]$M.Add("")
[void]$M.Add("$ErrorActionPreference=""Stop""")
[void]$M.Add("Set-StrictMode -Version Latest")
[void]$M.Add("")
[void]$M.Add(". (Join-Path $PSScriptRoot ""_lib_neverlost_v1.ps1"")")
[void]$M.Add("")
[void]$M.Add("function Die([string]$m){ throw $m }")
[void]$M.Add("function Write-Utf8NoBomLf([string]$Path,[string]$Text){")
[void]$M.Add("  $dir = Split-Path -Parent $Path")
[void]$M.Add("  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }")
[void]$M.Add("  $t = $Text -replace ""`r`n"",""`n"" -replace ""`r"",""`n""")
[void]$M.Add("  if (-not $t.EndsWith(""`n"")) { $t += ""`n"" }")
[void]$M.Add("  $enc = New-Object System.Text.UTF8Encoding($false)")
[void]$M.Add("  [System.IO.File]::WriteAllText($Path,$t,$enc)")
[void]$M.Add("}")
[void]$M.Add("")
[void]$M.Add("if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die (""RepoRoot not found: "" + $RepoRoot) }")
[void]$M.Add("$trust  = Join-Path $RepoRoot ""proofs\trust\trust_bundle.json""")
[void]$M.Add("$asPath = Join-Path $RepoRoot ""proofs\trust\allowed_signers""")
[void]$M.Add("if (-not (Test-Path -LiteralPath $trust -PathType Leaf)) { Die (""trust_bundle.json not found: "" + $trust) }")
[void]$M.Add("")
[void]$M.Add("$tb = (Get-Content -Raw -LiteralPath $trust -Encoding UTF8) | ConvertFrom-Json")
[void]$M.Add("if (-not $tb.keys) { Die ""trust_bundle.json missing 'keys' array."" }")
[void]$M.Add("")
[void]$M.Add("$lines = New-Object System.Collections.Generic.List[string]")
[void]$M.Add("foreach($k in @($tb.keys)){")
[void]$M.Add("  if (-not $k) { continue }")
[void]$M.Add("  $principal = [string]$k.principal")
[void]$M.Add("  $pubkey    = [string]$k.public_key")
[void]$M.Add("  $nsRaw     = $k.namespaces")
[void]$M.Add("  if ([string]::IsNullOrWhiteSpace($principal)) { Die ""trust_bundle key missing principal"" }")
[void]$M.Add("  if ([string]::IsNullOrWhiteSpace($pubkey))    { Die (""trust_bundle key for principal '"" + $principal + ""' missing public_key"") }")
[void]$M.Add("  $ns = @(@($nsRaw) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })")
[void]$M.Add("  if ($ns.Count -gt 0) {")
[void]$M.Add("    $opt = 'namespaces=""' + (($ns | ForEach-Object { $_ -replace '""',''} ) -join ',') + '""'")
[void]$M.Add("    [void]$lines.Add(($principal + "" "" + $opt + "" "" + $pubkey).Trim())")
[void]$M.Add("  } else {")
[void]$M.Add("    [void]$lines.Add(($principal + "" "" + $pubkey).Trim())")
[void]$M.Add("  }")
[void]$M.Add("}")
[void]$M.Add("")
[void]$M.Add("$sorted = $lines.ToArray() | Sort-Object")
[void]$M.Add("Write-Utf8NoBomLf $asPath (($sorted -join ""`n"") + ""`n"")")
[void]$M.Add("Write-Host (""OK: wrote allowed_signers => "" + $asPath) -ForegroundColor Green")
$makeText = ($M.ToArray() -join "`n") + "`n"
Write-Utf8NoBomLf $Make $makeText
Parse-GateFile $Make
Write-Host ("OK: patch v6 complete. Backup at: " + $BackupDir) -ForegroundColor Green
