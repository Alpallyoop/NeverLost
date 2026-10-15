param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text -replace "
","
" -replace "
","
"
  if (-not $t.EndsWith("
")) { $t += "
" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("Parse-Gate missing file: " + $Path) }
  $tk = $null; $er = $null
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
# 1) Append safe overrides to _lib_neverlost_v1.ps1
#    (NO here-strings inside here-strings; build via lines)
# =========================================================
$libText = Get-Content -Raw -LiteralPath $Lib -Encoding UTF8
if (-not $libText.EndsWith("
")) { $libText += "
" }

$marker = "# NEVERLOST_PATCH_V2_SSHKEYGEN"
if ($libText -notmatch [regex]::Escape($marker)) {
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add("")
  [void]$lines.Add($marker)
  [void]$lines.Add("# - Adds NL-InvokeProc if missing")
  [void]$lines.Add("# - Adds NL-TestSshKeygenY + NL-ResolveSshKeygen (safe '-Y help' probe)")
  [void]$lines.Add("")

  [void]$lines.Add("if (-not (Get-Command NL-InvokeProc -ErrorAction SilentlyContinue)) {")
  [void]$lines.Add("  function NL-InvokeProc([string]$Exe,[string]$Args,[int]$TimeoutMs){")
  [void]$lines.Add("    $psi = New-Object System.Diagnostics.ProcessStartInfo")
  [void]$lines.Add("    $psi.FileName = $Exe")
  [void]$lines.Add("    $psi.Arguments = $Args")
  [void]$lines.Add("    $psi.RedirectStandardOutput = $true")
  [void]$lines.Add("    $psi.RedirectStandardError  = $true")
  [void]$lines.Add("    $psi.RedirectStandardInput  = $true")
  [void]$lines.Add("    $psi.UseShellExecute        = $false")
  [void]$lines.Add("    $psi.CreateNoWindow         = $true")
  [void]$lines.Add("    $p = New-Object System.Diagnostics.Process")
  [void]$lines.Add("    $p.StartInfo = $psi")
  [void]$lines.Add("    [void]$p.Start()")
  [void]$lines.Add("    try { $p.StandardInput.Close() } catch { }")
  [void]$lines.Add("    if (-not $p.WaitForExit($TimeoutMs)) {")
  [void]$lines.Add("      try { $p.Kill() } catch { }")
  [void]$lines.Add("      $o=''; $e=''")
  [void]$lines.Add("      try { $o = $p.StandardOutput.ReadToEnd() } catch { }")
  [void]$lines.Add("      try { $e = $p.StandardError.ReadToEnd() } catch { }")
  [void]$lines.Add("      return [pscustomobject]@{ TimedOut=$true; ExitCode=-1; Stdout=$o; Stderr=$e }")
  [void]$lines.Add("    }")
  [void]$lines.Add("    $out = $p.StandardOutput.ReadToEnd()")
  [void]$lines.Add("    $err = $p.StandardError.ReadToEnd()")
  [void]$lines.Add("    return [pscustomobject]@{ TimedOut=$false; ExitCode=[int]$p.ExitCode; Stdout=[string]$out; Stderr=[string]$err }")
  [void]$lines.Add("  }")
  [void]$lines.Add("}")
  [void]$lines.Add("")

  [void]$lines.Add("function NL-TestSshKeygenY([string]$Exe){")
  [void]$lines.Add("  if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return $false }")
  [void]$lines.Add("  $r = NL-InvokeProc $Exe ""-Y help"" 3000")
  [void]$lines.Add("  if ($r.TimedOut) { return $false }")
  [void]$lines.Add("  $txt = (($r.Stdout + ""
"" + $r.Stderr) -replace ""
"",""
"")")
  [void]$lines.Add("  return ($txt -match 'find-principals' -and $txt -match '\bverify\b' -and $txt -match '\bsign\b')")
  [void]$lines.Add("}")
  [void]$lines.Add("")

  [void]$lines.Add("function NL-ResolveSshKeygen {")
  [void]$lines.Add("  $win = $env:WINDIR")
  [void]$lines.Add("  $sys = $null")
  [void]$lines.Add("  if ($win) { $sys = Join-Path $win ""System32\OpenSSH\ssh-keygen.exe"" }")
  [void]$lines.Add("  if ($sys -and (NL-TestSshKeygenY $sys)) { return $sys }")
  [void]$lines.Add("  $cands = New-Object System.Collections.Generic.List[string]")
  [void]$lines.Add("  try {")
  [void]$lines.Add("    $cmds = @(Get-Command ssh-keygen.exe -All -ErrorAction SilentlyContinue)")
  [void]$lines.Add("    foreach($c in $cmds){ if ($c -and $c.CommandType -eq 'Application' -and $c.Source) { [void]$cands.Add([string]$c.Source) } }")
  [void]$lines.Add("  } catch { }")
  [void]$lines.Add("  try {")
  [void]$lines.Add("    $w = & where.exe ssh-keygen.exe 2>$null")
  [void]$lines.Add("    foreach($p in @($w)){ if (-not [string]::IsNullOrWhiteSpace($p)) { [void]$cands.Add($p.Trim()) } }")
  [void]$lines.Add("  } catch { }")
  [void]$lines.Add("  $uniq = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)")
  [void]$lines.Add("  foreach($p in $cands){")
  [void]$lines.Add("    if ([string]::IsNullOrWhiteSpace($p)) { continue }")
  [void]$lines.Add("    $pp = $p.Trim()")
  [void]$lines.Add("    if (-not (Test-Path -LiteralPath $pp -PathType Leaf)) { continue }")
  [void]$lines.Add("    if (-not $uniq.Add($pp)) { continue }")
  [void]$lines.Add("    if (NL-TestSshKeygenY $pp) { return $pp }")
  [void]$lines.Add("  }")
  [void]$lines.Add("  throw ""NL-ResolveSshKeygen: No ssh-keygen.exe with '-Y' support found. Install/enable Windows OpenSSH Client (System32) or ship a portable OpenSSH and pin to it.""")
  [void]$lines.Add("}")
  [void]$lines.Add("")

  $appendText = ($lines.ToArray() -join "
")
  Write-Utf8NoBomLf $Lib ($libText + $appendText)
  Parse-GateFile $Lib
}

# =========================================================
# 2) Overwrite make_allowed_signers_v1.ps1 (NO NL-WriteAllowedSigners)
# =========================================================
$makeLines = New-Object System.Collections.Generic.List[string]
[void]$makeLines.Add("param([Parameter(Mandatory=$true)][string]$RepoRoot)")
[void]$makeLines.Add("")
[void]$makeLines.Add("$ErrorActionPreference=""Stop""")
[void]$makeLines.Add("Set-StrictMode -Version Latest")
[void]$makeLines.Add("")
[void]$makeLines.Add(". (Join-Path $PSScriptRoot ""_lib_neverlost_v1.ps1"")")
[void]$makeLines.Add("")
[void]$makeLines.Add("function Die([string]$m){ throw $m }")
[void]$makeLines.Add("function Write-Utf8NoBomLf([string]$Path,[string]$Text){")
[void]$makeLines.Add("  $dir = Split-Path -Parent $Path")
[void]$makeLines.Add("  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }")
[void]$makeLines.Add("  $t = $Text -replace ""
"",""
"" -replace ""
"",""
""")
[void]$makeLines.Add("  if (-not $t.EndsWith(""
"")) { $t += ""
"" }")
[void]$makeLines.Add("  $enc = New-Object System.Text.UTF8Encoding($false)")
[void]$makeLines.Add("  [System.IO.File]::WriteAllText($Path,$t,$enc)")
[void]$makeLines.Add("}")
[void]$makeLines.Add("")
[void]$makeLines.Add("if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die (""RepoRoot not found: "" + $RepoRoot) }")
[void]$makeLines.Add("$trust  = Join-Path $RepoRoot ""proofs\trust\trust_bundle.json""")
[void]$makeLines.Add("$asPath = Join-Path $RepoRoot ""proofs\trust\allowed_signers""")
[void]$makeLines.Add("if (-not (Test-Path -LiteralPath $trust -PathType Leaf)) { Die (""trust_bundle.json not found: "" + $trust) }")
[void]$makeLines.Add("")
[void]$makeLines.Add("$tb = (Get-Content -Raw -LiteralPath $trust -Encoding UTF8) | ConvertFrom-Json")
[void]$makeLines.Add("if (-not $tb.keys) { Die ""trust_bundle.json missing 'keys' array."" }")
[void]$makeLines.Add("")
[void]$makeLines.Add("$lines = New-Object System.Collections.Generic.List[string]")
[void]$makeLines.Add("foreach($k in @($tb.keys)){")
[void]$makeLines.Add("  if (-not $k) { continue }")
[void]$makeLines.Add("  $principal = [string]$k.principal")
[void]$makeLines.Add("  $pubkey    = [string]$k.public_key")
[void]$makeLines.Add("  $nsRaw     = $k.namespaces")
[void]$makeLines.Add("  if ([string]::IsNullOrWhiteSpace($principal)) { Die ""trust_bundle key missing principal"" }")
[void]$makeLines.Add("  if ([string]::IsNullOrWhiteSpace($pubkey))    { Die (""trust_bundle key for principal '"" + $principal + ""' missing public_key"") }")
[void]$makeLines.Add("  $ns = @(@($nsRaw) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })")
[void]$makeLines.Add("  if ($ns.Count -gt 0) {")
[void]$makeLines.Add("    $opt = 'namespaces=""' + (($ns | ForEach-Object { $_ -replace '""','' }) -join ',') + '""'")
[void]$makeLines.Add("    [void]$lines.Add(($principal + "" "" + $opt + "" "" + $pubkey).Trim())")
[void]$makeLines.Add("  } else {")
[void]$makeLines.Add("    [void]$lines.Add(($principal + "" "" + $pubkey).Trim())")
[void]$makeLines.Add("  }")
[void]$makeLines.Add("}")
[void]$makeLines.Add("")
[void]$makeLines.Add("$sorted = $lines.ToArray() | Sort-Object")
[void]$makeLines.Add("Write-Utf8NoBomLf $asPath (($sorted -join ""
"") + ""
"")")
[void]$makeLines.Add("Write-Host (""OK: wrote allowed_signers => "" + $asPath) -ForegroundColor Green")

$makeText = ($makeLines.ToArray() -join "
") + "
"
Write-Utf8NoBomLf $Make $makeText
Parse-GateFile $Make

Write-Host ("OK: patch v2 complete. Backup at: " + $BackupDir) -ForegroundColor Green
