param(
  [string]$JsonPath = "data/leagues.json",
  [string]$GroupPath = "data/bracket-groups.json",
  [string]$PaymentReportPath = "reports/private/redraft-bracket-payment-reconciliation/redraft-bracket-master-readable.txt",
  [string]$GroupId = "BRACKET-2026-1",
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "redraft-bracket-status",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_URL,
  [switch]$DryRun,
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

function Format-MoneyValue {
  param(
    [AllowNull()]
    [object]$Value
  )

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return ""
  }

  $text = ([string]$Value).Trim()
  if ($text.StartsWith('$')) {
    return $text
  }

  $number = 0
  if ([double]::TryParse(($text -replace ',', ''), [ref]$number)) {
    return ('$' + ('{0:N0}' -f $number))
  }

  return $text
}

function Convert-ToCurrencyNumber {
  param(
    [AllowNull()]
    [object]$Value
  )

  $cleaned = [string]$Value
  $cleaned = $cleaned -replace '[$,\s]', ''

  $parsed = 0
  if ([double]::TryParse($cleaned, [ref]$parsed)) {
    return [decimal]$parsed
  }

  return [decimal]0
}

function Format-DollarAmount {
  param(
    [decimal]$Value
  )

  return ('$' + ('{0:N0}' -f $Value))
}

function Normalize-FilledCount {
  param(
    [int]$Teams,
    [int]$Filled
  )

  return [math]::Min([math]::Max($Filled, 0), [math]::Max($Teams, 0))
}

function Get-ObjectPropertyValue {
  param(
    [AllowNull()]
    [object]$InputObject,
    [string]$Name
  )

  if ($null -eq $InputObject) {
    return $null
  }

  $property = $InputObject.PSObject.Properties[$Name]
  if ($property) {
    return $property.Value
  }

  return $null
}

function Get-SleeperAssignedSnapshot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LeagueId
  )

  $league = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}" -f $LeagueId)
  $teams = To-Number $league.total_rosters
  $rosters = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/rosters" -f $LeagueId)
  $drafts = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/drafts" -f $LeagueId)
  $rosterAssignedCount = @($rosters | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.owner_id) }).Count
  $latestDraft = @($drafts | Sort-Object { [double]$_.created } -Descending | Select-Object -First 1)
  $latestDraftOrder = Get-ObjectPropertyValue -InputObject $latestDraft -Name "draft_order"
  $draftAssignedCount = if ($latestDraftOrder) {
    @($latestDraftOrder.PSObject.Properties | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Name) }).Count
  } else {
    0
  }
  $assigned = Normalize-FilledCount -Teams $teams -Filled ([math]::Max($rosterAssignedCount, $draftAssignedCount))

  [pscustomobject]@{
    teams = $teams
    assigned = $assigned
    openSpots = [math]::Max($teams - $assigned, 0)
    status = ([string]$league.status).Trim().ToLowerInvariant()
  }
}

function Get-PaidCountsByLeagueId {
  param(
    [string]$Path
  )

  $counts = @{}
  if (-not (Test-Path -LiteralPath $Path)) {
    return $counts
  }

  $text = Get-Content -LiteralPath $Path -Raw
  $matches = [regex]::Matches($text, '(?m)^(RDB\d+)\s+-\s+.+?\r?\nAssigned paid:\s+(\d+)')
  foreach ($match in $matches) {
    $counts[$match.Groups[1].Value] = [int]$match.Groups[2].Value
  }

  return $counts
}

function Get-DivisionImageUrl {
  param(
    [string]$DivisionName,
    [string]$BaseUrl
  )

  if ([string]::IsNullOrWhiteSpace($DivisionName) -or [string]::IsNullOrWhiteSpace($BaseUrl)) {
    return ""
  }

  $slug = $DivisionName.Trim().ToLowerInvariant()
  $fileName = switch ($slug) {
    "apex" { "redraft-bracket-apex.png" }
    "dominion" { "redraft-bracket-dominion.png" }
    "iron" { "redraft-bracket-iron.png" }
    "titan" { "redraft-bracket-titan.png" }
    "vanguard" { "redraft-bracket-vanguard.png" }
    default { "" }
  }

  if (-not $fileName) {
    return ""
  }

  return ("{0}/assets/images/{1}" -f $BaseUrl.TrimEnd('/'), $fileName)
}

function Get-DivisionEmbedColor {
  param(
    [string]$DivisionName
  )

  switch ($DivisionName.Trim().ToLowerInvariant()) {
    "apex" { return 0x2F80ED }
    "dominion" { return 0x8E44AD }
    "iron" { return 0xA3A3A3 }
    "titan" { return 0xD35400 }
    "vanguard" { return 0x27AE60 }
    default { return 0x5865F2 }
  }
}

function Get-DiscordMessageState {
  param(
    [string]$Path,
    [string]$Key
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  return Get-ObjectPropertyValue -InputObject $state -Name $Key
}

function Save-DiscordMessageState {
  param(
    [string]$Path,
    [string]$Key,
    [string]$MessageId,
    [string]$GroupId
  )

  $state = [pscustomobject]@{}
  if (Test-Path -LiteralPath $Path) {
    $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } else {
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
      New-Item -ItemType Directory -Path $directory | Out-Null
    }
  }

  $entry = [pscustomobject]@{
    messageId = $MessageId
    groupId = $GroupId
    updatedAt = (Get-Date).ToString("s")
  }

  if ($state.PSObject.Properties[$Key]) {
    $state.$Key = $entry
  } else {
    $state | Add-Member -NotePropertyName $Key -NotePropertyValue $entry
  }

  $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find league data file at '$JsonPath'."
}

if (-not (Test-Path -LiteralPath $GroupPath)) {
  throw "Could not find bracket group file at '$GroupPath'."
}

$leaguePayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $JsonPath).Path -Raw | ConvertFrom-Json
$groupPayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $GroupPath).Path -Raw | ConvertFrom-Json
$group = $groupPayload.groups | Where-Object { [string]$_.groupId -eq $GroupId } | Select-Object -First 1

if (-not $group) {
  throw "Could not find bracket group '$GroupId'."
}

$paidCounts = Get-PaidCountsByLeagueId -Path $PaymentReportPath
$leagueRecords = foreach ($recordId in @($group.leagueRecordIds)) {
  $leaguePayload.leagues | Where-Object { [string]$_.id -eq [string]$recordId } | Select-Object -First 1
}

$divisionRows = foreach ($league in $leagueRecords) {
  if (-not $league) {
    continue
  }

  $snapshot = Get-SleeperAssignedSnapshot -LeagueId ([string]$league.sleeperLeagueId)
  $leagueId = [string]$league.id
  $paid = if ($paidCounts.ContainsKey($leagueId)) { [int]$paidCounts[$leagueId] } else { $null }

  [pscustomobject]@{
    id = $leagueId
    name = [string]$league.name
    draftStyle = if ([string]$league.division) { [string]$league.division } else { [string]$league.draftStyle }
    buyIn = Format-MoneyValue $league.buyIn
    assigned = $snapshot.assigned
    teams = $snapshot.teams
    openSpots = $snapshot.openSpots
    paid = $paid
    inviteLink = [string]$league.inviteLink
    imageUrl = Get-DivisionImageUrl -DivisionName ([string]$league.name) -BaseUrl $AssetBaseUrl
  }
}

$divisionRows = @($divisionRows | Sort-Object name)
$totalTeams = [int](@($divisionRows | Measure-Object -Property teams -Sum).Sum)
$totalAssigned = [int](@($divisionRows | Measure-Object -Property assigned -Sum).Sum)
$totalOpen = [int](@($divisionRows | Measure-Object -Property openSpots -Sum).Sum)
$paidRows = @($divisionRows | Where-Object { $null -ne $_.paid })
$totalPaid = if ($paidRows.Count -gt 0) { [int](@($paidRows | Measure-Object -Property paid -Sum).Sum) } else { $null }
$buyIn = @($divisionRows | Select-Object -First 1).buyIn
$buyInAmount = Convert-ToCurrencyNumber $buyIn
$divisionWinnerBonus = $buyInAmount * 2
$runnerUpPayout = $buyInAmount * 10
$semifinalistPayout = $buyInAmount * 4
$quarterfinalistPayout = $buyInAmount + 5
$divisionWinnerCount = 5
$semifinalistCount = 2
$quarterfinalistCount = 4
$fullPrizePool = $buyInAmount * $totalTeams
$championPayout = $fullPrizePool -
  ($divisionWinnerBonus * $divisionWinnerCount) -
  $runnerUpPayout -
  ($semifinalistPayout * $semifinalistCount) -
  ($quarterfinalistPayout * $quarterfinalistCount)

$updatedAt = Get-Date
$timestamp = $updatedAt.ToUniversalTime().ToString("o")
$message = ""
if ($message.Length -gt 1900) {
  throw "Discord message is $($message.Length) characters; shorten it before posting."
}

$overviewPaidText = if ($null -ne $totalPaid) {
  "$totalPaid/$totalTeams assigned teams paid in the latest bracket payment report."
} else {
  "Paid count not supplied."
}

$overviewDescription = @(
  "**Current Snapshot**",
  "$buyIn buy-in | 5 divisions | $totalTeams total teams",
  "$totalAssigned/$totalTeams assigned | $totalOpen open",
  $overviewPaidText,
  "",
  "**How It Works**",
  "Five separate 12-team Sleeper divisions play Weeks 1-12 with Progressive PPR scoring.",
  "Weeks 13-17 become one combined 32-team playoff: 5 division winners, the next 25 by record/points, plus 2 highest-scoring non-qualifiers in a Week 13 play-in.",
  "",
  "**Payout Math**",
  ("{0} prize pool" -f (Format-DollarAmount $fullPrizePool)),
  ("Champion {0} | Runner-up {1}" -f (Format-DollarAmount $championPayout), (Format-DollarAmount $runnerUpPayout)),
  ("Semifinal losers {0} each | Quarterfinal losers {1} each" -f (Format-DollarAmount $semifinalistPayout), (Format-DollarAmount $quarterfinalistPayout)),
  ("Division winners {0} each" -f (Format-DollarAmount $divisionWinnerBonus))
) -join "`n"

$overviewEmbed = @{
  title = "VBP Redraft Bracket Status"
  url = "https://vbp-fantasy-network.vercel.app/bracket-center.html"
  description = $overviewDescription
  color = 0xC0392B
  footer = @{
    text = "Division cards are listed below in alphabetical order."
  }
  timestamp = $timestamp
}

$divisionEmbeds = foreach ($row in $divisionRows) {
  $paidText = if ($null -ne $row.paid) { "$($row.paid)/$($row.teams)" } else { "Not supplied" }
  $draftText = if ($row.draftStyle) { "$($row.draftStyle) Draft" } else { "Draft TBD" }
  $description = @(
    "**Assigned teams:** $($row.assigned)/$($row.teams)",
    "**Paid teams:** $paidText",
    "**Open spots:** $($row.openSpots)",
    "**Buy-in:** $($row.buyIn)",
    "**Join:** $($row.inviteLink)"
  ) -join "`n"

  $embed = @{
    title = ("{0} - {1}" -f $row.name, $draftText)
    url = $row.inviteLink
    description = $description
    color = Get-DivisionEmbedColor -DivisionName $row.name
    footer = @{
      text = ("{0} | {1}" -f $row.id, "Redraft Bracket")
    }
    timestamp = $timestamp
  }

  if ($row.imageUrl) {
    $embed.thumbnail = @{
      url = $row.imageUrl
    }
  }

  $embed
}

$payloadObject = @{
  content = $message
  embeds = @($overviewEmbed) + @($divisionEmbeds)
}

$payload = $payloadObject | ConvertTo-Json -Depth 8

$result = [pscustomobject]@{
  groupId = $GroupId
  totalTeams = $totalTeams
  totalAssigned = $totalAssigned
  totalOpen = $totalOpen
  totalPaid = $totalPaid
  divisions = @($divisionRows)
  embeds = @($payloadObject.embeds)
  dryRun = [bool]$DryRun
  statePath = $StatePath
  stateKey = $StateKey
  messageId = $null
  action = if ($DryRun) { "dry-run" } else { "pending" }
  message = $message
}

if (-not $DryRun) {
  if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
    throw "Set DISCORD_WEBHOOK_URL or pass -WebhookUrl before posting to Discord."
  }

  $existingState = Get-DiscordMessageState -Path $StatePath -Key $StateKey
  $existingMessageId = if ($existingState) { [string]$existingState.messageId } else { "" }

  if (-not [string]::IsNullOrWhiteSpace($existingMessageId)) {
    try {
      Invoke-RestMethod -Uri ("{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $existingMessageId) -Method Patch -ContentType "application/json" -Body $payload | Out-Null
      $result.messageId = $existingMessageId
      $result.action = "updated"
    } catch {
      Write-Warning ("Could not update stored Discord message {0}; posting a new status message instead. {1}" -f $existingMessageId, $_.Exception.Message)
    }
  }

  if ([string]::IsNullOrWhiteSpace([string]$result.messageId)) {
    $postResponse = Invoke-RestMethod -Uri ("{0}?wait=true" -f $WebhookUrl) -Method Post -ContentType "application/json" -Body $payload
    $newMessageId = [string]$postResponse.id
    if ([string]::IsNullOrWhiteSpace($newMessageId)) {
      throw "Discord did not return a message ID. Cannot save update state."
    }

    Save-DiscordMessageState -Path $StatePath -Key $StateKey -MessageId $newMessageId -GroupId $GroupId
    $result.messageId = $newMessageId
    $result.action = "created"
  } else {
    Save-DiscordMessageState -Path $StatePath -Key $StateKey -MessageId ([string]$result.messageId) -GroupId $GroupId
  }
}

if ($PassThru) {
  $result
} else {
  Write-Host $message
  Write-Host ""
  if ($DryRun) {
    Write-Host "Dry run only. Set DISCORD_WEBHOOK_URL or pass -WebhookUrl to post this into Discord."
  } else {
    Write-Host ("Discord message {0}: {1}" -f $result.action, $result.messageId)
  }
}
