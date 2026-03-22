param(
  [string]$JsonPath = "data/leagues.json",
  [switch]$UpdateStatus,
  [switch]$UpdateNames,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Normalize-FilledCount {
  param(
    [int]$Teams,
    [int]$Filled
  )

  $safeTeams = [math]::Max($Teams, 0)
  $safeFilled = [math]::Max($Filled, 0)
  return [math]::Min($safeFilled, $safeTeams)
}

function Get-SleeperLeagueSnapshot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SleeperLeagueId
  )

  $league = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}" -f $SleeperLeagueId)
  $rosters = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/rosters" -f $SleeperLeagueId)

  $teams = To-Number $league.total_rosters
  $filled = Normalize-FilledCount -Teams $teams -Filled (@($rosters | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.owner_id) }).Count)

  [pscustomobject]@{
    sleeperLeagueId = $SleeperLeagueId
    name = [string]$league.name
    sleeperSeason = [string]$league.season
    teams = $teams
    filled = $filled
    sleeperStatus = ([string]$league.status).Trim().ToLowerInvariant()
    suggestedStatus = if ($teams -gt 0 -and $filled -ge $teams) { "full" } else { "open" }
  }
}

function Add-Warning {
  param(
    [System.Collections.Generic.List[string]]$Warnings,
    [string]$Message
  )

  $Warnings.Add($Message) | Out-Null
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find league data file at '$JsonPath'."
}

$jsonFullPath = (Resolve-Path -LiteralPath $JsonPath).Path
$payload = Get-Content -LiteralPath $jsonFullPath -Raw | ConvertFrom-Json

if (-not $payload.leagues) {
  throw "The JSON file at '$JsonPath' does not contain a 'leagues' array."
}

$results = [System.Collections.Generic.List[object]]::new()
$allWarnings = [System.Collections.Generic.List[string]]::new()

foreach ($league in $payload.leagues) {
  $leagueWarnings = [System.Collections.Generic.List[string]]::new()
  $leagueId = [string]$league.id
  $statusBefore = [string]$league.status
  $teamsBefore = To-Number $league.teams
  $filledBefore = To-Number $league.filled
  $nameBefore = [string]$league.name
  $seasonBefore = [string]$league.sleeperSeason
  $sleeperLeagueId = ([string]$league.sleeperLeagueId).Trim()

  if (-not $leagueId) {
    Add-Warning -Warnings $leagueWarnings -Message "WARN <missing-id>: league record is missing an id."
    continue
  }

  if (-not ([string]$league.constitutionPage).Trim()) {
    Add-Warning -Warnings $leagueWarnings -Message ("WARN {0}: missing constitutionPage." -f $leagueId)
  }

  if (-not ([string]$league.status).Trim()) {
    Add-Warning -Warnings $leagueWarnings -Message ("WARN {0}: missing status." -f $leagueId)
  }

  if ((([string]$league.status).Trim().ToLowerInvariant() -eq "open") -and -not ([string]$league.inviteLink).Trim()) {
    Add-Warning -Warnings $leagueWarnings -Message ("WARN {0}: open league is missing inviteLink." -f $leagueId)
  }

  if (-not ([string]$league.leagueSafeLink).Trim()) {
    Add-Warning -Warnings $leagueWarnings -Message ("WARN {0}: missing leagueSafeLink." -f $leagueId)
  }

  if (-not $sleeperLeagueId) {
    Add-Warning -Warnings $leagueWarnings -Message ("WARN {0}: missing sleeperLeagueId." -f $leagueId)

    $results.Add([pscustomobject]@{
      id = $leagueId
      synced = $false
      changed = $false
      reason = "missing sleeperLeagueId"
      warnings = @($leagueWarnings)
    }) | Out-Null

    foreach ($warning in $leagueWarnings) {
      $allWarnings.Add($warning) | Out-Null
    }

    continue
  }

  try {
    $snapshot = Get-SleeperLeagueSnapshot -SleeperLeagueId $sleeperLeagueId
    $changedFields = [System.Collections.Generic.List[string]]::new()

    if ($league.sleeperSeason -ne $snapshot.sleeperSeason) {
      $league.sleeperSeason = $snapshot.sleeperSeason
      $changedFields.Add("sleeperSeason") | Out-Null
    }

    if ((To-Number $league.teams) -ne $snapshot.teams) {
      $league.teams = $snapshot.teams
      $changedFields.Add("teams") | Out-Null
    }

    if ((To-Number $league.filled) -ne $snapshot.filled) {
      $league.filled = $snapshot.filled
      $changedFields.Add("filled") | Out-Null
    }

    if ($UpdateStatus -and ([string]$league.status).Trim().ToLowerInvariant() -ne $snapshot.suggestedStatus) {
      $league.status = $snapshot.suggestedStatus
      $changedFields.Add("status") | Out-Null
    } elseif (([string]$league.status).Trim().ToLowerInvariant() -ne $snapshot.suggestedStatus) {
      Add-Warning -Warnings $leagueWarnings -Message ("WARN {0}: status '{1}' differs from Sleeper-suggested status '{2}'." -f $leagueId, $statusBefore, $snapshot.suggestedStatus)
    }

    if ($UpdateNames -and $snapshot.name -and ([string]$league.name -ne $snapshot.name)) {
      $league.name = $snapshot.name
      $changedFields.Add("name") | Out-Null
    } elseif ($snapshot.name -and ([string]$league.name -ne $snapshot.name)) {
      Add-Warning -Warnings $leagueWarnings -Message ("WARN {0}: local name differs from Sleeper name '{1}'." -f $leagueId, $snapshot.name)
    }

    if ($snapshot.filled -gt $snapshot.teams) {
      Add-Warning -Warnings $leagueWarnings -Message ("WARN {0}: Sleeper returned filled greater than teams." -f $leagueId)
    }

    if (([string]$league.status).Trim().ToLowerInvariant() -eq "full" -and $snapshot.filled -lt $snapshot.teams) {
      Add-Warning -Warnings $leagueWarnings -Message ("WARN {0}: marked full locally but Sleeper shows open spots." -f $leagueId)
    }

    if (([string]$league.status).Trim().ToLowerInvariant() -eq "open" -and $snapshot.filled -ge $snapshot.teams) {
      Add-Warning -Warnings $leagueWarnings -Message ("WARN {0}: marked open locally but Sleeper shows full." -f $leagueId)
    }

    $results.Add([pscustomobject]@{
      id = $leagueId
      synced = $true
      changed = ($changedFields.Count -gt 0)
      changedFields = @($changedFields)
      teamsBefore = $teamsBefore
      teamsAfter = $snapshot.teams
      filledBefore = $filledBefore
      filledAfter = $snapshot.filled
      seasonBefore = $seasonBefore
      seasonAfter = $snapshot.sleeperSeason
      nameBefore = $nameBefore
      nameAfter = [string]$league.name
      warnings = @($leagueWarnings)
    }) | Out-Null
  } catch {
    Add-Warning -Warnings $leagueWarnings -Message ("ERROR {0}: Sleeper sync failed - {1}" -f $leagueId, $_.Exception.Message)

    $results.Add([pscustomobject]@{
      id = $leagueId
      synced = $false
      changed = $false
      reason = $_.Exception.Message
      warnings = @($leagueWarnings)
    }) | Out-Null
  }

  foreach ($warning in $leagueWarnings) {
    $allWarnings.Add($warning) | Out-Null
  }
}

$payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonFullPath

$report = [pscustomobject]@{
  jsonPath = $JsonPath
  updatedAt = (Get-Date).ToString("s")
  syncedCount = @($results | Where-Object { $_.synced }).Count
  changedCount = @($results | Where-Object { $_.changed }).Count
  warningCount = $allWarnings.Count
  results = @($results)
  warnings = @($allWarnings)
}

if ($PassThru) {
  $report
} else {
  Write-Host ("Synced {0} league(s); changed {1}; warnings {2}" -f $report.syncedCount, $report.changedCount, $report.warningCount)

  foreach ($result in $results) {
    if ($result.synced -and $result.changed) {
      Write-Host ("UPDATED {0}: {1}" -f $result.id, (($result.changedFields -join ", ")))
    } elseif ($result.synced) {
      Write-Host ("OK {0}: no field changes" -f $result.id)
    } else {
      Write-Host ("SKIP {0}: {1}" -f $result.id, $result.reason)
    }
  }

  if ($allWarnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Warnings:"
    foreach ($warning in $allWarnings) {
      Write-Host $warning
    }
  }
}
