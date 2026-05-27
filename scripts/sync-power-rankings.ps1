param(
  [string[]]$LeagueRecordIds = @(),
  [string]$LeaguesPath = ".\data\leagues.json",
  [string]$OverridesPath = ".\data\power-ranking-overrides.json",
  [string]$OutputPath = ".\data\power-rankings.json",
  [switch]$PublishDrafting,
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
  $separator = if ($Uri.Contains("?")) { "&" } else { "?" }
  $cacheBustedUri = "{0}{1}_={2}" -f $Uri, $separator, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  Invoke-RestMethod -Uri $cacheBustedUri -Headers @{
    "User-Agent" = "vbp-power-rankings/1.0"
    "Cache-Control" = "no-cache"
    "Pragma" = "no-cache"
  }
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

function Get-ScoringProfile {
  param($League)

  $settings = Get-ObjectProperty -Object $League -Name "scoring_settings"
  $rec = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "rec") 0
  $rbBonus = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "bonus_rec_rb") 0
  $wrBonus = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "bonus_rec_wr") 0
  $teBonus = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "bonus_rec_te") 0
  $rbPpr = $rec + $rbBonus
  $wrPpr = $rec + $wrBonus
  $tePpr = $rec + $teBonus
  $rushYard = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "rush_yd") 0
  $rushTd = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "rush_td") 0
  $receivingYard = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "rec_yd") 0
  $receivingTd = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "rec_td") 0
  $passingYard = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "pass_yd") 0
  $passingTd = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "pass_td") 0
  $interception = Get-NumberValue (Get-ObjectProperty -Object $settings -Name "pass_int") 0
  $matchesVbpDefault = [Math]::Abs($rbPpr - 0.50) -lt 0.001 -and [Math]::Abs($wrPpr - 0.25) -lt 0.001 -and [Math]::Abs($tePpr - 0.75) -lt 0.001 -and
    [Math]::Abs($rushYard - 0.10) -lt 0.001 -and [Math]::Abs($rushTd - 6) -lt 0.001 -and
    [Math]::Abs($receivingYard - 0.10) -lt 0.001 -and [Math]::Abs($receivingTd - 6) -lt 0.001 -and
    [Math]::Abs($passingYard - 0.04) -lt 0.001 -and [Math]::Abs($passingTd - 4) -lt 0.001 -and
    [Math]::Abs($interception - (-1)) -lt 0.001

  [pscustomobject]@{
    source = "Live Sleeper league scoring_settings"
    rec = [Math]::Round($rec, 2)
    bonusRecRb = [Math]::Round($rbBonus, 2)
    bonusRecWr = [Math]::Round($wrBonus, 2)
    bonusRecTe = [Math]::Round($teBonus, 2)
    rbPpr = [Math]::Round($rbPpr, 2)
    wrPpr = [Math]::Round($wrPpr, 2)
    tePpr = [Math]::Round($tePpr, 2)
    rushYard = [Math]::Round($rushYard, 3)
    rushTd = [Math]::Round($rushTd, 2)
    receivingYard = [Math]::Round($receivingYard, 3)
    receivingTd = [Math]::Round($receivingTd, 2)
    passingYard = [Math]::Round($passingYard, 3)
    passingTd = [Math]::Round($passingTd, 2)
    interception = [Math]::Round($interception, 2)
    usesConfiguredReceptionProfile = [bool]$matchesVbpDefault
    strategy = "Scoring settings verified from Sleeper for this league."
  }
}

function Get-LineupArchitecture {
  param($League)

  $positions = @(Convert-ToArray $League.roster_positions | ForEach-Object { (Get-TextValue $_).ToUpperInvariant() })
  $teamCount = [int](Get-NumberValue (Get-ObjectProperty -Object $League.settings -Name "num_teams") 0)
  $qbSlots = @($positions | Where-Object { $_ -eq "QB" }).Count
  $superflexSlots = @($positions | Where-Object { $_ -eq "SUPER_FLEX" }).Count
  $rbSlots = @($positions | Where-Object { $_ -eq "RB" }).Count
  $wrSlots = @($positions | Where-Object { $_ -eq "WR" }).Count
  $teSlots = @($positions | Where-Object { $_ -eq "TE" }).Count
  $flexSlots = @($positions | Where-Object { $_ -in @("FLEX", "WRRB_FLEX", "REC_FLEX") }).Count

  [pscustomobject]@{
    teamCount = $teamCount
    qbSlots = $qbSlots
    superflexSlots = $superflexSlots
    rbSlots = $rbSlots
    wrSlots = $wrSlots
    teSlots = $teSlots
    flexSlots = $flexSlots
    isSuperflex = [bool]($superflexSlots -gt 0 -or $qbSlots -gt 1)
    summary = "{0} teams; starters: {1} QB, {2} RB, {3} WR, {4} TE, {5} FLEX, {6} SUPER_FLEX." -f $teamCount, $qbSlots, $rbSlots, $wrSlots, $teSlots, $flexSlots, $superflexSlots
  }
}

function Get-FormatProfile {
  param([string]$Format)

  switch ($Format.ToLowerInvariant()) {
    "dynasty" {
      return [pscustomobject]@{
        label = "Dynasty Superflex"
        publicScope = "Individual league board"
        emphasis = "Current roster strength, Superflex quarterback stability, long-term player value, and draft capital."
      }
    }
    "dynastybracket" {
      return [pscustomobject]@{
        label = "Dynasty Bracket Superflex"
        publicScope = "Combined bracket board once drafts are complete"
        emphasis = "Current roster strength, Superflex quarterback stability, long-term player value, and draft capital across divisions."
      }
    }
    "bestball" {
      return [pscustomobject]@{
        label = "Best Ball Union"
        publicScope = "Combined Top 20 board"
        emphasis = "Automated weekly ceiling and draft-and-hold depth with no waiver or trade recovery."
      }
    }
    "gauntlet" {
      return [pscustomobject]@{
        label = "Best Ball Gauntlet"
        publicScope = "Single-league board after the draft is complete"
        emphasis = "Four-start micro-roster strength, Superflex ceiling, and availability risk in a locked roster format."
      }
    }
    "bracket" {
      return [pscustomobject]@{
        label = "Redraft Bracket"
        publicScope = "Combined bracket board once drafts are complete"
        emphasis = "Starting-lineup strength and usable seasonal depth across the five tournament divisions."
      }
    }
    "keeper" {
      return [pscustomobject]@{
        label = "Keeper"
        publicScope = "Individual league board after the draft is complete"
        emphasis = "Current roster strength with age runway relevant to future keeper choices."
      }
    }
    "chopped" {
      return [pscustomobject]@{
        label = "Chopped"
        publicScope = "Single-league survival board after the draft is complete"
        emphasis = "Weekly floor, active lineup health, and top-end strength needed to avoid elimination."
      }
    }
    "redraft" {
      return [pscustomobject]@{
        label = "Redraft"
        publicScope = "Individual league board after the draft is complete"
        emphasis = "Starting-lineup strength and usable in-season depth."
      }
    }
    default {
      return [pscustomobject]@{
        label = "Not roster ranked"
        publicScope = "No roster power-ranking board"
        emphasis = "This format does not produce a standard fantasy-roster power ranking."
      }
    }
  }
}

function Get-VbpScoringAdjustment {
  param([string]$Position, $ScoringProfile, $LineupArchitecture)

  $adjustment = 0.0
  switch ($Position) {
    "RB" { $adjustment = ((Get-NumberValue $ScoringProfile.rbPpr 0) - (Get-NumberValue $ScoringProfile.wrPpr 0)) * 10 }
    "WR" { $adjustment = 0 }
    "TE" { $adjustment = ((Get-NumberValue $ScoringProfile.tePpr 0) - (Get-NumberValue $ScoringProfile.wrPpr 0)) * 12 }
    "QB" {
      if ($LineupArchitecture.isSuperflex) { $adjustment = 8 }
    }
  }
  return [Math]::Round($adjustment, 1)
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
    $Adjustment,
    $ScoringProfile,
    $LineupArchitecture
  )

  $position = Get-PrimaryPosition $Player
  $base = Get-PositionBase $position
  $market = Get-SearchRankScore $Player
  $age = Get-AgeScore -Player $Player -Format $Format
  $depth = Get-DepthChartScore $Player
  $injuryPenalty = Get-InjuryPenalty -Player $Player -Adjustment $Adjustment
  $manual = if ($Adjustment) { Get-NumberValue (Get-ObjectProperty -Object $Adjustment -Name "valueAdjustment") 0 } else { 0 }
  $vbpAdjustment = Get-VbpScoringAdjustment -Position $position -ScoringProfile $ScoringProfile -LineupArchitecture $LineupArchitecture

  $value = ($base * 0.20) + ($market * 0.42) + ($age * 0.22) + ($depth * 0.16) + $vbpAdjustment - $injuryPenalty + $manual
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
    vbpAdjustment = $vbpAdjustment
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
        lineup = 0.25
        depth = 0.32
        quarterback = 0.10
        eliteCeiling = 0.12
        health = 0.10
        scoringContext = 0.06
        context = 0.05
      }
    }
    { $_ -in @("dynasty", "dynastybracket") } {
      return [ordered]@{
        lineup = 0.29
        depth = 0.16
        quarterback = 0.18
        eliteCeiling = 0.08
        health = 0.06
        dynastyValue = 0.15
        scoringContext = 0.08
      }
    }
    "keeper" {
      return [ordered]@{
        lineup = 0.35
        depth = 0.15
        quarterback = 0.10
        eliteCeiling = 0.09
        health = 0.08
        dynastyValue = 0.15
        scoringContext = 0.08
      }
    }
    "gauntlet" {
      return [ordered]@{
        lineup = 0.45
        depth = 0.05
        quarterback = 0.15
        eliteCeiling = 0.15
        health = 0.15
        scoringContext = 0.05
      }
    }
    "chopped" {
      return [ordered]@{
        lineup = 0.48
        depth = 0.14
        quarterback = 0.08
        eliteCeiling = 0.10
        health = 0.15
        scoringContext = 0.05
      }
    }
    default {
      return [ordered]@{
        lineup = 0.34
        depth = 0.17
        quarterback = 0.12
        eliteCeiling = 0.10
        health = 0.10
        scoringContext = 0.08
        context = 0.09
      }
    }
  }
}

function Get-BestBallScore {
  param(
    [double]$LineupScore,
    [double]$DepthScore,
    [double]$QuarterbackScore,
    [object[]]$PlayerEntries,
    [object[]]$InjuredPlayers,
    [double]$ManualContext
  )

  $eliteCount = @($PlayerEntries | Where-Object { (Get-NumberValue $_.value 0) -ge 84 }).Count
  $differenceMakerCount = @($PlayerEntries | Where-Object { (Get-NumberValue $_.value 0) -ge 78 }).Count
  $usefulDepthCount = @($PlayerEntries | Where-Object { (Get-NumberValue $_.value 0) -ge 70 }).Count
  $injuryPenalty = Get-NumberValue (($InjuredPlayers | Measure-Object -Property injuryPenalty -Sum).Sum) 0

  $score = 60
  $score += ($LineupScore - 72) * 2.00
  $score += ($DepthScore - 66) * 1.10
  $score += ($QuarterbackScore - 70) * 0.40
  $score += $eliteCount * 1.50
  $score += $differenceMakerCount * 0.55
  $score += [Math]::Min(6, [Math]::Max(0, $usefulDepthCount - 8)) * 0.45
  $score -= [Math]::Max(0, 8 - $usefulDepthCount) * 0.90
  $score -= $injuryPenalty * 0.32
  $score += $ManualContext

  return [Math]::Min(98, [Math]::Max(35, $score))
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
    $Overrides,
    $ScoringProfile,
    $LineupArchitecture
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
    $playerEntries += Get-PlayerValue -Player $player -PlayerId $playerId -Format $format -Adjustment $adjustment -ScoringProfile $ScoringProfile -LineupArchitecture $LineupArchitecture
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
  $scoringContextScore = [Math]::Min(100, [Math]::Max(0, 68 + ((Get-Average -Items $starters -PropertyName "vbpAdjustment") * 3)))
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
    scoringContext = [Math]::Round($scoringContextScore, 1)
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
  if ($format -eq "bestball") {
    $rawScore = Get-BestBallScore `
      -LineupScore $lineupScore `
      -DepthScore $depthScore `
      -QuarterbackScore $qbScore `
      -PlayerEntries $playerEntries `
      -InjuredPlayers $injuredPlayers `
      -ManualContext $manualContext
  }
  $score = [Math]::Min(100, [Math]::Max(0, $rawScore))

  $record = @{
    wins = [int](Get-NumberValue $Roster.settings.wins 0)
    losses = [int](Get-NumberValue $Roster.settings.losses 0)
    ties = [int](Get-NumberValue $Roster.settings.ties 0)
    pointsFor = [Math]::Round((Get-NumberValue $Roster.settings.fpts 0) + ((Get-NumberValue $Roster.settings.fpts_decimal 0) / 100), 2)
    maxPointsFor = [Math]::Round((Get-NumberValue $Roster.settings.ppts 0) + ((Get-NumberValue $Roster.settings.ppts_decimal 0) / 100), 2)
  }

  [pscustomobject]@{
    rosterId = $rosterId
    ownerId = Get-TextValue $Roster.owner_id
    teamName = Get-TeamName -User $User -Roster $Roster
    score = [Math]::Round($score, 3)
    record = $record
  }
}

function Convert-ToPublishedTeamScores {
  param([object[]]$Rankings, [string]$Format)

  if ($Rankings.Count -eq 0) { return @() }
  if ($Format -notin @("dynasty", "dynastybracket")) {
    foreach ($ranking in $Rankings) {
      $ranking.score = [Math]::Round((Get-NumberValue $ranking.score 0), 1)
    }
    return @($Rankings)
  }

  # Dynasty scores are displayed for comparison within one league. A fixed
  # scale expands real model-score separation without awarding points by rank.
  $averageScore = Get-Average -Items $Rankings -PropertyName "score"
  foreach ($ranking in $Rankings) {
    $relativeDifference = (Get-NumberValue $ranking.score 0) - $averageScore
    $publishedScore = 80 + ($relativeDifference * 3)
    $ranking.score = [Math]::Round([Math]::Min(98, [Math]::Max(35, $publishedScore)), 1)
  }
  return @($Rankings)
}

function Get-PositionGroupCount {
  param([string]$Position, $Architecture)

  switch ($Position) {
    "QB" { return [Math]::Max(1, ([int]$Architecture.qbSlots + [int]$Architecture.superflexSlots)) }
    "RB" { return [Math]::Max(1, [int]$Architecture.rbSlots) }
    "WR" { return [Math]::Max(1, [int]$Architecture.wrSlots) }
    "TE" { return [Math]::Max(1, [int]$Architecture.teSlots) }
    default { return 1 }
  }
}

function Get-PositionalRankings {
  param([object[]]$PlayerEntries, [object[]]$TeamRankings, $Architecture)

  $boards = [ordered]@{}
  $availablePositions = @($PlayerEntries | ForEach-Object { Get-TextValue $_.position } | Where-Object { $_ -and $_ -ne "UNK" } | Sort-Object -Unique)
  $preferredPositions = @("QB", "RB", "WR", "TE", "K", "DEF", "DL", "LB", "DB", "IDP")
  $positionOrder = @($preferredPositions | Where-Object { $availablePositions -contains $_ })
  $positionOrder += @($availablePositions | Where-Object { $preferredPositions -notcontains $_ } | Sort-Object)
  foreach ($position in $positionOrder) {
    $groupCount = Get-PositionGroupCount -Position $position -Architecture $Architecture
    $teamRows = @($TeamRankings | ForEach-Object {
      $team = $_
      $positionPlayers = @($PlayerEntries | Where-Object {
        [int](Get-NumberValue $_.rosterId 0) -eq [int](Get-NumberValue $team.rosterId 0) -and $_.position -eq $position
      } | Sort-Object @{ Expression = { $_.value }; Descending = $true })
      $positionScore = if ($positionPlayers.Count -gt 0) {
        Get-Average -Items @($positionPlayers | Select-Object -First $groupCount) -PropertyName "value"
      } else {
        0
      }
      [pscustomobject]@{
        manager = $team.teamName
        rosterId = $team.rosterId
        score = [Math]::Round($positionScore, 1)
      }
    } | Sort-Object @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.manager }; Descending = $false })
    $rank = 1
    $rows = @($teamRows | ForEach-Object {
      $result = [pscustomobject]@{
        rank = $rank
        manager = $_.manager
        rosterId = $_.rosterId
        score = $_.score
      }
      $rank++
      $result
    })
    $boards[$position] = [pscustomobject]@{
      position = $position
      rankings = $rows
    }
  }
  return [pscustomobject]$boards
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

function Get-DraftStage {
  param($LeagueRecord, $Draft)

  $format = (Get-TextValue $LeagueRecord.format).ToLowerInvariant()
  $playerType = [int](Get-NumberValue (Get-ObjectProperty -Object $Draft.settings -Name "player_type") -1)
  $draftType = (Get-TextValue $Draft.type).ToLowerInvariant()
  $rounds = [int](Get-NumberValue (Get-ObjectProperty -Object $Draft.settings -Name "rounds") 0)
  $name = (Get-TextValue (Get-ObjectProperty -Object $Draft.metadata -Name "name")).ToLowerInvariant()

  if ($playerType -eq 1 -or $name -match "rookie") {
    return "rookie"
  }

  if ($format -in @("dynasty", "dynastybracket", "keeper") -and ($rounds -ge 10 -or $draftType -eq "snake")) {
    return "startup"
  }

  return "regular"
}

function Get-DraftStageLabel {
  param([string]$Stage)

  switch ((Get-TextValue $Stage).ToLowerInvariant()) {
    "rookie" { return "Rookie draft complete" }
    "startup" { return "Startup draft complete" }
    "regular" { return "Regular draft complete" }
    default { return "Draft complete" }
  }
}

function Get-DraftReadiness {
  param($LeagueRecord, [object[]]$Drafts, $LeagueOverride)

  $draftSummaries = @($Drafts | ForEach-Object {
    $stage = Get-DraftStage -LeagueRecord $LeagueRecord -Draft $_
    [pscustomobject]@{
      draftId = Get-TextValue $_.draft_id
      status = (Get-TextValue $_.status).ToLowerInvariant()
      stage = $stage
      type = Get-TextValue $_.type
      season = Get-TextValue $_.season
      seasonType = Get-TextValue $_.season_type
      playerType = [int](Get-NumberValue (Get-ObjectProperty -Object $_.settings -Name "player_type") -1)
      rounds = [int](Get-NumberValue (Get-ObjectProperty -Object $_.settings -Name "rounds") 0)
      name = Get-TextValue (Get-ObjectProperty -Object $_.metadata -Name "name")
    }
  })

  $completedDrafts = @($draftSummaries | Where-Object { $_.status -eq "complete" })
  $openDrafts = @($draftSummaries | Where-Object { $_.status -and $_.status -ne "complete" })
  $latestCompletedDraft = @($completedDrafts | Sort-Object @{ Expression = { Get-NumberValue $_.season 0 }; Descending = $true }, @{ Expression = { $_.stage }; Descending = $false }) | Select-Object -First 1
  $publishOverride = Get-ObjectProperty -Object $LeagueOverride -Name "publishPowerRanking"
  $hasPublishOverride = $null -ne $publishOverride
  $overrideReason = Get-TextValue (Get-ObjectProperty -Object $LeagueOverride -Name "reason")

  $draftingDrafts = @($openDrafts | Where-Object { $_.status -eq "drafting" })
  $ready = $draftSummaries.Count -gt 0 -and $completedDrafts.Count -gt 0 -and $openDrafts.Count -eq 0
  if (-not $ready -and $PublishDrafting -and $draftingDrafts.Count -gt 0) {
    $ready = $true
  }
  $reason = ""
  if ($draftSummaries.Count -eq 0) {
    $reason = "No Sleeper draft data is available yet."
  } elseif ($openDrafts.Count -gt 0) {
    $openLabels = @($openDrafts | ForEach-Object {
      $label = switch ($_.stage) {
        "rookie" { "rookie draft" }
        "startup" { "startup draft" }
        "regular" { "regular draft" }
        default { "draft" }
      }
      "{0} is {1}" -f $label, $_.status
    })
    $reason = ($openLabels -join "; ")
  } elseif ($completedDrafts.Count -eq 0) {
    $reason = "Draft data is not complete."
  }

  if ($hasPublishOverride) {
    $ready = [bool]$publishOverride
    if ($overrideReason) {
      $reason = $overrideReason
    } elseif ($ready) {
      $reason = "Commissioner override marked this board publishable."
    } else {
      $reason = "Commissioner override is holding this board."
    }
  }

  $stage = if ($latestCompletedDraft) { $latestCompletedDraft.stage } elseif ($draftSummaries.Count -gt 0) { $draftSummaries[0].stage } else { "" }
  $label = if ($PublishDrafting -and $draftingDrafts.Count -gt 0) {
    "Live from current Sleeper rosters while draft is in progress"
  } elseif ($ready) {
    Get-DraftStageLabel -Stage $stage
  } elseif ($stage) {
    "Waiting on {0} draft" -f $stage
  } else {
    "Waiting on draft data"
  }

  return [pscustomobject]@{
    ready = [bool]$ready
    stage = $stage
    label = $label
    reason = $reason
    drafts = $draftSummaries
  }
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
  $formatProfile = Get-FormatProfile -Format (Get-TextValue $leagueRecord.format)

  Write-Host ("Refreshing power ranking inputs for {0}..." -f $leagueRecordId)

  try {
    $liveLeague = Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}" -f $sleeperLeagueId)
    $users = Convert-ToArray (Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}/users" -f $sleeperLeagueId))
    $rosterSourceUrl = "https://api.sleeper.app/v1/league/{0}/rosters" -f $sleeperLeagueId
    $rosters = Convert-ToArray (Invoke-SleeperJson -Uri $rosterSourceUrl)
    $drafts = Convert-ToArray (Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}/drafts" -f $sleeperLeagueId))
  } catch {
    $warnings.Add(("ERROR {0}: Sleeper input load failed - {1}" -f $leagueRecordId, $_.Exception.Message)) | Out-Null
    continue
  }

  $draftReadiness = Get-DraftReadiness -LeagueRecord $leagueRecord -Drafts $drafts -LeagueOverride $leagueOverride
  $draftStatuses = @($draftReadiness.drafts | ForEach-Object { $_.status } | Where-Object { $_ })
  $publish = [bool]$draftReadiness.ready
  $holdReason = Get-TextValue $draftReadiness.reason
  $scoringProfile = Get-ScoringProfile -League $liveLeague
  $lineupArchitecture = Get-LineupArchitecture -League $liveLeague
  $rosterSync = [pscustomobject]@{
    source = $rosterSourceUrl
    refreshedAt = (Get-Date).ToString("o")
    rosterCount = @($rosters).Count
    playerCount = [int]((@($rosters) | ForEach-Object { @(Convert-ToArray $_.players).Count } | Measure-Object -Sum).Sum)
    sleeperLeagueSeason = Get-TextValue $liveLeague.season
    sleeperLeagueStatus = Get-TextValue $liveLeague.status
  }

  if (-not $publish -and -not $IncludePending) {
    $warnings.Add(("SKIP {0}: {1}" -f $leagueRecordId, $(if ($holdReason) { $holdReason } else { "Draft data is not complete." }))) | Out-Null
    $generatedLeagues += [pscustomobject]@{
      leagueRecordId = $leagueRecordId
      sleeperLeagueId = $sleeperLeagueId
      name = Get-TextValue $leagueRecord.name
      format = Get-TextValue $leagueRecord.format
      publish = $false
      holdReason = $holdReason
      draftStatuses = $draftStatuses
      draftReadiness = $draftReadiness
      rosterSync = $rosterSync
      rosterPositions = @(Convert-ToArray $liveLeague.roster_positions)
      scoringProfile = $scoringProfile
      lineupArchitecture = $lineupArchitecture
      formatProfile = $formatProfile
      positionalRankings = [pscustomobject]@{}
      rankings = @()
    }
    continue
  }

  $usersById = @{}
  foreach ($user in $users) {
    $userId = Get-TextValue $user.user_id
    if ($userId) { $usersById[$userId] = $user }
  }

  $draftCapitalByRosterId = Get-DraftCapitalByRosterId -Drafts $drafts
  $rankings = @()
  $allPlayerEntries = @()
  foreach ($roster in ($rosters | Where-Object { -not [string]::IsNullOrWhiteSpace((Get-TextValue $_.owner_id)) })) {
    $ownerId = Get-TextValue $roster.owner_id
    $user = if ($usersById.ContainsKey($ownerId)) { $usersById[$ownerId] } else { $null }
    $teamName = Get-TeamName -User $user -Roster $roster
    $rankings += New-TeamRanking -LeagueRecord $leagueRecord -LiveLeague $liveLeague -Roster $roster -User $user -PlayersById $playersById -DraftCapitalByRosterId $draftCapitalByRosterId -Overrides $overrides -ScoringProfile $scoringProfile -LineupArchitecture $lineupArchitecture
    foreach ($playerId in (Convert-ToArray $roster.players | ForEach-Object { Get-TextValue $_ } | Where-Object { $_ })) {
      $player = Get-Player -PlayersById $playersById -PlayerId $playerId
      if ($null -eq $player) { continue }
      $adjustment = Get-ObjectProperty -Object $overrides.playerAdjustments -Name $playerId
      $entry = Get-PlayerValue -Player $player -PlayerId $playerId -Format (Get-TextValue $leagueRecord.format) -Adjustment $adjustment -ScoringProfile $scoringProfile -LineupArchitecture $lineupArchitecture
      $entry | Add-Member -NotePropertyName rosterId -NotePropertyValue ([int](Get-NumberValue $roster.roster_id 0)) -Force
      $entry | Add-Member -NotePropertyName manager -NotePropertyValue $teamName -Force
      $allPlayerEntries += $entry
    }
  }

  $rankings = Convert-ToPublishedTeamScores -Rankings $rankings -Format (Get-TextValue $leagueRecord.format)
  $rank = 1
  $rankings = @($rankings | Sort-Object @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.record.pointsFor }; Descending = $true } | ForEach-Object {
    $_ | Add-Member -NotePropertyName rank -NotePropertyValue $rank -Force
    $rank++
    $_
  })
  $positionalRankings = Get-PositionalRankings -PlayerEntries $allPlayerEntries -TeamRankings $rankings -Architecture $lineupArchitecture

  $generatedLeagues += [pscustomobject]@{
    leagueRecordId = $leagueRecordId
    sleeperLeagueId = $sleeperLeagueId
    name = Get-TextValue $leagueRecord.name
    format = Get-TextValue $leagueRecord.format
    publish = [bool]$publish
    holdReason = $holdReason
    draftStatuses = $draftStatuses
    draftReadiness = $draftReadiness
    rosterSync = $rosterSync
    rosterPositions = @(Convert-ToArray $liveLeague.roster_positions)
    scoringProfile = $scoringProfile
    lineupArchitecture = $lineupArchitecture
    formatProfile = $formatProfile
    positionalRankings = $positionalRankings
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
  source = "Sleeper league scoring settings, roster, user, draft, draft-pick, and player metadata endpoints plus data/power-ranking-overrides.json."
  methodology = [pscustomobject]@{
    summary = "The board compares each roster within its league using current Sleeper data and the league's scoring rules. Scores are for relative team strength, not projected standings."
    components = @(
      "League settings: active Sleeper scoring and starter requirements.",
      "Roster quality: lineup strength, useful depth, and quarterback stability.",
      "Dynasty outlook: age curve and future draft capital.",
      "Availability: current injury and player-status information.",
      "Position boards: each owner's strength at QB, RB, WR, and TE.",
      "Score meaning: relative roster grade, not a season prediction."
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
