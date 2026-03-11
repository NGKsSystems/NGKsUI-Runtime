param()

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path '.').Path
$expected = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ($root -ne $expected) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$proofRoot = Join-Path $root '_proof'
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $proofRoot ("phase_pfzip_provenance_gate_" + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$zip = "$pf.zip"

$f1 = Join-Path $pf '01_status.txt'
$f2 = Join-Path $pf '02_head.txt'
$f10 = Join-Path $pf '10_scan_hits.txt'
$f98 = Join-Path $pf '98_gate_pfzip_provenance.txt'

git status *> $f1
git log -1 *> $f2

$selfPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
$targets = Get-ChildItem -Path (Join-Path $root 'tools') -Recurse -Filter '*.ps1' |
  Where-Object { (Resolve-Path -LiteralPath $_.FullName).Path -ne $selfPath } |
  Sort-Object FullName

$rules = @(
  [pscustomobject]@{ id = 'raw_pf_print'; regex = 'Write-Output\s+"PF=\$pf"\s*$' }
  [pscustomobject]@{ id = 'raw_zip_print'; regex = 'Write-Output\s+"ZIP=\$zip"\s*$' }
  [pscustomobject]@{ id = 'raw_pf_writehost'; regex = 'Write-Host\s+"PF=\$pf"\s*$' }
  [pscustomobject]@{ id = 'raw_zip_writehost'; regex = 'Write-Host\s+"ZIP=\$zip"\s*$' }
)

$hits = New-Object System.Collections.Generic.List[object]

foreach ($file in $targets) {
  $lineNumber = 0
  Get-Content -LiteralPath $file.FullName | ForEach-Object {
    $lineNumber++
    $line = $_
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith('#')) { return }

    foreach ($rule in $rules) {
      if ($line -match $rule.regex) {
        $hits.Add([pscustomobject]@{
          rule = $rule.id
          file = $file.FullName
          line = $lineNumber
          text = $trimmed
        })
      }
    }
  }
}

"scan_root=$root" | Set-Content -Path $f10 -Encoding utf8
"scan_target=tools/**/*.ps1" | Add-Content -Path $f10 -Encoding utf8
"scan_rules=$($rules.id -join ',')" | Add-Content -Path $f10 -Encoding utf8
"hit_count=$($hits.Count)" | Add-Content -Path $f10 -Encoding utf8
"" | Add-Content -Path $f10 -Encoding utf8

if ($hits.Count -gt 0) {
  $hits | ForEach-Object {
    "{0}:{1}:{2}:{3}" -f $_.rule, $_.file, $_.line, $_.text
  } | Add-Content -Path $f10 -Encoding utf8
} else {
  'none' | Add-Content -Path $f10 -Encoding utf8
}

$gate = if ($hits.Count -eq 0) { 'PASS' } else { 'FAIL' }

@(
  'phase=pfzip_provenance_gate'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pf"
  "zip=$zip"
  "scan_file_count=$($targets.Count)"
  "hit_count=$($hits.Count)"
  "gate=$gate"
) | Set-Content -Path $f98 -Encoding utf8

if (Test-Path $zip) {
  Remove-Item -Force $zip
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output "PF=$pf"
Write-Output "ZIP=$zip"
Write-Output "GATE=$gate"

if ($gate -eq 'FAIL') {
  Get-Content -Path $f98
  Get-Content -Path $f10 -Tail 120
}
