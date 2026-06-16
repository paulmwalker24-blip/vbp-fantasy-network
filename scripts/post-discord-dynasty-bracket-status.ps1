param(
  [string]$JsonPath = "data/leagues.json",
  [string]$GroupPath = "data/dynasty-bracket-groups.json",
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "dynasty-bracket-status",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_URL,
  [switch]$DryRun,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function To-Number {
  param([AllowNull()][object]$Value)
  $cleaned = [string]$Value
  $cleaned = $cleaned -replace '[$,%\s]', ''
  $cleaned = $cleaned -replace ',', ''
  $parsed = 0
  if ([double]::TryParse($cleaned, [ref]$parsed)) { return [int][math]::Floor($parsed) }
  return 0
}

function Format-MoneyValue {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return "" }
  $text = ([string]$Value).Trim()
  if ($text.StartsWith('$')) { return $text }
  $number = 0
  if ([double]::TryParse(($text -replace ',', ''), [ref]$number)) { return ('$' + ('{0:N0}' -f $number)) }
  return $text
}

function Normalize-FilledCount {
  param([int]$Teams, [int]$Filled)
  return [math]::Min([math]::Max($Filled, 0), [math]::Max($Teams, 0))
}

function Get-ObjectPropertyValue {
  param([AllowNull()][object]$InputObject, [string]$Name)
  if ($null -eq $InputObject) { return $null }
  $property = $InputObject.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}

function Get-SleeperAssignedSnapshot {
  param([Parameter(Mandatory = $true)][string]$LeagueId)
  $league = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}" -f $LeagueId)
  $teams = To-Number $league.total_rosters
  $rosters = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/rosters" -f $LeagueId)
  $drafts = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/drafts" -f $LeagueId)
  $rosterAssignedCount = @($rosters | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.owner_id) }).Count
  $latestDraft = @($drafts | Sort-Object { [double]$_.created } -Descending | Select-Object -First 1)
  $latestDraftOrder = Get-ObjectPropertyValue -InputObject $latestDraft -Name "draft_order"
  $draftAssignedCount = if ($latestDraftOrder) {
    @($latestDraftOrder.PSObject.Properties | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Name) }).Count
  } else { 0 }
  $assigned = Normalize-FilledCount -Teams $teams -Filled ([math]::Max($rosterAssignedCount, $draftAssignedCount))
  [pscustomobject]@{
    teams = $teams
    assigned = $assigned
    openSpots = [math]::Max($teams - $assigned, 0)
    status = ([string]$league.status).Trim().ToLowerInvariant()
  }
}

function Get-DivisionImageUrl {
  param([string]$DivisionName, [string]$BaseUrl)
  $fileName = switch ($DivisionName.Trim().ToLowerInvariant()) {
    "empire" { "dynasty-bracket-empire.png" }
    "forge" { "dynasty-bracket-forge.png" }
    "foundry" { "dynasty-bracket-foundry.png" }
    "legacy" { "dynasty-bracket-legacy.png" }
    default { "" }
  }
  if (-not $fileName) { return "" }
  return ("{0}/assets/images/{1}" -f $BaseUrl.TrimEnd('/'), $fileName)
}

function Get-DivisionEmbedColor {
  param([string]$DivisionName)
  switch ($DivisionName.Trim().ToLowerInvariant()) {
    "empire" { return 0x8E44AD }
    "forge" { return 0xD35400 }
    "foundry" { return 0x7F8C8D }
    "legacy" { return 0x27AE60 }
    default { return 0x5865F2 }
  }
}

function Get-DiscordMessageState {
  param([string]$Path, [string]$Key)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  return Get-ObjectPropertyValue -InputObject $state -Name $Key
}

function Save-DiscordMessageState {
  param([string]$Path, [string]$Key, [string]$MessageId)
  $state = [pscustomobject]@{}
  if (Test-Path -LiteralPath $Path) {
    $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } else {
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
  }
  $entry = [pscustomobject]@{ messageId = $MessageId; updatedAt = (Get-Date).ToString("s") }
  if ($state.PSObject.Properties[$Key]) { $state.$Key = $entry } else { $state | Add-Member -NotePropertyName $Key -NotePropertyValue $entry }
  $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path
}

if (-not (Test-Path -LiteralPath $JsonPath)) { throw "Could not find league data file at '$JsonPath'." }
if (-not (Test-Path -LiteralPath $GroupPath)) { throw "Could not find dynasty bracket group file at '$GroupPath'." }

$leaguePayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $JsonPath).Path -Raw | ConvertFrom-Json
$groupPayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $GroupPath).Path -Raw | ConvertFrom-Json
$group = $groupPayload.groups | Select-Object -First 1
$divisionConfigs = @($group.sampleDivisions)

$divisionRows = foreach ($division in $divisionConfigs) {
  $leagueRecordId = [string]$division.leagueRecordId
  $league = $leaguePayload.leagues | Where-Object { [string]$_.id -eq $leagueRecordId } | Select-Object -First 1
  if (-not $league) { continue }
  $snapshot = Get-SleeperAssignedSnapshot -LeagueId ([string]$league.sleeperLeagueId)
  [pscustomobject]@{
    id = [string]$league.id
    name = [string]$league.name
    draftStyle = if ([string]$division.division) { [string]$division.division } else { [string]$league.draftStyle }
    buyIn = Format-MoneyValue $league.buyIn
    assigned = $snapshot.assigned
    teams = $snapshot.teams
    openSpots = $snapshot.openSpots
    inviteLink = [string]$league.inviteLink
    imageUrl = Get-DivisionImageUrl -DivisionName ([string]$league.name) -BaseUrl $AssetBaseUrl
  }
}

$divisionRows = @($divisionRows | Sort-Object name)
$totalTeams = [int](@($divisionRows | Measure-Object -Property teams -Sum).Sum)
$totalAssigned = [int](@($divisionRows | Measure-Object -Property assigned -Sum).Sum)
$totalOpen = [int](@($divisionRows | Measure-Object -Property openSpots -Sum).Sum)
$buyIn = @($divisionRows | Select-Object -First 1).buyIn
$updatedAt = Get-Date
$timestamp = $updatedAt.ToUniversalTime().ToString("o")

$overviewDescription = @(
  "**Current Snapshot**",
  "$buyIn buy-in | 4 divisions | $totalTeams total teams",
  "$totalAssigned/$totalTeams assigned | $totalOpen open",
  "",
  "**How It Works**",
  "Four 12-team dynasty divisions feed one combined 16-team playoff bracket.",
  "Division winners receive top-four seeding consideration, and playoff teams compete across divisions in Weeks 14-17.",
  "",
  "**Payouts**",
  "`$2,400 prize pool | Champion `$1,380 | Runner-up `$300",
  "Semifinal losers `$100 each | Quarterfinal losers `$55 each | Division winners `$75 each"
) -join "`n"

$overviewEmbed = @{
  title = "VBP Dynasty Bracket Status"
  url = "https://vbp-fantasy-network.vercel.app/bracket-center.html#dynasty"
  description = $overviewDescription
  color = 0x8E44AD
  footer = @{ text = "Living dynasty bracket openings board" }
  timestamp = $timestamp
}

$divisionEmbeds = foreach ($row in $divisionRows) {
  $description = @(
    "**Assigned teams:** $($row.assigned)/$($row.teams)",
    "**Open spots:** $($row.openSpots)",
    "**Buy-in:** $($row.buyIn)",
    "**Join:** $($row.inviteLink)",
    "**Rules:** https://vbp-fantasy-network.vercel.app/dynasty-bracket-constitution.html"
  ) -join "`n"
  $embed = @{
    title = ("{0} - {1} Draft" -f $row.name, $row.draftStyle)
    url = $row.inviteLink
    description = $description
    color = Get-DivisionEmbedColor -DivisionName $row.name
    footer = @{ text = ("{0} | Dynasty Bracket" -f $row.id) }
    timestamp = $timestamp
  }
  if ($row.imageUrl) { $embed.thumbnail = @{ url = $row.imageUrl } }
  $embed
}

$payloadObject = @{ content = ""; embeds = @($overviewEmbed) + @($divisionEmbeds) }
$payload = $payloadObject | ConvertTo-Json -Depth 8
$result = [pscustomobject]@{
  totalTeams = $totalTeams
  totalAssigned = $totalAssigned
  totalOpen = $totalOpen
  divisions = @($divisionRows)
  dryRun = [bool]$DryRun
  statePath = $StatePath
  stateKey = $StateKey
  messageId = $null
  action = if ($DryRun) { "dry-run" } else { "pending" }
}

if (-not $DryRun) {
  if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { throw "Set DISCORD_WEBHOOK_URL or pass -WebhookUrl before posting to Discord." }
  $existingState = Get-DiscordMessageState -Path $StatePath -Key $StateKey
  $existingMessageId = if ($existingState) { [string]$existingState.messageId } else { "" }
  if (-not [string]::IsNullOrWhiteSpace($existingMessageId)) {
    try {
      Invoke-RestMethod -Uri ("{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $existingMessageId) -Method Patch -ContentType "application/json" -Body $payload | Out-Null
      $result.messageId = $existingMessageId
      $result.action = "updated"
    } catch {
      Write-Warning ("Could not update stored Discord message {0}; posting a new dynasty bracket status message instead. {1}" -f $existingMessageId, $_.Exception.Message)
    }
  }
  if ([string]::IsNullOrWhiteSpace([string]$result.messageId)) {
    $postResponse = Invoke-RestMethod -Uri ("{0}?wait=true" -f $WebhookUrl) -Method Post -ContentType "application/json" -Body $payload
    $newMessageId = [string]$postResponse.id
    if ([string]::IsNullOrWhiteSpace($newMessageId)) { throw "Discord did not return a message ID. Cannot save update state." }
    Save-DiscordMessageState -Path $StatePath -Key $StateKey -MessageId $newMessageId
    $result.messageId = $newMessageId
    $result.action = "created"
  } else {
    Save-DiscordMessageState -Path $StatePath -Key $StateKey -MessageId ([string]$result.messageId)
  }
}

if ($PassThru) {
  $result
} else {
  if ($DryRun) { Write-Host "Dry run only. Set DISCORD_WEBHOOK_URL or pass -WebhookUrl to post this into Discord." }
  else { Write-Host ("Discord message {0}: {1}" -f $result.action, $result.messageId) }
}
