param(
  [Parameter(Mandatory=$true)]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_DEVICE_BINDING_SELFTEST_FAIL: " + $m)
}

function WT-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WT-ReadUtf8NoBomLf([string]$Path){
  return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n")
}

function WT-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function WT-Sha256HexBytes([byte[]]$b){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($b)) -replace "-","").ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

function WT-CanonicalJson([hashtable]$Map){
  $keys = New-Object System.Collections.Generic.List[string]
  foreach($k in $Map.Keys){ [void]$keys.Add([string]$k) }
  $keys.Sort()

  $parts = New-Object System.Collections.Generic.List[string]
  foreach($k in $keys){
    $nameJson = ConvertTo-Json ([string]$k) -Compress
    $valJson  = ConvertTo-Json $Map[$k] -Compress -Depth 20
    [void]$parts.Add(($nameJson + ":" + $valJson))
  }
  return "{" + ($parts -join ",") + "}"
}

function WT-ReadEventLines([string]$EventsPath){
  if(-not (Test-Path -LiteralPath $EventsPath -PathType Leaf)){
    return @()
  }
  $raw = WT-ReadUtf8NoBomLf $EventsPath
  $lines = @(@($raw -split "`n") | Where-Object { $_ -and $_.Trim().Length -gt 0 })
  return @($lines)
}

if($RepoRoot -is [System.IO.FileSystemInfo]){
  $RepoRoot = $RepoRoot.FullName
}
$RepoRoot = [string]$RepoRoot
if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$Bootstrap = Join-Path $RepoRoot "scripts\watchtower_device_bootstrap_v1.ps1"
$Bind      = Join-Path $RepoRoot "scripts\watchtower_bind_telemetry_to_device_event_v1.ps1"

if(-not (Test-Path -LiteralPath $Bootstrap -PathType Leaf)){ WT-Die ("MISSING_BOOTSTRAP_SCRIPT: " + $Bootstrap) }
if(-not (Test-Path -LiteralPath $Bind -PathType Leaf)){ WT-Die ("MISSING_BIND_SCRIPT: " + $Bind) }

$Scratch = Join-Path $RepoRoot "proofs\scratch\watchtower_device_binding_selftest"
if(Test-Path -LiteralPath $Scratch -PathType Container){
  Remove-Item -LiteralPath $Scratch -Recurse -Force
}
WT-EnsureDir $Scratch

$DevicesRoot = Join-Path $Scratch "devices"
WT-EnsureDir $DevicesRoot

$DevicePubKey = "ssh-ed25519 AAAATESTDEVICEKEY binding-selftest"
$HardwareFingerprint = "hwfp-binding-001"
$Manufacturer = "Lenovo"
$Serial = "SN-BIND-001"
$OsFamily = "windows"
$FirstSeenUtc = "2026-03-01T00:00:00Z"
$PolicyHash = "policyhash-binding-001"

$identityMap = [ordered]@{
  device_pubkey = $DevicePubKey
  first_seen_utc = $FirstSeenUtc
  hardware_fingerprint = $HardwareFingerprint
  manufacturer = $Manufacturer
  serial = $Serial
}
$identityJson = WT-CanonicalJson $identityMap
$DeviceId = WT-Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($identityJson))
$DeviceRoot = Join-Path $DevicesRoot $DeviceId
$EventsPath = Join-Path $DeviceRoot "events.ndjson"

# bootstrap directly
$bootstrapOut = & $Bootstrap `
  -RepoRoot $RepoRoot `
  -DevicePubKey $DevicePubKey `
  -HardwareFingerprint $HardwareFingerprint `
  -Manufacturer $Manufacturer `
  -Serial $Serial `
  -OsFamily $OsFamily `
  -FirstSeenUtc $FirstSeenUtc `
  -ProvisioningPolicyHash $PolicyHash `
  -TrustLevel "T1" `
  -Status "enrolled" `
  -DeviceRoot $DeviceRoot 2>&1

if($LASTEXITCODE -ne 0){
  WT-Die ("BOOTSTRAP_FAILED: " + (($bootstrapOut | ForEach-Object { [string]$_ }) -join "`n"))
}

$bootstrapTxt = (($bootstrapOut | ForEach-Object { [string]$_ }) -join "`n")
if($bootstrapTxt -notmatch 'WATCHTOWER_DEVICE_BOOTSTRAP_OK'){
  WT-Die "BOOTSTRAP_TOKEN_MISSING"
}

$beforeLines = @(@(WT-ReadEventLines $EventsPath))
$beforeCount = @($beforeLines).Count

$GoodTele = Join-Path $Scratch "good.ndjson"
WT-WriteUtf8NoBomLf -Path $GoodTele -Text ('{"schema":"watchtower.heartbeat.v1","device_id":"' + $DeviceId + '","observed_utc":"2026-03-01T00:15:00Z"}')

# bind directly
$bindOut = & $Bind `
  -RepoRoot $RepoRoot `
  -TelemetryPath $GoodTele `
  -DevicesRoot $DevicesRoot `
  -PolicyHash $PolicyHash `
  -Status "ok" 2>&1

if($LASTEXITCODE -ne 0){
  WT-Die ("GOOD_BIND_FAILED: " + (($bindOut | ForEach-Object { [string]$_ }) -join "`n"))
}

$afterLines = @(@(WT-ReadEventLines $EventsPath))
$afterCount = @($afterLines).Count
if($afterCount -ne ($beforeCount + 1)){
  WT-Die ("GOOD_BIND_EVENT_COUNT_BAD: before=" + $beforeCount + " after=" + $afterCount)
}

$lastObj = ([string]$afterLines[$afterCount - 1]) | ConvertFrom-Json
$lastDeviceId = [string]$lastObj.device_id
$lastEventType = [string]$lastObj.event_type

if($lastDeviceId -ne $DeviceId){
  WT-Die ("GOOD_BIND_DEVICE_ID_MISMATCH: " + $lastDeviceId)
}
if($lastEventType -notlike 'telemetry/*'){
  WT-Die ("GOOD_BIND_EVENT_TYPE_BAD: " + $lastEventType)
}

Write-Host "CASE_OK: good_bind" -ForegroundColor Green

$BadTele = Join-Path $Scratch "bad_multi.ndjson"
$badText = @(
  ('{"schema":"watchtower.heartbeat.v1","device_id":"' + $DeviceId + '","observed_utc":"2026-03-01T00:20:00Z"}'),
  '{"schema":"watchtower.heartbeat.v1","device_id":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","observed_utc":"2026-03-01T00:21:00Z"}'
) -join "`n"
WT-WriteUtf8NoBomLf -Path $BadTele -Text $badText

$badOut = & $Bind `
  -RepoRoot $RepoRoot `
  -TelemetryPath $BadTele `
  -DevicesRoot $DevicesRoot `
  -PolicyHash $PolicyHash `
  -Status "ok" 2>&1

if($LASTEXITCODE -eq 0){
  WT-Die "MULTI_DEVICE_BIND_EXIT_ZERO"
}

$badTxt = (($badOut | ForEach-Object { [string]$_ }) -join "`n")
if($badTxt -notmatch 'MULTI_DEVICE_TELEMETRY_NOT_ALLOWED'){
  WT-Die "MULTI_DEVICE_TOKEN_MISSING"
}

Write-Host "CASE_OK: multi_device_rejected" -ForegroundColor Green
Write-Host "WATCHTOWER_DEVICE_BINDING_SELFTEST_OK" -ForegroundColor Green