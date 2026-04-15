param(
  [switch]$Strict,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$issues = [System.Collections.Generic.List[object]]::new()

function Add-Issue {
  param(
    [string]$Severity,
    [string]$Source,
    [string]$Message
  )

  $issues.Add([pscustomobject]@{
    severity = $Severity
    source = $Source
    message = $Message
  }) | Out-Null
}

function Read-File {
  param(
    [string]$RelativePath
  )

  $fullPath = Join-Path $repoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $fullPath)) {
    Add-Issue -Severity "error" -Source $RelativePath -Message "Missing required file."
    return ""
  }

  return Get-Content -LiteralPath $fullPath -Raw
}

$requiredFiles = @(
  "index.html",
  "assets/css/styles.css",
  "assets/js/app.js",
  "data/leagues.json",
  "data/donations.json"
)

foreach ($file in $requiredFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $file))) {
    Add-Issue -Severity "error" -Source $file -Message "Missing required file."
  }
}

$indexHtml = Read-File -RelativePath "index.html"
$appJs = Read-File -RelativePath "assets/js/app.js"

foreach ($requiredId in @("limitedSpotsContainer", "formatFilters", "leaguesContainer", "donationProjectsContainer", "lastUpdated")) {
  if ($indexHtml -notmatch ("id=""{0}""" -f [regex]::Escape($requiredId))) {
    Add-Issue -Severity "error" -Source "index.html" -Message ("Missing required element id '{0}'." -f $requiredId)
  }
}

foreach ($format in @("all", "redraft", "dynasty", "dynastybracket", "bestball", "bracket", "keeper", "chopped")) {
  if ($indexHtml -notmatch ("data-format=""{0}""" -f [regex]::Escape($format))) {
    Add-Issue -Severity "error" -Source "index.html" -Message ("Missing format filter '{0}'." -f $format)
  }
}

foreach ($page in @(
  "redraft-constitution.html",
  "dynasty-constitution.html",
  "dynasty-bracket-constitution.html",
  "bestball-constitution.html",
  "bracket-constitution.html",
  "keeper-constitution.html",
  "chopped-constitution.html"
)) {
  if ($indexHtml -notmatch [regex]::Escape($page)) {
    Add-Issue -Severity "warning" -Source "index.html" -Message ("Homepage does not link to '{0}'." -f $page)
  }

  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $page))) {
    Add-Issue -Severity "error" -Source $page -Message "Linked constitution page file is missing."
  }
}

if ($indexHtml -notmatch 'assets/css/styles\.css\?v=') {
  Add-Issue -Severity "warning" -Source "index.html" -Message "Missing cache-busting query string on assets/css/styles.css."
}

if ($indexHtml -notmatch 'assets/js/app\.js\?v=') {
  Add-Issue -Severity "warning" -Source "index.html" -Message "Missing cache-busting query string on assets/js/app.js."
}

foreach ($formatKey in @("redraft", "dynasty", "dynastybracket", "bestball", "bracket", "keeper", "chopped")) {
  if ($appJs -notmatch ("{0}:" -f [regex]::Escape($formatKey))) {
    Add-Issue -Severity "error" -Source "assets/js/app.js" -Message ("FORMAT_META appears to be missing '{0}'." -f $formatKey)
  }
}

$validatorScript = Join-Path $PSScriptRoot "validate-leagues-json.ps1"
if (-not (Test-Path -LiteralPath $validatorScript)) {
  Add-Issue -Severity "error" -Source "scripts/validate-leagues-json.ps1" -Message "Validator script is missing."
} else {
  $validatorReport = & $validatorScript -PassThru
  foreach ($issue in $validatorReport.issues) {
    Add-Issue -Severity $issue.severity -Source "data/leagues.json" -Message ("{0}: {1}" -f $issue.leagueId, $issue.message)
  }
}

$donationValidatorScript = Join-Path $PSScriptRoot "validate-donations-json.ps1"
if (-not (Test-Path -LiteralPath $donationValidatorScript)) {
  Add-Issue -Severity "error" -Source "scripts/validate-donations-json.ps1" -Message "Donation validator script is missing."
} else {
  $donationReport = & $donationValidatorScript -PassThru
  foreach ($issue in $donationReport.issues) {
    Add-Issue -Severity $issue.severity -Source "data/donations.json" -Message ("{0}: {1}" -f $issue.project, $issue.message)
  }
}

$constitutionCheckScript = Join-Path $PSScriptRoot "check-constitutions.ps1"
if (-not (Test-Path -LiteralPath $constitutionCheckScript)) {
  Add-Issue -Severity "error" -Source "scripts/check-constitutions.ps1" -Message "Constitution check script is missing."
} else {
  $constitutionReport = & $constitutionCheckScript -PassThru
  foreach ($issue in $constitutionReport.issues) {
    Add-Issue -Severity $issue.severity -Source $issue.source -Message $issue.message
  }
}

$errorCount = @($issues | Where-Object { $_.severity -eq "error" }).Count
$warningCount = @($issues | Where-Object { $_.severity -eq "warning" }).Count
$report = [pscustomobject]@{
  checkedAt = (Get-Date).ToString("s")
  errorCount = $errorCount
  warningCount = $warningCount
  issues = @($issues)
}

if ($PassThru) {
  $report
} else {
  Write-Host ("Site check complete: {0} error(s), {1} warning(s)" -f $errorCount, $warningCount)
  foreach ($issue in $issues) {
    Write-Host ("{0} [{1}] {2}" -f $issue.severity.ToUpperInvariant(), $issue.source, $issue.message)
  }
}

if ($Strict -and $errorCount -gt 0) {
  exit 1
}
