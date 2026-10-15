# NeverLost host helpers v1
#
# Resolves the PowerShell host and ssh-keygen without hard-coded machine paths, and starts child
# PowerShell processes with captured stdout/stderr. Works on Windows PowerShell 5.1 and PowerShell 7
# (Windows, Linux, macOS).
#
# Resolution order (PowerShell host):
#   1. NEVERLOST_PS_HOST when set (must exist, otherwise fail closed)
#   2. Windows: %WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe (the canonical PS 5.1 lane)
#   3. pwsh on PATH
#   4. the current process
#
# Resolution order (ssh-keygen):
#   1. NEVERLOST_SSH_KEYGEN when set (must exist, otherwise fail closed)
#   2. ssh-keygen.exe (Windows) / ssh-keygen (other) on PATH

function NL-IsWindowsHost(){
  if($PSVersionTable.PSEdition -ne 'Core'){ return $true }
  return [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}

function NL-ResolvePsHost(){
  $override = [string]$env:NEVERLOST_PS_HOST
  if(-not [string]::IsNullOrWhiteSpace($override)){
    if(Test-Path -LiteralPath $override -PathType Leaf){ return $override }
    throw ("PS_HOST_OVERRIDE_MISSING: " + $override)
  }
  if(NL-IsWindowsHost){
    if(-not [string]::IsNullOrWhiteSpace([string]$env:WINDIR)){
      $winPs = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
      if(Test-Path -LiteralPath $winPs -PathType Leaf){ return $winPs }
    }
  }
  $pw = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if($null -ne $pw){ return [string]$pw.Source }
  $self = [string](Get-Process -Id $PID).Path
  if(-not [string]::IsNullOrWhiteSpace($self) -and (Test-Path -LiteralPath $self -PathType Leaf)){ return $self }
  throw "PS_HOST_NOT_FOUND"
}

function NL-ResolveSshKeygen(){
  $override = [string]$env:NEVERLOST_SSH_KEYGEN
  if(-not [string]::IsNullOrWhiteSpace($override)){
    if(Test-Path -LiteralPath $override -PathType Leaf){ return $override }
    throw ("SSH_KEYGEN_OVERRIDE_MISSING: " + $override)
  }
  $names = @("ssh-keygen")
  if(NL-IsWindowsHost){ $names = @("ssh-keygen.exe","ssh-keygen") }
  foreach($n in $names){
    $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if($null -ne $c){ return [string]$c.Source }
  }
  throw "SSH_KEYGEN_NOT_FOUND"
}

function NL-QuoteArg([string]$Value){
  if($null -eq $Value -or $Value.Length -eq 0){ return '""' }
  if($Value -match '[\s"]'){ return ('"' + ($Value -replace '"','\"') + '"') }
  return $Value
}

# Runs a PowerShell script file in a child host. Arguments are passed as an array and quoted here,
# so paths with spaces work on both hosts. Returns ExitCode / Stdout / Stderr (CRLF normalized to LF).
function NL-InvokePsFile {
  param(
    [Parameter(Mandatory=$true)][string]$File,
    [string[]]$Arguments = @(),
    [Parameter(Mandatory=$true)][string]$StdoutPath,
    [Parameter(Mandatory=$true)][string]$StderrPath,
    [string]$PsHost = ""
  )
  if([string]::IsNullOrWhiteSpace($PsHost)){ $PsHost = NL-ResolvePsHost }
  foreach($p in @($StdoutPath,$StderrPath)){
    $d = Split-Path -Parent $p
    if($d -and -not (Test-Path -LiteralPath $d -PathType Container)){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
  }
  $parts = New-Object System.Collections.Generic.List[string]
  foreach($a in @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$File)){ [void]$parts.Add((NL-QuoteArg $a)) }
  foreach($a in @($Arguments)){ [void]$parts.Add((NL-QuoteArg ([string]$a))) }
  $argLine = (@($parts.ToArray()) -join ' ')

  $sp = @{
    FilePath = $PsHost
    ArgumentList = $argLine
    Wait = $true
    PassThru = $true
    RedirectStandardOutput = $StdoutPath
    RedirectStandardError = $StderrPath
  }
  if(NL-IsWindowsHost){ $sp["WindowStyle"] = "Hidden" }
  $proc = Start-Process @sp

  $stdout = ""
  if(Test-Path -LiteralPath $StdoutPath -PathType Leaf){ $stdout = [string](Get-Content -Raw -LiteralPath $StdoutPath -Encoding UTF8) }
  $stderr = ""
  if(Test-Path -LiteralPath $StderrPath -PathType Leaf){ $stderr = [string](Get-Content -Raw -LiteralPath $StderrPath -Encoding UTF8) }
  if($null -eq $stdout){ $stdout = "" }
  if($null -eq $stderr){ $stderr = "" }

  return [pscustomobject]@{
    ExitCode = [int]$proc.ExitCode
    Stdout   = ($stdout -replace "`r`n","`n")
    Stderr   = ($stderr -replace "`r`n","`n")
  }
}

# Trust source for sandboxed proof lanes: "live" (proofs/trust of this checkout, the default) or
# "fixture" (the committed public-only trust root in test_vectors/fixtures/trust_root_v1, for clean
# clones, cloud sessions and CI). Chosen explicitly through NEVERLOST_TRUST_SOURCE; never a silent fallback.
function NL-TrustSource(){
  $v = ([string]$env:NEVERLOST_TRUST_SOURCE).Trim().ToLowerInvariant()
  if([string]::IsNullOrWhiteSpace($v)){ return "live" }
  if(@("live","fixture") -notcontains $v){ throw ("NEVERLOST_TRUST_SOURCE_INVALID: " + $v) }
  return $v
}

# Creates an isolated copy of the instrument inside <RepoRoot>/.scratch/sandbox/ so proof lanes never
# write test receipts into the live authority ledger. Copies scripts, vectors, schemas, the trust
# directory and PUBLIC keys only. Private keys are never copied.
function NL-NewSandboxRepo {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$Label
  )
  $root = (Resolve-Path -LiteralPath $RepoRoot).Path
  $trustSource = NL-TrustSource
  $liveBundle = Join-Path (Join-Path (Join-Path $root "proofs") "trust") "trust_bundle.json"
  if($trustSource -eq "live" -and -not (Test-Path -LiteralPath $liveBundle -PathType Leaf)){
    throw "LIVE_TRUST_MISSING: proofs/trust/trust_bundle.json not found (set NEVERLOST_TRUST_SOURCE=fixture to run against the committed fixture trust root)"
  }
  $sbParent = Join-Path (Join-Path $root ".scratch") "sandbox"
  if(-not (Test-Path -LiteralPath $sbParent -PathType Container)){ New-Item -ItemType Directory -Force -Path $sbParent | Out-Null }
  $sb = Join-Path $sbParent ($Label + "_" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $sb | Out-Null

  $scriptsSrc = Join-Path $root "scripts"
  $scriptsDst = Join-Path $sb "scripts"
  New-Item -ItemType Directory -Force -Path $scriptsDst | Out-Null
  Get-ChildItem -LiteralPath $scriptsSrc -File -Filter *.ps1 | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $scriptsDst $_.Name) -Force
  }

  foreach($rel in @("test_vectors","schemas")){
    $src = Join-Path $root $rel
    if(Test-Path -LiteralPath $src -PathType Container){ Copy-Item -LiteralPath $src -Destination (Join-Path $sb $rel) -Recurse -Force }
  }

  $proofsDst = Join-Path $sb "proofs"
  New-Item -ItemType Directory -Force -Path (Join-Path $proofsDst "receipts") | Out-Null
  $trustSrc = Join-Path (Join-Path $root "proofs") "trust"
  $keysSrc = Join-Path (Join-Path $root "proofs") "keys"
  if($trustSource -eq "fixture"){
    $fxRoot = Join-Path (Join-Path (Join-Path $root "test_vectors") "fixtures") "trust_root_v1"
    $trustSrc = Join-Path $fxRoot "trust"
    $keysSrc = Join-Path $fxRoot "keys"
    if(-not (Test-Path -LiteralPath (Join-Path $trustSrc "trust_bundle.json") -PathType Leaf)){ throw ("FIXTURE_TRUST_MISSING: " + $trustSrc) }
  }
  if(Test-Path -LiteralPath $trustSrc -PathType Container){ Copy-Item -LiteralPath $trustSrc -Destination (Join-Path $proofsDst "trust") -Recurse -Force }
  $keysDst = Join-Path $proofsDst "keys"
  New-Item -ItemType Directory -Force -Path $keysDst | Out-Null
  if(Test-Path -LiteralPath $keysSrc -PathType Container){
    Get-ChildItem -LiteralPath $keysSrc -File -Filter *.pub | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $keysDst $_.Name) -Force
    }
  }
  return $sb
}

# Removes a scratch tree. Retries because Windows (antivirus, indexers, just-closed child handles) and
# mounted file systems can report "directory not empty" for a moment after files are deleted.
function NL-RemoveScratchTree([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if($Path -notmatch '[\\/]\.scratch[\\/]'){ throw ("SCRATCH_REMOVE_REFUSED: " + $Path) }
  for($i = 0; $i -lt 20; $i++){
    if(-not (Test-Path -LiteralPath $Path)){ return }
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 250 }
  }
  if(Test-Path -LiteralPath $Path){ throw ("SCRATCH_REMOVE_FAILED: " + $Path) }
}

function NL-RemoveSandboxRepo([string]$SandboxRoot){
  if([string]::IsNullOrWhiteSpace($SandboxRoot)){ return }
  if($SandboxRoot -notmatch '[\\/]\.scratch[\\/]sandbox[\\/]'){ throw ("SANDBOX_REMOVE_REFUSED: " + $SandboxRoot) }
  NL-RemoveScratchTree $SandboxRoot
}

# Restricts a private key file to the current user so ssh-keygen accepts it.
function NL-ProtectPrivateKey([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw ("PRIVATE_KEY_MISSING: " + $Path) }
  if(NL-IsWindowsHost){
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls $Path "/inheritance:r" | Out-Null
    if($LASTEXITCODE -ne 0){ throw ("ICACLS_FAILED: inheritance " + $Path) }
    & icacls $Path "/grant:r" ($user + ":(R,W)") | Out-Null
    if($LASTEXITCODE -ne 0){ throw ("ICACLS_FAILED: grant " + $Path) }
  } else {
    & chmod 600 $Path
    if($LASTEXITCODE -ne 0){ throw ("CHMOD_FAILED: " + $Path) }
  }
}
