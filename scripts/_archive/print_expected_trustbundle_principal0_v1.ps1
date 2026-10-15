param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")

$tb = NL-LoadTrustBundleInfoV1 $RepoRoot
$e  = @(NL-GetTrustBundleEntriesCompat $tb.Obj)
if($e.Count -lt 1){ throw "NO_ENTRIES" }

$p0 = [string]$e[0].principal
$ns = @($e[0].namespaces) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_.Length -gt 0 } | Sort-Object -Unique

Write-Host ("EXPECTED_PRINCIPAL_0: " + $p0)
Write-Host ("EXPECTED_NAMESPACES_0: [" + ($ns -join ",") + "]")
