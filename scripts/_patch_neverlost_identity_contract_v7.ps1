param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$enc = [System.Text.UTF8Encoding]::new($false)
function Ensure-Dir([string]$p){ if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Bytes([string]$Path,[byte[]]$Bytes){ $dir=Split-Path -Parent $Path; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }; [System.IO.File]::WriteAllBytes($Path,$Bytes) }
if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "RepoRoot not found: $RepoRoot" }
Ensure-Dir (Join-Path $RepoRoot "scripts")
Ensure-Dir (Join-Path $RepoRoot "proofs\keys")
Ensure-Dir (Join-Path $RepoRoot "proofs\trust")
Ensure-Dir (Join-Path $RepoRoot "proofs\receipts")
$rcptPath = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"
if (-not (Test-Path -LiteralPath $rcptPath)) { [System.IO.File]::WriteAllBytes($rcptPath, $enc.GetBytes("")) }
$libPath = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
$libB64 = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZT0iU3RvcCIKU2V0LVN0cmljdE1vZGUgLVZlcnNpb24gTGF0ZXN0CgpmdW5jdGlvbiBOTC1HZXRVdGY4Tm9Cb21FbmNvZGluZygpeyBbU3lzdGVtLlRleHQuVVRGOEVuY29kaW5nXTo6bmV3KCRmYWxzZSkgfQpmdW5jdGlvbiBOTC1SZXNvbHZlUGF0aChbc3RyaW5nXSRQYXRoKXsgKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBhdGggJFBhdGgpLlBhdGggfQpmdW5jdGlvbiBOTC1SZWFkQWxsQnl0ZXMoW3N0cmluZ10kUGF0aCl7IFtTeXN0ZW0uSU8uRmlsZV06OlJlYWRBbGxCeXRlcygoTkwtUmVzb2x2ZVBhdGggJFBhdGgpKSB9CmZ1bmN0aW9uIE5MLVJlYWRVdGY4KFtzdHJpbmddJFBhdGgpeyAoTkwtR2V0VXRmOE5vQm9tRW5jb2RpbmcpLkdldFN0cmluZygoTkwtUmVhZEFsbEJ5dGVzICRQYXRoKSkgfQoKZnVuY3Rpb24gTkwtV3JpdGVVdGY4Tm9Cb21GaWxlKFtzdHJpbmddJFBhdGgsW3N0cmluZ10kVGV4dCl7CiAgJGVuYyA9IE5MLUdldFV0ZjhOb0JvbUVuY29kaW5nCiAgJGRpciA9IFNwbGl0LVBhdGggLVBhcmVudCAkUGF0aAogIGlmICgkZGlyIC1hbmQgLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZGlyKSkgeyBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1Gb3JjZSAtUGF0aCAkZGlyIHwgT3V0LU51bGwgfQogIFtTeXN0ZW0uSU8uRmlsZV06OldyaXRlQWxsQnl0ZXMoJFBhdGgsICRlbmMuR2V0Qnl0ZXMoJFRleHQuUmVwbGFjZSgiYHJgbiIsImBuIikuVHJpbUVuZCgpICsgImBuIikpCn0KCmZ1bmN0aW9uIE5MLVNoYTI1NkhleEJ5dGVzKFtieXRlW11dJEJ5dGVzKXsKICBpZiAoJG51bGwgLWVxICRCeXRlcykgeyB0aHJvdyAic2hhMjU2IGJ5dGVzIGlzIG51bGwiIH0KICAkc2hhID0gW1N5c3RlbS5TZWN1cml0eS5DcnlwdG9ncmFwaHkuU0hBMjU2XTo6Q3JlYXRlKCkKICB0cnkgewogICAgJGggPSAkc2hhLkNvbXB1dGVIYXNoKFtieXRlW11dJEJ5dGVzKQogICAgcmV0dXJuICgoW0JpdENvbnZlcnRlcl06OlRvU3RyaW5nKCRoKSAtcmVwbGFjZSAiLSIsIiIpLlRvTG93ZXJJbnZhcmlhbnQoKSkKICB9IGZpbmFsbHkgeyAkc2hhLkRpc3Bvc2UoKSB9Cn0KCmZ1bmN0aW9uIE5MLVNoYTI1NkhleFBhdGgoW3N0cmluZ10kUGF0aCl7CiAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFBhdGgpKSB7IHRocm93ICJQYXRoIG5vdCBmb3VuZCBmb3Igc2hhMjU2OiAkUGF0aCIgfQogICRiID0gW2J5dGVbXV0oTkwtUmVhZEFsbEJ5dGVzICRQYXRoKQogIHJldHVybiAoTkwtU2hhMjU2SGV4Qnl0ZXMgJGIpCn0KCmZ1bmN0aW9uIE5MLUFzc2VydFByaW5jaXBhbChbc3RyaW5nXSRQcmluY2lwYWwpewogIGlmIChbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKCRQcmluY2lwYWwpKSB7IHRocm93ICJwcmluY2lwYWwgaXMgcmVxdWlyZWQuIiB9CiAgaWYgKCRQcmluY2lwYWwgLWNuZSAkUHJpbmNpcGFsLlRvTG93ZXJJbnZhcmlhbnQoKSkgeyB0aHJvdyAicHJpbmNpcGFsIG11c3QgYmUgbG93ZXJjYXNlOiAkUHJpbmNpcGFsIiB9CiAgaWYgKCRQcmluY2lwYWwgLW1hdGNoICJccyIpIHsgdGhyb3cgInByaW5jaXBhbCBtdXN0IG5vdCBjb250YWluIHdoaXRlc3BhY2U6ICRQcmluY2lwYWwiIH0KICBpZiAoJFByaW5jaXBhbC5MZW5ndGggLWd0IDI1NikgeyB0aHJvdyAicHJpbmNpcGFsIHRvbyBsb25nICg+MjU2KTogJFByaW5jaXBhbCIgfQogICRzZWcgPSAiW2EtejAtOV1bYS16MC05XC1fXSoiCiAgJHJlICA9ICJec2luZ2xlLXRlbmFudFwvJHNlZ1wvYXV0aG9yaXR5XC8kc2VnJCIKICBpZiAoJFByaW5jaXBhbCAtbm90bWF0Y2ggJHJlKSB7IHRocm93ICJwcmluY2lwYWwgZm9ybWF0IGludmFsaWQgKHYxKTogJFByaW5jaXBhbCIgfQp9CgpmdW5jdGlvbiBOTC1Bc3NlcnRLZXlJZChbc3RyaW5nXSRLZXlJZCl7CiAgaWYgKFtzdHJpbmddOjpJc051bGxPcldoaXRlU3BhY2UoJEtleUlkKSkgeyB0aHJvdyAia2V5X2lkIGlzIHJlcXVpcmVkLiIgfQogIGlmICgkS2V5SWQuTGVuZ3RoIC1ndCAxMjgpIHsgdGhyb3cgImtleV9pZCB0b28gbG9uZyAoPjEyOCk6ICRLZXlJZCIgfQogIGlmICgkS2V5SWQgLW1hdGNoICJccyIpIHsgdGhyb3cgImtleV9pZCBtdXN0IG5vdCBjb250YWluIHdoaXRlc3BhY2U6ICRLZXlJZCIgfQogICRyZSA9ICJeW2EtejAtOV1bYS16MC05XC1dKlthLXowLTldJCIKICBpZiAoJEtleUlkIC1ub3RtYXRjaCAkcmUpIHsgdGhyb3cgImtleV9pZCBmb3JtYXQgaW52YWxpZDogJEtleUlkIiB9Cn0KCmZ1bmN0aW9uIE5MLUNvbnZlcnRGcm9tSnNvbkNvbXBhdChbc3RyaW5nXSRKc29uLFtpbnRdJERlcHRoPTY0KXsKICAkY21kID0gR2V0LUNvbW1hbmQgQ29udmVydEZyb20tSnNvbiAtRXJyb3JBY3Rpb24gU3RvcAogIGlmICgkY21kLlBhcmFtZXRlcnMuQ29udGFpbnNLZXkoIkRlcHRoIikpIHsgcmV0dXJuICgkSnNvbiB8IENvbnZlcnRGcm9tLUpzb24gLURlcHRoICREZXB0aCkgfQogIHJldHVybiAoJEpzb24gfCBDb252ZXJ0RnJvbS1Kc29uKQp9CgpmdW5jdGlvbiBOTC1DYW5vbmlmeSgkb2JqKXsKICBpZiAoJG51bGwgLWVxICRvYmopIHsgcmV0dXJuICRudWxsIH0KCiAgaWYgKCRvYmogLWlzIFtTeXN0ZW0uQ29sbGVjdGlvbnMuSURpY3Rpb25hcnldKSB7CiAgICAkc2QgPSBbU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuU29ydGVkRGljdGlvbmFyeVtzdHJpbmcsb2JqZWN0XV06Om5ldygpCiAgICBmb3JlYWNoICgkayBpbiBAKCRvYmouS2V5cykgfCBTb3J0LU9iamVjdCkgewogICAgICBpZiAoJG51bGwgLWVxICRrKSB7IHRocm93ICJkaWN0aW9uYXJ5IGtleSBpcyBudWxsIChpbnZhbGlkKSIgfQogICAgICAka3MgPSBbc3RyaW5nXSRrCiAgICAgICRzZFska3NdID0gTkwtQ2Fub25pZnkgJG9ialska10KICAgIH0KICAgIHJldHVybiAkc2QKICB9CgogIGlmICgkb2JqIC1pcyBbU3lzdGVtLkNvbGxlY3Rpb25zLklFbnVtZXJhYmxlXSAtYW5kIC1ub3QgKCRvYmogLWlzIFtzdHJpbmddKSkgewogICAgJGFyciA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtvYmplY3RdCiAgICBmb3JlYWNoICgkeCBpbiAkb2JqKSB7IFt2b2lkXSRhcnIuQWRkKChOTC1DYW5vbmlmeSAkeCkpIH0KICAgIHJldHVybiAkYXJyLlRvQXJyYXkoKQogIH0KCiAgcmV0dXJuICRvYmoKfQoKZnVuY3Rpb24gTkwtVG9DYW5vbkpzb24oJG9iaixbaW50XSREZXB0aD02NCl7CiAgJGNhbm9uID0gTkwtQ2Fub25pZnkgJG9iagogIHJldHVybiAoJGNhbm9uIHwgQ29udmVydFRvLUpzb24gLURlcHRoICREZXB0aCAtQ29tcHJlc3MpCn0KCmZ1bmN0aW9uIE5MLUxvYWRUcnVzdEJ1bmRsZShbc3RyaW5nXSRUcnVzdEJ1bmRsZVBhdGgpewogIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRUcnVzdEJ1bmRsZVBhdGgpKSB7IHRocm93ICJ0cnVzdF9idW5kbGUuanNvbiBub3QgZm91bmQ6ICRUcnVzdEJ1bmRsZVBhdGgiIH0KICAkdHh0ID0gTkwtUmVhZFV0ZjggJFRydXN0QnVuZGxlUGF0aAogICR0YiAgPSBOTC1Db252ZXJ0RnJvbUpzb25Db21wYXQgJHR4dCA2NAoKICBpZiAoJHRiLnNjaGVtYSAtbmUgIm5ldmVybG9zdC50cnVzdF9idW5kbGUudjEiKSB7IHRocm93ICJ0cnVzdF9idW5kbGUuanNvbiBzY2hlbWEgbXVzdCBiZSBuZXZlcmxvc3QudHJ1c3RfYnVuZGxlLnYxIiB9CiAgaWYgKC1ub3QgJHRiLnByaW5jaXBhbHMpIHsgdGhyb3cgInRydXN0X2J1bmRsZS5qc29uIG1pc3NpbmcgcHJpbmNpcGFscyIgfQoKICAjIG5vcm1hbGl6ZTogZW5zdXJlIHByaW5jaXBhbHMgaXMgYXJyYXkKICAkcHJpbmNpcGFscyA9IEAoJHRiLnByaW5jaXBhbHMpCgogIGZvcmVhY2ggKCRwIGluICRwcmluY2lwYWxzKSB7CiAgICBpZiAoJG51bGwgLWVxICRwIC1vciAtbm90ICgkcC5QU09iamVjdC5Qcm9wZXJ0aWVzLk5hbWUgLWNvbnRhaW5zICJwcmluY2lwYWwiKSkgewogICAgICB0aHJvdyAidHJ1c3RfYnVuZGxlIHByaW5jaXBhbHNbXSBtdXN0IGJlIG9iamVjdHMgd2l0aCBwcm9wZXJ0eSAncHJpbmNpcGFsJyAoYmFkIGVsZW1lbnQ6ICQoJHAgfCBPdXQtU3RyaW5nKSkiCiAgICB9CiAgICBOTC1Bc3NlcnRQcmluY2lwYWwgJHAucHJpbmNpcGFsCgogICAgaWYgKC1ub3QgKCRwLlBTT2JqZWN0LlByb3BlcnRpZXMuTmFtZSAtY29udGFpbnMgImtleXMiKSAtb3IgLW5vdCAkcC5rZXlzKSB7CiAgICAgIHRocm93ICJwcmluY2lwYWwgbWlzc2luZyBrZXlzOiAkKCRwLnByaW5jaXBhbCkiCiAgICB9CgogICAgZm9yZWFjaCAoJGsgaW4gQCgkcC5rZXlzKSkgewogICAgICBpZiAoLW5vdCAoJGsuUFNPYmplY3QuUHJvcGVydGllcy5OYW1lIC1jb250YWlucyAia2V5X2lkIikpIHsgdGhyb3cgImtleSBtaXNzaW5nIGtleV9pZCBmb3IgcHJpbmNpcGFsPSQoJHAucHJpbmNpcGFsKSIgfQogICAgICBOTC1Bc3NlcnRLZXlJZCAkay5rZXlfaWQKICAgICAgaWYgKC1ub3QgJGsubmFtZXNwYWNlcykgICB7IHRocm93ICJrZXkgbWlzc2luZyBuYW1lc3BhY2VzIGZvciBwcmluY2lwYWw9JCgkcC5wcmluY2lwYWwpIGtleV9pZD0kKCRrLmtleV9pZCkiIH0KICAgICAgaWYgKC1ub3QgJGsucHVia2V5X3BhdGgpICB7IHRocm93ICJrZXkgbWlzc2luZyBwdWJrZXlfcGF0aCBmb3IgcHJpbmNpcGFsPSQoJHAucHJpbmNpcGFsKSBrZXlfaWQ9JCgkay5rZXlfaWQpIiB9CiAgICAgIGlmICgtbm90ICRrLnB1YmtleV9zaGEyNTYpeyB0aHJvdyAia2V5IG1pc3NpbmcgcHVia2V5X3NoYTI1NiBmb3IgcHJpbmNpcGFsPSQoJHAucHJpbmNpcGFsKSBrZXlfaWQ9JCgkay5rZXlfaWQpIiB9CiAgICAgIGlmICgtbm90ICRrLmFsZykgeyAkayB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUgImFsZyIgLU5vdGVQcm9wZXJ0eVZhbHVlICJzc2gtZWQyNTUxOSIgLUZvcmNlIH0KICAgIH0KICB9CgogIHJldHVybiAkdGIKfQoKZnVuY3Rpb24gTkwtV3JpdGVBbGxvd2VkU2lnbmVycyhbc3RyaW5nXSRUcnVzdEJ1bmRsZVBhdGgsW3N0cmluZ10kUmVwb1Jvb3QsW3N0cmluZ10kT3V0UGF0aCl7CiAgJHRiID0gTkwtTG9hZFRydXN0QnVuZGxlICRUcnVzdEJ1bmRsZVBhdGgKICAkbGluZXMgPSBAKCkKCiAgZm9yZWFjaCAoJHAgaW4gKEAoJHRiLnByaW5jaXBhbHMpIHwgU29ydC1PYmplY3QgcHJpbmNpcGFsKSkgewogICAgZm9yZWFjaCAoJGsgaW4gKEAoJHAua2V5cykgfCBTb3J0LU9iamVjdCBrZXlfaWQpKSB7CiAgICAgICRwdWJBYnMgPSBKb2luLVBhdGggJFJlcG9Sb290ICgkay5wdWJrZXlfcGF0aCAtcmVwbGFjZSAiLyIsIlwiKQogICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkcHViQWJzKSkgeyB0aHJvdyAicHVia2V5IG5vdCBmb3VuZDogJHB1YkFicyIgfQoKICAgICAgJHB1YkZpbGVIYXNoID0gTkwtU2hhMjU2SGV4UGF0aCAkcHViQWJzCiAgICAgIGlmICgkcHViRmlsZUhhc2ggLW5lICRrLnB1YmtleV9zaGEyNTYpIHsKICAgICAgICB0aHJvdyAicHVia2V5X3NoYTI1NiBtaXNtYXRjaC4gcHJpbmNpcGFsPSQoJHAucHJpbmNpcGFsKSBrZXlfaWQ9JCgkay5rZXlfaWQpIGV4cGVjdGVkPSQoJGsucHVia2V5X3NoYTI1NikgYWN0dWFsPSRwdWJGaWxlSGFzaCIKICAgICAgfQoKICAgICAgJHB1YkxpbmUgPSAoTkwtUmVhZFV0ZjggJHB1YkFicykuVHJpbSgpCiAgICAgIGZvcmVhY2ggKCRucyBpbiBAKCRrLm5hbWVzcGFjZXMgfCBTb3J0LU9iamVjdCkpIHsKICAgICAgICBpZiAoW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkbnMpKSB7IHRocm93ICJuYW1lc3BhY2UgaXMgZW1wdHkgZm9yIHByaW5jaXBhbD0kKCRwLnByaW5jaXBhbCkga2V5X2lkPSQoJGsua2V5X2lkKSIgfQogICAgICAgICRsaW5lcyArPSAoInswfSBuYW1lc3BhY2VzPWAiezF9YCIgezJ9IiAtZiAkcC5wcmluY2lwYWwsICRucywgJHB1YkxpbmUpCiAgICAgIH0KICAgIH0KICB9CgogIE5MLVdyaXRlVXRmOE5vQm9tRmlsZSAkT3V0UGF0aCAoKCRsaW5lcyAtam9pbiAiYG4iKSArICJgbiIpCiAgcmV0dXJuICR0cnVlCn0KCmZ1bmN0aW9uIE5MLVdyaXRlUmVjZWlwdChbc3RyaW5nXSRSZWNlaXB0c1BhdGgsICRPYmopewogICRsaW5lID0gKE5MLVRvQ2Fub25Kc29uICRPYmopCiAgJGVuYyA9IE5MLUdldFV0ZjhOb0JvbUVuY29kaW5nCiAgJGJ5dGVzID0gJGVuYy5HZXRCeXRlcygkbGluZSArICJgbiIpCiAgJGZzID0gW1N5c3RlbS5JTy5GaWxlXTo6T3BlbigkUmVjZWlwdHNQYXRoLFtTeXN0ZW0uSU8uRmlsZU1vZGVdOjpBcHBlbmQsW1N5c3RlbS5JTy5GaWxlQWNjZXNzXTo6V3JpdGUsW1N5c3RlbS5JTy5GaWxlU2hhcmVdOjpSZWFkKQogIHRyeSB7ICRmcy5Xcml0ZSgkYnl0ZXMsMCwkYnl0ZXMuTGVuZ3RoKSB9IGZpbmFsbHkgeyAkZnMuRGlzcG9zZSgpIH0KfQ=="
$libBytes = [Convert]::FromBase64String($libB64)
Write-Bytes $libPath $libBytes
$libTxt = $enc.GetString([System.IO.File]::ReadAllBytes($libPath))
if ($libTxt -match '\$ordered') { throw "LIB PROOF FAILED: `$ordered still present." }
. $libPath

# --- Hard overwrite trust bundle to canonical Watchtower shape ---
$trustPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$pubRel    = "proofs/keys/watchtower_authority_ed25519.pub"
$pubAbs    = Join-Path $RepoRoot "proofs\keys\watchtower_authority_ed25519.pub"
if (-not (Test-Path -LiteralPath $pubAbs)) { throw "Missing pubkey: $pubAbs" }
$principal = "single-tenant/watchtower_authority/authority/watchtower"
$keyId     = "watchtower-authority-ed25519"
$pubLine   = (NL-ReadUtf8 $pubAbs).Trim()
$bundle = @{ schema="neverlost.trust_bundle.v1"; created_utc=(Get-Date).ToUniversalTime().ToString("o"); principals=@(@{ principal=$principal; keys=@(@{ key_id=$keyId; alg="ssh-ed25519"; pubkey_path=$pubRel; pubkey_sha256=(NL-Sha256HexPath $pubAbs); pubkey=$pubLine; namespaces=@("packet/envelope","watchtower","watchtower/device-pledge","nfl/ingest-receipt") }) }) }
NL-WriteUtf8NoBomFile $trustPath ((NL-ToCanonJson $bundle) + "`n")

# --- Shape proof: principals must contain objects with .principal + .keys ---
$tb = NL-LoadTrustBundle $trustPath
$ps = @($tb.principals)
if ($ps.Count -lt 1) { throw "trust_bundle principals empty" }
foreach($p in $ps){ if (-not ($p.PSObject.Properties.Name -contains "principal")) { throw "principals element missing principal" }; if (-not ($p.PSObject.Properties.Name -contains "keys")) { throw "principals element missing keys" } }

# --- allowed_signers ---
$allowed = Join-Path $RepoRoot "proofs\trust\allowed_signers"
[void](NL-WriteAllowedSigners $trustPath $RepoRoot $allowed)

# --- Entry scripts ---
NL-WriteUtf8NoBomFile (Join-Path $RepoRoot "scripts\make_allowed_signers_v1.ps1") (@
param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")
$trust = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$out   = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$rcpt  = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"
[void](NL-WriteAllowedSigners $trust $RepoRoot $out)
NL-WriteReceipt $rcpt @{ schema="neverlost.receipt.v1"; time_utc=(Get-Date).ToUniversalTime().ToString("o"); action="make_allowed_signers"; ok=$true; hashes=@{ trust_bundle_sha256=(NL-Sha256HexPath $trust); allowed_signers_sha256=(NL-Sha256HexPath $out) } }
@ + "`n")

NL-WriteUtf8NoBomFile (Join-Path $RepoRoot "scripts\show_identity_v1.ps1") (@
param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")
$trust = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$as    = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$rcpt  = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"
$tb = NL-LoadTrustBundle $trust
Write-Host "NeverLost v1 - Identity Layer (Watchtower contract)"
Write-Host ("trust_bundle_sha256    : " + (NL-Sha256HexPath $trust))
Write-Host ("allowed_signers_sha256 : " + (if (Test-Path -LiteralPath $as) { NL-Sha256HexPath $as } else { "" }))
Write-Host ("principals_count       : " + @($tb.principals).Count)
Write-Host ""
foreach($p in (@($tb.principals) | Sort-Object principal)) {
  Write-Host ("principal: " + $p.principal)
  foreach($k in (@($p.keys) | Sort-Object key_id)) {
    Write-Host ("  key_id     : " + $k.key_id)
    Write-Host ("  alg        : " + $k.alg)
    Write-Host ("  pubkey_path: " + $k.pubkey_path)
    Write-Host ("  namespaces : " + ((@($k.namespaces) | Sort-Object) -join ", "))
  }
  Write-Host ""
}
NL-WriteReceipt $rcpt @{ schema="neverlost.receipt.v1"; time_utc=(Get-Date).ToUniversalTime().ToString("o"); action="show_identity"; ok=$true; hashes=@{ trust_bundle_sha256=(NL-Sha256HexPath $trust); allowed_signers_sha256=(if (Test-Path -LiteralPath $as) { NL-Sha256HexPath $as } else { "" }) } }
@ + "`n")

NL-WriteReceipt $rcptPath @{ schema="neverlost.receipt.v1"; time_utc=(Get-Date).ToUniversalTime().ToString("o"); action="patch_neverlost_identity_contract_v7"; ok=$true; hashes=@{ lib_sha256=(NL-Sha256HexPath $libPath); trust_bundle_sha256=(NL-Sha256HexPath $trustPath); allowed_signers_sha256=(NL-Sha256HexPath $allowed); make_allowed_signers_sha256=(NL-Sha256HexPath (Join-Path $RepoRoot "scripts\make_allowed_signers_v1.ps1")); show_identity_sha256=(NL-Sha256HexPath (Join-Path $RepoRoot "scripts\show_identity_v1.ps1")) } }
Write-Host "OK: NeverLost v1 patched (identity contract v7)" -ForegroundColor Green
