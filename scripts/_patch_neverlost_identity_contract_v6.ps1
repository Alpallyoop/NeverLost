param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$enc = [System.Text.UTF8Encoding]::new($false)
function Ensure-Dir([string]$p){ if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomBytes([string]$Path,[byte[]]$Bytes){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllBytes($Path,$Bytes)
}
if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "RepoRoot not found: $RepoRoot" }
Ensure-Dir (Join-Path $RepoRoot "scripts")
Ensure-Dir (Join-Path $RepoRoot "proofs\keys")
Ensure-Dir (Join-Path $RepoRoot "proofs\trust")
Ensure-Dir (Join-Path $RepoRoot "proofs\receipts")
$rcptPath = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"
if (-not (Test-Path -LiteralPath $rcptPath)) { [System.IO.File]::WriteAllBytes($rcptPath, $enc.GetBytes("")) }
$libPath = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
$libB64 = "JEVycm9yQWN0aW9uUHJlZmVyZW5jZT0iU3RvcCIKU2V0LVN0cmljdE1vZGUgLVZlcnNpb24gTGF0ZXN0CgpmdW5jdGlvbiBOTC1HZXRVdGY4Tm9Cb21FbmNvZGluZygpeyBbU3lzdGVtLlRleHQuVVRGOEVuY29kaW5nXTo6bmV3KCRmYWxzZSkgfQpmdW5jdGlvbiBOTC1SZXNvbHZlUGF0aChbc3RyaW5nXSRQYXRoKXsgKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBhdGggJFBhdGgpLlBhdGggfQpmdW5jdGlvbiBOTC1SZWFkQWxsQnl0ZXMoW3N0cmluZ10kUGF0aCl7IFtTeXN0ZW0uSU8uRmlsZV06OlJlYWRBbGxCeXRlcygoTkwtUmVzb2x2ZVBhdGggJFBhdGgpKSB9CmZ1bmN0aW9uIE5MLVJlYWRVdGY4KFtzdHJpbmddJFBhdGgpeyAoTkwtR2V0VXRmOE5vQm9tRW5jb2RpbmcpLkdldFN0cmluZygoTkwtUmVhZEFsbEJ5dGVzICRQYXRoKSkgfQoKZnVuY3Rpb24gTkwtV3JpdGVVdGY4Tm9Cb21GaWxlKFtzdHJpbmddJFBhdGgsW3N0cmluZ10kVGV4dCl7CiAgJGVuYyA9IE5MLUdldFV0ZjhOb0JvbUVuY29kaW5nCiAgJGRpciA9IFNwbGl0LVBhdGggLVBhcmVudCAkUGF0aAogIGlmICgkZGlyIC1hbmQgLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZGlyKSkgeyBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1Gb3JjZSAtUGF0aCAkZGlyIHwgT3V0LU51bGwgfQogIFtTeXN0ZW0uSU8uRmlsZV06OldyaXRlQWxsQnl0ZXMoJFBhdGgsICRlbmMuR2V0Qnl0ZXMoJFRleHQuUmVwbGFjZSgiYHJgbiIsImBuIikuVHJpbUVuZCgpICsgImBuIikpCn0KCmZ1bmN0aW9uIE5MLVNoYTI1NkhleEJ5dGVzKFtieXRlW11dJEJ5dGVzKXsKICBpZiAoJG51bGwgLWVxICRCeXRlcykgeyB0aHJvdyAic2hhMjU2IGJ5dGVzIGlzIG51bGwiIH0KICAkc2hhID0gW1N5c3RlbS5TZWN1cml0eS5DcnlwdG9ncmFwaHkuU0hBMjU2XTo6Q3JlYXRlKCkKICB0cnkgewogICAgJGggPSAkc2hhLkNvbXB1dGVIYXNoKFtieXRlW11dJEJ5dGVzKQogICAgcmV0dXJuICgoW0JpdENvbnZlcnRlcl06OlRvU3RyaW5nKCRoKSAtcmVwbGFjZSAiLSIsIiIpLlRvTG93ZXJJbnZhcmlhbnQoKSkKICB9IGZpbmFsbHkgeyAkc2hhLkRpc3Bvc2UoKSB9Cn0KCmZ1bmN0aW9uIE5MLVNoYTI1NkhleFBhdGgoW3N0cmluZ10kUGF0aCl7CiAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFBhdGgpKSB7IHRocm93ICJQYXRoIG5vdCBmb3VuZCBmb3Igc2hhMjU2OiAkUGF0aCIgfQogICRiID0gW2J5dGVbXV0oTkwtUmVhZEFsbEJ5dGVzICRQYXRoKQogIHJldHVybiAoTkwtU2hhMjU2SGV4Qnl0ZXMgJGIpCn0KCiMgc2luZ2xlLXRlbmFudC88dGVuYW50X2F1dGhvcml0eT4vYXV0aG9yaXR5Lzxwcm9kdWNlcj4KZnVuY3Rpb24gTkwtQXNzZXJ0UHJpbmNpcGFsKFtzdHJpbmddJFByaW5jaXBhbCl7CiAgaWYgKFtzdHJpbmddOjpJc051bGxPcldoaXRlU3BhY2UoJFByaW5jaXBhbCkpIHsgdGhyb3cgInByaW5jaXBhbCBpcyByZXF1aXJlZC4iIH0KICBpZiAoJFByaW5jaXBhbCAtY25lICRQcmluY2lwYWwuVG9Mb3dlckludmFyaWFudCgpKSB7IHRocm93ICJwcmluY2lwYWwgbXVzdCBiZSBsb3dlcmNhc2U6ICRQcmluY2lwYWwiIH0KICBpZiAoJFByaW5jaXBhbCAtbWF0Y2ggIlxzIikgeyB0aHJvdyAicHJpbmNpcGFsIG11c3Qgbm90IGNvbnRhaW4gd2hpdGVzcGFjZTogJFByaW5jaXBhbCIgfQogIGlmICgkUHJpbmNpcGFsLkxlbmd0aCAtZ3QgMjU2KSB7IHRocm93ICJwcmluY2lwYWwgdG9vIGxvbmcgKD4yNTYpOiAkUHJpbmNpcGFsIiB9CiAgJHNlZyA9ICJbYS16MC05XVthLXowLTlcLV9dKiIKICAkcmUgID0gIl5zaW5nbGUtdGVuYW50XC8kc2VnXC9hdXRob3JpdHlcLyRzZWckIgogIGlmICgkUHJpbmNpcGFsIC1ub3RtYXRjaCAkcmUpIHsgdGhyb3cgInByaW5jaXBhbCBmb3JtYXQgaW52YWxpZCAodjEpOiAkUHJpbmNpcGFsIiB9Cn0KCmZ1bmN0aW9uIE5MLUFzc2VydEtleUlkKFtzdHJpbmddJEtleUlkKXsKICBpZiAoW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkS2V5SWQpKSB7IHRocm93ICJrZXlfaWQgaXMgcmVxdWlyZWQuIiB9CiAgaWYgKCRLZXlJZC5MZW5ndGggLWd0IDEyOCkgeyB0aHJvdyAia2V5X2lkIHRvbyBsb25nICg+MTI4KTogJEtleUlkIiB9CiAgaWYgKCRLZXlJZCAtbWF0Y2ggIlxzIikgeyB0aHJvdyAia2V5X2lkIG11c3Qgbm90IGNvbnRhaW4gd2hpdGVzcGFjZTogJEtleUlkIiB9CiAgJHJlID0gIl5bYS16MC05XVthLXowLTlcLV0qW2EtejAtOV0kIgogIGlmICgkS2V5SWQgLW5vdG1hdGNoICRyZSkgeyB0aHJvdyAia2V5X2lkIGZvcm1hdCBpbnZhbGlkOiAkS2V5SWQiIH0KfQoKZnVuY3Rpb24gTkwtQ29udmVydEZyb21Kc29uQ29tcGF0KFtzdHJpbmddJEpzb24sW2ludF0kRGVwdGg9NjQpewogICRjbWQgPSBHZXQtQ29tbWFuZCBDb252ZXJ0RnJvbS1Kc29uIC1FcnJvckFjdGlvbiBTdG9wCiAgaWYgKCRjbWQuUGFyYW1ldGVycy5Db250YWluc0tleSgiRGVwdGgiKSkgeyByZXR1cm4gKCRKc29uIHwgQ29udmVydEZyb20tSnNvbiAtRGVwdGggJERlcHRoKSB9CiAgcmV0dXJuICgkSnNvbiB8IENvbnZlcnRGcm9tLUpzb24pCn0KCiMgRGV0ZXJtaW5pc3RpYyBKU09OIChubyBbb3JkZXJlZF0sIG5vIE9yZGVyZWREaWN0aW9uYXJ5KS4gVXNlIFNvcnRlZERpY3Rpb25hcnkuCmZ1bmN0aW9uIE5MLUNhbm9uaWZ5KCRvYmopewogIGlmICgkbnVsbCAtZXEgJG9iaikgeyByZXR1cm4gJG51bGwgfQoKICBpZiAoJG9iaiAtaXMgW1N5c3RlbS5Db2xsZWN0aW9ucy5JRGljdGlvbmFyeV0pIHsKICAgICRzZCA9IFtTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5Tb3J0ZWREaWN0aW9uYXJ5W3N0cmluZyxvYmplY3RdXTo6bmV3KCkKICAgIGZvcmVhY2ggKCRrIGluIEAoJG9iai5LZXlzKSB8IFNvcnQtT2JqZWN0KSB7CiAgICAgIGlmICgkbnVsbCAtZXEgJGspIHsgdGhyb3cgImRpY3Rpb25hcnkga2V5IGlzIG51bGwgKGludmFsaWQpIiB9CiAgICAgICRrcyA9IFtzdHJpbmddJGsKICAgICAgJHNkWyRrc10gPSBOTC1DYW5vbmlmeSAkb2JqWyRrXQogICAgfQogICAgcmV0dXJuICRzZAogIH0KCiAgaWYgKCRvYmogLWlzIFtTeXN0ZW0uQ29sbGVjdGlvbnMuSUVudW1lcmFibGVdIC1hbmQgLW5vdCAoJG9iaiAtaXMgW3N0cmluZ10pKSB7CiAgICAkYXJyID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W29iamVjdF0KICAgIGZvcmVhY2ggKCR4IGluICRvYmopIHsgW3ZvaWRdJGFyci5BZGQoKE5MLUNhbm9uaWZ5ICR4KSkgfQogICAgcmV0dXJuICRhcnIuVG9BcnJheSgpCiAgfQoKICByZXR1cm4gJG9iagp9CgpmdW5jdGlvbiBOTC1Ub0Nhbm9uSnNvbigkb2JqLFtpbnRdJERlcHRoPTY0KXsKICAkY2Fub24gPSBOTC1DYW5vbmlmeSAkb2JqCiAgcmV0dXJuICgkY2Fub24gfCBDb252ZXJ0VG8tSnNvbiAtRGVwdGggJERlcHRoIC1Db21wcmVzcykKfQoKZnVuY3Rpb24gTkwtTG9hZFRydXN0QnVuZGxlKFtzdHJpbmddJFRydXN0QnVuZGxlUGF0aCl7CiAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJFRydXN0QnVuZGxlUGF0aCkpIHsgdGhyb3cgInRydXN0X2J1bmRsZS5qc29uIG5vdCBmb3VuZDogJFRydXN0QnVuZGxlUGF0aCIgfQogICR0eHQgPSBOTC1SZWFkVXRmOCAkVHJ1c3RCdW5kbGVQYXRoCiAgJHRiICA9IE5MLUNvbnZlcnRGcm9tSnNvbkNvbXBhdCAkdHh0IDY0CgogIGlmICgkdGIuc2NoZW1hIC1uZSAibmV2ZXJsb3N0LnRydXN0X2J1bmRsZS52MSIpIHsgdGhyb3cgInRydXN0X2J1bmRsZS5qc29uIHNjaGVtYSBtdXN0IGJlIG5ldmVybG9zdC50cnVzdF9idW5kbGUudjEiIH0KICBpZiAoLW5vdCAkdGIucHJpbmNpcGFscykgeyB0aHJvdyAidHJ1c3RfYnVuZGxlLmpzb24gbWlzc2luZyBwcmluY2lwYWxzIiB9CgogIGZvcmVhY2ggKCRwIGluICR0Yi5wcmluY2lwYWxzKSB7CiAgICBOTC1Bc3NlcnRQcmluY2lwYWwgJHAucHJpbmNpcGFsCiAgICBpZiAoLW5vdCAkcC5rZXlzKSB7IHRocm93ICJwcmluY2lwYWwgbWlzc2luZyBrZXlzOiAkKCRwLnByaW5jaXBhbCkiIH0KICAgIGZvcmVhY2ggKCRrIGluICRwLmtleXMpIHsKICAgICAgTkwtQXNzZXJ0S2V5SWQgJGsua2V5X2lkCiAgICAgIGlmICgtbm90ICRrLm5hbWVzcGFjZXMpIHsgdGhyb3cgImtleSBtaXNzaW5nIG5hbWVzcGFjZXMgZm9yIHByaW5jaXBhbD0kKCRwLnByaW5jaXBhbCkga2V5X2lkPSQoJGsua2V5X2lkKSIgfQogICAgICBpZiAoLW5vdCAkay5wdWJrZXlfcGF0aCkgeyB0aHJvdyAia2V5IG1pc3NpbmcgcHVia2V5X3BhdGggZm9yIHByaW5jaXBhbD0kKCRwLnByaW5jaXBhbCkga2V5X2lkPSQoJGsua2V5X2lkKSIgfQogICAgICBpZiAoLW5vdCAkay5wdWJrZXlfc2hhMjU2KSB7IHRocm93ICJrZXkgbWlzc2luZyBwdWJrZXlfc2hhMjU2IGZvciBwcmluY2lwYWw9JCgkcC5wcmluY2lwYWwpIGtleV9pZD0kKCRrLmtleV9pZCkiIH0KICAgICAgaWYgKC1ub3QgJGsuYWxnKSB7ICRrIHwgQWRkLU1lbWJlciAtTm90ZVByb3BlcnR5TmFtZSAiYWxnIiAtTm90ZVByb3BlcnR5VmFsdWUgInNzaC1lZDI1NTE5IiAtRm9yY2UgfQogICAgfQogIH0KCiAgcmV0dXJuICR0Ygp9CgpmdW5jdGlvbiBOTC1Xcml0ZUFsbG93ZWRTaWduZXJzKFtzdHJpbmddJFRydXN0QnVuZGxlUGF0aCxbc3RyaW5nXSRSZXBvUm9vdCxbc3RyaW5nXSRPdXRQYXRoKXsKICAkdGIgPSBOTC1Mb2FkVHJ1c3RCdW5kbGUgJFRydXN0QnVuZGxlUGF0aAogICRsaW5lcyA9IEAoKQoKICBmb3JlYWNoICgkcCBpbiAoJHRiLnByaW5jaXBhbHMgfCBTb3J0LU9iamVjdCBwcmluY2lwYWwpKSB7CiAgICBmb3JlYWNoICgkayBpbiAoJHAua2V5cyB8IFNvcnQtT2JqZWN0IGtleV9pZCkpIHsKICAgICAgJHB1YkFicyA9IEpvaW4tUGF0aCAkUmVwb1Jvb3QgKCRrLnB1YmtleV9wYXRoIC1yZXBsYWNlICIvIiwiXCIpCiAgICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwdWJBYnMpKSB7IHRocm93ICJwdWJrZXkgbm90IGZvdW5kOiAkcHViQWJzIiB9CgogICAgICAkcHViRmlsZUhhc2ggPSBOTC1TaGEyNTZIZXhQYXRoICRwdWJBYnMKICAgICAgaWYgKCRwdWJGaWxlSGFzaCAtbmUgJGsucHVia2V5X3NoYTI1NikgewogICAgICAgIHRocm93ICJwdWJrZXlfc2hhMjU2IG1pc21hdGNoLiBwcmluY2lwYWw9JCgkcC5wcmluY2lwYWwpIGtleV9pZD0kKCRrLmtleV9pZCkgZXhwZWN0ZWQ9JCgkay5wdWJrZXlfc2hhMjU2KSBhY3R1YWw9JHB1YkZpbGVIYXNoIgogICAgICB9CgogICAgICAkcHViTGluZSA9IChOTC1SZWFkVXRmOCAkcHViQWJzKS5UcmltKCkKICAgICAgZm9yZWFjaCAoJG5zIGluIEAoJGsubmFtZXNwYWNlcyB8IFNvcnQtT2JqZWN0KSkgewogICAgICAgIGlmIChbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKCRucykpIHsgdGhyb3cgIm5hbWVzcGFjZSBpcyBlbXB0eSBmb3IgcHJpbmNpcGFsPSQoJHAucHJpbmNpcGFsKSBrZXlfaWQ9JCgkay5rZXlfaWQpIiB9CiAgICAgICAgJGxpbmVzICs9ICgiezB9IG5hbWVzcGFjZXM9YCJ7MX1gIiB7Mn0iIC1mICRwLnByaW5jaXBhbCwgJG5zLCAkcHViTGluZSkKICAgICAgfQogICAgfQogIH0KCiAgTkwtV3JpdGVVdGY4Tm9Cb21GaWxlICRPdXRQYXRoICgoJGxpbmVzIC1qb2luICJgbiIpICsgImBuIikKICByZXR1cm4gJHRydWUKfQoKZnVuY3Rpb24gTkwtV3JpdGVSZWNlaXB0KFtzdHJpbmddJFJlY2VpcHRzUGF0aCwgJE9iail7CiAgJGxpbmUgPSAoTkwtVG9DYW5vbkpzb24gJE9iaikKICAkZW5jID0gTkwtR2V0VXRmOE5vQm9tRW5jb2RpbmcKICAkYnl0ZXMgPSAkZW5jLkdldEJ5dGVzKCRsaW5lICsgImBuIikKICAkZnMgPSBbU3lzdGVtLklPLkZpbGVdOjpPcGVuKCRSZWNlaXB0c1BhdGgsW1N5c3RlbS5JTy5GaWxlTW9kZV06OkFwcGVuZCxbU3lzdGVtLklPLkZpbGVBY2Nlc3NdOjpXcml0ZSxbU3lzdGVtLklPLkZpbGVTaGFyZV06OlJlYWQpCiAgdHJ5IHsgJGZzLldyaXRlKCRieXRlcywwLCRieXRlcy5MZW5ndGgpIH0gZmluYWxseSB7ICRmcy5EaXNwb3NlKCkgfQp9"
$libBytes = [Convert]::FromBase64String($libB64)
Write-Utf8NoBomBytes $libPath $libBytes
$libTxt = $enc.GetString([System.IO.File]::ReadAllBytes($libPath))
if ($libTxt -match '\$ordered') { throw "LIB PROOF FAILED: `$ordered still present." }
. $libPath

$trustPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$pubRel    = "proofs/keys/watchtower_authority_ed25519.pub"
$pubAbs    = Join-Path $RepoRoot "proofs\keys\watchtower_authority_ed25519.pub"
if (-not (Test-Path -LiteralPath $pubAbs)) { throw "Missing pubkey: $pubAbs" }
$principal = "single-tenant/watchtower_authority/authority/watchtower"
$keyId     = "watchtower-authority-ed25519"
$pubLine   = (NL-ReadUtf8 $pubAbs).Trim()
$bundle = @{ schema="neverlost.trust_bundle.v1"; created_utc=(Get-Date).ToUniversalTime().ToString("o"); principals=@(@{ principal=$principal; keys=@(@{ key_id=$keyId; alg="ssh-ed25519"; pubkey_path=$pubRel; pubkey_sha256=(NL-Sha256HexPath $pubAbs); pubkey=$pubLine; namespaces=@("packet/envelope","watchtower","watchtower/device-pledge","nfl/ingest-receipt") }) }) }
NL-WriteUtf8NoBomFile $trustPath ((NL-ToCanonJson $bundle) + "`n")
$allowed = Join-Path $RepoRoot "proofs\trust\allowed_signers"
[void](NL-WriteAllowedSigners $trustPath $RepoRoot $allowed)

$mk = Join-Path $RepoRoot "scripts\make_allowed_signers_v1.ps1"
$mkTxt = @(
"param([Parameter(Mandatory=$true)][string]$RepoRoot)",
"$ErrorActionPreference=`"Stop`"",
"Set-StrictMode -Version Latest",
". (Join-Path $PSScriptRoot `"_lib_neverlost_v1.ps1`")",
"$trust = Join-Path $RepoRoot `"`"proofs\trust\trust_bundle.json`"`"",
"$out   = Join-Path $RepoRoot `"`"proofs\trust\allowed_signers`"`"",
"$rcpt  = Join-Path $RepoRoot `"`"proofs\receipts\neverlost.ndjson`"`"",
"[void](NL-WriteAllowedSigners $trust $RepoRoot $out)",
"NL-WriteReceipt $rcpt @{ schema=`"neverlost.receipt.v1`"; time_utc=(Get-Date).ToUniversalTime().ToString(`"o`"); action=`"make_allowed_signers`"; ok=$true; hashes=@{ trust_bundle_sha256=(NL-Sha256HexPath $trust); allowed_signers_sha256=(NL-Sha256HexPath $out) } }"
) -join "`n"
NL-WriteUtf8NoBomFile $mk ($mkTxt + "`n")

$si = Join-Path $RepoRoot "scripts\show_identity_v1.ps1"
$siTxt = @(
"param([Parameter(Mandatory=$true)][string]$RepoRoot)",
"$ErrorActionPreference=`"Stop`"",
"Set-StrictMode -Version Latest",
". (Join-Path $PSScriptRoot `"_lib_neverlost_v1.ps1`")",
"$trust = Join-Path $RepoRoot `"`"proofs\trust\trust_bundle.json`"`"",
"$as    = Join-Path $RepoRoot `"`"proofs\trust\allowed_signers`"`"",
"$rcpt  = Join-Path $RepoRoot `"`"proofs\receipts\neverlost.ndjson`"`"",
"$tb = NL-LoadTrustBundle $trust",
"Write-Host `"`"NeverLost v1 - Identity Layer (Watchtower contract)`"`"",
"Write-Host (`"`"trust_bundle_sha256    : `"`" + (NL-Sha256HexPath $trust))",
"Write-Host (`"`"allowed_signers_sha256 : `"`" + (if (Test-Path -LiteralPath $as) { NL-Sha256HexPath $as } else { `"`"`" }))",
"Write-Host (`"`"principals_count       : `"`" + @($tb.principals).Count)",
"Write-Host `"`"`"",
"foreach($p in ($tb.principals | Sort-Object principal)) { Write-Host (`"`"principal: `"`" + $p.principal); foreach($k in ($p.keys | Sort-Object key_id)) { Write-Host (`"`"  key_id     : `"`" + $k.key_id); Write-Host (`"`"  alg        : `"`" + $k.alg); Write-Host (`"`"  pubkey_path: `"`" + $k.pubkey_path); Write-Host (`"`"  namespaces : `"`" + ((@($k.namespaces) | Sort-Object) -join `"`", `"`")); }; Write-Host `"`"`" }",
"NL-WriteReceipt $rcpt @{ schema=`"neverlost.receipt.v1`"; time_utc=(Get-Date).ToUniversalTime().ToString(`"o`"); action=`"show_identity`"; ok=$true; hashes=@{ trust_bundle_sha256=(NL-Sha256HexPath $trust); allowed_signers_sha256=(if (Test-Path -LiteralPath $as) { NL-Sha256HexPath $as } else { `"`"`" }) } }"
) -join "`n"
NL-WriteUtf8NoBomFile $si ($siTxt + "`n")

NL-WriteReceipt $rcptPath @{ schema="neverlost.receipt.v1"; time_utc=(Get-Date).ToUniversalTime().ToString("o"); action="patch_neverlost_identity_contract_v6"; ok=$true; hashes=@{ lib_sha256=(NL-Sha256HexPath $libPath); trust_bundle_sha256=(NL-Sha256HexPath $trustPath); allowed_signers_sha256=(NL-Sha256HexPath $allowed); make_allowed_signers_sha256=(NL-Sha256HexPath $mk); show_identity_sha256=(NL-Sha256HexPath $si) } }
Write-Host "OK: NeverLost v1 patched (identity contract v6)" -ForegroundColor Green
Write-Host ("lib_sha256            : " + (NL-Sha256HexPath $libPath))
Write-Host ("trust_bundle_sha256    : " + (NL-Sha256HexPath $trustPath))
Write-Host ("allowed_signers_sha256 : " + (NL-Sha256HexPath $allowed))
