param(
  [string]$JsonPath = "data/leagues.json",
  [switch]$PassThru,
  [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$validFormats = @("redraft", "dynasty", "bestball", "bracket", "keeper", "chopped")
$validStatuses = @("open", "full", "coming-soon")
$idPrefixByFormat = @{
  redraft = "RD"
  dynasty = "DYN"
  bestball = "BBU"
  bracket = "RDB"
  keeper = "KP"
  chopped = "CH"
}
$knownConstitutionPages = @(
  "redraft-constitution.html",
  "dynasty-constitution.html",
  "bestball-constitution.html",
  "bracket-constitution.html",
  "chopped-constitution.html"
)

function To-Number {
  param(
    [AllowNull()]
    [object]$Value
  )

  $cleaned = [string]$Value
  $cleaned = $cleaned -replace '[$,%\s]', ''
  $cleaned = $cleaned -replace ',', ''

  $parsed = 0
  if ([double]::TryParse($cleaned, [ref]$parsed)) {
    return [int][math]::Floor($parsed)
  }

  return 0
}

function Test-HttpUrl {
  param(
    [AllowNull()]
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }

  $uri = $null
  return [System.Uri]::TryCreate($Value.Trim(), [System.UriKind]::Absolute, [ref]$uri) -and (
    $uri.Scheme -eq "http" -or $uri.Scheme -eq "https"
  )
}

function Add-Issue {
  param(
    [System.Collections.Generic.List[object]]$Issues,
    [string]$Severity,
    [string]$LeagueId,
    [string]$Message
  )

  $Issues.Add([pscustomobject]@{
    severity = $Severity
    leagueId = $LeagueId
    message = $Message
  }) | Out-Null
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find league data file at '$JsonPath'."
}

$jsonFullPath = (Resolve-Path -LiteralPath $JsonPath).Path
$payload = Get-Content -LiteralPath $jsonFullPath -Raw | ConvertFrom-Json

if (-not $payload.leagues) {
  throw "The JSON file at '$JsonPath' does not contain a 'leagues' array."
}

$issues = [System.Collections.Generic.List[object]]::new()
$seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($league in $payload.leagues) {
  $leagueId = [string]$league.id
  $format = ([string]$league.format).Trim().ToLowerInvariant()
  $status = ([string]$league.status).Trim().ToLowerInvariant()
  $constitutionPage = ([string]$league.constitutionPage).Trim()
  $inviteLink = ([string]$league.inviteLink).Trim()
  $leagueSafeLink = ([string]$league.leagueSafeLink).Trim()
  $sleeperLeagueId = ([string]$league.sleeperLeagueId).Trim()
  $division = ([string]$league.division).Trim()
  $teams = To-Number $league.teams
  $filled = To-Number $league.filled
  $buyIn = To-Number $league.buyIn

  if ([string]::IsNullOrWhiteSpace($leagueId)) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId "<missing-id>" -Message "League record is missing id."
    continue
  }

  if (-not $seenIds.Add($leagueId)) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message "Duplicate league id."
  }

  if (-not $validFormats.Contains($format)) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message ("Invalid format '{0}'." -f $league.format)
  }

  if (-not $validStatuses.Contains($status)) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message ("Invalid status '{0}'." -f $league.status)
  }

  if ($validFormats.Contains($format)) {
    $expectedPrefix = $idPrefixByFormat[$format]
    if (-not $leagueId.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message ("ID prefix does not match format '{0}'." -f $format)
    }
  }

  if ($teams -le 0) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message "teams must be greater than 0."
  }

  if ($filled -lt 0) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message "filled must be 0 or greater."
  }

  if ($filled -gt $teams -and $teams -gt 0) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message "filled cannot exceed teams."
  }

  if ($buyIn -lt 0) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message "buyIn cannot be negative."
  }

  if ([string]::IsNullOrWhiteSpace($constitutionPage)) {
    Add-Issue -Issues $issues -Severity "warning" -LeagueId $leagueId -Message "Missing constitutionPage."
  } elseif ($constitutionPage -notin $knownConstitutionPages) {
    Add-Issue -Issues $issues -Severity "warning" -LeagueId $leagueId -Message ("Unknown constitutionPage '{0}'." -f $constitutionPage)
  } elseif (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $jsonFullPath | Split-Path -Parent) $constitutionPage))) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message ("constitutionPage file does not exist: {0}" -f $constitutionPage)
  }

  if ($status -eq "open" -and [string]::IsNullOrWhiteSpace($inviteLink)) {
    Add-Issue -Issues $issues -Severity "warning" -LeagueId $leagueId -Message "Open league is missing inviteLink."
  }

  if (-not [string]::IsNullOrWhiteSpace($inviteLink) -and -not (Test-HttpUrl $inviteLink)) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message "inviteLink is not a valid http/https URL."
  }

  if (-not [string]::IsNullOrWhiteSpace($leagueSafeLink) -and -not (Test-HttpUrl $leagueSafeLink)) {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message "leagueSafeLink is not a valid http/https URL."
  }

  if ([string]::IsNullOrWhiteSpace($leagueSafeLink)) {
    Add-Issue -Issues $issues -Severity "warning" -LeagueId $leagueId -Message "Missing leagueSafeLink."
  }

  if (-not [string]::IsNullOrWhiteSpace($sleeperLeagueId) -and $sleeperLeagueId -notmatch '^\d+$') {
    Add-Issue -Issues $issues -Severity "error" -LeagueId $leagueId -Message "sleeperLeagueId must be numeric when present."
  }

  if ([string]::IsNullOrWhiteSpace($sleeperLeagueId)) {
    Add-Issue -Issues $issues -Severity "warning" -LeagueId $leagueId -Message "Missing sleeperLeagueId."
  }

  if ([string]::IsNullOrWhiteSpace([string]$league.sleeperSeason)) {
    Add-Issue -Issues $issues -Severity "warning" -LeagueId $leagueId -Message "Missing sleeperSeason."
  }

  if ($format -eq "bracket" -and [string]::IsNullOrWhiteSpace($division)) {
    Add-Issue -Issues $issues -Severity "warning" -LeagueId $leagueId -Message "Bracket league is missing draft type in division."
  }

  if ($format -eq "chopped" -and $teams -ne 18) {
    Add-Issue -Issues $issues -Severity "warning" -LeagueId $leagueId -Message "Chopped league is expected to use 18 teams."
  }
}

$errorCount = @($issues | Where-Object { $_.severity -eq "error" }).Count
$warningCount = @($issues | Where-Object { $_.severity -eq "warning" }).Count
$report = [pscustomobject]@{
  jsonPath = $JsonPath
  checkedAt = (Get-Date).ToString("s")
  leagueCount = @($payload.leagues).Count
  errorCount = $errorCount
  warningCount = $warningCount
  issues = @($issues)
}

if ($PassThru) {
  $report
} else {
  Write-Host ("Checked {0} league(s): {1} error(s), {2} warning(s)" -f $report.leagueCount, $errorCount, $warningCount)
  foreach ($issue in $issues) {
    Write-Host ("{0} {1}: {2}" -f $issue.severity.ToUpperInvariant(), $issue.leagueId, $issue.message)
  }
}

if ($Strict -and $errorCount -gt 0) {
  exit 1
}
