param(
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$LedgerPath = "data/keeper-ledger.json",
  [string[]]$LeagueRecordIds,
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

function Get-KeeperLedgerPrompts {
  [pscustomobject]@{
    refreshLeaguesAndRosters = "Run the keeper ledger sync and refresh data/keeper-ledger.json from Sleeper so the current keeper leagues, managers, and roster players are up to date. If roster players are still empty, tell me Sleeper has not populated them yet."
    refreshSpecificLeague = "Run the keeper ledger sync for KP1 only and refresh data/keeper-ledger.json from Sleeper so that league's managers and roster players are up to date."
  }
}

function New-DefaultKeeperSlot {
  param(
    [int]$Slot
  )

  [pscustomobject]@{
    slot = $Slot
    playerName = ""
    playerId = ""
    keeperRound = ""
    originType = ""
    originSeason = ""
    originRound = ""
    acquiredVia = ""
    timelineStartSeason = ""
    manualNotes = ""
  }
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

function Merge-KeeperSlots {
  param(
    [AllowNull()]
    [object[]]$ExistingSlots
  )

  $existingBySlot = @{}
  foreach ($slot in @($ExistingSlots)) {
    $slotNumber = 0
    if ([int]::TryParse((Get-StringValue $slot.slot), [ref]$slotNumber) -and $slotNumber -ge 1 -and $slotNumber -le 2) {
      $existingBySlot[$slotNumber] = $slot
    }
  }

  $merged = [System.Collections.Generic.List[object]]::new()
  foreach ($slotNumber in 1..2) {
    if ($existingBySlot.ContainsKey($slotNumber)) {
      $existing = $existingBySlot[$slotNumber]
      $merged.Add([pscustomobject]@{
        slot = $slotNumber
        playerName = Get-StringValue $existing.playerName
        playerId = Get-StringValue $existing.playerId
        keeperRound = Get-StringValue $existing.keeperRound
        originType = Get-StringValue $existing.originType
        originSeason = Get-StringValue $existing.originSeason
        originRound = Get-StringValue $existing.originRound
        acquiredVia = Get-StringValue $existing.acquiredVia
        timelineStartSeason = Get-StringValue $existing.timelineStartSeason
        manualNotes = Get-StringValue $existing.manualNotes
      }) | Out-Null
    } else {
      $merged.Add((New-DefaultKeeperSlot -Slot $slotNumber)) | Out-Null
    }
  }

  return @($merged)
}

function Resolve-ExistingLeague {
  param(
    [AllowNull()]
    [object[]]$ExistingLeagues,
    [string]$LeagueRecordId
  )

  foreach ($league in @($ExistingLeagues)) {
    if ((Get-StringValue $league.leagueRecordId) -eq $LeagueRecordId) {
      return $league
    }
  }

  return $null
}

function Get-TeamName {
  param(
    [AllowNull()]
    [object]$User,
    [AllowNull()]
    [object]$Roster,
    [AllowNull()]
    [object]$ExistingManager
  )

  $candidateValues = @(
    $(if ($User -and $User.PSObject.Properties.Match("metadata").Count -gt 0) { Get-PropertyValue $User.metadata "team_name" } else { $null }),
    $(if ($Roster -and $Roster.PSObject.Properties.Match("metadata").Count -gt 0) { Get-PropertyValue $Roster.metadata "team_name" } else { $null }),
    $(if ($ExistingManager) { $ExistingManager.teamName } else { $null })
  )

  foreach ($value in $candidateValues) {
    $text = Get-StringValue $value
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      return $text
    }
  }

  return ""
}

function Get-RosterSortValue {
  param(
    [AllowNull()]
    [object]$Roster
  )

  $value = 0
  if ([int]::TryParse((Get-StringValue $(if ($Roster) { $Roster.roster_id } else { "" })), [ref]$value)) {
    return $value
  }

  return [int]::MaxValue
}

function Get-PlayerEntry {
  param(
    [string]$PlayerId,
    [AllowNull()]
    [object]$PlayersById
  )

  $player = Get-PropertyValue $PlayersById $PlayerId
  $fullName = Get-StringValue $(if ($player) { Get-PropertyValue $player "full_name" } else { "" })
  $position = Get-StringValue $(if ($player) { Get-PropertyValue $player "position" } else { "" })
  $team = Get-StringValue $(if ($player) { Get-PropertyValue $player "team" } else { "" })

  if ([string]::IsNullOrWhiteSpace($fullName)) {
    $fullName = $PlayerId
  }

  return [pscustomobject]@{
    playerId = $PlayerId
    fullName = $fullName
    position = $position
    team = $team
  }
}

if (-not (Test-Path -LiteralPath $LeaguesJsonPath)) {
  throw "Could not find league data file at '$LeaguesJsonPath'."
}

$leaguesFullPath = (Resolve-Path -LiteralPath $LeaguesJsonPath).Path
$leaguePayload = Get-Content -LiteralPath $leaguesFullPath -Raw | ConvertFrom-Json

if (-not $leaguePayload.leagues) {
  throw "The JSON file at '$LeaguesJsonPath' does not contain a 'leagues' array."
}

$ledgerExists = Test-Path -LiteralPath $LedgerPath
if ($ledgerExists) {
  $ledgerPayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $LedgerPath).Path -Raw | ConvertFrom-Json
} else {
  $ledgerPayload = [pscustomobject]@{
    prompts = Get-KeeperLedgerPrompts
    generatedAt = ""
    leagues = @()
  }
}

if (-not $ledgerPayload.PSObject.Properties.Match("leagues").Count) {
  $ledgerPayload | Add-Member -NotePropertyName "leagues" -NotePropertyValue @()
}

$keeperLeagues = @($leaguePayload.leagues | Where-Object {
  (Get-StringValue $_.format).ToLowerInvariant() -eq "keeper" -and
  -not [string]::IsNullOrWhiteSpace((Get-StringValue $_.sleeperLeagueId))
})

if ($LeagueRecordIds -and $LeagueRecordIds.Count -gt 0) {
  $lookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($id in $LeagueRecordIds) {
    [void]$lookup.Add((Get-StringValue $id))
  }

  $keeperLeagues = @($keeperLeagues | Where-Object { $lookup.Contains((Get-StringValue $_.id)) })
}

if (-not $keeperLeagues -or $keeperLeagues.Count -eq 0) {
  throw "No keeper leagues with Sleeper IDs matched the current selection."
}

$updatedLeagues = [System.Collections.Generic.List[object]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$playersById = $null

foreach ($league in ($keeperLeagues | Sort-Object { Get-StringValue $_.id })) {
  $leagueRecordId = Get-StringValue $league.id
  $sleeperLeagueId = Get-StringValue $league.sleeperLeagueId
  $existingLeague = Resolve-ExistingLeague -ExistingLeagues $ledgerPayload.leagues -LeagueRecordId $leagueRecordId

  $leagueSnapshot = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}" -f $sleeperLeagueId)
  $users = Convert-ToFlatObjectArray (Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/users" -f $sleeperLeagueId))
  $rosters = Convert-ToFlatObjectArray (Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/rosters" -f $sleeperLeagueId))

  if ($null -eq $playersById) {
    $playersById = Invoke-RestMethod -Uri "https://api.sleeper.app/v1/players/nfl"
  }

  $usersById = @{}
  foreach ($user in $users) {
    $userId = Get-StringValue $user.user_id
    if (-not [string]::IsNullOrWhiteSpace($userId)) {
      $usersById[$userId] = $user
    }
  }

  $existingManagersByOwnerId = @{}
  if ($existingLeague -and $existingLeague.PSObject.Properties.Match("managers").Count -gt 0) {
    foreach ($manager in @($existingLeague.managers)) {
      $ownerId = Get-StringValue $manager.ownerId
      if (-not [string]::IsNullOrWhiteSpace($ownerId)) {
        $existingManagersByOwnerId[$ownerId] = $manager
      }
    }
  }

  $managers = [System.Collections.Generic.List[object]]::new()
  foreach ($roster in ($rosters | Sort-Object { Get-RosterSortValue $_ })) {
    $ownerId = Get-StringValue $roster.owner_id
    if ([string]::IsNullOrWhiteSpace($ownerId)) {
      continue
    }

    $user = if ($usersById.ContainsKey($ownerId)) { $usersById[$ownerId] } else { $null }
    $existingManager = if ($existingManagersByOwnerId.ContainsKey($ownerId)) { $existingManagersByOwnerId[$ownerId] } else { $null }
    $displayName = Get-StringValue $(if ($user) { Get-PropertyValue $user "display_name" } else { $existingManager.displayName })
    $username = Get-StringValue $(if ($user) { Get-PropertyValue $user "username" } else { $existingManager.username })
    $teamName = Get-TeamName -User $user -Roster $roster -ExistingManager $existingManager
    $manualNotes = Get-StringValue $(if ($existingManager) { $existingManager.manualNotes } else { "" })
    $keeperSlots = Merge-KeeperSlots -ExistingSlots $(if ($existingManager) { $existingManager.keepers } else { @() })
    $rosterPlayerIds = Convert-ToFlatObjectArray (Get-PropertyValue $roster "players")
    $currentRosterPlayers = [System.Collections.Generic.List[object]]::new()
    foreach ($playerId in ($rosterPlayerIds | ForEach-Object { Get-StringValue $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
      $currentRosterPlayers.Add((Get-PlayerEntry -PlayerId $playerId -PlayersById $playersById)) | Out-Null
    }

    $managers.Add([pscustomobject]@{
      ownerId = $ownerId
      rosterId = [int]$roster.roster_id
      displayName = $displayName
      username = $username
      teamName = $teamName
      manualNotes = $manualNotes
      currentRosterPlayers = @($currentRosterPlayers | Sort-Object fullName)
      keepers = @($keeperSlots)
    }) | Out-Null
  }

  $updatedLeagues.Add([pscustomobject]@{
    leagueRecordId = $leagueRecordId
    sleeperLeagueId = $sleeperLeagueId
    season = Get-StringValue $league.sleeperSeason
    leagueName = Get-StringValue $(if ($leagueSnapshot) { $leagueSnapshot.name } else { $league.name })
    buyIn = [int]$league.buyIn
    teamCount = [int]$league.teams
    status = Get-StringValue $league.status
    constitutionPage = Get-StringValue $league.constitutionPage
    lastSyncedAt = (Get-Date).ToString("s")
    manualNotes = Get-StringValue $(if ($existingLeague) { $existingLeague.manualNotes } else { "" })
    managers = @($managers)
  }) | Out-Null

  $results.Add([pscustomobject]@{
    leagueRecordId = $leagueRecordId
    sleeperLeagueId = $sleeperLeagueId
    managerCount = @($managers).Count
  }) | Out-Null
}

$unchangedNonKeeperLeagues = @($ledgerPayload.leagues | Where-Object {
  $currentId = Get-StringValue $_.leagueRecordId
  -not ($updatedLeagues | Where-Object { (Get-StringValue $_.leagueRecordId) -eq $currentId })
})

$generatedAt = (Get-Date).ToString("s")
$updatedLeagueSet = @(
  @($unchangedNonKeeperLeagues) +
  @($updatedLeagues)
) | Sort-Object { Get-StringValue $_.leagueRecordId }

$ledgerOutput = [pscustomobject]@{
  prompts = Get-KeeperLedgerPrompts
  generatedAt = $generatedAt
  leagues = @($updatedLeagueSet)
}

$ledgerOutput | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $LedgerPath

$report = [pscustomobject]@{
  ledgerPath = $LedgerPath
  generatedAt = $generatedAt
  leagueCount = @($updatedLeagues).Count
  managerCount = (@($updatedLeagues | ForEach-Object { @($_.managers).Count } | Measure-Object -Sum).Sum)
  leagues = @($results)
}

if ($PassThru) {
  $report
} else {
  Write-Host ("Synced keeper ledger for {0} league(s) and {1} manager(s)." -f $report.leagueCount, $report.managerCount)
  foreach ($result in $results) {
    Write-Host ("UPDATED {0}: {1} manager(s)" -f $result.leagueRecordId, $result.managerCount)
  }
}
