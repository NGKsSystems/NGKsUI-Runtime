Set-StrictMode -Version 3

function Get-ReferencedRuntimeProofFolders {
  param([string]$PhaseProofFolder)

  $result = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  $stdoutFiles = Get-ChildItem -Path $PhaseProofFolder -Filter '*_stdout.txt' -File -ErrorAction SilentlyContinue
  foreach ($f in $stdoutFiles) {
    $lines = Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
      if ($line -match '^PROOF_PATH=(.+)$') {
        $p = $Matches[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p)) {
          [void]$result.Add((Resolve-Path -LiteralPath $p).Path)
        }
      }
    }
  }
  return @($result)
}

function New-SingleProofBundle {
  param(
    [string]$PhaseProofFolder,
    [string]$BundleZipPath
  )

  $phaseResolved = (Resolve-Path -LiteralPath $PhaseProofFolder).Path
  $referenced = @(Get-ReferencedRuntimeProofFolders -PhaseProofFolder $phaseResolved)
  $itemsToZip = @($phaseResolved) + $referenced

  if (Test-Path -LiteralPath $BundleZipPath) {
    Remove-Item -LiteralPath $BundleZipPath -Force
  }

  Compress-Archive -Path $itemsToZip -DestinationPath $BundleZipPath -Force

  return [pscustomobject]@{
    BundleZipPath = $BundleZipPath
    ItemCount = $itemsToZip.Count
    IncludedItems = $itemsToZip
  }
}

function Remove-BundledRuntimeProofFolders {
  param([string[]]$RuntimeProofFolders)

  $deleted = @()
  foreach ($p in $RuntimeProofFolders) {
    if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p).PSIsContainer)) {
      Remove-Item -LiteralPath $p -Recurse -Force
      $deleted += $p
    }
  }
  return $deleted
}
