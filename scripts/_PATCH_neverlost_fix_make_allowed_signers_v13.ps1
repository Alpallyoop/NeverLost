param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("Parse-Gate missing file: " + $Path) }
  $tk=$null; $er=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tk,[ref]$er)
  if ($er -and @($er).Count -gt 0) { Die ("Parse-Gate error in " + $Path + ": " + (($er | Select-Object -First 1 | ForEach-Object { $_.Message }))) }
}

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("Missing RepoRoot: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("Missing scripts dir: " + $ScriptsDir) }
$Make = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"

# ---- backup current ----
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ScriptsDir ("_neverlost_backup_make_allowed_signers_v13_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
if (Test-Path -LiteralPath $Make -PathType Leaf) { Copy-Item -LiteralPath $Make -Destination (Join-Path $BackupDir "make_allowed_signers_v1.ps1.pre_v13") -Force }

$M = New-Object System.Collections.Generic.List[string]
[void]$M.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot)')
[void]$M.Add('$ErrorActionPreference="Stop"' )
[void]$M.Add('Set-StrictMode -Version Latest')
[void]$M.Add('')
[void]$M.Add('function Die([string]$m){ throw $m }')
[void]$M.Add('')
[void]$M.Add('function Write-Utf8NoBomLf([string]$Path,[string]$Text){')
[void]$M.Add('  $dir = Split-Path -Parent $Path')
[void]$M.Add('  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }')
[void]$M.Add('  $t = $Text -replace "`r`n","`n" -replace "`r","`n"' )
[void]$M.Add('  $enc = New-Object System.Text.UTF8Encoding($false)' )
[void]$M.Add('  [System.IO.File]::WriteAllText($Path,$t,$enc)' )
[void]$M.Add('}')
[void]$M.Add('')
[void]$M.Add('function Has-Prop($obj,[string]$name){ if ($null -eq $obj) { return $false } return ($obj.PSObject.Properties.Match($name).Count -gt 0) }')
[void]$M.Add('function Get-Prop($obj,[string]$name){ if (Has-Prop $obj $name) { return $obj.PSObject.Properties[$name].Value } return $null }')
[void]$M.Add('function Coerce-Array($v){ return @(@($v)) }' )
[void]$M.Add('function First-NonEmptyString([object[]]$vals){ foreach($v in @($vals)){ if ($null -eq $v) { continue }; $s=[string]$v; if (-not [string]::IsNullOrWhiteSpace($s)) { return $s } } return "" }')
[void]$M.Add('')
[void]$M.Add('if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("Missing RepoRoot: " + $RepoRoot) }')
[void]$M.Add('$tbPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"' )
[void]$M.Add('$asPath = Join-Path $RepoRoot "proofs\trust\allowed_signers"' )
[void]$M.Add('if (-not (Test-Path -LiteralPath $tbPath -PathType Leaf)) { Die ("Missing trust bundle: " + $tbPath) }')
[void]$M.Add('')
[void]$M.Add('$raw = Get-Content -Raw -LiteralPath $tbPath -Encoding UTF8' )
[void]$M.Add('if ([string]::IsNullOrWhiteSpace($raw)) { Die ("Empty trust bundle: " + $tbPath) }')
[void]$M.Add('$tb = $raw | ConvertFrom-Json' )
[void]$M.Add('if ($null -eq $tb) { Die ("Failed to parse trust bundle JSON: " + $tbPath) }')
[void]$M.Add('')
[void]$M.Add('# locate keys array safely' )
[void]$M.Add('$keys = $null' )
[void]$M.Add('if (Has-Prop $tb "keys") { $keys = Coerce-Array (Get-Prop $tb "keys") }' )
[void]$M.Add('if (($null -eq $keys -or $keys.Count -lt 1) -and (Has-Prop $tb "trust")) { $t = Get-Prop $tb "trust"; if (Has-Prop $t "keys") { $keys = Coerce-Array (Get-Prop $t "keys") } }' )
[void]$M.Add('if (($null -eq $keys -or $keys.Count -lt 1) -and (Has-Prop $tb "trust_bundle")) { $t = Get-Prop $tb "trust_bundle"; if (Has-Prop $t "keys") { $keys = Coerce-Array (Get-Prop $t "keys") } }' )
[void]$M.Add('if ($null -eq $keys -or $keys.Count -lt 1) { foreach($alt in @("signers","trusted_keys","allowed_keys")){ if (Has-Prop $tb $alt) { $keys = Coerce-Array (Get-Prop $tb $alt); break } } }' )
[void]$M.Add('if ($null -eq $keys -or $keys.Count -lt 1) { $top=@($tb.PSObject.Properties.Name) -join ","; $trustProps=""; if (Has-Prop $tb "trust") { $trustProps="; trust={" + (@((Get-Prop $tb "trust").PSObject.Properties.Name) -join ",") + "}" }; $tbProps=""; if (Has-Prop $tb "trust_bundle") { $tbProps="; trust_bundle={" + (@((Get-Prop $tb "trust_bundle").PSObject.Properties.Name) -join ",") + "}" }; Die ("Could not locate keys array in trust_bundle.json. Top-level props={" + $top + "}" + $trustProps + $tbProps) }' )
[void]$M.Add('')
[void]$M.Add('$lines = New-Object System.Collections.Generic.List[string]' )
[void]$M.Add('foreach($k in $keys){' )
[void]$M.Add('  $principal = First-NonEmptyString @((Get-Prop $k "principal"),(Get-Prop $k "signer_identity"),(Get-Prop $k "identity"),(Get-Prop $k "id"))' )
[void]$M.Add('  $pubkey = First-NonEmptyString @((Get-Prop $k "public_key"),(Get-Prop $k "publicKey"),(Get-Prop $k "pubkey"),(Get-Prop $k "pub_key"))' )
[void]$M.Add('  $nsRaw = $null; foreach($n in @("namespaces","namespace","ns")){ if (Has-Prop $k $n) { $nsRaw = Get-Prop $k $n; break } }' )
[void]$M.Add('  if ([string]::IsNullOrWhiteSpace($principal)) { Die "trust_bundle key missing principal (principal/signer_identity/identity/id)" }' )
[void]$M.Add('  if ([string]::IsNullOrWhiteSpace($pubkey)) { Die ("trust_bundle key for principal '" + $principal + "' missing public_key (public_key/publicKey/pubkey/pub_key)") }' )
[void]$M.Add('  $ns = @(@($nsRaw) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })' )
[void]$M.Add('  if ($ns.Count -gt 0) { $opt = "namespaces=`"" + (($ns | ForEach-Object { $_ -replace "`"","" } ) -join ",") + "`""; [void]$lines.Add(($principal + " " + $opt + " " + $pubkey).Trim()) } else { [void]$lines.Add(($principal + " " + $pubkey).Trim()) }' )
[void]$M.Add('}' )
[void]$M.Add('')
[void]$M.Add('$sorted = $lines.ToArray() | Sort-Object' )
[void]$M.Add('Write-Utf8NoBomLf $asPath (($sorted -join "`n") + "`n")' )
[void]$M.Add('Write-Host ("OK: wrote allowed_signers => " + $asPath) -ForegroundColor Green' )

$makeText = ($M.ToArray() -join "`n") + "`n"
Write-Utf8NoBomLf $Make $makeText
Parse-GateFile $Make

# hard verify NL-WriteAllowedSigners is gone
$hits = Select-String -LiteralPath $Make -Pattern "NL-WriteAllowedSigners" -SimpleMatch -ErrorAction SilentlyContinue
if ($hits) { Die ("FAIL: make_allowed_signers still references NL-WriteAllowedSigners at: " + ($hits | Select-Object -First 1 | ForEach-Object { $_.Path + ":" + $_.LineNumber })) }

Write-Host ("OK: patch v13 complete. Backup at: " + $BackupDir) -ForegroundColor Green
