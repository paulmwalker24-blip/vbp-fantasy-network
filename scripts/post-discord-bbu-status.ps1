param(
  [string]$JsonPath = "data/leagues.json",
  [string]$PaymentReportPath = "reports/private/bbu-payment-reconciliation/bbu-master-readable.txt",
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "bbu-status",
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

function Get-SleeperSnapshot {
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
    leagueStatus = ([string]$league.status).Trim().ToLowerInvariant()
    draftStatus = if ($latestDraft) { ([string]$latestDraft.status).Trim().ToLowerInvariant() } else { "" }
  }
}

function Get-BbuPaidCounts {
  param([string]$Path)
  $counts = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $counts }
  $text = Get-Content -LiteralPath $Path -Raw
  $matches = [regex]::Matches($text, '(?m)^(BBU\d+)\s+-\s+.+?\r?\nPaid:\s+(\d+)\s+\|\s+Paid candidate:\s+(\d+)')
  foreach ($match in $matches) {
    $counts[$match.Groups[1].Value] = [pscustomobject]@{
      paid = [int]$match.Groups[2].Value
      candidates = [int]$match.Groups[3].Value
    }
  }
  return $counts
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
$leaguePayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $JsonPath).Path -Raw | ConvertFrom-Json
$paidCounts = Get-BbuPaidCounts -Path $PaymentReportPath

$roomRows = foreach ($league in $leaguePayload.leagues) {
  if (([string]$league.format).Trim().ToLowerInvariant() -ne "bestball") { continue }
  $snapshot = Get-SleeperSnapshot -LeagueId ([string]$league.sleeperLeagueId)
  $id = [string]$league.id
  $paidInfo = if ($paidCounts.ContainsKey($id)) { $paidCounts[$id] } else { $null }
  [pscustomobject]@{
    id = $id
    name = [string]$league.name
    buyIn = Format-MoneyValue $league.buyIn
    assigned = $snapshot.assigned
    teams = $snapshot.teams
    openSpots = $snapshot.openSpots
    paid = if ($paidInfo) { $paidInfo.paid } else { $null }
    candidates = if ($paidInfo) { $paidInfo.candidates } else { $null }
    draftStatus = $snapshot.draftStatus
    isFilled = ($snapshot.assigned -ge $snapshot.teams -and $snapshot.teams -gt 0)
    isDrafted = ($snapshot.assigned -ge $snapshot.teams -and $snapshot.draftStatus -eq "complete")
    inviteLink = [string]$league.inviteLink
  }
}

$roomRows = @($roomRows | Sort-Object { To-Number (($_.id -replace '\D', '')) })
$filledCount = @($roomRows | Where-Object { $_.isFilled }).Count
$draftedFilledCount = @($roomRows | Where-Object { $_.isDrafted }).Count
$highScorePot = $draftedFilledCount * 25
$totalTeams = [int](@($roomRows | Measure-Object -Property teams -Sum).Sum)
$totalAssigned = [int](@($roomRows | Measure-Object -Property assigned -Sum).Sum)
$totalOpen = [int](@($roomRows | Measure-Object -Property openSpots -Sum).Sum)
$updatedAt = Get-Date
$timestamp = $updatedAt.ToUniversalTime().ToString("o")

$overviewDescription = @(
  "**Current Snapshot**",
  "$filledCount/$($roomRows.Count) rooms filled",
  "$draftedFilledCount filled rooms drafted",
  "$totalAssigned/$totalTeams assigned across all BBU rooms | $totalOpen open",
  "",
  "**Overall High-Score Pot**",
  "$draftedFilledCount drafted full rooms x `$25 = `$$highScorePot",
  "",
  "**How It Works**",
  "Each 10-team room is a `$10 fast best ball league.",
  "Each full drafted room contributes `$75 to its league winner and `$25 to the Union-wide highest total season score."
) -join "`n"

$overviewEmbed = @{
  title = "VBP Best Ball Union Status"
  url = "https://vbp-fantasy-network.vercel.app/bestball-center.html"
  description = $overviewDescription
  color = 0x2F80ED
  thumbnail = @{ url = ("{0}/assets/images/constitution-bestball-union.png" -f $AssetBaseUrl.TrimEnd('/')) }
  footer = @{ text = "Living Best Ball Union board" }
  timestamp = $timestamp
}

$filledRoomLines = @($roomRows | Where-Object { $_.isFilled } | ForEach-Object {
  $draftLabel = if ($_.isDrafted) { "drafted" } else { "filled, not drafted" }
  "- $($_.id): $($_.assigned)/$($_.teams), $draftLabel"
})

$filledSummaryEmbed = @{
  title = "Filled Room Summary"
  url = "https://vbp-fantasy-network.vercel.app/bestball-center.html"
  description = if ($filledRoomLines.Count -gt 0) { ($filledRoomLines -join "`n") } else { "No filled Best Ball Union rooms yet." }
  color = 0x27AE60
  thumbnail = @{ url = ("{0}/assets/images/constitution-bestball-union.png" -f $AssetBaseUrl.TrimEnd('/')) }
  footer = @{ text = "Filled rooms drive the Union high-score pot once drafted." }
  timestamp = $timestamp
}

$activeRoomEmbeds = foreach ($row in @($roomRows | Where-Object { -not $_.isDrafted })) {
  $paidText = if ($null -ne $row.paid) {
    if ($row.candidates -gt 0) { "$($row.paid)/$($row.teams) confirmed (+$($row.candidates) candidate)" } else { "$($row.paid)/$($row.teams)" }
  } else { "Not supplied" }
  $draftText = if ($row.draftStatus) { $row.draftStatus -replace '_', ' ' } else { "not created" }
  $description = @(
    "**Assigned teams:** $($row.assigned)/$($row.teams)",
    "**Paid teams:** $paidText",
    "**Open spots:** $($row.openSpots)",
    "**Draft status:** $draftText",
    "**Buy-in:** $($row.buyIn)",
    "**Join:** $($row.inviteLink)"
  ) -join "`n"
  @{
    title = $row.name
    url = $row.inviteLink
    description = $description
    color = if ($row.isDrafted) { 0x27AE60 } elseif ($row.isFilled) { 0xF1C40F } else { 0x2F80ED }
    thumbnail = @{ url = ("{0}/assets/images/constitution-bestball-union.png" -f $AssetBaseUrl.TrimEnd('/')) }
    footer = @{ text = ("{0} | Best Ball Union" -f $row.id) }
    timestamp = $timestamp
  }
}

$payloadObject = @{ content = ""; embeds = @($overviewEmbed, $filledSummaryEmbed) + @($activeRoomEmbeds | Select-Object -First 8) }
$payload = $payloadObject | ConvertTo-Json -Depth 8
$result = [pscustomobject]@{
  filledRooms = $filledCount
  draftedFilledRooms = $draftedFilledCount
  highScorePot = $highScorePot
  rooms = @($roomRows)
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
      Write-Warning ("Could not update stored Discord message {0}; posting a new BBU status message instead. {1}" -f $existingMessageId, $_.Exception.Message)
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
