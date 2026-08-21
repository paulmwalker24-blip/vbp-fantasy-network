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
$script:ProjectionProfileCache = @{}

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
  foreach ($attempt in 1..4) {
    $separator = if ($Uri.Contains("?")) { "&" } else { "?" }
    $cacheBustedUri = "{0}{1}_={2}" -f $Uri, $separator, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    try {
      return Invoke-RestMethod -Uri $cacheBustedUri -Headers @{
        "User-Agent" = "vbp-power-rankings/2.0"
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
      }
    } catch {
      $statusCode = 0
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      }
      if ($attempt -ge 4 -or ($statusCode -ne 429 -and $statusCode -lt 500)) { throw }
      Start-Sleep -Seconds ([Math]::Min([Math]::Pow(2, $attempt), 30))
    }
  }
}

function Get-ObjectProperty {
  param($Object, [string]$Name)
  if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $null }
  if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-Player {
  param($PlayersById, [string]$PlayerId)
  if ([string]::IsNullOrWhiteSpace($PlayerId)) { return $null }
  return Get-ObjectProperty -Object $PlayersById -Name $PlayerId
}

function Test-ScoringDerivedFormat {
  param([string]$Format)
  return (Get-TextValue $Format).ToLowerInvariant() -in @("bestball", "gauntlet", "redraft", "bracket", "keeper", "chopped")
}

function Test-OffensiveProjectionKey {
  param([string]$Name)
  return $Name -match '^(pass_|rush_|rec_|bonus_pass_|bonus_rush_|bonus_rec_|fum$|fum_lost$|fum_rec$|fum_rec_td$|def_fum_td$)'
}

function Get-ProjectionPointProfile {
  param(
    [string]$PlayerId,
    [object[]]$ProjectionWeeks,
    $ScoringSettings
  )

  $scoringSignature = @($ScoringSettings.PSObject.Properties | Where-Object {
    [Math]::Abs((Get-NumberValue $_.Value 0)) -gt 0.000001
  } | Sort-Object Name | ForEach-Object { "{0}={1}" -f $_.Name, (Get-NumberValue $_.Value 0) }) -join ";"
  $cacheKey = "${scoringSignature}|${PlayerId}"
  if ($script:ProjectionProfileCache.ContainsKey($cacheKey)) {
    return $script:ProjectionProfileCache[$cacheKey]
  }

  $weeklyPoints = New-Object System.Collections.Generic.List[double]
  $coveredWeeks = 0
  foreach ($weekMap in $ProjectionWeeks) {
    $projection = Get-ObjectProperty -Object $weekMap -Name $PlayerId
    $points = 0.0
    $hasProjection = $false
    if ($projection) {
      foreach ($setting in $ScoringSettings.PSObject.Properties) {
        $multiplier = Get-NumberValue $setting.Value 0
        if ([Math]::Abs($multiplier) -lt 0.000001) { continue }
        $statValue = Get-ObjectProperty -Object $projection -Name $setting.Name
        if ($null -eq $statValue) { continue }
        $hasProjection = $true
        $points += (Get-NumberValue $statValue 0) * $multiplier
      }
      if ((Get-NumberValue (Get-ObjectProperty -Object $projection -Name "gp") 0) -gt 0) {
        $hasProjection = $true
      }
    }
    if ($hasProjection) { $coveredWeeks++ }
    $weeklyPoints.Add([Math]::Max(0, [Math]::Round($points, 3))) | Out-Null
  }

  $seasonTotal = Get-NumberValue (($weeklyPoints | Measure-Object -Sum).Sum) 0
  $weeklyAverage = if ($ProjectionWeeks.Count -gt 0) { $seasonTotal / $ProjectionWeeks.Count } else { 0 }
  $ceilingWeeks = @($weeklyPoints | Where-Object { $_ -gt 0 } | Sort-Object -Descending | Select-Object -First 3)
  $weeklyCeiling = if ($ceilingWeeks.Count -gt 0) { Get-NumberValue (($ceilingWeeks | Measure-Object -Average).Average) 0 } else { 0 }

  $profile = [pscustomobject]@{
    seasonTotal = [Math]::Round($seasonTotal, 2)
    weeklyAverage = [Math]::Round($weeklyAverage, 3)
    weeklyCeiling = [Math]::Round($weeklyCeiling, 3)
    coveredWeeks = $coveredWeeks
  }
  $script:ProjectionProfileCache[$cacheKey] = $profile
  return $profile
}

function Convert-ProjectionToPlayerValue {
  param(
    $ProjectionProfile,
    [double]$InjuryPenalty,
    [double]$ManualAdjustment
  )

  $averagePoints = Get-NumberValue $ProjectionProfile.weeklyAverage 0
  $ceilingPoints = Get-NumberValue $ProjectionProfile.weeklyCeiling 0
  $averageGrade = [Math]::Min(99, [Math]::Max(15, 30 + ($averagePoints * 3.50)))
  $ceilingGrade = [Math]::Min(99, [Math]::Max(15, 28 + ($ceilingPoints * 3.35)))
  $grade = ($averageGrade * 0.72) + ($ceilingGrade * 0.28) - ($InjuryPenalty * 0.35) + $ManualAdjustment
  return [Math]::Min(99, [Math]::Max(0, $grade))
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
    $LineupArchitecture,
    [object[]]$ProjectionWeeks = @(),
    $ScoringSettings = $null
  )

  $position = Get-PrimaryPosition $Player
  $base = Get-PositionBase $position
  $market = Get-SearchRankScore $Player
  $age = Get-AgeScore -Player $Player -Format $Format
  $depth = Get-DepthChartScore $Player
  $injuryPenalty = Get-InjuryPenalty -Player $Player -Adjustment $Adjustment
  $manual = if ($Adjustment) { Get-NumberValue (Get-ObjectProperty -Object $Adjustment -Name "valueAdjustment") 0 } else { 0 }
  $vbpAdjustment = Get-VbpScoringAdjustment -Position $position -ScoringProfile $ScoringProfile -LineupArchitecture $LineupArchitecture

  $projectionProfile = if ($ProjectionWeeks.Count -gt 0 -and $ScoringSettings) {
    Get-ProjectionPointProfile -PlayerId $PlayerId -ProjectionWeeks $ProjectionWeeks -ScoringSettings $ScoringSettings
  } else {
    [pscustomobject]@{ seasonTotal = 0; weeklyAverage = 0; weeklyCeiling = 0; coveredWeeks = 0 }
  }
  $projectionValue = Convert-ProjectionToPlayerValue -ProjectionProfile $projectionProfile -InjuryPenalty $injuryPenalty -ManualAdjustment $manual

  $value = ($base * 0.20) + ($market * 0.42) + ($age * 0.22) + ($depth * 0.16) + $vbpAdjustment - $injuryPenalty + $manual
  $value = [Math]::Min(99, [Math]::Max(0, $value))
  $seasonValue = ($base * 0.18) + ($market * 0.52) + ($depth * 0.30) + $vbpAdjustment - $injuryPenalty + $manual
  $seasonValue = [Math]::Min(99, [Math]::Max(0, $seasonValue))

  if (Test-ScoringDerivedFormat -Format $Format) {
    $value = $projectionValue
    $seasonValue = $projectionValue
  } elseif ($Format -in @("dynasty", "dynastybracket")) {
    # Dynasty asset value remains long-term, while its current-season board is
    # calculated from the same full scoring-derived projection standard.
    $seasonValue = $projectionValue
  }

  [pscustomobject]@{
    playerId = $PlayerId
    name = Get-PlayerName -Player $Player -PlayerId $PlayerId
    position = $position
    team = Get-TextValue $Player.team
    age = Get-NumberValue $Player.age 0
    injuryStatus = Get-TextValue $Player.injury_status
    searchRank = Get-NumberValue $Player.search_rank 0
    value = [Math]::Round($value, 1)
    seasonValue = [Math]::Round($seasonValue, 1)
    projectedSeasonPoints = Get-NumberValue $projectionProfile.seasonTotal 0
    projectedWeeklyPoints = Get-NumberValue $projectionProfile.weeklyAverage 0
    projectedWeeklyCeiling = Get-NumberValue $projectionProfile.weeklyCeiling 0
    projectionWeeks = [int](Get-NumberValue $projectionProfile.coveredWeeks 0)
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
  $displayName = if ($User) { Get-TextValue $User.display_name } else { "" }
  if (-not [string]::IsNullOrWhiteSpace($teamName) -and $teamName -notmatch "^Slot\s+\d+$") { return $teamName }
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

function Get-CurrentSeasonProfile {
  param(
    [object[]]$PlayerEntries,
    $LiveLeague,
    [double]$ManualContext
  )

  $seasonEntries = @($PlayerEntries | ForEach-Object {
    [pscustomobject]@{
      position = $_.position
      value = Get-NumberValue $_.seasonValue 0
      injuryPenalty = Get-NumberValue $_.injuryPenalty 0
    }
  })
  $slots = Get-LineupSlots -League $LiveLeague
  $optimized = Get-OptimizedLineup -Players $seasonEntries -Slots $slots
  $starters = @($optimized.starters)
  $bench = @($optimized.bench | Select-Object -First 7)
  $qbs = @($seasonEntries | Where-Object { $_.position -eq "QB" } | Sort-Object @{ Expression = { $_.value }; Descending = $true } | Select-Object -First 2)
  $elitePlayers = @($seasonEntries | Where-Object { $_.value -ge 84 })
  $injuryPenalty = Get-NumberValue (($seasonEntries | Measure-Object -Property injuryPenalty -Sum).Sum) 0

  $lineupScore = Get-Average -Items $starters -PropertyName "value"
  $depthScore = Get-Average -Items $bench -PropertyName "value"
  $quarterbackScore = Get-Average -Items $qbs -PropertyName "value"
  $eliteScore = [Math]::Min(100, 58 + ($elitePlayers.Count * 8))
  $healthScore = [Math]::Max(0, 100 - $injuryPenalty)

  $components = [ordered]@{
    lineup = [Math]::Round($lineupScore, 1)
    depth = [Math]::Round($depthScore, 1)
    quarterback = [Math]::Round($quarterbackScore, 1)
    eliteCeiling = [Math]::Round($eliteScore, 1)
    health = [Math]::Round($healthScore, 1)
  }

  [pscustomobject]@{
    score = (($lineupScore * 0.50) + ($depthScore * 0.18) + ($quarterbackScore * 0.14) + ($eliteScore * 0.08) + ($healthScore * 0.10) + $ManualContext)
    components = $components
  }
}

function Get-Ordinal {
  param([int]$Value)
  $suffix = "th"
  if (($Value % 100) -notin @(11, 12, 13)) {
    switch ($Value % 10) {
      1 { $suffix = "st" }
      2 { $suffix = "nd" }
      3 { $suffix = "rd" }
    }
  }
  return "{0}{1}" -f $Value, $suffix
}

function Get-RankingReasonText {
  param(
    [string]$Component,
    [string]$Tone,
    [double]$Score,
    [int]$Rank,
    [int]$TeamCount
  )

  $labels = @{
    lineup = "Starting lineup"
    depth = "Usable depth"
    quarterback = "Quarterback room"
    eliteCeiling = "Top-end ceiling"
    health = "Player availability"
    scoringContext = "Scoring-system fit"
    dynastyValue = "Dynasty value and draft capital"
    context = "Commissioner-reviewed context"
  }
  $impacts = @{
    lineup = "drives the weekly baseline"
    depth = "shapes bye-week and injury resilience"
    quarterback = "is especially important in Superflex"
    eliteCeiling = "creates matchup-winning upside"
    health = "affects how much of the roster is immediately usable"
    scoringContext = "shows how well the roster matches league scoring"
    dynastyValue = "supports the roster beyond the current season"
    context = "captures reviewed factors outside Sleeper's raw data"
  }
  $label = if ($labels.ContainsKey($Component)) { $labels[$Component] } else { $Component }
  $impact = if ($impacts.ContainsKey($Component)) { $impacts[$Component] } else { "affects the overall outlook" }
  $rankLabel = Get-Ordinal -Value $Rank
  $ending = if ($Tone -eq "positive") { "one of this roster's strongest pillars" } else { "the clearest area holding the roster back" }
  return "{0}: {1:N1} grade, {2} of {3}; {4} and is {5}." -f $label, $Score, $rankLabel, $TeamCount, $impact, $ending
}

function Add-RankingReasons {
  param([object[]]$Rankings, [string]$ComponentPropertyName)

  if ($Rankings.Count -eq 0) { return @() }
  $firstComponents = Get-ObjectProperty -Object $Rankings[0] -Name $ComponentPropertyName
  $componentNames = if ($firstComponents -is [System.Collections.IDictionary]) {
    @($firstComponents.Keys)
  } else {
    @($firstComponents.PSObject.Properties.Name)
  }
  $averages = @{}
  $spreads = @{}
  $valuesByComponent = @{}
  foreach ($componentName in $componentNames) {
    $values = @($Rankings | ForEach-Object {
      $components = Get-ObjectProperty -Object $_ -Name $ComponentPropertyName
      Get-NumberValue (Get-ObjectProperty -Object $components -Name $componentName) 0
    })
    $measure = $values | Measure-Object -Average -Minimum -Maximum
    $averages[$componentName] = $measure.Average
    $spreads[$componentName] = $measure.Maximum - $measure.Minimum
    $valuesByComponent[$componentName] = $values
  }
  $meaningfulComponents = @($componentNames | Where-Object { $spreads[$_] -ge 0.5 })
  if ($meaningfulComponents.Count -ge 3) { $componentNames = $meaningfulComponents }

  foreach ($ranking in $Rankings) {
    $components = Get-ObjectProperty -Object $ranking -Name $ComponentPropertyName
    $differences = @($componentNames | ForEach-Object {
      $score = Get-NumberValue (Get-ObjectProperty -Object $components -Name $_) 0
      [pscustomobject]@{
        component = $_
        score = $score
        rank = 1 + @($valuesByComponent[$_] | Where-Object { $_ -gt $score }).Count
        difference = $score - $averages[$_]
      }
    })
    $strengths = @($differences | Sort-Object @{ Expression = { $_.difference }; Descending = $true } | Select-Object -First 2)
    $concern = $differences | Sort-Object @{ Expression = { $_.difference }; Descending = $false } | Select-Object -First 1
    $reasons = @($strengths | ForEach-Object {
      [pscustomobject]@{ tone = "positive"; text = Get-RankingReasonText -Component $_.component -Tone "positive" -Score $_.score -Rank $_.rank -TeamCount $Rankings.Count }
    })
    $reasons += [pscustomobject]@{ tone = "concern"; text = Get-RankingReasonText -Component $concern.component -Tone "concern" -Score $concern.score -Rank $concern.rank -TeamCount $Rankings.Count }
    $ranking | Add-Member -NotePropertyName reasons -NotePropertyValue $reasons -Force
  }
  return @($Rankings)
}

function Join-PlayerNames {
  param([object[]]$Players, [int]$Limit = 3)
  $names = @($Players | Select-Object -First $Limit | ForEach-Object { Get-TextValue $_.name } | Where-Object { $_ })
  if ($names.Count -eq 0) { return "" }
  if ($names.Count -eq 1) { return $names[0] }
  if ($names.Count -eq 2) { return "{0} and {1}" -f $names[0], $names[1] }
  return "{0}, {1}, and {2}" -f $names[0], $names[1], $names[2]
}

function New-NarrativeReason {
  param([string]$Tone, [int]$Priority, [string]$Text)
  [pscustomobject]@{ tone = $Tone; priority = $Priority; text = $Text }
}

function Get-DynastyNarrativeReasons {
  param(
    [object[]]$PlayerEntries,
    $LiveLeague,
    [double]$DraftCapitalScore,
    [string]$Mode
  )

  $seasonEntries = @($PlayerEntries | ForEach-Object {
    [pscustomobject]@{
      name = $_.name
      position = $_.position
      age = $_.age
      value = Get-NumberValue $_.seasonValue 0
      dynastyValue = Get-NumberValue $_.value 0
      injuryPenalty = Get-NumberValue $_.injuryPenalty 0
    }
  })
  $seasonOptimized = Get-OptimizedLineup -Players $seasonEntries -Slots (Get-LineupSlots -League $LiveLeague)
  $seasonStarters = @($seasonOptimized.starters)
  $seasonBench = @($seasonOptimized.bench | Select-Object -First 7)
  $startingQbs = @($seasonStarters | Where-Object position -eq "QB" | Sort-Object value -Descending)
  $startingRbs = @($seasonStarters | Where-Object position -eq "RB" | Sort-Object value -Descending)
  $startingWrs = @($seasonStarters | Where-Object position -eq "WR" | Sort-Object value -Descending)
  $seasonStars = @($seasonEntries | Where-Object { $_.value -ge 82 } | Sort-Object value -Descending)
  $youngStarters = @($seasonStarters | Where-Object { $_.age -gt 0 -and $_.age -le 24 })
  $lineupScore = Get-Average -Items $seasonStarters -PropertyName "value"
  $depthScore = Get-Average -Items $seasonBench -PropertyName "value"
  $qbScore = Get-Average -Items (@($startingQbs | Select-Object -First 2)) -PropertyName "value"

  $positives = New-Object System.Collections.Generic.List[object]
  $concerns = New-Object System.Collections.Generic.List[object]

  if ($Mode -eq "current") {
    if ($startingQbs.Count -ge 2 -and $qbScore -ge 72) {
      $positives.Add((New-NarrativeReason "positive" 95 ("Strong Superflex quarterbacks: {0} give this roster two dependable weekly QB options." -f (Join-PlayerNames $startingQbs 2)))) | Out-Null
    }
    if ($seasonStars.Count -ge 3) {
      $positives.Add((New-NarrativeReason "positive" 92 ("Difference-making stars: {0} give this lineup multiple players capable of swinging weekly matchups." -f (Join-PlayerNames $seasonStars 3)))) | Out-Null
    }
    if ($lineupScore -ge 75) {
      $positives.Add((New-NarrativeReason "positive" 88 ("Championship-ready starters: the projected starting lineup is built around proven weekly production led by {0}." -f (Join-PlayerNames ($seasonStarters | Sort-Object value -Descending) 3)))) | Out-Null
    }
    if ($depthScore -ge 69) {
      $positives.Add((New-NarrativeReason "positive" 82 ("Excellent usable depth: {0} provide credible injury and bye-week coverage." -f (Join-PlayerNames $seasonBench 3)))) | Out-Null
    }
    if ((Get-Average -Items $startingWrs -PropertyName "value") -ge 74) {
      $positives.Add((New-NarrativeReason "positive" 78 ("Reliable receiving corps: {0} give the lineup a strong weekly floor at WR and FLEX." -f (Join-PlayerNames $startingWrs 3)))) | Out-Null
    }
    if ((Get-Average -Items $startingRbs -PropertyName "value") -ge 72) {
      $positives.Add((New-NarrativeReason "positive" 76 ("Immediate RB production: {0} anchor a backfield positioned to contribute right away." -f (Join-PlayerNames $startingRbs 3)))) | Out-Null
    }

    if ($startingQbs.Count -lt 2 -or $qbScore -lt 67) {
      $concerns.Add((New-NarrativeReason "concern" 98 ("Quarterback uncertainty: the roster lacks two dependable Superflex starters behind {0}." -f (Join-PlayerNames $startingQbs 1)))) | Out-Null
    }
    if ($depthScore -lt 65) {
      $concerns.Add((New-NarrativeReason "concern" 94 "Thin behind the starters: an injury or heavy bye week could force unreliable bench options into the lineup.")) | Out-Null
    }
    if ($seasonStars.Count -lt 2) {
      $concerns.Add((New-NarrativeReason "concern" 88 "Missing weekly ceiling: the roster has usable players but few proven difference-makers who can decide matchups.")) | Out-Null
    }
    if ($youngStarters.Count -ge 4) {
      $concerns.Add((New-NarrativeReason "concern" 84 ("Too breakout-dependent: {0} still need young players to become immediate weekly producers." -f (Join-PlayerNames $youngStarters 3)))) | Out-Null
    }
    if ((Get-Average -Items $startingRbs -PropertyName "value") -lt 67) {
      $concerns.Add((New-NarrativeReason "concern" 80 ("Running back risk: the projected backfield led by {0} lacks secure immediate production." -f (Join-PlayerNames $startingRbs 2)))) | Out-Null
    }
  } else {
    $youngCore = @($PlayerEntries | Where-Object {
      $_.value -ge 78 -and $_.age -gt 0 -and (($_.position -eq "QB" -and $_.age -le 28) -or ($_.position -ne "QB" -and $_.age -le 25))
    } | Sort-Object value -Descending)
    $youngQbs = @($PlayerEntries | Where-Object { $_.position -eq "QB" -and $_.age -gt 0 -and $_.age -le 28 -and $_.value -ge 70 } | Sort-Object value -Descending)
    $youngWrs = @($PlayerEntries | Where-Object { $_.position -eq "WR" -and $_.age -gt 0 -and $_.age -le 25 -and $_.value -ge 70 } | Sort-Object value -Descending)
    $agingCore = @($PlayerEntries | Where-Object {
      $_.value -ge 72 -and $_.age -gt 0 -and (($_.position -eq "QB" -and $_.age -ge 34) -or ($_.position -ne "QB" -and $_.age -ge 29))
    } | Sort-Object value -Descending)
    $cornerstones = @($PlayerEntries | Where-Object { $_.value -ge 84 } | Sort-Object value -Descending)

    if ($youngCore.Count -ge 3) {
      $positives.Add((New-NarrativeReason "positive" 98 ("Elite young foundation: {0} give this roster multiple cornerstone assets entering or already within their prime." -f (Join-PlayerNames $youngCore 3)))) | Out-Null
    }
    if ($youngQbs.Count -ge 2) {
      $positives.Add((New-NarrativeReason "positive" 94 ("Long-term quarterback security: {0} provide stability at dynasty's most valuable position." -f (Join-PlayerNames $youngQbs 2)))) | Out-Null
    }
    if ($youngWrs.Count -ge 3) {
      $positives.Add((New-NarrativeReason "positive" 90 ("Ascending receiving corps: {0} combine current production with long-term upside." -f (Join-PlayerNames $youngWrs 3)))) | Out-Null
    }
    if ($DraftCapitalScore -ge 76) {
      $positives.Add((New-NarrativeReason "positive" 86 "Future flexibility: the rookie-pick inventory gives this manager options to add young talent or trade for proven help.")) | Out-Null
    }
    if ($cornerstones.Count -ge 3 -and $agingCore.Count -le 2) {
      $positives.Add((New-NarrativeReason "positive" 82 ("Extended championship window: {0} support competing now without forcing an immediate rebuild." -f (Join-PlayerNames $cornerstones 3)))) | Out-Null
    }

    if ($agingCore.Count -ge 4) {
      $concerns.Add((New-NarrativeReason "concern" 98 ("Aging core: {0} may lose dynasty value quickly and shorten the roster's competitive window." -f (Join-PlayerNames $agingCore 3)))) | Out-Null
    }
    if ($DraftCapitalScore -le 64) {
      $concerns.Add((New-NarrativeReason "concern" 94 "Limited future draft capital: the roster has fewer rookie-pick resources available to repair weaknesses or acquire help.")) | Out-Null
    }
    if ($youngQbs.Count -eq 0) {
      $concerns.Add((New-NarrativeReason "concern" 92 "No young quarterback foundation: long-term Superflex stability remains a major concern.")) | Out-Null
    }
    if ($cornerstones.Count -lt 2) {
      $concerns.Add((New-NarrativeReason "concern" 88 "Missing cornerstone assets: the roster lacks enough players capable of anchoring its value for several seasons.")) | Out-Null
    }
    if ($youngCore.Count -ge 5 -and $lineupScore -lt 73) {
      $concerns.Add((New-NarrativeReason "concern" 84 ("Prospect-heavy roster: {0} provide upside, but the team still needs young assets to become proven producers." -f (Join-PlayerNames $youngCore 3)))) | Out-Null
    }
  }

  if ($positives.Count -lt 2) {
    $bestPlayers = if ($Mode -eq "current") { @($seasonEntries | Sort-Object value -Descending) } else { @($PlayerEntries | Sort-Object value -Descending) }
    $positives.Add((New-NarrativeReason "positive" 20 ("Core building blocks: {0} give the roster a credible foundation for its next move." -f (Join-PlayerNames $bestPlayers 3)))) | Out-Null
    $positives.Add((New-NarrativeReason "positive" 10 "Balanced roster construction: the team has enough usable pieces across positions to remain flexible.")) | Out-Null
  }
  if ($concerns.Count -eq 0) {
    if ($Mode -eq "current") {
      if ($depthScore -le $qbScore -and $depthScore -le $lineupScore) {
        $concerns.Add((New-NarrativeReason "concern" 20 ("Depth pressure: behind {0}, the bench has fewer proven weekly options if injuries or bye weeks hit together." -f (Join-PlayerNames $seasonBench 3)))) | Out-Null
      } elseif ($qbScore -le $lineupScore) {
        $concerns.Add((New-NarrativeReason "concern" 20 ("Quarterback depth: {0} form a strong starting pair, but the roster has limited protection behind them in Superflex." -f (Join-PlayerNames $startingQbs 2)))) | Out-Null
      } else {
        $concerns.Add((New-NarrativeReason "concern" 20 ("Flex volatility: after {0}, the final weekly starting spots carry more uncertainty than the roster's stars." -f (Join-PlayerNames ($seasonStarters | Sort-Object value -Descending) 3)))) | Out-Null
      }
    } else {
      if ($agingCore.Count -gt 0) {
        $concerns.Add((New-NarrativeReason "concern" 20 ("Succession planning: veterans such as {0} remain valuable, but the roster will eventually need younger replacements behind them." -f (Join-PlayerNames $agingCore 3)))) | Out-Null
      } elseif ($youngQbs.Count -lt 2) {
        $concerns.Add((New-NarrativeReason "concern" 20 ("Quarterback succession: {0} provide a foundation, but another young long-term starter would strengthen the Superflex outlook." -f (Join-PlayerNames $youngQbs 2)))) | Out-Null
      } elseif ($youngWrs.Count -lt 3) {
        $concerns.Add((New-NarrativeReason "concern" 20 ("Receiving succession: the roster needs another young long-term WR alongside {0}." -f (Join-PlayerNames $youngWrs 2)))) | Out-Null
      } else {
        $concerns.Add((New-NarrativeReason "concern" 20 "Future flexibility: the roster is strong, but preserving rookie picks will matter when the current core eventually needs reinforcement.")) | Out-Null
      }
    }
  }

  $selected = @($positives | Sort-Object priority -Descending | Select-Object -First 2)
  $selected += @($concerns | Sort-Object priority -Descending | Select-Object -First 1)
  return @($selected | ForEach-Object { [pscustomobject]@{ tone = $_.tone; text = $_.text } })
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
    $LineupArchitecture,
    [object[]]$ProjectionWeeks = @()
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
    $playerEntries += Get-PlayerValue -Player $player -PlayerId $playerId -Format $format -Adjustment $adjustment -ScoringProfile $ScoringProfile -LineupArchitecture $LineupArchitecture -ProjectionWeeks $ProjectionWeeks -ScoringSettings $LiveLeague.scoring_settings
  }

  $slots = Get-LineupSlots -League $LiveLeague
  if (Test-ScoringDerivedFormat -Format $format) {
    $projectedPlayers = @($playerEntries | Where-Object { (Get-NumberValue $_.projectionWeeks 0) -gt 0 -and (Get-NumberValue $_.projectedWeeklyPoints 0) -gt 0 })
    if ($projectedPlayers.Count -lt $slots.Count) {
      throw "Roster $rosterId in $leagueRecordId has only $($projectedPlayers.Count) positively projected players for $($slots.Count) required starters. Scoring-derived rankings were not published."
    }
  }
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
  $currentSeasonProfile = Get-CurrentSeasonProfile -PlayerEntries $playerEntries -LiveLeague $LiveLeague -ManualContext $manualContext
  $futureReasons = if ($format -eq "dynasty") { Get-DynastyNarrativeReasons -PlayerEntries $playerEntries -LiveLeague $LiveLeague -DraftCapitalScore $draftCapitalScore -Mode "future" } else { @() }
  $currentSeasonReasons = if ($format -eq "dynasty") { Get-DynastyNarrativeReasons -PlayerEntries $playerEntries -LiveLeague $LiveLeague -DraftCapitalScore $draftCapitalScore -Mode "current" } else { @() }

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
    currentSeasonScore = [Math]::Round($currentSeasonProfile.score, 3)
    componentScores = $componentScores
    currentSeasonComponents = $currentSeasonProfile.components
    futureReasons = $futureReasons
    currentSeasonReasons = $currentSeasonReasons
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

function Get-CurrentSeasonRankings {
  param([object[]]$Rankings)

  if ($Rankings.Count -eq 0) { return @() }
  $averageScore = Get-Average -Items $Rankings -PropertyName "currentSeasonScore"
  $rows = @($Rankings | ForEach-Object {
    $relativeDifference = (Get-NumberValue $_.currentSeasonScore 0) - $averageScore
    [pscustomobject]@{
      rosterId = $_.rosterId
      ownerId = $_.ownerId
      teamName = $_.teamName
      score = [Math]::Round([Math]::Min(98, [Math]::Max(35, (80 + ($relativeDifference * 3)))), 1)
      reasons = $_.currentSeasonReasons
      record = $_.record
    }
  })

  $rank = 1
  return @($rows | Sort-Object @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.record.pointsFor }; Descending = $true } | ForEach-Object {
    $_ | Add-Member -NotePropertyName rank -NotePropertyValue $rank -Force
    $rank++
    $_
  })
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

$projectionSeason = Get-TextValue (Get-ObjectProperty -Object $nflState -Name "season")
if ([string]::IsNullOrWhiteSpace($projectionSeason)) {
  $projectionSeason = Get-TextValue (Get-ObjectProperty -Object $selectedLeagues[0] -Name "sleeperSeason")
}
if ($projectionSeason -notmatch '^\d{4}$') {
  throw "Could not resolve a four-digit season for scoring-derived projections."
}

Write-Host ("Loading Sleeper {0} weekly stat projections for scoring-derived rankings..." -f $projectionSeason)
$projectionWeeks = New-Object System.Collections.Generic.List[object]
$projectionSupportedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$projectionQuery = "season_type=regular&position%5B%5D=QB&position%5B%5D=RB&position%5B%5D=WR&position%5B%5D=TE"
foreach ($projectionWeek in 1..17) {
  $projectionUri = "https://api.sleeper.app/v1/projections/nfl/regular/{0}/{1}?{2}" -f $projectionSeason, $projectionWeek, $projectionQuery
  $weekMap = Invoke-SleeperJson -Uri $projectionUri
  $weekProperties = @($weekMap.PSObject.Properties)
  $usableProjectionCount = 0
  foreach ($playerProjection in $weekProperties) {
    $hasUsableProjection = (Get-NumberValue (Get-ObjectProperty -Object $playerProjection.Value -Name "gp") 0) -gt 0 -or
      $null -ne (Get-ObjectProperty -Object $playerProjection.Value -Name "pass_yd") -or
      $null -ne (Get-ObjectProperty -Object $playerProjection.Value -Name "rush_yd") -or
      $null -ne (Get-ObjectProperty -Object $playerProjection.Value -Name "rec_yd")
    if (-not $hasUsableProjection) { continue }
    $usableProjectionCount++
    if ($projectionWeek -eq 1) {
      foreach ($statProperty in $playerProjection.Value.PSObject.Properties) {
        [void]$projectionSupportedKeys.Add($statProperty.Name)
      }
    }
    if ($usableProjectionCount -ge 300) { break }
  }
  if ($usableProjectionCount -lt 300) {
    throw "Sleeper projection Week $projectionWeek returned only $usableProjectionCount usable offensive players. Existing published rankings were preserved."
  }
  $projectionWeeks.Add($weekMap) | Out-Null
}
if ($projectionWeeks.Count -ne 17) { throw "Scoring-derived rankings require all 17 weekly projection maps." }
$projectionWeekMaps = $projectionWeeks.ToArray()

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
  $nonzeroOffensiveScoringKeys = @($liveLeague.scoring_settings.PSObject.Properties | Where-Object {
    [Math]::Abs((Get-NumberValue $_.Value 0)) -gt 0.000001 -and (Test-OffensiveProjectionKey -Name $_.Name)
  } | ForEach-Object { $_.Name } | Sort-Object -Unique)
  $projectionAppliedKeys = @($nonzeroOffensiveScoringKeys | Where-Object { $projectionSupportedKeys.Contains($_) })
  $projectionZeroAssumptionKeys = @($nonzeroOffensiveScoringKeys | Where-Object { -not $projectionSupportedKeys.Contains($_) })
  $requiredProjectionKeys = @("pass_yd", "pass_td", "pass_int", "rush_yd", "rush_td", "rec_yd", "rec_td", "bonus_rec_rb", "bonus_rec_wr", "bonus_rec_te")
  $missingRequiredKeys = @($requiredProjectionKeys | Where-Object {
    [Math]::Abs((Get-NumberValue (Get-ObjectProperty -Object $liveLeague.scoring_settings -Name $_) 0)) -gt 0.000001 -and
      -not $projectionSupportedKeys.Contains($_)
  })
  if ($missingRequiredKeys.Count -gt 0) {
    throw "League '$leagueRecordId' cannot meet the scoring-derived standard because Sleeper projections are missing required keys: $($missingRequiredKeys -join ', ')."
  }
  $scoringProfile | Add-Member -NotePropertyName projectionModel -NotePropertyValue ([pscustomobject]@{
    version = "2.0-scoring-derived"
    source = "Sleeper weekly stat projections, Weeks 1-17"
    formula = "For each player and week, sum projected_stat multiplied by the matching live Sleeper scoring_settings coefficient."
    appliedScoringKeys = $projectionAppliedKeys
    zeroAssumptionKeys = $projectionZeroAssumptionKeys
    note = "Nonzero offensive categories without a projection field are explicitly treated as zero, never silently replaced with generic PPR points."
  }) -Force
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
  $rankingFailure = ""
  try {
    foreach ($roster in ($rosters | Where-Object { -not [string]::IsNullOrWhiteSpace((Get-TextValue $_.owner_id)) })) {
      $ownerId = Get-TextValue $roster.owner_id
      $user = if ($usersById.ContainsKey($ownerId)) { $usersById[$ownerId] } else { $null }
      $teamName = Get-TeamName -User $user -Roster $roster
      $rankings += New-TeamRanking -LeagueRecord $leagueRecord -LiveLeague $liveLeague -Roster $roster -User $user -PlayersById $playersById -DraftCapitalByRosterId $draftCapitalByRosterId -Overrides $overrides -ScoringProfile $scoringProfile -LineupArchitecture $lineupArchitecture -ProjectionWeeks $projectionWeekMaps
      foreach ($playerId in (Convert-ToArray $roster.players | ForEach-Object { Get-TextValue $_ } | Where-Object { $_ })) {
        $player = Get-Player -PlayersById $playersById -PlayerId $playerId
        if ($null -eq $player) { continue }
        $adjustment = Get-ObjectProperty -Object $overrides.playerAdjustments -Name $playerId
        $entry = Get-PlayerValue -Player $player -PlayerId $playerId -Format (Get-TextValue $leagueRecord.format) -Adjustment $adjustment -ScoringProfile $scoringProfile -LineupArchitecture $lineupArchitecture -ProjectionWeeks $projectionWeekMaps -ScoringSettings $liveLeague.scoring_settings
        $entry | Add-Member -NotePropertyName rosterId -NotePropertyValue ([int](Get-NumberValue $roster.roster_id 0)) -Force
        $entry | Add-Member -NotePropertyName manager -NotePropertyValue $teamName -Force
        $allPlayerEntries += $entry
      }
    }
  } catch {
    $rankingFailure = $_.Exception.Message
  }

  if ($rankingFailure) {
    $warnings.Add(("SKIP {0}: {1}" -f $leagueRecordId, $rankingFailure)) | Out-Null
    $generatedLeagues += [pscustomobject]@{
      leagueRecordId = $leagueRecordId
      sleeperLeagueId = $sleeperLeagueId
      name = Get-TextValue $leagueRecord.name
      format = Get-TextValue $leagueRecord.format
      publish = $false
      holdReason = $rankingFailure
      draftStatuses = $draftStatuses
      draftReadiness = $draftReadiness
      rosterSync = $rosterSync
      rosterPositions = @(Convert-ToArray $liveLeague.roster_positions)
      scoringProfile = $scoringProfile
      lineupArchitecture = $lineupArchitecture
      formatProfile = $formatProfile
      positionalRankings = [pscustomobject]@{}
      currentSeasonRankings = @()
      rankings = @()
    }
    continue
  }

  if ((Get-TextValue $leagueRecord.format) -eq "dynasty") {
    foreach ($ranking in $rankings) {
      $ranking | Add-Member -NotePropertyName reasons -NotePropertyValue $ranking.futureReasons -Force
    }
  } else {
    $rankings = Add-RankingReasons -Rankings $rankings -ComponentPropertyName "componentScores"
  }
  $rankings = Convert-ToPublishedTeamScores -Rankings $rankings -Format (Get-TextValue $leagueRecord.format)
  $rank = 1
  $rankings = @($rankings | Sort-Object @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.record.pointsFor }; Descending = $true } | ForEach-Object {
    $_ | Add-Member -NotePropertyName rank -NotePropertyValue $rank -Force
    $rank++
    $_
  })
  $positionalRankings = Get-PositionalRankings -PlayerEntries $allPlayerEntries -TeamRankings $rankings -Architecture $lineupArchitecture
  $currentSeasonRankings = @()
  if ((Get-TextValue $leagueRecord.format) -eq "dynasty") {
    $currentSeasonRankings = Get-CurrentSeasonRankings -Rankings $rankings
  }
  foreach ($ranking in $rankings) {
    $ranking.PSObject.Properties.Remove("currentSeasonScore")
    $ranking.PSObject.Properties.Remove("componentScores")
    $ranking.PSObject.Properties.Remove("currentSeasonComponents")
    $ranking.PSObject.Properties.Remove("futureReasons")
    $ranking.PSObject.Properties.Remove("currentSeasonReasons")
  }

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
    currentSeasonRankings = $currentSeasonRankings
    rankings = $rankings
  }
}

$output = [pscustomobject]@{
  generatedAt = (Get-Date).ToString("o")
  modelVersion = "2.0-scoring-derived"
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
  source = "Sleeper weekly stat projections, live league scoring settings, roster, user, draft, draft-pick, and player metadata endpoints plus data/power-ranking-overrides.json."
  methodology = [pscustomobject]@{
    summary = "Current-season player values are calculated by applying every matching live Sleeper scoring coefficient to Sleeper's Week 1-17 stat projections. Team scores remain comparative roster-strength grades, not predicted records."
    components = @(
      "Scoring-derived projections: projected player stats multiplied by the matching live Sleeper scoring settings.",
      "League settings: exact starter requirements and positional eligibility from Sleeper.",
      "Roster quality: optimized lineup strength, best-ball ceiling, locked depth, and quarterback stability.",
      "Dynasty outlook: age curve and future draft capital.",
      "Availability: current injury and player-status information.",
      "Position boards: each owner's strength at QB, RB, WR, and TE.",
      "Unsupported projected stat categories: explicitly treated as zero and reported in each league's projection model metadata.",
      "Score meaning: relative roster grade derived from custom-scoring projections, not a predicted record."
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
