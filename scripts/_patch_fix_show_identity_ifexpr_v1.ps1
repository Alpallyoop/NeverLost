param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$outPath = Join-Path $RepoRoot "scripts\show_identity_v1.ps1"
$libRel  = "scripts\_lib_neverlost_v1.ps1"
$libAbs  = Join-Path $RepoRoot $libRel
if (-not (Test-Path -LiteralPath $libAbs)) { throw "Missing lib: $libAbs" }

$text = @()
$text += 'param([Parameter(Mandatory=$true)][string]$RepoRoot)'
$text += '$ErrorActionPreference="Stop"'
$text += 'Set-StrictMode -Version Latest'
$text += '. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")'
$text += ''
$text += '$trust = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"'
$text += '$as    = Join-Path $RepoRoot "proofs\trust\allowed_signers"'
$text += '$rcpt  = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"'
$text += ''
$text += '$tb = NL-LoadTrustBundle $trust'
$text += ''
$text += '$asHash = ""'
$text += 'if (Test-Path -LiteralPath $as) { $asHash = NL-Sha256HexPath $as }'
$text += ''
$text += 'Write-Host "NeverLost v1 - Identity Layer (Watchtower contract)"'
$text += 'Write-Host ("trust_bundle_sha256    : " + (NL-Sha256HexPath $trust))'
$text += 'Write-Host ("allowed_signers_sha256 : " + $asHash)'
$text += 'Write-Host ("principals_count       : " + @($tb.principals).Count)'
$text += 'Write-Host ""'
$text += ''
$text += 'foreach($p in (@($tb.principals) | Sort-Object principal)) {'
$text += '  Write-Host ("principal: " + $p.principal)'
$text += '  foreach($k in (@($p.keys) | Sort-Object key_id)) {'
$text += '    Write-Host ("  key_id     : " + $k.key_id)'
$text += '    Write-Host ("  alg        : " + $k.alg)'
$text += '    Write-Host ("  pubkey_path: " + $k.pubkey_path)'
$text += '    Write-Host ("  namespaces : " + ((@($k.namespaces) | Sort-Object) -join ", "))'
$text += '  }'
$text += '  Write-Host ""'
$text += '}'
$text += ''
$text += 'NL-WriteReceipt $rcpt @{'
$text += '  schema="neverlost.receipt.v1"'
$text += '  time_utc=(Get-Date).ToUniversalTime().ToString("o")'
$text += '  action="show_identity"'
$text += '  ok=$true'
$text += '  hashes=@{'
$text += '    trust_bundle_sha256=(NL-Sha256HexPath $trust)'
$text += '    allowed_signers_sha256=$asHash'
$text += '  }'
$text += '}'

$fixed = ($text -join "`n") + "`n"
[System.IO.File]::WriteAllBytes($outPath, ([System.Text.UTF8Encoding]::new($false)).GetBytes($fixed))
Write-Host ("OK: rewrote " + $outPath) -ForegroundColor Green
