param(
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$GroupsPath = "data/bracket-groups.json",
  [string]$LedgerPath = "data/bracket-ledger.json",
  [string[]]$GroupIds,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-StringValue {
  param(
    [AllowNull()]
    [object]$Value
  )

  return ([string]$Value).Trim()
}

function Get-PropertyValue {
  param(
    [AllowNull()]
    [object]$Object,
    [string]$PropertyName
  )

  if ($null -eq $Object) {
    return $null
  }

  if ($Object.PSObject.Properties.Match($PropertyName).Count -gt 0) {
    return $Object.PSObject.Properties[$PropertyName].Value
  }

  return $null
}

function Convert-ToFlatObjectArray {
  param(
    [AllowNull()]
    [object]$Value
  )

  $items = [System.Collections.Generic.List[object]]::new()
  foreach ($item in @($Value)) {
    if ($null -eq $item) {
      continue
    }

    if ($item -is [System.Array]) {
      foreach ($nested in $item) {
        if ($null -ne $nested) {
          $items.Add($nested) | Out-Null
        }
      }
    } else {
      $items.Add($item) | Out-Null
    }
  }

  return @($items)
}

function Get-TeamName {
  param(
    [AllowNull()]
    [object]$User,
    [AllowNull()]
    [object]$Roster,
    [AllowNull()]
    [object]$ExistingEntry
  )

  $candidateValues = @(
    $(if ($User -and $User.PSObject.Properties.Match("metadata").Count -gt 0) { Get-PropertyValue $User.metadata "team_name" } else { $null }),
    $(if ($Roster -and $Roster.PSObject.Properties.Match("metadata").Count -gt 0) { Get-PropertyValue $Roster.metadata "team_name" } else { $null }),
    $(if ($ExistingEntry) { $ExistingEntry.teamName } else { $null })
  )

  foreach ($value in $candidateValues) {
    $text = Get-StringValue $value
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      return $text
    }
  }

  return ""
}

function Get-IntValue {
  param(
    [AllowNull()]
    [object]$Value
  )

  $parsed = 0
  if ([int]::TryParse((Get-StringValue $Value), [ref]$parsed)) {
    return $parsed
  }

  return 0
}

function Get-PointsForValue {
  param(
    [AllowNull()]
    [object]$Settings
  )

  $whole = 0
  $decimal = 0
  [void][int]::TryParse((Get-StringValue (Get-PropertyValue $Settings "fpts")), [ref]$whole)
  [void][int]::TryParse((Get-StringValue (Get-PropertyValue $Settings "fpts_decimal")), [ref]$decimal)

  return [math]::Round(($whole + ($decimal / 100.0)), 2)
}

function Get-RecordPct {
  param(
    [int]$Wins,
    [int]$Losses,
    [int]$Ties
  )

  $games = $Wins + $Losses + $Ties
  if ($games -le 0) {
    return 0.0
  }

  return [math]::Round((($Wins + ($Ties * 0.5)) / $games), 6)
}

function Get-StandingsOrder {
  param(
    [AllowNull()]
    [object[]]$Entries
  )

  return @($Entries | Sort-Object `
    @{ Expression = { $_.recordPct }; Descending = $true }, `
    @{ Expression = { $_.pointsFor }; Descending = $true }, `
    @{ Expression = { $_.wins }; Descending = $true }, `
    @{ Expression = { $_.ties }; Descending = $true }, `
    @{ Expression = { $_.displayName }; Descending = $false }, `
    @{ Expression = { $_.rosterId }; Descending = $false })
}

function Get-WildCardOrder {
  param(
    [AllowNull()]
    [object[]]$Entries
  )

  return @($Entries | Sort-Object `
    @{ Expression = { $_.pointsFor }; Descending = $true }, `
    @{ Expression = { $_.recordPct }; Descending = $true }, `
    @{ Expression = { $_.wins }; Descending = $true }, `
    @{ Expression = { $_.ties }; Descending = $true }, `
    @{ Expression = { $_.displayName }; Descending = $false }, `
    @{ Expression = { $_.rosterId }; Descending = $false })
}

function Get-BracketLedgerPrompts {
  [pscustomobject]@{
    refreshGroupsAndSeeds = "Run the bracket ledger sync and refresh data/bracket-ledger.json from Sleeper so the current bracket leagues, managers, standings, and seeding outputs are up to date. If the season is not far enough along for meaningful seeds, tell me that the results are only structural or provisional."
    refreshSpecificGroup = "Run the bracket ledger sync for BRACKET-2026-1 only and refresh data/bracket-ledger.json from Sleeper so that bracket group's standings and playoff output are up to date."
    refreshOverallStandings = "Run the bracket ledger sync and refresh data/bracket-ledger.json from Sleeper, then give me the current combined overall standings for BRACKET-2026-1 with rank, team name, league/division, record, and points for. If the season is not far enough along or the group is not full yet, tell me the standings are provisional."
  }
}

function Resolve-ExistingGroup {
  param(
    [AllowNull()]
    [object[]]$ExistingGroups,
    [string]$GroupId
  )

  foreach ($group in @($ExistingGroups)) {
    if ((Get-StringValue $group.groupId) -eq $GroupId) {
      return $group
    }
  }

  return $null
}

function New-RoundOf16Template {
  $templates = [System.Collections.Generic.List[object]]::new()
  foreach ($match in @(
    @{ order = 1; home = "Highest Remaining Seed"; away = "Lowest Remaining Seed" },
    @{ order = 2; home = "4th Highest Remaining Seed"; away = "5th Lowest Remaining Seed" },
    @{ order = 3; home = "5th Highest Remaining Seed"; away = "4th Lowest Remaining Seed" },
    @{ order = 4; home = "8th Highest Remaining Seed"; away = "Wild Card Winner" },
    @{ order = 5; home = "6th Highest Remaining Seed"; away = "3rd Lowest Remaining Seed" },
    @{ order = 6; home = "3rd Highest Remaining Seed"; away = "6th Lowest Remaining Seed" },
    @{ order = 7; home = "7th Highest Remaining Seed"; away = "2nd Lowest Remaining Seed" },
    @{ order = 8; home = "2nd Highest Remaining Seed"; away = "7th Lowest Remaining Seed" }
  )) {
    $templates.Add([pscustomobject]@{
      order = $match.order
      home = $match.home
      away = $match.away
    }) | Out-Null
  }

  return @($templates)
}

if (-not (Test-Path -LiteralPath $LeaguesJsonPath)) {
  throw "Could not find league data file at '$LeaguesJsonPath'."
}

if (-not (Test-Path -LiteralPath $GroupsPath)) {
  throw "Could not find bracket group config at '$GroupsPath'."
}

$leaguePayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $LeaguesJsonPath).Path -Raw | ConvertFrom-Json
$groupPayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $GroupsPath).Path -Raw | ConvertFrom-Json

if (-not $leaguePayload.leagues) {
  throw "The JSON file at '$LeaguesJsonPath' does not contain a 'leagues' array."
}

if (-not $groupPayload.groups) {
  throw "The JSON file at '$GroupsPath' does not contain a 'groups' array."
}

$ledgerExists = Test-Path -LiteralPath $LedgerPath
if ($ledgerExists) {
  $existingLedger = Get-Content -LiteralPath (Resolve-Path -LiteralPath $LedgerPath).Path -Raw | ConvertFrom-Json
} else {
  $existingLedger = [pscustomobject]@{
    prompts = Get-BracketLedgerPrompts
    generatedAt = ""
    groups = @()
  }
}

$selectedGroups = @($groupPayload.groups)
if ($GroupIds -and $GroupIds.Count -gt 0) {
  $lookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($groupId in $GroupIds) {
    [void]$lookup.Add((Get-StringValue $groupId))
  }

  $selectedGroups = @($selectedGroups | Where-Object { $lookup.Contains((Get-StringValue $_.groupId)) })
}

if (-not $selectedGroups -or $selectedGroups.Count -eq 0) {
  throw "No bracket groups matched the current selection."
}

$updatedGroups = [System.Collections.Generic.List[object]]::new()
$results = [System.Collections.Generic.List[object]]::new()

foreach ($group in ($selectedGroups | Sort-Object { Get-StringValue $_.groupId })) {
  $groupId = Get-StringValue $group.groupId
  $existingGroup = Resolve-ExistingGroup -ExistingGroups $existingLedger.groups -GroupId $groupId
  $leagueRecordIds = @($group.leagueRecordIds | ForEach-Object { Get-StringValue $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

  $groupLeagues = [System.Collections.Generic.List[object]]::new()
  foreach ($leagueRecordId in $leagueRecordIds) {
    $leagueRecord = @($leaguePayload.leagues | Where-Object { (Get-StringValue $_.id) -eq $leagueRecordId }) | Select-Object -First 1
    if (-not $leagueRecord) {
      throw "Bracket group '$groupId' references missing league '$leagueRecordId'."
    }

    if ((Get-StringValue $leagueRecord.format).ToLowerInvariant() -notin @("bracket", "dynastybracket")) {
      throw "Bracket group '$groupId' references a league that is not bracket-enabled: '$leagueRecordId'."
    }

    if ([string]::IsNullOrWhiteSpace((Get-StringValue $leagueRecord.sleeperLeagueId))) {
      throw "Bracket league '$leagueRecordId' is missing sleeperLeagueId."
    }

    $groupLeagues.Add($leagueRecord) | Out-Null
  }

  $allTeams = [System.Collections.Generic.List[object]]::new()
  $leagueSnapshots = [System.Collections.Generic.List[object]]::new()

  foreach ($leagueRecord in $groupLeagues) {
    $leagueRecordId = Get-StringValue $leagueRecord.id
    $sleeperLeagueId = Get-StringValue $leagueRecord.sleeperLeagueId

    $sleeperLeague = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}" -f $sleeperLeagueId)
    $users = Convert-ToFlatObjectArray (Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/users" -f $sleeperLeagueId))
    $rosters = Convert-ToFlatObjectArray (Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/rosters" -f $sleeperLeagueId))

    $usersById = @{}
    foreach ($user in $users) {
      $userId = Get-StringValue (Get-PropertyValue $user "user_id")
      if (-not [string]::IsNullOrWhiteSpace($userId)) {
        $usersById[$userId] = $user
      }
    }

    $teamEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($roster in ($rosters | Sort-Object @{ Expression = { Get-IntValue (Get-PropertyValue $_ "roster_id") }; Descending = $false })) {
      $ownerId = Get-StringValue (Get-PropertyValue $roster "owner_id")
      if ([string]::IsNullOrWhiteSpace($ownerId)) {
        continue
      }

      $user = if ($usersById.ContainsKey($ownerId)) { $usersById[$ownerId] } else { $null }
      $settings = Get-PropertyValue $roster "settings"
      $wins = Get-IntValue (Get-PropertyValue $settings "wins")
      $losses = Get-IntValue (Get-PropertyValue $settings "losses")
      $ties = Get-IntValue (Get-PropertyValue $settings "ties")
      $pointsFor = Get-PointsForValue -Settings $settings
      $recordPct = Get-RecordPct -Wins $wins -Losses $losses -Ties $ties

      $entry = [pscustomobject]@{
        groupId = $groupId
        leagueRecordId = $leagueRecordId
        sleeperLeagueId = $sleeperLeagueId
        division = Get-StringValue $leagueRecord.division
        localLeagueName = Get-StringValue $leagueRecord.name
        sleeperLeagueName = Get-StringValue (Get-PropertyValue $sleeperLeague "name")
        ownerId = $ownerId
        rosterId = Get-IntValue (Get-PropertyValue $roster "roster_id")
        displayName = Get-StringValue (Get-PropertyValue $user "display_name")
        teamName = Get-TeamName -User $user -Roster $roster -ExistingEntry $null
        wins = $wins
        losses = $losses
        ties = $ties
        recordPct = $recordPct
        pointsFor = $pointsFor
        pointsForDisplay = ("{0:N2}" -f $pointsFor)
        seasonStatus = Get-StringValue (Get-PropertyValue $sleeperLeague "status")
      }

      $teamEntries.Add($entry) | Out-Null
      $allTeams.Add($entry) | Out-Null
    }

    $orderedLeagueTeams = Get-StandingsOrder -Entries @($teamEntries)
    $divisionWinner = @($orderedLeagueTeams | Select-Object -First 1)

    $leagueSnapshots.Add([pscustomobject]@{
      leagueRecordId = $leagueRecordId
      sleeperLeagueId = $sleeperLeagueId
      localLeagueName = Get-StringValue $leagueRecord.name
      sleeperLeagueName = Get-StringValue (Get-PropertyValue $sleeperLeague "name")
      division = Get-StringValue $leagueRecord.division
      status = Get-StringValue (Get-PropertyValue $sleeperLeague "status")
      standings = @($orderedLeagueTeams)
      divisionWinner = if ($divisionWinner.Count -gt 0) { $divisionWinner[0] } else { $null }
    }) | Out-Null
  }

  $overallStandings = [System.Collections.Generic.List[object]]::new()
  $overallRank = 1
  foreach ($team in (Get-StandingsOrder -Entries @($allTeams))) {
    $resolvedTeamName = Get-StringValue $team.teamName
    if ([string]::IsNullOrWhiteSpace($resolvedTeamName)) {
      $resolvedTeamName = Get-StringValue $team.displayName
    }

    $overallStandings.Add([pscustomobject]@{
      rank = $overallRank
      teamName = $resolvedTeamName
      displayName = Get-StringValue $team.displayName
      leagueRecordId = Get-StringValue $team.leagueRecordId
      leagueName = Get-StringValue $team.localLeagueName
      division = Get-StringValue $team.division
      record = ("{0}-{1}-{2}" -f $team.wins, $team.losses, $team.ties)
      pointsFor = $team.pointsFor
      pointsForDisplay = Get-StringValue $team.pointsForDisplay
      ownerId = Get-StringValue $team.ownerId
      rosterId = $team.rosterId
    }) | Out-Null

    $overallRank++
  }

  $divisionWinners = Get-StandingsOrder -Entries @($leagueSnapshots | ForEach-Object { $_.divisionWinner } | Where-Object { $null -ne $_ })
  $divisionWinnerOwnerIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $seededDivisionWinners = [System.Collections.Generic.List[object]]::new()
  $seedNumber = 1
  foreach ($winner in $divisionWinners) {
    [void]$divisionWinnerOwnerIds.Add((Get-StringValue $winner.ownerId))
    $seededDivisionWinners.Add([pscustomobject]@{
      seed = $seedNumber
      seedType = "division-winner"
      team = $winner
    }) | Out-Null
    $seedNumber += 1
  }

  $remainingTeams = @($allTeams | Where-Object { -not $divisionWinnerOwnerIds.Contains((Get-StringValue $_.ownerId)) })
  $orderedRemaining = Get-StandingsOrder -Entries $remainingTeams

  $seededDirectQualifiers = [System.Collections.Generic.List[object]]::new()
  $directQualifierTarget = Get-IntValue (Get-PropertyValue $group.rules "directQualifiers")
  $directQualifierCount = [math]::Max($directQualifierTarget - $seededDivisionWinners.Count, 0)

  $remainingAfterDirect = [System.Collections.Generic.List[object]]::new()
  foreach ($team in $orderedRemaining) {
    if ($seededDirectQualifiers.Count -lt $directQualifierCount) {
      $seededDirectQualifiers.Add([pscustomobject]@{
        seed = ($seededDivisionWinners.Count + $seededDirectQualifiers.Count + 1)
        seedType = "direct-qualifier"
        team = $team
      }) | Out-Null
    } else {
      $remainingAfterDirect.Add($team) | Out-Null
    }
  }

  $wildCardCount = Get-IntValue (Get-PropertyValue $group.rules "wildCards")
  $orderedWildCardCandidates = Get-WildCardOrder -Entries @($remainingAfterDirect)
  $seededWildCards = [System.Collections.Generic.List[object]]::new()
  $bubbleTeams = [System.Collections.Generic.List[object]]::new()

  foreach ($team in $orderedWildCardCandidates) {
    if ($seededWildCards.Count -lt $wildCardCount) {
      $seededWildCards.Add([pscustomobject]@{
        seed = ($seededDivisionWinners.Count + $seededDirectQualifiers.Count + $seededWildCards.Count + 1)
        seedType = "wild-card"
        team = $team
      }) | Out-Null
    } else {
      $bubbleTeams.Add($team) | Out-Null
    }
  }

  $playoffField = @(
    @($seededDivisionWinners) +
    @($seededDirectQualifiers) +
    @($seededWildCards)
  ) | Sort-Object seed

  $week13MainRound = [System.Collections.Generic.List[object]]::new()
  foreach ($topSeed in 1..15) {
    $bottomSeed = 31 - $topSeed
    $homeEntry = @($playoffField | Where-Object { $_.seed -eq $topSeed } | Select-Object -First 1)
    $awayEntry = @($playoffField | Where-Object { $_.seed -eq $bottomSeed } | Select-Object -First 1)
    if ($homeEntry.Count -gt 0 -and $awayEntry.Count -gt 0) {
      $week13MainRound.Add([pscustomobject]@{
        order = $topSeed
        homeSeed = $topSeed
        awaySeed = $bottomSeed
        homeTeam = $homeEntry[0].team
        awayTeam = $awayEntry[0].team
      }) | Out-Null
    }
  }

  $wildCardHomeEntry = @($playoffField | Where-Object { $_.seed -eq 31 } | Select-Object -First 1)
  $wildCardAwayEntry = @($playoffField | Where-Object { $_.seed -eq 32 } | Select-Object -First 1)

  $wildCardPlayIn = [pscustomobject]@{
    order = 16
    homeSeed = 31
    awaySeed = 32
    homeTeam = if ($wildCardHomeEntry.Count -gt 0) { $wildCardHomeEntry[0].team } else { $null }
    awayTeam = if ($wildCardAwayEntry.Count -gt 0) { $wildCardAwayEntry[0].team } else { $null }
  }

  $seasonStatuses = @($leagueSnapshots | ForEach-Object { Get-StringValue $_.status } | Sort-Object -Unique)
  $teamCount = @($allTeams).Count
  $requiredPlayoffFieldSize = (Get-IntValue $group.rules.directQualifiers 30) + (Get-IntValue $group.rules.wildCards 2)
  $seasonDataReady = -not (@($seasonStatuses | Where-Object { $_ -in @("pre_draft", "drafting") }).Count -gt 0)
  $seedingReady = $seasonDataReady -and ($teamCount -ge $requiredPlayoffFieldSize)

  $updatedGroups.Add([pscustomobject]@{
    groupId = $groupId
    label = Get-StringValue $group.label
    season = Get-StringValue $group.season
    leagueRecordIds = @($leagueRecordIds)
    rules = $group.rules
    lastSyncedAt = (Get-Date).ToString("s")
    seasonStatuses = @($seasonStatuses)
    seedingReady = $seedingReady
    seasonDataReady = $seasonDataReady
    notes = if (-not $seasonDataReady) {
      "One or more bracket leagues are still pre-draft or drafting, so the seeding output is structural or provisional."
    } elseif ($teamCount -lt $requiredPlayoffFieldSize) {
      "Sleeper standings are live, but only $teamCount owner-filled teams are currently available across the group. Seeds and matchups remain partial until the playoff field can reach $requiredPlayoffFieldSize teams."
    } else {
      "Standings and seeding reflect current Sleeper roster settings."
    }
    overallStandings = @($overallStandings)
    leagueSnapshots = @($leagueSnapshots)
    divisionWinners = @($seededDivisionWinners)
    directQualifiers = @($seededDirectQualifiers)
    wildCards = @($seededWildCards)
    bubbleTeams = @($bubbleTeams)
    playoffField = @($playoffField)
    week13 = [pscustomobject]@{
      wildCardPlayIn = $wildCardPlayIn
      mainRound = @($week13MainRound)
    }
    postWeek13Reset = [pscustomobject]@{
      roundOf16Template = @((New-RoundOf16Template))
      displayNote = "Top-to-bottom display order keeps the highest remaining seed at the top of the bracket and the second-highest remaining seed at the bottom, with the Wild Card Winner assigned to the 8th-highest remaining seed."
    }
  }) | Out-Null

  $results.Add([pscustomobject]@{
    groupId = $groupId
    leagueCount = @($leagueSnapshots).Count
    teamCount = @($allTeams).Count
    directQualifierCount = @($seededDivisionWinners).Count + @($seededDirectQualifiers).Count
    wildCardCount = @($seededWildCards).Count
  }) | Out-Null
}

$unchangedGroups = @($existingLedger.groups | Where-Object {
  $currentGroupId = Get-StringValue $_.groupId
  -not ($updatedGroups | Where-Object { (Get-StringValue $_.groupId) -eq $currentGroupId })
})

$generatedAt = (Get-Date).ToString("s")
$ledgerOutput = [pscustomobject]@{
  prompts = Get-BracketLedgerPrompts
  generatedAt = $generatedAt
  groups = @(
    (
      @($unchangedGroups) +
      @($updatedGroups)
    ) | Sort-Object { Get-StringValue $_.groupId }
  )
}

$ledgerOutput | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $LedgerPath

$report = [pscustomobject]@{
  ledgerPath = $LedgerPath
  generatedAt = $generatedAt
  groupCount = @($updatedGroups).Count
  results = @($results)
}

if ($PassThru) {
  $report
} else {
  Write-Host ("Synced bracket ledger for {0} group(s)." -f $report.groupCount)
  foreach ($result in $results) {
    Write-Host ("UPDATED {0}: {1} league(s), {2} team(s), {3} playoff teams, {4} wild card teams" -f $result.groupId, $result.leagueCount, $result.teamCount, $result.directQualifierCount, $result.wildCardCount)
  }
}
