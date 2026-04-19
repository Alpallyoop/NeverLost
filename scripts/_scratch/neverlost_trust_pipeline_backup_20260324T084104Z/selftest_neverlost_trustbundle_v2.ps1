param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ throw "EnsureDir: empty" }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){ EnsureDir (Split-Path -Parent $Path); $t = ($Text -replace "`r`n","`n") -replace "`r","`n"; if(-not $t.EndsWith("`n")){ $t += "`n" }; [System.IO.File]::WriteAllBytes($Path,(New-Object System.Text.UTF8Encoding($false)).GetBytes($t)) }

$RepoRoot   = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath    = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
if(-not (Test-Path -LiteralPath $LibPath -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }
. $LibPath

# --- harden: trust_bundle.json must be readable ---
$TrustDir = Join-Path $RepoRoot "proofs\trust"
$TbPath   = Join-Path $TrustDir "trust_bundle.json"
if(-not (Test-Path -LiteralPath $TbPath -PathType Leaf)){ Die ("MISSING_TRUST_BUNDLE: " + $TbPath) }
$user = "$env:USERDOMAIN\$env:USERNAME"
& icacls $TbPath /inheritance:r | Out-Host
& icacls $TbPath /remove:d "${user}" | Out-Host
& icacls $TbPath /remove:d "Users" | Out-Host
& icacls $TbPath /remove:d "Authenticated Users" | Out-Host
& icacls $TbPath /remove:d "Everyone" | Out-Host
& icacls $TbPath /grant:r "${user}:R" "SYSTEM:F" "Administrators:F" | Out-Host

# 1) entries compat + Count >= 1
$tbInfo  = NL-LoadTrustBundleInfoV1 $RepoRoot
$entries = @(NL-GetTrustBundleEntriesCompat $tbInfo.Obj)
if($entries.Count -lt 1){ Die ("SELFTEST_FAIL: PRINCIPALS_COUNT_LT_1 actual=" + $entries.Count) }

# 2) freeze/verify principal0
$p0 = [string]$entries[0].principal
if([string]::IsNullOrWhiteSpace($p0)){ Die "SELFTEST_FAIL: FIRST_PRINCIPAL_EMPTY" }
$p0ExpectPath = Join-Path $TrustDir "expected_principal0.txt"
if(-not (Test-Path -LiteralPath $p0ExpectPath -PathType Leaf)){ WriteUtf8NoBomLf -Path $p0ExpectPath -Text ($p0 + "`n"); Write-Host ("EXPECTED_PRINCIPAL_WROTE: " + $p0ExpectPath) -ForegroundColor Yellow }
$p0Expected = ((Get-Content -LiteralPath $p0ExpectPath -Encoding UTF8 | Select-Object -First 1) + "").Trim()
if($p0 -ne $p0Expected){ Die ("SELFTEST_FAIL: PRINCIPAL0_MISMATCH actual=" + $p0 + " expected=" + $p0Expected) }

# 3) freeze/verify namespaces0
$nsActual = @($entries[0].namespaces) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_.Length -gt 0 } | Sort-Object -Unique
$nsExpectPath = Join-Path $TrustDir "expected_namespaces_principal0.txt"
if(-not (Test-Path -LiteralPath $nsExpectPath -PathType Leaf)){ WriteUtf8NoBomLf -Path $nsExpectPath -Text ((@($nsActual) -join "`n") + "`n"); Write-Host ("EXPECTED_NAMESPACES_WROTE: " + $nsExpectPath) -ForegroundColor Yellow }
$nsExpected = @(Get-Content -LiteralPath $nsExpectPath -Encoding UTF8) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_.Length -gt 0 } | Sort-Object -Unique
$a = @($nsActual); $b = @($nsExpected)
if($a.Count -ne $b.Count){ Die ("SELFTEST_FAIL: NAMESPACE_COUNT_MISMATCH actual=" + $a.Count + " expected=" + $b.Count) }
for($i=0;$i -lt $a.Count;$i++){ if($a[$i] -ne $b[$i]){ Die ("SELFTEST_FAIL: NAMESPACE_MISMATCH idx=" + $i + " actual=" + $a[$i] + " expected=" + $b[$i]) } }

# 4) allowed_signers write + first line prefix
$asPath = NL-WriteAllowedSignersFromTrust $RepoRoot
if(-not (Test-Path -LiteralPath $asPath -PathType Leaf)){ Die ("SELFTEST_FAIL: ALLOWED_SIGNERS_MISSING_AFTER_WRITE: " + $asPath) }
$first = (Get-Content -LiteralPath $asPath -Encoding UTF8 | Select-Object -First 1)
if($null -eq $first){ Die "SELFTEST_FAIL: ALLOWED_SIGNERS_EMPTY" }
if(-not $first.StartsWith(($p0 + " "), [System.StringComparison]::Ordinal)){ Die ("SELFTEST_FAIL: FIRST_LINE_PREFIX_MISMATCH expected_prefix=" + $p0 + " actual_line=" + $first) }

Write-Host ("SELFTEST_OK: principals=" + $entries.Count + " p0=" + $p0 + " namespaces=" + $a.Count + " allowed_signers=" + $asPath) -ForegroundColor Green
