<#
NeverLost CLI (nl) - one entry point for the NeverLost instrument.

  nl help                 overview of every command
  nl help <command>       details for one command

Runs on Windows PowerShell 5.1 and PowerShell 7 (Windows, Linux, macOS). From Windows use nl.cmd in the
repository root, or the double-click launchers (*.cmd) next to it.
#>
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$NL_CLI_VERSION = "1.0.0"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
. (Join-Path $ScriptsDir "_lib_neverlost_host_v1.ps1")
. (Join-Path $ScriptsDir "_lib_neverlost_v1.ps1")
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------------------------------
# output helpers
# ---------------------------------------------------------------------------------------------------
$script:NL_Problems = New-Object System.Collections.Generic.List[string]
$script:NL_Warnings = New-Object System.Collections.Generic.List[string]

function Say([string]$t){ Write-Host $t }
function Head([string]$t){ Write-Host ""; Write-Host ("== " + $t) -ForegroundColor Cyan }
function Ok([string]$t){ Write-Host ("  [ OK ] " + $t) -ForegroundColor Green }
function Warn([string]$t){ Write-Host ("  [WARN] " + $t) -ForegroundColor Yellow; [void]$script:NL_Warnings.Add($t) }
function Bad([string]$t){ Write-Host ("  [FAIL] " + $t) -ForegroundColor Red; [void]$script:NL_Problems.Add($t) }
function Info([string]$t){ Write-Host ("         " + $t) -ForegroundColor Gray }

function Usage-Exit([string]$msg){
  Write-Host ("nl: " + $msg) -ForegroundColor Red
  Write-Host "Run 'nl help' for the list of commands."
  exit 2
}

# ---------------------------------------------------------------------------------------------------
# argument parsing: positional words, --name value, --flag
# ---------------------------------------------------------------------------------------------------
$script:StagedByNl = $false
$script:Pos = New-Object System.Collections.Generic.List[string]
$script:Opt = @{}
$script:Flags = @{}
$knownFlags = @("strict","fixture","skip-tests","online","yes","help","h","no-pull","allow-main")
for($i = 0; $i -lt $args.Count; $i++){
  $a = [string]$args[$i]
  if($a -match '^--?([A-Za-z][A-Za-z0-9\-]*)$'){
    $name = $matches[1].ToLowerInvariant()
    if($knownFlags -contains $name){ $script:Flags[$name] = $true; continue }
    if($i + 1 -ge $args.Count){ Usage-Exit ("option --" + $name + " needs a value") }
    $script:Opt[$name] = [string]$args[$i + 1]
    $i++
    continue
  }
  [void]$script:Pos.Add($a)
}
function OptVal([string]$n,[string]$default = ""){ if($script:Opt.ContainsKey($n)){ return [string]$script:Opt[$n] }; return $default }
function Need([string]$n){ $v = OptVal $n; if([string]::IsNullOrWhiteSpace($v)){ Usage-Exit ("missing --" + $n) }; return $v }
function Flag([string]$n){ return $script:Flags.ContainsKey($n) }

# ---------------------------------------------------------------------------------------------------
# running the canonical scripts (live output, exit code returned)
# ---------------------------------------------------------------------------------------------------
$script:PSExe = $null
function Ps(){ if($null -eq $script:PSExe){ $script:PSExe = NL-ResolvePsHost }; return $script:PSExe }

function Run-Script([string]$Name,[string[]]$ScriptArgs){
  $path = Join-Path $ScriptsDir $Name
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ throw ("SCRIPT_MISSING: " + $path) }
  & (Ps) -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $path @ScriptArgs | Out-Host
  return [int]$LASTEXITCODE
}

function Capture-Script([string]$Name,[string[]]$ScriptArgs){
  $io = Join-Path (Join-Path $RepoRoot ".scratch") "cli"
  $id = [Guid]::NewGuid().ToString("N")
  $r = NL-InvokePsFile -File (Join-Path $ScriptsDir $Name) -PsHost (Ps) -Arguments $ScriptArgs -StdoutPath (Join-Path $io ($id + ".out")) -StderrPath (Join-Path $io ($id + ".err"))
  Remove-Item -LiteralPath (Join-Path $io ($id + ".out")),(Join-Path $io ($id + ".err")) -Force -ErrorAction SilentlyContinue
  return $r
}

$script:GitExe = $null
function Git([string[]]$GitArgs){
  if($null -eq $script:GitExe){ $script:GitExe = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
  $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { $out = & $script:GitExe -C $RepoRoot @GitArgs 2>&1 } finally { $ErrorActionPreference = $prevEap }
  return [pscustomobject]@{ Code = [int]$LASTEXITCODE; Text = ((@($out) | ForEach-Object { [string]$_ }) -join "`n").Trim() }
}

function Have([string]$cmd){ return ($null -ne (Get-Command $cmd -CommandType Application -ErrorAction SilentlyContinue)) }

function First-Error([string]$text){
  foreach($l in ($text -split "`n")){
    $m = [regex]::Match($l, '(TRUST_[A-Z_:]+[^\s]*|LEDGER_[A-Z_:]+|SIGN_[A-Z_]+|VERIFY_[A-Z_]+|[A-Z_]+_FAIL[A-Z_]*|LIVE_TRUST_MISSING)')
    if($m.Success){ return $l.Trim() }
  }
  $lines = @($text -split "`n" | Where-Object { $_.Trim().Length -gt 0 })
  if($lines.Count -gt 0){ return $lines[$lines.Count - 1].Trim() }
  return ""
}

# ---------------------------------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------------------------------
$script:Help = [ordered]@{
  "status" = @"
nl status
  One-screen summary: authority session, trust root, signer list, ledger, git branch and sync state.
  Read-only.
"@
  "authority" = @"
nl authority status|start|confirm|end
  Operator authority lifecycle (scripts/neverlost_cli_v1.ps1).
  start and confirm verify the trust root first and refuse on malformed, missing, mismatched or stale
  trust. end always works so you can leave the active state.
  Exit codes: 0 ok, 1 refused/failed, 2 start refused because a session is already active.
  Shortcuts: nl start | nl confirm | nl end
"@
  "trust" = @"
nl trust verify [--bundle <file>]
  Verify the trust bundle fail-closed (schema, closed role set, key files and hashes, namespaces) and
  check it against proofs/trust/expected_principal0.txt and expected_namespaces_principal0.txt.
  --bundle verifies another bundle (for example a product bundle) without the expectation files.

nl trust show
  List the principals, key ids and namespaces in the trust bundle.
"@
  "signers" = @"
nl signers make
  Rebuild proofs/trust/allowed_signers from the verified trust bundle.

nl signers check
  Confirm proofs/trust/allowed_signers is exactly what the trust bundle derives.

nl signers export --out <file> [--namespace <ns>] [--consumer <service>] [--bundle <file>]
  Publish a signer list for another service (for example LawVM). With --namespace only keys granted
  that namespace are exported. Writes a receipt.
"@
  "sign" = @"
nl sign --file <file> --namespace <ns> --principal <principal> --key-id <key_id> --key <private key> [--out <sig>]
  Identity-bound signing: refuses unless the trust bundle grants that principal, key id and namespace
  and the private key matches the trusted public key. Never overwrites a signature. Writes a receipt.
"@
  "verify" = @"
nl verify --file <file> --sig <sig> --namespace <ns> --principal <principal>
  Verify a detached SSHSIG signature against the current trusted signer list. Writes a receipt.
"@
  "ledger" = @"
nl ledger verify [--strict] [--path <file>]
  Verify the receipt ledger (proofs/receipts/neverlost.ndjson): encoding, every line, authority receipt
  fields, and the session provenance chain. Historic anomalies are listed; --strict fails on them.
"@
  "test" = @"
nl test [--fixture]
  Run every portable proof lane (parse gate, trust verify, ledger verify, CLI selftest, 12 CLI vectors,
  trust/signature/ledger vectors, authority lifecycle, admin plugin). Lanes run in sandbox copies and
  never touch the live session or ledger. --fixture uses the committed fixture trust root (clean clones).

nl test tier0     Tier-0 full green (writes evidence under proofs/receipts and a run receipt)
nl test freeze    Run all-green twice and require identical results
nl test workbench Type-check and build the frontend, cargo check and cargo test the backend
"@
  "identity" = @"
nl identity [--online]
  Check every identity this repository depends on:
  - Git: user.name / user.email set, origin points at the ecosystem owner's account
    (Constellation registry/owner.json when found, else .constellation/REMOTE_WORK.md)
  - GitHub (--online): origin reachable with your credentials
  - Trust: bundle verifies, expected principal present, allowed_signers current
  - Keys: each trusted public key file present; private half present on this machine and matching;
    keys on disk that the bundle does not trust; no private key tracked by git
  - Session: the active session's principal is still trusted
"@
  "doctor" = @"
nl doctor
  Check the tools and ecosystem files: PowerShell host, ssh-keygen with -Y sign/verify, git, node/npm,
  cargo, the .constellation copies, and that project.contract.json agrees with the registry.
"@
  "constellation" = @"
nl constellation
  What NeverLost needs from Constellation and from other projects: registry role and dependencies,
  downstream consumers and the contracts they use, managed-file drift, and every open proposal.
"@
  "update" = @"
nl update [--no-pull] [--skip-tests] [--fixture]
  Bring this checkout fully up to date and prove it:
  1. git fetch, then fast-forward the current branch (never merges or rewrites; stops if diverged)
  2. verify the trust bundle; rebuild allowed_signers if it is stale
  3. verify the receipt ledger
  4. run every proof lane (nl test)
"@
  "push" = @"
nl push [--message "<commit message>"] [--skip-tests] [--allow-main] [--yes]
  Commit and push the current branch safely:
  - refuses on a detached HEAD, and on main/master unless --allow-main
  - stages source changes only (never proofs/, osf/, runtime/, .scratch/), refuses if anything staged
    looks like a private key or secret
  - asks for a commit message when there are changes and --message is not given
  - runs every proof lane first (unless --skip-tests)
  - fast-forwards from origin if needed, then pushes; never force-pushes
"@
  "git" = @"
nl git status | pull | push
  status: branch, upstream, ahead/behind, uncommitted files.  pull: fetch + fast-forward only.
  push: same as 'nl push'.
"@
  "version" = @"
nl version
  Print the CLI version and the tool versions in use.
"@
}

function Show-Help([string]$topic){
  if(-not [string]::IsNullOrWhiteSpace($topic)){
    $t = $topic.ToLowerInvariant()
    if($t -in @("start","confirm","end")){ $t = "authority" }
    if($script:Help.Contains($t)){ Say ""; Say $script:Help[$t]; return }
    Usage-Exit ("no help for '" + $topic + "'")
  }
  Say ""
  Say ("NeverLost CLI " + $NL_CLI_VERSION + " - identity, signing, trust and provenance authority")
  Say ""
  Say "Usage: nl <command> [options]        nl help <command> for details"
  Say ""
  Say "Everyday"
  Say "  status                       summary of authority, trust, ledger and git"
  Say "  update                       pull (fast-forward), check trust and ledger, run all tests"
  Say "  push                         commit (asks for a message), test, push - never force"
  Say "  identity                     check git, GitHub, trust, key and session identities"
  Say "  test [tier0|freeze|workbench] run the proof lanes"
  Say ""
  Say "Authority"
  Say "  authority status|start|confirm|end   (shortcuts: start, confirm, end)"
  Say ""
  Say "Trust and signing"
  Say "  trust verify | trust show"
  Say "  signers make | check | export --out <file> [--namespace <ns>] [--consumer <svc>]"
  Say "  sign --file --namespace --principal --key-id --key [--out]"
  Say "  verify --file --sig --namespace --principal"
  Say "  ledger verify [--strict]"
  Say ""
  Say "Ecosystem and tools"
  Say "  constellation                what NeverLost needs from Constellation and other projects"
  Say "  doctor                       tool and ecosystem-file checks"
  Say "  git status|pull|push"
  Say "  version"
  Say ""
  Say "Environment: NEVERLOST_PS_HOST, NEVERLOST_SSH_KEYGEN, NEVERLOST_TRUST_SOURCE=live|fixture"
  Say ("Repository: " + $RepoRoot)
}

# ---------------------------------------------------------------------------------------------------
# shared checks
# ---------------------------------------------------------------------------------------------------
function Trust-Paths(){
  $t = Join-Path (Join-Path $RepoRoot "proofs") "trust"
  return @{
    Dir = $t
    Bundle = Join-Path $t "trust_bundle.json"
    Signers = Join-Path $t "allowed_signers"
    Principal = Join-Path $t "expected_principal0.txt"
    Namespaces = Join-Path $t "expected_namespaces_principal0.txt"
    Session = Join-Path (Join-Path (Join-Path $RepoRoot "proofs") "receipts") "active_authority_session.json"
    Ledger = Join-Path (Join-Path (Join-Path $RepoRoot "proofs") "receipts") "neverlost.ndjson"
  }
}


function Check-Trust([bool]$Quiet){
  $p = Trust-Paths
  if(-not (Test-Path -LiteralPath $p.Bundle -PathType Leaf)){ Bad "trust bundle missing (proofs/trust/trust_bundle.json)"; return $null }
  $r = Capture-Script "verify_trust_bundle_v1.ps1" @("-RepoRoot",$RepoRoot,"-UseExpectedFiles")
  if($r.ExitCode -ne 0){ Bad ("trust bundle: " + (First-Error ($r.Stdout + "`n" + $r.Stderr))); return $null }
  $lines = @($r.Stdout -split "`n" | Where-Object { $_ -match '^(SIGNER=|TRUST_BUNDLE_SHA256=)' })
  Ok "trust bundle verifies against the expected principal and namespaces"
  if(-not $Quiet){ foreach($l in $lines){ Info $l } }
  return $lines
}

function Check-Signers(){
  try {
    $entries = NL-AssertTrustBundleV1 -RepoRoot $RepoRoot
    NL-AssertAllowedSignersCurrentV1 $RepoRoot $entries
    Ok "allowed_signers is current"
    return $true
  } catch {
    $m = $_.Exception.Message
    if($m -like "TRUST_ALLOWED_SIGNERS_STALE*" -or $m -like "TRUST_ALLOWED_SIGNERS_MISSING*"){ Warn "allowed_signers is stale or missing (fix: nl signers make)"; return $false }
    Bad ("allowed_signers: " + $m); return $false
  }
}

function Check-Ledger([bool]$Strict){
  $p = Trust-Paths
  if(-not (Test-Path -LiteralPath $p.Ledger -PathType Leaf)){ Warn "no receipt ledger in this checkout"; return }
  $a = @("-RepoRoot",$RepoRoot)
  if($Strict){ $a += "-Strict" }
  $r = Capture-Script "verify_receipt_ledger_v1.ps1" $a
  if($r.ExitCode -ne 0){ Bad ("ledger: " + (First-Error ($r.Stdout + "`n" + $r.Stderr))); return }
  $lines = [regex]::Match($r.Stdout,'LEDGER_LINES=(\d+)').Groups[1].Value
  $anom = [regex]::Match($r.Stdout,'ANOMALIES=(\d+)')
  if($anom.Success){ Ok ("ledger verifies (" + $lines + " lines, " + $anom.Groups[1].Value + " known historic anomalies)") } else { Ok ("ledger verifies (" + $lines + " lines)") }
}

function Session-Info(){
  $p = Trust-Paths
  if(-not (Test-Path -LiteralPath $p.Session -PathType Leaf)){ return $null }
  try { $o = ([System.IO.File]::ReadAllText($p.Session) | ConvertFrom-Json) } catch { return $null }
  foreach($tp in @("started_utc","ended_utc")){
    $pp = $o.PSObject.Properties[$tp]
    if($null -ne $pp -and $pp.Value -is [datetime]){ $pp.Value = $pp.Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
  }
  return $o
}

function Expected-Owner(){
  # Constellation's registry/owner.json is the source of truth; look for it near this repository.
  $dir = Split-Path -Parent $RepoRoot
  for($i = 0; $i -lt 5 -and $dir; $i++){
    foreach($cand in @((Join-Path $dir "registry\owner.json"), (Join-Path (Join-Path $dir "constellation") "registry\owner.json"), (Join-Path (Join-Path $dir "Constellation") "registry\owner.json"))){
      if(Test-Path -LiteralPath $cand -PathType Leaf){
        try {
          $o = [System.IO.File]::ReadAllText($cand) | ConvertFrom-Json
          foreach($n in @("owner","github_owner","login","name")){
            $pp = $o.PSObject.Properties[$n]
            if($null -ne $pp -and -not [string]::IsNullOrWhiteSpace([string]$pp.Value)){ return @{ Owner = [string]$pp.Value; Source = $cand } }
          }
        } catch { }
      }
    }
    $dir = Split-Path -Parent $dir
  }
  $rw = Join-Path (Join-Path $RepoRoot ".constellation") "REMOTE_WORK.md"
  if(Test-Path -LiteralPath $rw -PathType Leaf){
    $m = [regex]::Match([System.IO.File]::ReadAllText($rw), 'currently `([^`]+)`')
    if($m.Success){ return @{ Owner = $m.Groups[1].Value; Source = ".constellation/REMOTE_WORK.md" } }
  }
  return $null
}

function Git-State(){
  if(-not (Have "git")){ return $null }
  $b = Git @("rev-parse","--abbrev-ref","HEAD")
  if($b.Code -ne 0){ return $null }
  $up = Git @("rev-parse","--abbrev-ref","--symbolic-full-name","@{u}")
  $ahead = 0; $behind = 0
  if($up.Code -eq 0){
    $c = Git @("rev-list","--left-right","--count",("HEAD..." + $up.Text))
    if($c.Code -eq 0){ $parts = $c.Text -split '\s+'; $ahead = [int]$parts[0]; $behind = [int]$parts[1] }
  }
  $st = Git @("status","--porcelain","--untracked-files=normal","--",".",":!proofs",":!osf",":!runtime")
  $dirty = @($st.Text -split "`n" | Where-Object { $_.Trim().Length -gt 0 })
  return [pscustomobject]@{ Branch = $b.Text; Upstream = $(if($up.Code -eq 0){ $up.Text } else { "" }); Ahead = $ahead; Behind = $behind; Dirty = $dirty }
}

function Finish([string]$okToken){
  Say ""
  if($script:NL_Problems.Count -gt 0){
    Write-Host ("RESULT: " + $script:NL_Problems.Count + " problem(s), " + $script:NL_Warnings.Count + " warning(s)") -ForegroundColor Red
    exit 1
  }
  if($script:NL_Warnings.Count -gt 0){ Write-Host ("RESULT: OK with " + $script:NL_Warnings.Count + " warning(s)") -ForegroundColor Yellow }
  else { Write-Host "RESULT: OK" -ForegroundColor Green }
  if($okToken){ Say $okToken }
  exit 0
}

# ---------------------------------------------------------------------------------------------------
# commands
# ---------------------------------------------------------------------------------------------------
function Cmd-Status(){
  Head "Authority"
  $s = Session-Info
  if($null -eq $s){ Info "no session recorded" }
  else {
    $active = $false
    if($s.PSObject.Properties["active"]){ $active = [bool]$s.active }
    $sid = [string]$s.session_id
    if($active){ Ok ("ACTIVE  principal=" + [string]$s.principal + "  session=" + $sid.Substring(0,[Math]::Min(12,$sid.Length)) + "  since " + [string]$s.started_utc) }
    else { Info ("INACTIVE  last principal=" + [string]$s.principal + "  ended " + $(if($s.PSObject.Properties["ended_utc"]){ [string]$s.ended_utc } else { "" })) }
  }
  Head "Trust"
  [void](Check-Trust $false)
  [void](Check-Signers)
  Head "Ledger"
  Check-Ledger $false
  Head "Git"
  $g = Git-State
  if($null -eq $g){ Warn "git not available or not a repository" }
  else {
    Info ("branch " + $g.Branch + $(if($g.Upstream){ " -> " + $g.Upstream + "  ahead " + $g.Ahead + ", behind " + $g.Behind } else { " (no upstream yet; nl push sets it)" }))
    if($g.Dirty.Count -gt 0){ Warn ($g.Dirty.Count.ToString() + " uncommitted change(s) (nl push to commit and push)") } else { Ok "working tree clean" }
    if($g.Behind -gt 0){ Warn "behind origin (nl update)" }
  }
  Finish ""
}

function Cmd-Authority([string]$action){
  if([string]::IsNullOrWhiteSpace($action)){ $action = "status" }
  if(@("status","start","confirm","end") -notcontains $action){ Usage-Exit ("unknown authority action '" + $action + "'") }
  $code = Run-Script "neverlost_cli_v1.ps1" @("-RepoRoot",$RepoRoot,"-Area","authority","-Action",$action)
  exit $code
}

function Cmd-Trust([string]$sub){
  switch($sub){
    "verify" {
      $b = OptVal "bundle"
      if($b){ exit (Run-Script "verify_trust_bundle_v1.ps1" @("-RepoRoot",$RepoRoot,"-TrustBundlePath",(Resolve-Path -LiteralPath $b).Path)) }
      exit (Run-Script "verify_trust_bundle_v1.ps1" @("-RepoRoot",$RepoRoot,"-UseExpectedFiles"))
    }
    "show" { exit (Run-Script "show_identity_v1.ps1" @("-RepoRoot",$RepoRoot)) }
    default { Usage-Exit "use: nl trust verify | nl trust show" }
  }
}

function Cmd-Signers([string]$sub){
  switch($sub){
    "make" { exit (Run-Script "make_allowed_signers_v1.ps1" @("-RepoRoot",$RepoRoot)) }
    "check" { Head "Signer list"; [void](Check-Signers); Finish "" }
    "export" {
      $a = @("-RepoRoot",$RepoRoot,"-OutPath",(Need "out"))
      if(OptVal "namespace"){ $a += @("-Namespace",(OptVal "namespace")) }
      if(OptVal "consumer"){ $a += @("-Consumer",(OptVal "consumer")) }
      if(OptVal "bundle"){ $a += @("-TrustBundlePath",(OptVal "bundle")) }
      exit (Run-Script "export_allowed_signers_v1.ps1" $a)
    }
    default { Usage-Exit "use: nl signers make | check | export --out <file>" }
  }
}

function Cmd-Sign(){
  $a = @("-RepoRoot",$RepoRoot,"-TargetPath",(Need "file"),"-SigNamespace",(Need "namespace"),"-Principal",(Need "principal"),"-KeyId",(Need "key-id"),"-PrivKeyPath",(Need "key"))
  if(OptVal "out"){ $a += @("-OutSigPath",(OptVal "out")) }
  exit (Run-Script "sign_file_v1.ps1" $a)
}

function Cmd-Verify(){
  exit (Run-Script "verify_sig_v1.ps1" @("-RepoRoot",$RepoRoot,"-TargetPath",(Need "file"),"-SigPath",(Need "sig"),"-SigNamespace",(Need "namespace"),"-Principal",(Need "principal")))
}

function Cmd-Ledger([string]$sub){
  if($sub -ne "verify"){ Usage-Exit "use: nl ledger verify [--strict] [--path <file>]" }
  $a = @("-RepoRoot",$RepoRoot)
  if(OptVal "path"){ $a += @("-LedgerPath",(OptVal "path")) }
  if(Flag "strict"){ $a += "-Strict" }
  exit (Run-Script "verify_receipt_ledger_v1.ps1" $a)
}

function Run-AllLanes([bool]$Fixture){
  $prev = $env:NEVERLOST_TRUST_SOURCE
  if($Fixture){ $env:NEVERLOST_TRUST_SOURCE = "fixture" }
  try { $code = Run-Script "_RUN_neverlost_ci_v1.ps1" @("-RepoRoot",$RepoRoot) } finally { $env:NEVERLOST_TRUST_SOURCE = $prev }
  return $code
}

function Cmd-Test([string]$sub){
  switch($sub){
    "" { exit (Run-AllLanes (Flag "fixture")) }
    "tier0" { exit (Run-Script "_RUN_neverlost_tier0_full_green_v1.ps1" @("-RepoRoot",$RepoRoot)) }
    "freeze" { exit (Run-Script "_RUN_neverlost_tier0_freeze_v1.ps1" @("-RepoRoot",$RepoRoot)) }
    "workbench" {
      Push-Location $RepoRoot
      try {
        foreach($step in @(@("npm","ci"),@("npx","tsc","--noEmit"),@("npm","run","build"),@("cargo","check","--manifest-path","src-tauri/Cargo.toml"),@("cargo","test","--manifest-path","src-tauri/Cargo.toml"))){
          Head ($step -join " ")
          $exe = $step[0]; $rest = @($step | Select-Object -Skip 1)
          if(-not (Have $exe)){ Bad ($exe + " not found"); continue }
          $app = (Get-Command $exe -CommandType Application | Select-Object -First 1).Source
          & $app @rest | Out-Host
          if($LASTEXITCODE -ne 0){ Bad (($step -join " ") + " failed (exit " + $LASTEXITCODE + ")") } else { Ok ($step -join " ") }
        }
      } finally { Pop-Location }
      Finish "NEVERLOST_WORKBENCH_GREEN"
    }
    default { Usage-Exit "use: nl test [--fixture] | nl test tier0 | freeze | workbench" }
  }
}

function Cmd-Identity(){
  Head "Git identity"
  if(-not (Have "git")){ Bad "git is not installed or not on PATH" }
  else {
    $n = Git @("config","user.name"); $e = Git @("config","user.email")
    if($n.Code -ne 0 -or -not $n.Text){ Bad "git user.name is not set (git config --global user.name ""Your Name"")" } else { Ok ("user.name  = " + $n.Text) }
    if($e.Code -ne 0 -or -not $e.Text){ Bad "git user.email is not set (git config --global user.email you@example.com)" } else { Ok ("user.email = " + $e.Text) }
    $o = Git @("remote","get-url","origin")
    if($o.Code -ne 0){ Bad "no 'origin' remote" }
    else {
      $m = [regex]::Match($o.Text, 'github\.com[:/]+([^/]+)/([^/\s]+?)(\.git)?$')
      $exp = Expected-Owner
      if(-not $m.Success){ Warn ("origin is not a GitHub URL: " + $o.Text) }
      else {
        $owner = $m.Groups[1].Value
        Info ("origin = " + $o.Text)
        if($null -eq $exp){ Warn "could not find the ecosystem owner (Constellation registry/owner.json)" }
        elseif($owner -ieq $exp.Owner){ Ok ("origin owner '" + $owner + "' matches the ecosystem owner (" + $exp.Source + ")") }
        elseif($owner -ieq "ScrappyHub"){ Warn ("origin uses the former account name 'ScrappyHub'; the owner is now '" + $exp.Owner + "' (works through GitHub's redirect; update with: git remote set-url origin https://github.com/" + $exp.Owner + "/" + $m.Groups[2].Value + ".git)") }
        else { Bad ("origin owner '" + $owner + "' is not the ecosystem owner '" + $exp.Owner + "' (" + $exp.Source + ")") }
      }
      if(Flag "online"){
        $ls = Git @("ls-remote","--heads","origin")
        if($ls.Code -eq 0){ Ok "GitHub: origin reachable with your credentials" } else { Bad ("GitHub: cannot reach origin: " + (First-Error $ls.Text)) }
      } else { Info "GitHub reachability not checked (add --online)" }
    }
    $tracked = Git @("ls-files","proofs/keys")
    $privTracked = @($tracked.Text -split "`n" | Where-Object { $_ -and $_ -notmatch '\.pub$' -and $_ -notmatch '\.gitkeep$' })
    if($privTracked.Count -gt 0){ Bad ("private key file(s) tracked by git: " + ($privTracked -join ", ") + " - rotate the keys") } else { Ok "no private key is tracked by git" }
  }

  Head "Trust identity"
  [void](Check-Trust $false)
  [void](Check-Signers)

  Head "Keys on this machine"
  $p = Trust-Paths
  if(Test-Path -LiteralPath $p.Bundle -PathType Leaf){
    try {
        $entries = @(NL-AssertTrustBundleV1 -RepoRoot $RepoRoot)
      $tb = [System.IO.File]::ReadAllText($p.Bundle) | ConvertFrom-Json
      $trustedPub = @{}
      $ssh = $null
      try { $ssh = NL-ResolveSshKeygen } catch { Warn "ssh-keygen not found; cannot compare private keys" }
      foreach($pr in @($tb.principals)){
        foreach($k in @($pr.keys)){
          $rel = [string]$k.pubkey_path
          $pub = $RepoRoot; foreach($seg in ($rel -split '[\\/]')){ if($seg){ $pub = Join-Path $pub $seg } }
          $trustedPub[[System.IO.Path]::GetFileName($pub)] = $true
          $priv = $pub -replace '\.pub$',''
          if(-not (Test-Path -LiteralPath $priv -PathType Leaf)){ Info ([string]$k.key_id + ": private key not on this machine (fine for verify-only machines)"); continue }
          if($null -eq $ssh){ continue }
          $dr = NL-InvokeNative -Exe $ssh -Arguments @("-y","-P","","-f",$priv) -NullStdin
          $derived = $dr.Output
          if($dr.Code -ne 0){ Warn ([string]$k.key_id + ": private key present but unreadable without a passphrase (or bad permissions)"); continue }
          if((NL-PubkeyCore $derived) -ceq (NL-PubkeyCore ([string]$k.pubkey))){ Ok ([string]$k.key_id + ": private key present and matches the trusted public key") }
          else { Bad ([string]$k.key_id + ": private key does NOT match the trusted public key") }
        }
      }
      $keysDir = Join-Path (Join-Path $RepoRoot "proofs") "keys"
      if(Test-Path -LiteralPath $keysDir -PathType Container){
        foreach($f in @(Get-ChildItem -LiteralPath $keysDir -File -Filter *.pub)){
          if(-not $trustedPub.ContainsKey($f.Name)){ Warn ("key " + $f.Name + " is on disk but not trusted by the bundle (see docs/proposals/0004 item B)") }
          $raw = [System.IO.File]::ReadAllBytes($f.FullName)
          if(([System.Text.Encoding]::ASCII.GetString($raw)).Contains("`r")){ Info ($f.Name + " uses CRLF; keep it byte-exact (proposal 0004 item A)") }
        }
      }
    } catch { Bad ("keys: " + $_.Exception.Message) }
  }

  Head "Session identity"
  $s = Session-Info
  if($null -eq $s){ Info "no session recorded" }
  else {
    $pr = [string]$s.principal
    $active = $false; if($s.PSObject.Properties["active"]){ $active = [bool]$s.active }
    try {
        $entries = @(NL-AssertTrustBundleV1 -RepoRoot $RepoRoot)
      if(@($entries | Where-Object { [string]$_.principal -ceq $pr }).Count -gt 0){ Ok ("session principal " + $pr + " is trusted" + $(if($active){ " (ACTIVE)" } else { " (inactive)" })) }
      elseif($active){ Bad ("ACTIVE session principal " + $pr + " is no longer trusted - end it: nl end") }
      else { Warn ("last session principal " + $pr + " is not in the current bundle") }
    } catch { }
  }
  $profiles = Join-Path (Join-Path $RepoRoot "proofs") "profiles"
  if(Test-Path -LiteralPath $profiles -PathType Container){
    foreach($pf in @(Get-ChildItem -LiteralPath $profiles -Directory)){
      $pj = Join-Path $pf.FullName "profile.json"
      if(Test-Path -LiteralPath $pj -PathType Leaf){
        try { $pv = [string](([System.IO.File]::ReadAllText($pj) | ConvertFrom-Json).principal) } catch { $pv = "" }
        if($pv -cnotmatch '^single-tenant/(owner|org_admin|device_admin|operator|auditor|device_agent|watchtower_authority)/[^\s,"]+$'){ Warn ("profile '" + $pf.Name + "' uses principal '" + $pv + "', outside the v1 format (proposal 0004 item D)") }
      }
    }
  }
  Finish "NEVERLOST_IDENTITY_CHECKED"
}

function Cmd-Doctor(){
  Head "Tools"
  try { $ps = Ps; Ok ("PowerShell host: " + $ps) } catch { Bad $_.Exception.Message }
  Info ("this CLI runs on PowerShell " + $PSVersionTable.PSVersion.ToString() + " (" + $PSVersionTable.PSEdition + ")")
  try {
    $ssh = NL-ResolveSshKeygen
    $txt = (NL-InvokeNative -Exe $ssh -Arguments @("-Y") -NullStdin).Output
    if($txt -match 'unknown option|illegal option'){ Bad ("ssh-keygen at " + $ssh + " has no -Y sign/verify (needs OpenSSH 8.2+)") } else { Ok ("ssh-keygen: " + $ssh) }
  } catch { Bad $_.Exception.Message }
  foreach($t in @("git","node","npm","cargo")){
    if(Have $t){ $app = (Get-Command $t -CommandType Application | Select-Object -First 1).Source; $v = ((NL-InvokeNative -Exe $app -Arguments @("--version")).Output -split "`n")[0]; Ok ($t + ": " + [string]$v) }
    elseif($t -eq "git"){ Bad "git not found" }
    else { Warn ($t + " not found (needed only to build the workbench)") }
  }
  Head "Ecosystem files"
  foreach($f in @("SERVICE_MAP.md","registry.json","AGENT_POLICY.md","SHARED_INVARIANTS.md","REMOTE_WORK.md")){
    $fp = Join-Path (Join-Path $RepoRoot ".constellation") $f
    if(Test-Path -LiteralPath $fp -PathType Leaf){ Ok (".constellation/" + $f) } else { Bad (".constellation/" + $f + " missing (Constellation publish)") }
  }
  Check-ContractDrift
  Finish "NEVERLOST_DOCTOR_OK"
}

function Registry-Self(){
  $rp = Join-Path (Join-Path $RepoRoot ".constellation") "registry.json"
  if(-not (Test-Path -LiteralPath $rp -PathType Leaf)){ return $null }
  $reg = [System.IO.File]::ReadAllText($rp) | ConvertFrom-Json
  foreach($s in @($reg.services)){ if([string]$s.id -eq "neverlost"){ return @{ Registry = $reg; Self = $s } } }
  return $null
}

function Check-ContractDrift(){
  $r = Registry-Self
  if($null -eq $r){ Bad "neverlost not found in .constellation/registry.json"; return }
  $pc = Join-Path $RepoRoot "project.contract.json"
  if(-not (Test-Path -LiteralPath $pc -PathType Leaf)){ Bad "project.contract.json missing"; return }
  $c = [System.IO.File]::ReadAllText($pc) | ConvertFrom-Json
  $regDown = @($r.Self.downstream_users | ForEach-Object { [string]$_ } | Sort-Object)
  $conDown = @($c.ecosystem.downstream_users | ForEach-Object { [string]$_ } | Sort-Object)
  if(($regDown -join ",") -eq ($conDown -join ",")){ Ok "project.contract.json downstream users match the registry" }
  else {
    $missing = @($regDown | Where-Object { $conDown -notcontains $_ })
    Warn ("project.contract.json lists " + $conDown.Count + " downstream users, the registry " + $regDown.Count + " (missing: " + ($missing -join ", ") + ") - Constellation must republish (proposal 0003)")
  }
  if([string]$c.ecosystem.role -eq [string]$r.Self.role -and [string]$c.ecosystem.layer -eq [string]$r.Self.layer){ Ok "role and layer match the registry" } else { Bad "role or layer differs from the registry" }
}

function Cmd-Constellation(){
  $r = Registry-Self
  if($null -eq $r){ Bad "cannot read .constellation/registry.json"; Finish "" }
  $s = $r.Self
  Head ("NeverLost in Constellation (registry " + [string]$r.Registry.registry_version + ")")
  Info ("role:  " + [string]$s.role)
  Info ("layer: " + [string]$s.layer + "   family: " + [string]$s.ecosystem)
  Info ("upstream (what NeverLost depends on): " + $(if(@($s.upstream_services).Count -eq 0){ "none - foundation service" } else { (@($s.upstream_services) -join ", ") }))
  Info ("downstream (" + @($s.downstream_users).Count + "): " + (@($s.downstream_users) -join ", "))

  Head "Consumers and the contracts they use (registry integrations)"
  $map = Join-Path (Join-Path $RepoRoot ".constellation") "SERVICE_MAP.md"
  if(Test-Path -LiteralPath $map -PathType Leaf){
    $published = @("neverlost.trust_bundle.v1","neverlost.allowed_signers.v1","neverlost.allowed_signers.export.v1","neverlost.sig.sign.v1","neverlost.sig.verify.v1","neverlost.receipt.v1")
    foreach($line in [System.IO.File]::ReadAllLines($map)){
      $m = [regex]::Match($line, '^\|\s*([a-z0-9\-]+)\s*\|\s*neverlost\s*\|\s*([a-z\-]+)\s*\|\s*([a-z\-]+)\s*\|\s*([^|]*)\|\s*([^|]*)\|')
      if(-not $m.Success){ continue }
      $consumer = $m.Groups[1].Value; $strength = $m.Groups[2].Value; $contracts = $m.Groups[4].Value.Trim()
      $bad = @()
      foreach($ct in ($contracts -split ',\s*')){ $ct = $ct.Trim(); if($ct -and $ct -ne "None" -and $published -notcontains $ct){ $bad += $ct } }
      $label = ("{0,-20} {1,-14} {2}" -f $consumer, $strength, $contracts)
      if($bad.Count -gt 0){ Warn ($label + "   <- not a published contract name: " + ($bad -join ", ")) }
      elseif($contracts -eq "None"){ Info ($label + "   (consumer has not declared contracts)") }
      else { Ok $label }
    }
    foreach($line in [System.IO.File]::ReadAllLines($map)){
      $m = [regex]::Match($line, '^\|\s*neverlost\s*\|\s*([a-z0-9\-]+)\s*\|\s*([a-z\-]+)\s*\|\s*([a-z\-]+)\s*\|\s*([^|]*)\|')
      if($m.Success){ Warn ("registry records NeverLost consuming " + $m.Groups[1].Value + " (" + $m.Groups[4].Value.Trim() + "); NeverLost has no upstream - Constellation should drop or reverse it") }
    }
  }

  Head "Managed-file drift"
  Check-ContractDrift

  Head "Open proposals (decisions NeverLost is waiting on)"
  $pd = Join-Path (Join-Path $RepoRoot "docs") "proposals"
  foreach($f in @(Get-ChildItem -LiteralPath $pd -File -Filter *.md | Sort-Object Name)){
    $txt = [System.IO.File]::ReadAllText($f.FullName)
    $title = ([regex]::Match($txt,'^#\s*(.+)$',[System.Text.RegularExpressions.RegexOptions]::Multiline)).Groups[1].Value
    $status = ([regex]::Match($txt,'\|\s*Status\s*\|\s*([^|]+)\|')).Groups[1].Value.Trim()
    Info ($f.Name)
    Info ("    " + $title)
    if($status){ Info ("    status: " + $status) }
  }
  Say ""
  Say "Summary of what NeverLost needs:"
  Say "  From Constellation: republish project.contract.json / ECOSYSTEM_INTEGRATION.md with all downstream users;"
  Say "    rename or re-point the contract names flagged above; drop the reverse 'neverlost -> watchtower' edge;"
  Say "    ask Contract Registry to stop writing into runtime/ (proposal 0003)."
  Say "  From you (owner): CRLF key files, a NeverLost root key and signed bundles, the LawVM seal signer,"
  Say "    the profiles feature, GOS role/algorithm requests, enabling CI (proposals 0004, 0005)."
  Say "  From other projects: LawVM picks up the exported signer list; WatchTower takes the archived device"
  Say "    binding test; PacketPuncture, SoteriaVault and Global Workbench confirm which NeverLost contract they read;"
  Say "    Covenant Gate, Live State Surgeon, Podsteps and ShutterWall declare their contracts."
  Finish ""
}

function Cmd-GitStatus(){
  $g = Git-State
  if($null -eq $g){ Bad "not a git repository or git missing"; Finish "" }
  Head "Git"
  Info ("branch:   " + $g.Branch)
  Info ("upstream: " + $(if($g.Upstream){ $g.Upstream } else { "(none)" }))
  Info ("ahead " + $g.Ahead + ", behind " + $g.Behind)
  if($g.Dirty.Count -gt 0){ Warn ("uncommitted:"); foreach($d in $g.Dirty){ Info $d } } else { Ok "clean" }
  Finish ""
}

function Do-Pull([bool]$Required){
  $g = Git-State
  if($null -eq $g){ Bad "not a git repository or git missing"; return $false }
  if($g.Branch -eq "HEAD"){ Bad "detached HEAD; check out a branch first"; return $false }
  $f = Git @("fetch","--prune","origin")
  if($f.Code -ne 0){ if($Required){ Bad ("git fetch failed: " + (First-Error $f.Text)) } else { Warn ("git fetch failed (offline?): " + (First-Error $f.Text)) }; return (-not $Required) }
  $g = Git-State
  if(-not $g.Upstream){
    $remoteBranch = Git @("rev-parse","--verify","--quiet",("refs/remotes/origin/" + $g.Branch))
    if($remoteBranch.Code -ne 0){ Info ("branch " + $g.Branch + " is not on origin yet (nl push publishes it)"); return $true }
    [void](Git @("branch","--set-upstream-to",("origin/" + $g.Branch)))
    $g = Git-State
  }
  if($g.Behind -eq 0){ Ok ("up to date with " + $g.Upstream); return $true }
  if($g.Ahead -gt 0){ Bad ("branch has diverged from " + $g.Upstream + " (" + $g.Ahead + " ahead, " + $g.Behind + " behind); resolve by hand - nothing was changed"); return $false }
  $m = Git @("merge","--ff-only",$g.Upstream)
  if($m.Code -ne 0){ Bad ("fast-forward failed: " + (First-Error $m.Text)); return $false }
  Ok ("fast-forwarded " + $g.Behind + " commit(s) from " + $g.Upstream)
  return $true
}

function Cmd-Update(){
  Head "1. Sync with GitHub"
  if(Flag "no-pull"){ Info "skipped (--no-pull)" } else { [void](Do-Pull $false) }
  Head "2. Trust root"
  $t = Check-Trust $true
  if($null -ne $t){
    if(-not (Check-Signers)){
      $code = Run-Script "make_allowed_signers_v1.ps1" @("-RepoRoot",$RepoRoot)
      if($code -eq 0){ Ok "allowed_signers rebuilt from the verified trust bundle"; $script:NL_Warnings.RemoveAt($script:NL_Warnings.Count - 1) } else { Bad "could not rebuild allowed_signers" }
    }
  }
  Head "3. Receipt ledger"
  Check-Ledger $false
  Head "4. Proof lanes"
  if(Flag "skip-tests"){ Info "skipped (--skip-tests)" }
  else {
    $code = Run-AllLanes (Flag "fixture")
    if($code -ne 0){ Bad "proof lanes failed (see output above)" } else { Ok "all proof lanes green" }
  }
  Finish "NEVERLOST_UPDATE_OK"
}

function Staged-Secrets(){
  $names = Git @("diff","--cached","--name-only")
  $hits = New-Object System.Collections.Generic.List[string]
  foreach($n in @($names.Text -split "`n" | Where-Object { $_ })){
    if($n -match '(^|/)(id_rsa|id_ed25519|[^/]*_ed25519)$' -or $n -match '\.(key|pem|pfx|p12)$' -or $n -match '(^|/)\.env(\.|$)'){ [void]$hits.Add($n); continue }
    $full = Join-Path $RepoRoot $n
    if(Test-Path -LiteralPath $full -PathType Leaf){
      $fi = New-Object System.IO.FileInfo($full)
      if($fi.Length -lt 2000000){
        $txt = [System.IO.File]::ReadAllText($full)
        if($txt -match '-----BEGIN [A-Z ]*PRIVATE KEY-----' -or $txt -match 'ghp_[A-Za-z0-9]{30,}' -or $txt -match 'github_pat_[A-Za-z0-9_]{40,}' -or $txt -match 'AKIA[0-9A-Z]{16}'){ [void]$hits.Add($n) }
      }
    }
  }
  return @($hits.ToArray())
}

function Cmd-Push(){
  $g = Git-State
  if($null -eq $g){ Bad "not a git repository or git missing"; Finish "" }
  if($g.Branch -eq "HEAD"){ Bad "detached HEAD; check out a branch first"; Finish "" }
  if(@("main","master") -contains $g.Branch -and -not (Flag "allow-main")){ Bad ("you are on '" + $g.Branch + "'; work on a branch, or pass --allow-main"); Finish "" }
  Head ("Push " + $g.Branch)

  if($g.Dirty.Count -gt 0){
    Info "changes to commit:"
    foreach($d in $g.Dirty){ Info ("  " + $d) }
    $msg = OptVal "message"
    if([string]::IsNullOrWhiteSpace($msg)){
      if(Flag "yes"){ Bad "--yes needs --message"; Finish "" }
      $msg = Read-Host "Commit message (empty to cancel)"
      if([string]::IsNullOrWhiteSpace($msg)){ Bad "cancelled - nothing committed"; Finish "" }
    }
    $add = Git @("add","-A","--",".",":!proofs",":!osf",":!runtime")
    if($add.Code -ne 0){ [void](Git @("reset","-q")); Bad ("git add failed (nothing staged): " + $add.Text); Finish "" }
    $script:StagedByNl = $true
    try { $secrets = @(Staged-Secrets) } catch { [void](Git @("reset","-q")); Bad ("secret scan failed (nothing staged): " + $_.Exception.Message); Finish "" }
    if($secrets.Count -gt 0){
      [void](Git @("reset","-q"))
      Bad ("refusing to commit files that look like secrets: " + ($secrets -join ", ") + " (unstaged again)"); Finish ""
    }
  }

  if(Flag "skip-tests"){ Warn "proof lanes skipped (--skip-tests)" }
  else {
    Head "Proof lanes"
    $code = Run-AllLanes (Flag "fixture")
    if($code -ne 0){ if($g.Dirty.Count -gt 0){ [void](Git @("reset","-q")) }; Bad "proof lanes failed - nothing committed or pushed"; Finish "" }
    Ok "all proof lanes green"
  }

  if($g.Dirty.Count -gt 0){
    $c = Git @("commit","-q","-m",$msg)
    if($c.Code -ne 0){ [void](Git @("reset","-q")); Bad ("git commit failed (unstaged again): " + $c.Text); Finish "" }
    $script:StagedByNl = $false
    Ok ("committed: " + $msg)
  }

  Head "Sync and push"
  if(-not (Do-Pull $true)){ Finish "" }
  $g = Git-State
  $pushArgs = @("push","origin",$g.Branch)
  if(-not $g.Upstream){ $pushArgs = @("push","-u","origin",$g.Branch) }
  $p = Git $pushArgs
  if($p.Code -ne 0){ Bad ("git push failed: " + (First-Error $p.Text)); Info $p.Text; Finish "" }
  Ok ("pushed " + $g.Branch + " to origin")
  $url = [regex]::Match($p.Text,'https://github\.com/\S+/pull/new/\S+')
  if($url.Success){ Info ("open a pull request: " + $url.Value) }
  Finish "NEVERLOST_PUSH_OK"
}

function Cmd-Version(){
  Say ("nl " + $NL_CLI_VERSION)
  Say ("PowerShell " + $PSVersionTable.PSVersion.ToString() + " " + $PSVersionTable.PSEdition)
  try { Say ("host for scripts: " + (Ps)) } catch { Say "host for scripts: not found" }
  try { Say ("ssh-keygen: " + (NL-ResolveSshKeygen)) } catch { Say "ssh-keygen: not found" }
  if(Have "git"){ $h = Git @("rev-parse","--short","HEAD"); if($h.Code -eq 0){ Say ("commit: " + $h.Text) } }
  exit 0
}

# ---------------------------------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------------------------------
$cmd = ""
if($script:Pos.Count -gt 0){ $cmd = $script:Pos[0].ToLowerInvariant() }
$sub = ""
if($script:Pos.Count -gt 1){ $sub = $script:Pos[1].ToLowerInvariant() }

if($cmd -eq "" -or $cmd -eq "help" -or (Flag "help") -or (Flag "h")){
  $topic = $sub
  if($cmd -ne "" -and $cmd -ne "help"){ $topic = $cmd }
  Show-Help $topic
  exit 0
}

try {
  switch($cmd){
    "status"        { Cmd-Status }
    "authority"     { Cmd-Authority $sub }
    "start"         { Cmd-Authority "start" }
    "confirm"       { Cmd-Authority "confirm" }
    "end"           { Cmd-Authority "end" }
    "trust"         { Cmd-Trust $sub }
    "signers"       { Cmd-Signers $sub }
    "sign"          { Cmd-Sign }
    "verify"        { Cmd-Verify }
    "ledger"        { Cmd-Ledger $sub }
    "test"          { Cmd-Test $sub }
    "identity"      { Cmd-Identity }
    "doctor"        { Cmd-Doctor }
    "constellation" { Cmd-Constellation }
    "update"        { Cmd-Update }
    "push"          { Cmd-Push }
    "git"           { switch($sub){ "status" { Cmd-GitStatus } "pull" { Head "Pull"; [void](Do-Pull $true); Finish "" } "push" { Cmd-Push } default { Usage-Exit "use: nl git status | pull | push" } } }
    "version"       { Cmd-Version }
    default         { Usage-Exit ("unknown command '" + $cmd + "'") }
  }
} catch {
  Write-Host ("nl: " + $_.Exception.Message) -ForegroundColor Red
  if($script:StagedByNl){ [void](Git @("reset","-q")); Write-Host "nl: staged changes were unstaged again; nothing was committed" -ForegroundColor Yellow }
  exit 1
}
