param(
  [string]$SourcePath,
  [switch]$Workbook,
  [switch]$OpenWorkbook,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$durations = [ordered]@{}
$totalWatch = [System.Diagnostics.Stopwatch]::StartNew()

function Invoke-TimedStep {
  param(
    [string]$Name,
    [string]$ScriptName,
    [hashtable]$Arguments = @{}
  )

  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  & (Join-Path $PSScriptRoot $ScriptName) @Arguments *> $null
  if (-not $?) {
    throw "BBU payment refresh step failed: $Name"
  }
  $watch.Stop()
  $script:durations[$Name] = [math]::Round($watch.Elapsed.TotalSeconds, 2)
}

if ($OpenWorkbook) {
  $Workbook = $true
}

Push-Location $repoRoot
try {
  if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
    Invoke-TimedStep -Name "Import LeagueSafe export" -ScriptName "import-bbu-leaguesafe-export.ps1" -Arguments @{ SourcePath = $SourcePath }
  }

  Invoke-TimedStep -Name "Reconcile BBU readable reports" -ScriptName "reconcile-bbu-payments.ps1"
} finally {
  Pop-Location
  $totalWatch.Stop()
}

$summary = [pscustomobject]@{
  sourceImported = -not [string]::IsNullOrWhiteSpace($SourcePath)
  workbookBuilt = $false
  totalSeconds = [math]::Round($totalWatch.Elapsed.TotalSeconds, 2)
  durations = [pscustomobject]$durations
}

if ($PassThru) {
  $summary
} else {
  $workbookNote = if ($Workbook) { "Workbook output is skipped because the BBU workflow now uses readable text reports only." } else { "Readable BBU reports refreshed." }
  Write-Host ("Quick BBU payment refresh complete in {0:N2} seconds. {1}" -f $summary.totalSeconds, $workbookNote)
}
