param(
  [string[]]$LeagueRecordIds = @(),
  [string]$LeaguesPath = ".\data\leagues.json",
  [string]$OverridesPath = ".\data\power-ranking-overrides.json",
  [string]$OutputPath = ".\data\power-rankings.json",
  [switch]$IncludePending,
  [switch]$PassThru
)

$ErrorActionPreference = "Stop"

function Get-TextValue {
  param($Value)
  if ($null -eq $Value) { return "" }
  return ([string]$Value).Trim()
}

function Get-NumberValue {
  param($Value, [double]$Default = 0)
  if ($null -eq $Value) { return $Default }
  $parsed = 0.0
  if ([double]::TryParse(([string]$Value), [ref]$parsed)) { return $parsed }
  return $Default
}

function Convert-ToArray {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return @($Value) }
  return @($Value)
}

function Get-JsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Invoke-SleeperJson {
  param([string]$Uri)
  Invoke-RestMethod -Uri $Uri -Headers @{ "User-Agent" = "vbp-power-rankings/1.0" }
}

function Get-ObjectProperty {
  param($Object, [string]$Name)
  if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-Player {
  param($PlayersById, [string]$PlayerId)
  if ([string]::IsNullOrWhiteSpace($PlayerId)) { return $null }
  return Get-ObjectProperty -Object $PlayersById -Name $PlayerId
}

function Get-PrimaryPosition {
  param($Player)
  $position = Get-TextValue $Player.position
  if (-not [string]::IsNullOrWhiteSpace($position)) { return $position.ToUpperInvariant() }
  $positions = Convert-ToArray $Player.fantasy_positions
  if ($positions.Count -gt 0) { return (Get-TextValue $positions[0]).ToUpperInvariant() }
  return "UNK"
}

function Get-PlayerName {
  param($Player, [string]$PlayerId)
  $fullName = Get-TextValue $Player.full_name
  if (-not [string]::IsNullOrWhiteSpace($fullName)) { return $fullName }
  $first = Get-TextValue $Player.first_name
  $last = Get-TextValue $Player.last_name
  $combined = "$first $last".Trim()
  if (-not [string]::IsNullOrWhiteSpace($combined)) { return $combined }
  return $PlayerId
}

function Get-InjuryPenalty {
  param($Player, $Adjustment)
  $status = (Get-TextValue $Player.injury_status).ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($status)) {
    $status = (Get-TextValue $Player.status).ToLowerInvariant()
  }

  $penalty = 0.0
  if ($status -match "ir|pup|out|suspend") { $penalty = 22 }
  elseif ($status -match "doubt") { $penalty = 14 }
  elseif ($status -match "question") { $penalty = 6 }
  elseif ($status -match "probable") { $penalty = 2 }

  if ($Adjustment) {
    $penalty += Get-NumberValue (Get-ObjectProperty -Object $Adjustment -Name "injuryPenalty") 0
  }

  return [Math]::Max(0, $penalty)
}

function Get-PositionBase {
  param([string]$Position)
  switch ($Position) {
    "QB" { return 70 }
    "RB" { return 66 }
    "WR" { return 66 }
    "TE" { return 62 }
    "K" { return 35 }
    "DEF" { return 38 }
    default { return 45 }
  }
}

function Get-AgeScore {
  param($Player, [string]$Format)
  $position = Get-PrimaryPosition $Player
  $age = Get-NumberValue $Player.age 0
  if ($age -le 0) { return 72 }
  if ($Format -notin @("dynasty", "dynastybracket", "keeper")) { return 75 }

  switch ($position) {
    "QB" {
      if ($age -le 27) { return 93 }
      if ($age -le 32) { return 86 }
      if ($age -le 36) { return 72 }
      return 58
    }
    "RB" {
      if ($age -le 24) { return 94 }
      if ($age -le 26) { return 84 }
      if ($age -le 28) { return 68 }
      return 50
    }
    "WR" {
      if ($age -le 25) { return 93 }
      if ($age -le 28) { return 86 }
      if ($age -le 31) { return 70 }
      return 52
    }
    "TE" {
      if ($age -le 26) { return 90 }
      if ($age -le 30) { return 84 }
      if ($age -le 33) { return 68 }
      return 52
    }
    default { return 70 }
  }
}

function Get-SearchRankScore {
  param($Player)
  $rank = Get-NumberValue $Player.search_rank 0
  if ($rank -le 0) { $rank = Get-NumberValue $Player.search_rank_ppr 0 }
  if ($rank -le 0) { return 52 }
  $score = 103 - (18 * [Math]::Log10([Math]::Max(1, $rank)))
  return [Math]::Min(99, [Math]::Max(20, $score))
}

function Get-DepthChartScore {
  param($Player)
  $order = Get-NumberValue $Player.depth_chart_order 0
  if ($order -eq 1) { return 92 }
  if ($order -eq 2) { return 78 }
  if ($order -eq 3) { return 62 }
  if ($order -gt 3) { return 48 }
  return 60
}

function Get-PlayerValue {
  param(
    $Player,
    [string]$PlayerId,
    [string]$Format,
    $Adjustment
  )

  $position = Get-PrimaryPosition $Player
  $base = Get-PositionBase $position
  $market = Get-SearchRankScore $Player
  $age = Get-AgeScore -Player $Player -Format $Format
  $depth = Get-DepthChartScore $Player
  $injuryPenalty = Get-InjuryPenalty -Player $Player -Adjustment $Adjustment
  $manual = if ($Adjustment) { Get-NumberValue (Get-ObjectProperty -Object $Adjustment -Name "valueAdjustment") 0 } else { 0 }

  $value = ($base * 0.20) + ($market * 0.42) + ($age * 0.22) + ($depth * 0.16) - $injuryPenalty + $manual
  $value = [Math]::Min(99, [Math]::Max(0, $value))

  [pscustomobject]@{
    playerId = $PlayerId
    name = Get-PlayerName -Player $Player -PlayerId $PlayerId
    position = $position
    team = Get-TextValue $Player.team
    age = Get-NumberValue $Player.age 0
    injuryStatus = Get-TextValue $Player.injury_status
    searchRank = Get-NumberValue $Player.search_rank 0
    value = [Math]::Round($value, 1)
    injuryPenalty = [Math]::Round($injuryPenalty, 1)
    note = if ($Adjustment) { Get-TextValue (Get-ObjectProperty -Object $Adjustment -Name "note") } else { "" }
  }
}

function Test-EligibleForSlot {
  param($PlayerEntry, [string]$Slot)
  $position = $PlayerEntry.position
  switch ($Slot.ToUpperInvariant()) {
    "QB" { return $position -eq "QB" }
    "RB" { return $position -eq "RB" }
    "WR" { return $position -eq "WR" }
    "TE" { return $position -eq "TE" }
    "SUPER_FLEX" { return $position -in @("QB", "RB", "WR", "TE") }
    "FLEX" { return $position -in @("RB", "WR", "TE") }
    "WRRB_FLEX" { return $position -in @("WR", "RB") }
    "REC_FLEX" { return $position -in @("WR", "TE") }
    "IDP_FLEX" { return $position -in @("DL", "LB", "DB", "IDP") }
    default { return $false }
  }
}

function Get-SlotFitScore {
  param($PlayerEntry, [string]$Slot)
  $score = Get-NumberValue $PlayerEntry.value 0
  $position = $PlayerEntry.position
  switch ($Slot.ToUpperInvariant()) {
    "SUPER_FLEX" {
      if ($position -eq "QB") { return $score + 10 }
      return $score
    }
    "QB" {
      if ($position -eq "QB") { return $score + 6 }
      return $score
    }
    "TE" {
      if ($position -eq "TE") { return $score + 4 }
      return $score
    }
    default { return $score }
  }
}

function Get-LineupSlots {
  param($League)
  $slots = Convert-ToArray $League.roster_positions |
    ForEach-Object { (Get-TextValue $_).ToUpperInvariant() } |
    Where-Object { $_ -notin @("BN", "BE", "IR", "TAXI", "K", "DEF") -and -not [string]::IsNullOrWhiteSpace($_) }

  $slotOrder = @{
    "QB" = 1
    "SUPER_FLEX" = 2
    "RB" = 3
    "WR" = 4
    "TE" = 5
    "FLEX" = 6
    "WRRB_FLEX" = 7
    "REC_FLEX" = 8
    "IDP_FLEX" = 9
  }

  return @($slots | Sort-Object { if ($slotOrder.ContainsKey($_)) { $slotOrder[$_] } else { 99 } })
}

function Get-OptimizedLineup {
  param($Players, $Slots)
  $available = New-Object System.Collections.ArrayList
  foreach ($player in ($Players | Sort-Object @{ Expression = { $_.value }; Descending = $true })) {
    [void]$available.Add($player)
  }

  $starters = New-Object System.Collections.ArrayList
  foreach ($slot in $Slots) {
    $selected = $null
    $selectedFitScore = -999
    foreach ($candidate in @($available)) {
      if (Test-EligibleForSlot -PlayerEntry $candidate -Slot $slot) {
        $fitScore = Get-SlotFitScore -PlayerEntry $candidate -Slot $slot
        if ($fitScore -gt $selectedFitScore) {
          $selected = $candidate
          $selectedFitScore = $fitScore
        }
      }
    }
    if ($selected) {
      [void]$available.Remove($selected)
      $selected | Add-Member -NotePropertyName selectedSlot -NotePropertyValue $slot -Force
      [void]$starters.Add($selected)
    }
  }

  [pscustomobject]@{
    starters = @($starters)
    bench = @($available | Sort-Object @{ Expression = { $_.value }; Descending = $true })
  }
}

function Get-Average {
  param($Items, [string]$PropertyName)
  $values = @($Items | ForEach-Object { Get-NumberValue (Get-ObjectProperty -Object $_ -Name $PropertyName) 0 } | Where-Object { $_ -gt 0 })
  if ($values.Count -eq 0) { return 0 }
  return ($values | Measure-Object -Average).Average
}

function Get-TeamName {
  param($User, $Roster)
  $metadata = if ($User) { $User.metadata } else { $null }
  $teamName = Get-TextValue (Get-ObjectProperty -Object $metadata -Name "team_name")
  if (-not [string]::IsNullOrWhiteSpace($teamName)) { return $teamName }
  $displayName = if ($User) { Get-TextValue $User.display_name } else { "" }
  if (-not [string]::IsNullOrWhiteSpace($displayName)) { return $displayName }
  return "Roster $(Get-NumberValue $Roster.roster_id 0)"
}

function Get-FormatWeights {
  param([string]$Format)
  switch ($Format) {
    "bestball" {
      return [ordered]@{
        lineup = 0.28
        depth = 0.34
        quarterback = 0.10
        eliteCeiling = 0.13
        health = 0.10
        context = 0.05
      }
    }
    "dynasty" {
      return [ordered]@{
        lineup = 0.32
        depth = 0.18
        quarterback = 0.18
        eliteCeiling = 0.10
        health = 0.07
        dynastyValue = 0.15
      }
    }
    default {
      return [ordered]@{
        lineup = 0.38
        depth = 0.18
        quarterback = 0.12
        eliteCeiling = 0.12
        health = 0.10
        context = 0.10
      }
    }
  }
}

function Get-TeamAdjustment {
  param($Overrides, [string]$LeagueRecordId, [int]$RosterId)
  $adjustments = Convert-ToArray $Overrides.teamAdjustments
  foreach ($adjustment in $adjustments) {
    if ((Get-TextValue $adjustment.leagueRecordId) -eq $LeagueRecordId -and [int](Get-NumberValue $adjustment.rosterId 0) -eq $RosterId) {
      return $adjustment
    }
  }
  return $null
}

function New-TeamRanking {
  param(
    $LeagueRecord,
    $LiveLeague,
    $Roster,
    $User,
    $PlayersById,
    $DraftCapitalByRosterId,
    $Overrides
  )

  $leagueRecordId = Get-TextValue $LeagueRecord.id
  $format = Get-TextValue $LeagueRecord.format
  $rosterId = [int](Get-NumberValue $Roster.roster_id 0)
  $teamAdjustment = Get-TeamAdjustment -Overrides $Overrides -LeagueRecordId $leagueRecordId -RosterId $rosterId
  $playerAdjustments = if ($Overrides) { $Overrides.playerAdjustments } else { $null }

  $playerEntries = @()
  foreach ($playerId in (Convert-ToArray $Roster.players | ForEach-Object { Get-TextValue $_ } | Where-Object { $_ })) {
    $player = Get-Player -PlayersById $PlayersById -PlayerId $playerId
    if ($null -eq $player) { continue }
    $adjustment = Get-ObjectProperty -Object $playerAdjustments -Name $playerId
    $playerEntries += Get-PlayerValue -Player $player -PlayerId $playerId -Format $format -Adjustment $adjustment
  }

  $slots = Get-LineupSlots -League $LiveLeague
  $optimized = Get-OptimizedLineup -Players $playerEntries -Slots $slots
  $starters = @($optimized.starters)
  $bench = @($optimized.bench)
  $topBench = @($bench | Select-Object -First 7)
  $qbs = @($playerEntries | Where-Object { $_.position -eq "QB" } | Sort-Object @{ Expression = { $_.value }; Descending = $true })
  $elitePlayers = @($playerEntries | Where-Object { $_.value -ge 84 })
  $injuredPlayers = @($playerEntries | Where-Object { $_.injuryPenalty -ge 6 })

  $lineupScore = Get-Average -Items $starters -PropertyName "value"
  $depthScore = Get-Average -Items $topBench -PropertyName "value"
  $qbScore = Get-Average -Items (@($qbs | Select-Object -First 2)) -PropertyName "value"
  $eliteScore = [Math]::Min(100, 58 + ($elitePlayers.Count * 8))
  $healthScore = [Math]::Max(0, 100 - (($injuredPlayers | Measure-Object -Property injuryPenalty -Sum).Sum))
  $dynastyScore = Get-Average -Items $playerEntries -PropertyName "value"
  $draftCapitalScore = if ($DraftCapitalByRosterId.ContainsKey($rosterId)) { $DraftCapitalByRosterId[$rosterId] } else { 70 }
  $manualContext = if ($teamAdjustment) { Get-NumberValue (Get-ObjectProperty -Object $teamAdjustment -Name "contextAdjustment") 0 } else { 0 }

  if ($format -in @("dynasty", "dynastybracket")) {
    $dynastyScore = (($dynastyScore * 0.70) + ($draftCapitalScore * 0.30))
  }

  $weights = Get-FormatWeights -Format $format
  $componentScores = [ordered]@{
    lineup = [Math]::Round($lineupScore, 1)
    depth = [Math]::Round($depthScore, 1)
    quarterback = [Math]::Round($qbScore, 1)
    eliteCeiling = [Math]::Round($eliteScore, 1)
    health = [Math]::Round($healthScore, 1)
  }
  if ($weights.Contains("dynastyValue")) {
    $componentScores.dynastyValue = [Math]::Round($dynastyScore, 1)
  } else {
    $componentScores.context = [Math]::Round((70 + $manualContext), 1)
  }

  $rawScore = 0.0
  foreach ($key in $weights.Keys) {
    $rawScore += (Get-NumberValue $componentScores[$key] 0) * $weights[$key]
  }
  $rawScore += $manualContext
  $score = [Math]::Min(100, [Math]::Max(0, $rawScore))

  $record = @{
    wins = [int](Get-NumberValue $Roster.settings.wins 0)
    losses = [int](Get-NumberValue $Roster.settings.losses 0)
    ties = [int](Get-NumberValue $Roster.settings.ties 0)
    pointsFor = [Math]::Round((Get-NumberValue $Roster.settings.fpts 0) + ((Get-NumberValue $Roster.settings.fpts_decimal 0) / 100), 2)
    maxPointsFor = [Math]::Round((Get-NumberValue $Roster.settings.ppts 0) + ((Get-NumberValue $Roster.settings.ppts_decimal 0) / 100), 2)
  }

  $topPlayers = @($playerEntries | Sort-Object @{ Expression = { $_.value }; Descending = $true } | Select-Object -First 8)
  $reasonBits = New-Object System.Collections.Generic.List[string]
  if ($qbs.Count -gt 0) { $reasonBits.Add(("QB room: {0}" -f (($qbs | Select-Object -First 2 | ForEach-Object { $_.name }) -join ", "))) }
  if ($starters.Count -gt 0) { $reasonBits.Add(("Starter grade {0}" -f ([Math]::Round($lineupScore, 1)))) }
  if ($topBench.Count -gt 0) { $reasonBits.Add(("Bench grade {0}" -f ([Math]::Round($depthScore, 1)))) }
  if ($injuredPlayers.Count -gt 0) { $reasonBits.Add(("Health watch: {0}" -f (($injuredPlayers | Select-Object -First 3 | ForEach-Object { $_.name }) -join ", "))) }
  if ($teamAdjustment -and -not [string]::IsNullOrWhiteSpace((Get-TextValue $teamAdjustment.scheduleNote))) { $reasonBits.Add((Get-TextValue $teamAdjustment.scheduleNote)) }
  if ($teamAdjustment -and -not [string]::IsNullOrWhiteSpace((Get-TextValue $teamAdjustment.note))) { $reasonBits.Add((Get-TextValue $teamAdjustment.note)) }

  [pscustomobject]@{
    rosterId = $rosterId
    ownerId = Get-TextValue $Roster.owner_id
    teamName = Get-TeamName -User $User -Roster $Roster
    score = [Math]::Round($score, 1)
    record = $record
    components = $componentScores
    topPlayers = @($topPlayers | ForEach-Object {
      [pscustomobject]@{
        name = $_.name
        position = $_.position
        team = $_.team
        age = $_.age
        injuryStatus = $_.injuryStatus
        value = $_.value
      }
    })
    starterSnapshot = @($starters | Select-Object -First 12 | ForEach-Object {
      [pscustomobject]@{
        slot = $_.selectedSlot
        name = $_.name
        position = $_.position
        value = $_.value
      }
    })
    benchSnapshot = @($topBench | ForEach-Object {
      [pscustomobject]@{
        name = $_.name
        position = $_.position
        value = $_.value
      }
    })
    reasons = @($reasonBits)
  }
}

function Get-DraftCapitalByRosterId {
  param($Drafts)
  $capital = @{}
  foreach ($draft in (Convert-ToArray $Drafts)) {
    $draftId = Get-TextValue $draft.draft_id
    if ([string]::IsNullOrWhiteSpace($draftId)) { continue }
    try {
      $picks = Convert-ToArray (Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/draft/{0}/picks" -f $draftId))
      $total = [Math]::Max(1, $picks.Count)
      $byRoster = $picks | Group-Object roster_id
      foreach ($group in $byRoster) {
        $rosterId = [int](Get-NumberValue $group.Name 0)
        if ($rosterId -le 0) { continue }
        $scores = @($group.Group | ForEach-Object {
          $pickNo = Get-NumberValue $_.pick_no 0
          if ($pickNo -le 0) { 70 } else { 100 - (($pickNo - 1) / $total * 45) }
        })
        if ($scores.Count -gt 0) {
          $avg = ($scores | Measure-Object -Average).Average
          if (-not $capital.ContainsKey($rosterId) -or $avg -gt $capital[$rosterId]) {
            $capital[$rosterId] = [Math]::Round($avg, 1)
          }
        }
      }
    } catch {
      Write-Warning ("Unable to load draft picks for draft {0}: {1}" -f $draftId, $_.Exception.Message)
    }
  }
  return $capital
}

function Get-LeagueOverride {
  param($Overrides, [string]$LeagueRecordId)
  if ($null -eq $Overrides) { return $null }
  return Get-ObjectProperty -Object $Overrides.leagueOverrides -Name $LeagueRecordId
}

$leagueData = Get-JsonFile -Path $LeaguesPath
if ($null -eq $leagueData -or $null -eq $leagueData.leagues) {
  throw "Could not read league data from $LeaguesPath."
}

$overrides = Get-JsonFile -Path $OverridesPath
if ($null -eq $overrides) {
  $overrides = [pscustomobject]@{
    leagueOverrides = [pscustomobject]@{}
    teamAdjustments = @()
    playerAdjustments = [pscustomobject]@{}
  }
}

$selectedLeagues = @($leagueData.leagues | Where-Object {
  $leagueRecordId = Get-TextValue $_.id
  $sleeperLeagueId = Get-TextValue $_.sleeperLeagueId
  -not [string]::IsNullOrWhiteSpace($sleeperLeagueId) -and
    ($LeagueRecordIds.Count -eq 0 -or $leagueRecordId -in $LeagueRecordIds)
})

if ($selectedLeagues.Count -eq 0) {
  throw "No leagues with Sleeper IDs matched the current selection."
}

Write-Host "Loading Sleeper NFL player metadata..."
$playersById = Invoke-SleeperJson -Uri "https://api.sleeper.app/v1/players/nfl"
$nflState = $null
try {
  $nflState = Invoke-SleeperJson -Uri "https://api.sleeper.app/v1/state/nfl"
} catch {
  Write-Warning ("Unable to load Sleeper NFL state for snapshot labels: {0}" -f $_.Exception.Message)
}

$generatedLeagues = @()
$warnings = New-Object System.Collections.Generic.List[string]

foreach ($leagueRecord in $selectedLeagues) {
  $leagueRecordId = Get-TextValue $leagueRecord.id
  $sleeperLeagueId = Get-TextValue $leagueRecord.sleeperLeagueId
  $leagueOverride = Get-LeagueOverride -Overrides $overrides -LeagueRecordId $leagueRecordId

  Write-Host ("Refreshing power ranking inputs for {0}..." -f $leagueRecordId)

  try {
    $liveLeague = Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}" -f $sleeperLeagueId)
    $users = Convert-ToArray (Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}/users" -f $sleeperLeagueId))
    $rosters = Convert-ToArray (Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}/rosters" -f $sleeperLeagueId))
    $drafts = Convert-ToArray (Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}/drafts" -f $sleeperLeagueId))
  } catch {
    $warnings.Add(("ERROR {0}: Sleeper input load failed - {1}" -f $leagueRecordId, $_.Exception.Message)) | Out-Null
    continue
  }

  $draftStatuses = @($drafts | ForEach-Object { (Get-TextValue $_.status).ToLowerInvariant() } | Where-Object { $_ })
  $allDraftsComplete = $draftStatuses.Count -gt 0 -and (@($draftStatuses | Where-Object { $_ -ne "complete" }).Count -eq 0)
  $publishOverride = Get-ObjectProperty -Object $leagueOverride -Name "publishPowerRanking"
  $hasPublishOverride = $null -ne $publishOverride
  $publish = if ($hasPublishOverride) { [bool]$publishOverride } else { $allDraftsComplete }
  $holdReason = Get-TextValue (Get-ObjectProperty -Object $leagueOverride -Name "reason")

  if (-not $publish -and -not $IncludePending) {
    $warnings.Add(("SKIP {0}: {1}" -f $leagueRecordId, $(if ($holdReason) { $holdReason } else { "Draft data is not complete." }))) | Out-Null
    continue
  }

  $usersById = @{}
  foreach ($user in $users) {
    $userId = Get-TextValue $user.user_id
    if ($userId) { $usersById[$userId] = $user }
  }

  $draftCapitalByRosterId = Get-DraftCapitalByRosterId -Drafts $drafts
  $rankings = @()
  foreach ($roster in ($rosters | Where-Object { -not [string]::IsNullOrWhiteSpace((Get-TextValue $_.owner_id)) })) {
    $ownerId = Get-TextValue $roster.owner_id
    $user = if ($usersById.ContainsKey($ownerId)) { $usersById[$ownerId] } else { $null }
    $rankings += New-TeamRanking -LeagueRecord $leagueRecord -LiveLeague $liveLeague -Roster $roster -User $user -PlayersById $playersById -DraftCapitalByRosterId $draftCapitalByRosterId -Overrides $overrides
  }

  $rank = 1
  $rankings = @($rankings | Sort-Object @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.record.pointsFor }; Descending = $true } | ForEach-Object {
    $_ | Add-Member -NotePropertyName rank -NotePropertyValue $rank -Force
    $rank++
    $_
  })

  $generatedLeagues += [pscustomobject]@{
    leagueRecordId = $leagueRecordId
    sleeperLeagueId = $sleeperLeagueId
    name = Get-TextValue $leagueRecord.name
    format = Get-TextValue $leagueRecord.format
    publish = [bool]$publish
    holdReason = $holdReason
    draftStatuses = $draftStatuses
    rosterPositions = @(Convert-ToArray $liveLeague.roster_positions)
    rankings = $rankings
  }
}

$output = [pscustomobject]@{
  generatedAt = (Get-Date).ToString("o")
  snapshot = [pscustomobject]@{
    season = Get-TextValue (Get-ObjectProperty -Object $nflState -Name "season")
    seasonType = Get-TextValue (Get-ObjectProperty -Object $nflState -Name "season_type")
    week = [int](Get-NumberValue (Get-ObjectProperty -Object $nflState -Name "week") 0)
    display = if ($nflState -and (Get-NumberValue (Get-ObjectProperty -Object $nflState -Name "week") 0) -gt 0) {
      "{0} Week {1}" -f (Get-TextValue (Get-ObjectProperty -Object $nflState -Name "season")), ([int](Get-NumberValue (Get-ObjectProperty -Object $nflState -Name "week") 0))
    } else {
      "Current snapshot"
    }
  }
  source = "Sleeper league, roster, user, draft, draft-pick, and player metadata endpoints plus data/power-ranking-overrides.json."
  methodology = [pscustomobject]@{
    summary = "Power rankings combine optimized starters, bench strength, quarterback room, elite-player count, health/injury flags, dynasty value, draft capital, standings, and commissioner context adjustments."
    components = @(
      "Lineup: best legal starter set from Sleeper roster positions.",
      "Depth: top bench pieces after the optimized lineup is filled.",
      "Quarterback: top quarterback values, weighted higher in superflex/dynasty formats.",
      "Elite ceiling: count of high-value players who can swing a week.",
      "Health: current Sleeper injury/status flags plus manual injury overrides.",
      "Dynasty value: age curve, player value, and draft capital for dynasty formats.",
      "Context: commissioner-owned schedule, role, and league-readiness adjustments from overrides."
    )
  }
  warnings = @($warnings)
  leagues = $generatedLeagues
}

$json = $output | ConvertTo-Json -Depth 14
Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8

if ($PassThru) {
  $output
} else {
  Write-Host ("Power rankings refreshed: {0}" -f $OutputPath)
  foreach ($warning in $warnings) {
    Write-Warning $warning
  }
}
