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

  Invoke-TimedStep -Name "Reconcile BBU payments" -ScriptName "reconcile-bbu-payments.ps1"
  Invoke-TimedStep -Name "Build payment index" -ScriptName "build-payment-index.ps1"
  Invoke-TimedStep -Name "Build Payment Center" -ScriptName "build-commissioner-payment-center.ps1"

  if ($Workbook) {
    $workbookArguments = @{}
    if ($OpenWorkbook) {
      $workbookArguments.Open = $true
    }
    Invoke-TimedStep -Name "Build Excel workbook" -ScriptName "export-bbu-payment-workbook.ps1" -Arguments $workbookArguments
  }
} finally {
  Pop-Location
  $totalWatch.Stop()
}

$summary = [pscustomobject]@{
  sourceImported = -not [string]::IsNullOrWhiteSpace($SourcePath)
  workbookBuilt = [bool]$Workbook
  totalSeconds = [math]::Round($totalWatch.Elapsed.TotalSeconds, 2)
  durations = [pscustomobject]$durations
}

if ($PassThru) {
  $summary
} else {
  $workbookNote = if ($Workbook) { "Excel workbook rebuilt." } else { "Excel workbook skipped; add -Workbook only when you need the .xlsx file refreshed." }
  Write-Host ("Quick BBU Payment Center refresh complete in {0:N2} seconds. {1}" -f $summary.totalSeconds, $workbookNote)
}
