param(
  [string]$PreviewTarget = "index.html",
  [switch]$NoPreview,
  [switch]$NoOpen,
  [switch]$TreatWarningsAsBlocking,
  [switch]$PassThru,
  [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$siteCheckScript = Join-Path $PSScriptRoot "check-site.ps1"
if (-not (Test-Path -LiteralPath $siteCheckScript)) {
  throw "Could not find site check script at '$siteCheckScript'."
}

$siteReport = & $siteCheckScript -PassThru
$previewResult = $null
$previewWarning = $null

if (-not $NoPreview) {
  $previewScript = Join-Path $PSScriptRoot "open-preview.ps1"

  if (-not (Test-Path -LiteralPath $previewScript)) {
    $previewWarning = "Preview script is missing."
  } else {
    try {
      if ($NoOpen) {
        $previewResult = & $previewScript -Target $PreviewTarget -NoOpen -PassThru
      } else {
        $previewResult = & $previewScript -Target $PreviewTarget -PassThru
      }
    } catch {
      $previewWarning = $_.Exception.Message
    }
  }
}

$status = if ($siteReport.errorCount -gt 0) {
  "not-ready"
} elseif ($TreatWarningsAsBlocking -and $siteReport.warningCount -gt 0) {
  "not-ready"
} elseif ($siteReport.warningCount -gt 0 -or $previewWarning) {
  "ready-with-warnings"
} else {
  "ready"
}

$report = [pscustomobject]@{
  checkedAt = (Get-Date).ToString("s")
  status = $status
  readyToPush = ($status -eq "ready" -or $status -eq "ready-with-warnings")
  treatWarningsAsBlocking = [bool]$TreatWarningsAsBlocking
  previewTarget = $PreviewTarget
  previewSkipped = [bool]$NoPreview
  previewUrl = if ($previewResult) { $previewResult.url } else { $null }
  previewWarning = $previewWarning
  errorCount = $siteReport.errorCount
  warningCount = $siteReport.warningCount
  issues = @($siteReport.issues)
}

if ($PassThru) {
  $report
} else {
  $statusLabel = switch ($status) {
    "ready" { "READY" }
    "ready-with-warnings" { "READY WITH WARNINGS" }
    default { "NOT READY" }
  }

  Write-Host ("Release helper status: {0}" -f $statusLabel)
  Write-Host ("Site check: {0} error(s), {1} warning(s)" -f $report.errorCount, $report.warningCount)

  if ($NoPreview) {
    Write-Host "Preview: skipped"
  } elseif ($previewResult) {
    Write-Host ("Preview: {0}" -f $previewResult.url)
  } elseif ($previewWarning) {
    Write-Host ("Preview warning: {0}" -f $previewWarning)
  }

  if ($report.issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Issues:"
    foreach ($issue in $report.issues) {
      Write-Host ("- [{0}] {1}" -f $issue.source, $issue.message)
    }
  }
}

if ($Strict -and $status -eq "not-ready") {
  exit 1
}
