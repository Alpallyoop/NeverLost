param([Parameter(Mandatory=$true)][string]$RepoRoot)

# Static guard for Windows PowerShell 5.1, the canonical Windows host.
# In 5.1 a built-in alias wins over a script function of the same name (for example a function named
# "Ps" is shadowed by the alias ps = Get-Process). PowerShell 7 on Linux drops several of these aliases,
# so this cannot be caught by running the lanes there. Fails when any top-level script defines a
# function whose name is a Windows PowerShell 5.1 default alias.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$aliases51 = @(
  "%","?","ac","asnp","cat","cd","cfs","chdir","clc","clear","clhy","cli","clp","cls","clv","cnsn","compare",
  "copy","cp","cpi","cpp","curl","cvpa","dbp","del","diff","dir","dnsn","ebp","echo","epal","epcsv","epsn",
  "erase","etsn","exsn","fc","fhx","fl","foreach","ft","fw","gal","gbp","gc","gcb","gci","gcm","gcs","gdr",
  "ghy","gi","gin","gjb","gl","gm","gmo","gp","gps","gpv","group","gsn","gsnp","gsv","gtz","gu","gv","gwmi",
  "h","history","icm","iex","ihy","ii","ipal","ipcsv","ipmo","ipsn","irm","ise","iwmi","iwr","kill","lp","ls",
  "man","md","measure","mi","mount","move","mp","mv","nal","ndr","ni","nmo","npssc","nsn","nv","ogv","oh",
  "popd","ps","pushd","pwd","r","rbp","rcjb","rcsn","rd","rdr","ren","ri","rjb","rm","rmdir","rmo","rni",
  "rnp","rp","rsn","rsnp","rujb","rv","rvpa","rwmi","sajb","sal","saps","sasv","sbp","sc","scb","select",
  "set","shcm","si","sl","sleep","sls","sort","sp","spjb","spps","spsv","start","stz","sujb","sv","swmi",
  "tee","trcm","type","wget","where","wjb","write"
)
# Plus whatever aliases the running host defines.
$all = @{}
foreach($a in $aliases51){ $all[$a.ToLowerInvariant()] = $true }
foreach($a in @(Get-Alias)){ $all[([string]$a.Name).ToLowerInvariant()] = $true }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$bad = New-Object System.Collections.Generic.List[string]
foreach($f in @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "scripts") -File -Filter *.ps1 | Sort-Object Name)){
  $tok = $null; $err = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tok,[ref]$err)
  $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
  foreach($d in $defs){
    if($all.ContainsKey(([string]$d.Name).ToLowerInvariant())){ [void]$bad.Add($f.Name + ": function '" + $d.Name + "' is shadowed by a built-in alias") }
  }
}
if($bad.Count -gt 0){
  foreach($b in $bad){ Write-Output ("ALIAS_COLLISION " + $b) }
  throw ("PS51_COMPAT_FAIL: " + $bad.Count + " function name(s) collide with built-in aliases")
}
Write-Output "NEVERLOST_PS51_COMPAT_OK"
