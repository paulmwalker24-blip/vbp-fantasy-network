param(
  [string]$JsonPath = "data/leagues.json",
  [string]$BracketGroupPath = "data/bracket-groups.json",
  [string]$DynastyBracketGroupPath = "data/dynasty-bracket-groups.json",
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "league-directory-status",
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

function Get-PropertySum {
  param([object[]]$Rows, [string]$PropertyName)
  if (-not $Rows -or $Rows.Count -eq 0) { return 0 }
  $sum = ($Rows | Measure-Object -Property $PropertyName -Sum).Sum
  if ($null -eq $sum) { return 0 }
  return [int]$sum
}

function Format-MoneyValue {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return "Not listed" }
  $text = ([string]$Value).Trim()
  if ($text.StartsWith('$')) { return $text }
  $number = 0
  if ([double]::TryParse(($text -replace ',', ''), [ref]$number)) { return ('$' + ('{0:N0}' -f $number)) }
  return $text
}

function Get-SleeperAssignedSnapshot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LeagueId,
    [switch]$UseUsers
  )

  $league = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}" -f $LeagueId)
  $teams = To-Number $league.total_rosters

  if ($UseUsers) {
    $users = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/users" -f $LeagueId)
    $assigned = Normalize-FilledCount -Teams $teams -Filled @($users).Count
    return [pscustomobject]@{
      teams = $teams
      assigned = $assigned
      openSpots = [math]::Max($teams - $assigned, 0)
      status = ([string]$league.status).Trim().ToLowerInvariant()
    }
  }

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
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
      New-Item -ItemType Directory -Path $directory | Out-Null
    }
  }
  $entry = [pscustomobject]@{ messageId = $MessageId; updatedAt = (Get-Date).ToString("s") }
  if ($state.PSObject.Properties[$Key]) { $state.$Key = $entry } else { $state | Add-Member -NotePropertyName $Key -NotePropertyValue $entry }
  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path
}

function New-SummaryRow {
  param(
    [string]$Label,
    [string]$Channel,
    [object[]]$Rows,
    [string]$Url,
    [string]$Note = ""
  )

  $rowsArray = @($Rows)
  $teams = Get-PropertySum -Rows $rowsArray -PropertyName "teams"
  $assigned = Get-PropertySum -Rows $rowsArray -PropertyName "assigned"
  $open = Get-PropertySum -Rows $rowsArray -PropertyName "openSpots"
  $openLeagues = @($rowsArray | Where-Object { -not $_.isFull }).Count
  $fullLeagues = @($rowsArray | Where-Object { $_.isFull }).Count

  [pscustomobject]@{
    label = $Label
    channel = $Channel
    teams = $teams
    assigned = $assigned
    openSpots = $open
    openLeagues = $openLeagues
    fullLeagues = $fullLeagues
    url = $Url
    note = $Note
  }
}

function Format-OpenChannelLine {
  param([object]$Row)

  $note = if ($Row.note) { " - $($Row.note)" } else { "" }
  return ("- **{0}**: {1} open spots ({2}/{3} assigned) - {4}{5}" -f $Row.channel, $Row.openSpots, $Row.assigned, $Row.teams, $Row.label, $note)
}

function Format-FullChannelLine {
  param([object]$Row)

  if ($Row.fullLeagues -gt 0) {
    return ("- **{0}**: {1} full/established - {2}" -f $Row.channel, $Row.fullLeagues, $Row.label)
  }

  if ($Row.teams -gt 0) {
    return ("- **{0}**: no current openings - {1}" -f $Row.channel, $Row.label)
  }

  $note = if ($Row.note) { $Row.note } else { "info board" }
  return ("- **{0}**: {1} - {2}" -f $Row.channel, $note, $Row.label)
}

if (-not (Test-Path -LiteralPath $JsonPath)) { throw "Could not find league data file at '$JsonPath'." }

$leaguePayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $JsonPath).Path -Raw | ConvertFrom-Json
$leagueRows = foreach ($league in $leaguePayload.leagues) {
  $sleeperLeagueId = ([string]$league.sleeperLeagueId).Trim()
  $format = ([string]$league.format).Trim().ToLowerInvariant()
  $teams = To-Number $league.teams
  $assigned = Normalize-FilledCount -Teams $teams -Filled (To-Number $league.filled)
  $sleeperStatus = ""

  if (-not [string]::IsNullOrWhiteSpace($sleeperLeagueId)) {
    $snapshot = Get-SleeperAssignedSnapshot -LeagueId $sleeperLeagueId -UseUsers:($format -eq "pickem")
    $teams = $snapshot.teams
    $assigned = $snapshot.assigned
    $sleeperStatus = $snapshot.status
  }

  [pscustomobject]@{
    id = [string]$league.id
    name = [string]$league.name
    format = $format
    status = ([string]$league.status).Trim().ToLowerInvariant()
    sleeperStatus = $sleeperStatus
    teams = $teams
    assigned = $assigned
    openSpots = [math]::Max($teams - $assigned, 0)
    isFull = ($teams -gt 0 -and ($assigned -ge $teams -or ([string]$league.status).Trim().ToLowerInvariant() -eq "full"))
    buyIn = Format-MoneyValue $league.buyIn
    inviteLink = ([string]$league.inviteLink).Trim()
  }
}

$redraftRows = @($leagueRows | Where-Object { $_.format -eq "redraft" })
$redraftBracketRows = @($leagueRows | Where-Object { $_.format -eq "bracket" })
$dynastyRows = @($leagueRows | Where-Object { $_.format -eq "dynasty" })
$dynastyBracketRows = @($leagueRows | Where-Object { $_.format -eq "dynastybracket" })
$bbuRows = @($leagueRows | Where-Object { $_.format -eq "bestball" })
$bbgRows = @($leagueRows | Where-Object { $_.format -eq "gauntlet" })
$keeperRows = @($leagueRows | Where-Object { $_.format -eq "keeper" })
$pickemRows = @($leagueRows | Where-Object { $_.format -eq "pickem" })
$choppedRows = @($leagueRows | Where-Object { $_.format -eq "chopped" })
$comanagerRows = @($leagueRows | Where-Object { $_.format -eq "comanager" })
$redraft32Rows = @($leagueRows | Where-Object { $_.format -eq "redraft32" })

$summaryRows = @(
  New-SummaryRow -Label "Redraft" -Channel "<#1515842197063340126>" -Rows $redraftRows -Url "$($AssetBaseUrl.TrimEnd('/'))/#leagues" -Note "standard seasonal only"
  New-SummaryRow -Label "Redraft Bracket" -Channel "<#1515830642422710303>" -Rows $redraftBracketRows -Url "$($AssetBaseUrl.TrimEnd('/'))/bracket-center.html"
  New-SummaryRow -Label "Dynasty" -Channel "<#1515842872526503988>" -Rows $dynastyRows -Url "$($AssetBaseUrl.TrimEnd('/'))/dynasty-constitution.html"
  New-SummaryRow -Label "Dynasty Bracket" -Channel "<#1515842272669995141>" -Rows $dynastyBracketRows -Url "$($AssetBaseUrl.TrimEnd('/'))/bracket-center.html#dynasty"
  New-SummaryRow -Label "Best Ball Union" -Channel "<#1515842331956351097>" -Rows $bbuRows -Url "$($AssetBaseUrl.TrimEnd('/'))/bestball-center.html"
  New-SummaryRow -Label "Best Ball Gauntlet" -Channel "<#1515843013040017629>" -Rows $bbgRows -Url "$($AssetBaseUrl.TrimEnd('/'))/bestball-gauntlet-constitution.html"
  New-SummaryRow -Label "Keeper" -Channel "<#1515842591177048184>" -Rows $keeperRows -Url "$($AssetBaseUrl.TrimEnd('/'))/keeper-constitution.html"
  New-SummaryRow -Label "Pick'em" -Channel "<#1515842672873574500>" -Rows $pickemRows -Url "$($AssetBaseUrl.TrimEnd('/'))/pickem-constitution.html" -Note "uses Sleeper users"
  New-SummaryRow -Label "Chopped" -Channel "<#1515842718591352852>" -Rows $choppedRows -Url "$($AssetBaseUrl.TrimEnd('/'))/chopped-constitution.html"
  New-SummaryRow -Label "Co-Manager Redraft" -Channel "<#1515843047823245383>" -Rows $comanagerRows -Url "$($AssetBaseUrl.TrimEnd('/'))/co-manager-constitution.html"
  New-SummaryRow -Label "32-Team Redraft" -Channel "<#1515843235308900433>" -Rows $redraft32Rows -Url "$($AssetBaseUrl.TrimEnd('/'))/32-team-redraft-constitution.html"
  New-SummaryRow -Label "Sacrifice Redraft" -Channel "<#1515842792255914068>" -Rows @() -Url "$($AssetBaseUrl.TrimEnd('/'))/sacrifice-redraft-constitution.html" -Note "rules/info board"
)

$networkRows = @($leagueRows)
$totalTeams = Get-PropertySum -Rows $networkRows -PropertyName "teams"
$totalAssigned = Get-PropertySum -Rows $networkRows -PropertyName "assigned"
$totalOpen = Get-PropertySum -Rows $networkRows -PropertyName "openSpots"
$fullCount = @($networkRows | Where-Object { $_.isFull }).Count
$openLeagueCount = @($networkRows | Where-Object { -not $_.isFull }).Count
$timestamp = (Get-Date).ToUniversalTime().ToString("o")
$siteUrl = $AssetBaseUrl.TrimEnd('/')

$overviewDescription = @(
  "**Start Here**",
  "Pick the league type below, then use that channel's live status post for details.",
  "Full leagues are still shown as proof that the network is active.",
  "",
  "**Snapshot**",
  "$($networkRows.Count) tracked league records",
  "$fullCount full/established",
  "$openLeagueCount with openings",
  "$totalOpen total open spots, including Pick'em capacity",
  "",
  "**Website:** $siteUrl/"
) -join "`n"

$openChannelRows = @($summaryRows | Where-Object { $_.openLeagues -gt 0 -and $_.openSpots -gt 0 })
$closedChannelRows = @($summaryRows | Where-Object { -not ($_.openLeagues -gt 0 -and $_.openSpots -gt 0) })
$openChannelLines = @($openChannelRows | ForEach-Object { Format-OpenChannelLine $_ })
$closedChannelLines = @($closedChannelRows | ForEach-Object { Format-FullChannelLine $_ })
$openingsDescription = if ($openChannelLines.Count -gt 0) {
  $openChannelLines -join "`n"
} else {
  "No tracked league-type channels have openings right now."
}
$closedDescription = if ($closedChannelLines.Count -gt 0) {
  $closedChannelLines -join "`n"
} else {
  "No full or info-only boards yet."
}

$overviewEmbed = @{
  title = "VBP League Directory"
  url = "$siteUrl/"
  description = $overviewDescription
  color = 0x5865F2
  thumbnail = @{ url = "$siteUrl/assets/images/sleeper-thumbnail-general.png" }
  footer = @{ text = "Living league directory" }
  timestamp = $timestamp
}

$openingsEmbed = @{
  title = "Open Now"
  description = $openingsDescription
  color = 0x27AE60
  footer = @{ text = "For full details, use the matching league-type channel." }
  timestamp = $timestamp
}

$closedEmbed = @{
  title = "Full / Info Boards"
  description = $closedDescription
  color = 0x2F80ED
  footer = @{ text = "These channels are still useful for rules, proof of activity, and future openings." }
  timestamp = $timestamp
}

$payloadObject = @{ content = ""; embeds = @($overviewEmbed, $openingsEmbed, $closedEmbed) }
$payload = $payloadObject | ConvertTo-Json -Depth 8

$result = [pscustomobject]@{
  totalTeams = $totalTeams
  totalAssigned = $totalAssigned
  totalOpen = $totalOpen
  fullLeagueRecords = $fullCount
  openLeagueRecords = $openLeagueCount
  summaryRows = @($summaryRows)
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
      Write-Warning ("Could not update stored Discord directory message {0}; posting a new directory message instead. {1}" -f $existingMessageId, $_.Exception.Message)
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
  if ($DryRun) { Write-Host "Dry run only. Set DISCORD_WEBHOOK_URL or pass -WebhookUrl to post the league directory into Discord." }
  else { Write-Host ("Discord league directory message {0}: {1}" -f $result.action, $result.messageId) }
}
