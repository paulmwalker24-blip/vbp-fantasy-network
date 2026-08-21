param(
  [string]$LeaguesPath = "data/leagues.json",
  [string]$ConfigPath = "data/discord-trade-tracker-config.json",
  [string]$StatePath = "data/discord-trade-tracker-state.json",
  [string]$WebhookConfigPath = "data/private/discord-webhooks.json",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_TRADE_TRACKER,
  [string[]]$LeagueRecordIds,
  [switch]$IncludeHistorical,
  [switch]$DryRun,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PropertyValue {
  param(
    [AllowNull()][object]$InputObject,
    [string]$Name
  )

  if ($null -eq $InputObject) { return $null }
  $property = $InputObject.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}
function Get-StringValue {
  param([AllowNull()][object]$Value)
  return ([string]$Value).Trim()
}

function Get-IntValue {
  param([AllowNull()][object]$Value)
  $parsed = 0
  if ([int]::TryParse((Get-StringValue $Value), [ref]$parsed)) { return $parsed }
  return 0
}

function Convert-ToPlainDiscordText {
  param(
    [AllowNull()][object]$Value,
    [int]$MaximumLength = 80
  )

  $text = Get-StringValue $Value
  $text = [regex]::Replace($text, '[\r\n\t]+', ' ')
  $text = [regex]::Replace($text, '[*_~`>|]', '')
  $text = [regex]::Replace($text, '\s{2,}', ' ').Trim()
  if ($MaximumLength -gt 3 -and $text.Length -gt $MaximumLength) {
    return ($text.Substring(0, $MaximumLength - 3).TrimEnd() + "...")
  }
  return $text
}

function Get-StateRoot {
  param([string]$Path)

  if (Test-Path -LiteralPath $Path) {
    $loaded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -ne $loaded) {
      if (-not $loaded.PSObject.Properties["transactions"]) {
        $loaded | Add-Member -NotePropertyName transactions -NotePropertyValue ([pscustomobject]@{})
      }
      if (-not $loaded.PSObject.Properties["initialized"]) {
        $loaded | Add-Member -NotePropertyName initialized -NotePropertyValue $false
      }
      return $loaded
    }
  }

  return [pscustomobject]@{
    version = 1
    channelId = ""
    webhookId = ""
    initialized = $false
    transactions = [pscustomobject]@{}
    updatedAt = ""
  }
}

function Set-StateProperty {
  param(
    [object]$State,
    [string]$Name,
    [AllowNull()][object]$Value
  )

  if ($State.PSObject.Properties[$Name]) {
    $State.$Name = $Value
  } else {
    $State | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

function Save-StateRoot {
  param(
    [string]$Path,
    [object]$State
  )

  Set-StateProperty -State $State -Name updatedAt -Value ([datetimeoffset]::UtcNow.ToString("o"))
  $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path
}

function Test-StateHasTransaction {
  param(
    [object]$State,
    [string]$TransactionId
  )

  $transactions = Get-PropertyValue $State "transactions"
  return $null -ne $transactions.PSObject.Properties[$TransactionId]
}

function Add-StateTransaction {
  param(
    [object]$State,
    [object]$Trade,
    [string]$MessageId,
    [string]$Disposition
  )

  $entry = [pscustomobject]@{
    leagueRecordId = Get-StringValue $Trade.leagueRecordId
    sleeperLeagueId = Get-StringValue $Trade.sleeperLeagueId
    transactionId = Get-StringValue $Trade.transactionId
    created = [long]$Trade.created
    messageId = $MessageId
    disposition = $Disposition
    recordedAt = [datetimeoffset]::UtcNow.ToString("o")
  }
  $transactions = Get-PropertyValue $State "transactions"
  $transactions | Add-Member -NotePropertyName $Trade.transactionId -NotePropertyValue $entry -Force
}

function Invoke-JsonGet {
  param([string]$Uri)

  foreach ($attempt in 1..4) {
    try {
      $response = Invoke-RestMethod -Uri $Uri -Method Get
      if ($response -is [System.Array]) {
        foreach ($item in $response) { Write-Output $item }
        return
      }
      return $response
    } catch {
      $statusCode = 0
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      }
      if ($attempt -ge 4 -or ($statusCode -lt 500 -and $statusCode -ne 429)) { throw }
      Start-Sleep -Seconds ([math]::Min([math]::Pow(2, $attempt), 20))
    }
  }
}

function Invoke-DiscordPost {
  param(
    [string]$Uri,
    [object]$Payload
  )

  $body = $Payload | ConvertTo-Json -Depth 12 -Compress
  foreach ($attempt in 1..4) {
    try {
      return Invoke-RestMethod -Uri $Uri -Method Post -ContentType "application/json" -Body $body
    } catch {
      $statusCode = 0
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      }
      if ($attempt -ge 4 -or ($statusCode -lt 500 -and $statusCode -ne 429)) { throw }
      Start-Sleep -Seconds ([math]::Min([math]::Pow(2, $attempt), 20))
    }
  }
}

function Get-WebhookUri {
  param(
    [string]$BaseUrl,
    [hashtable]$Query
  )

  $pairs = @($Query.GetEnumerator() | Sort-Object Name | ForEach-Object {
    "{0}={1}" -f [uri]::EscapeDataString([string]$_.Name), [uri]::EscapeDataString([string]$_.Value)
  })
  if ($pairs.Count -eq 0) { return $BaseUrl }
  $separator = if ($BaseUrl.Contains("?")) { "&" } else { "?" }
  return ("{0}{1}{2}" -f $BaseUrl.TrimEnd('/'), $separator, ($pairs -join "&"))
}

function Resolve-WebhookUrl {
  param(
    [string]$DirectUrl,
    [string]$PrivateConfigPath
  )

  if (-not [string]::IsNullOrWhiteSpace($DirectUrl)) { return $DirectUrl.Trim() }
  if (-not (Test-Path -LiteralPath $PrivateConfigPath)) { return "" }

  $privateConfig = Get-Content -LiteralPath $PrivateConfigPath -Raw | ConvertFrom-Json
  $channels = Get-PropertyValue $privateConfig "channels"
  return Get-StringValue (Get-PropertyValue $channels "trade-tracker")
}

function Get-UnixTimestampIso {
  param([long]$Milliseconds)

  if ($Milliseconds -le 0) { return [datetimeoffset]::UtcNow.ToString("o") }
  $epoch = [datetimeoffset]::new(1970, 1, 1, 0, 0, 0, [timespan]::Zero)
  return $epoch.AddMilliseconds($Milliseconds).ToString("o")
}

function Get-Ordinal {
  param([int]$Value)

  if ($Value -le 0) { return "Pick" }
  $mod100 = $Value % 100
  if ($mod100 -in @(11, 12, 13)) { return "${Value}th" }
  switch ($Value % 10) {
    1 { return "${Value}st" }
    2 { return "${Value}nd" }
    3 { return "${Value}rd" }
    default { return "${Value}th" }
  }
}

function Get-PlayerLabel {
  param(
    [string]$PlayerId,
    [hashtable]$PlayersById
  )

  if ($PlayersById.ContainsKey($PlayerId)) {
    $player = $PlayersById[$PlayerId]
    $name = Get-StringValue (Get-PropertyValue $player "full_name")
    if (-not $name) {
      $name = ((Get-StringValue (Get-PropertyValue $player "first_name")), (Get-StringValue (Get-PropertyValue $player "last_name")) | Where-Object { $_ }) -join " "
    }
    if (-not $name) { $name = "Player $PlayerId" }
    $position = Get-StringValue (Get-PropertyValue $player "position")
    $team = Get-StringValue (Get-PropertyValue $player "team")
    $meta = @($position, $team | Where-Object { $_ }) -join " - "
    if ($meta) { return "$name ($meta)" }
    return $name
  }
  return "Player $PlayerId"
}

function Get-RosterNameMap {
  param(
    [string]$SleeperLeagueId,
    [object[]]$Users,
    [object[]]$Rosters
  )

  $usersById = @{}
  foreach ($user in $Users) {
    $userId = Get-StringValue (Get-PropertyValue $user "user_id")
    if ($userId) { $usersById[$userId] = $user }
  }

  $lookup = @{}
  foreach ($roster in $Rosters) {
    $rosterId = Get-IntValue (Get-PropertyValue $roster "roster_id")
    $ownerId = Get-StringValue (Get-PropertyValue $roster "owner_id")
    $user = if ($ownerId -and $usersById.ContainsKey($ownerId)) { $usersById[$ownerId] } else { $null }
    $metadata = Get-PropertyValue $user "metadata"
    $teamName = Get-StringValue (Get-PropertyValue $metadata "team_name")
    if (-not $teamName) { $teamName = Get-StringValue (Get-PropertyValue $user "display_name") }
    if (-not $teamName) { $teamName = Get-StringValue (Get-PropertyValue $user "username") }
    if (-not $teamName) { $teamName = "Roster $rosterId" }
    if ($rosterId -gt 0) { $lookup[$rosterId] = Convert-ToPlainDiscordText $teamName 70 }
  }
  return $lookup
}

function Get-TradeAssetFields {
  param(
    [object]$Transaction,
    [hashtable]$RosterNames,
    [hashtable]$PlayersById
  )

  $assetsByRoster = @{}
  foreach ($rosterIdValue in @(Get-PropertyValue $Transaction "roster_ids")) {
    $rosterId = Get-IntValue $rosterIdValue
    if ($rosterId -gt 0 -and -not $assetsByRoster.ContainsKey($rosterId)) {
      $assetsByRoster[$rosterId] = [System.Collections.Generic.List[string]]::new()
    }
  }

  $adds = Get-PropertyValue $Transaction "adds"
  if ($null -ne $adds) {
    foreach ($property in $adds.PSObject.Properties) {
      $rosterId = Get-IntValue $property.Value
      if ($rosterId -le 0) { continue }
      if (-not $assetsByRoster.ContainsKey($rosterId)) { $assetsByRoster[$rosterId] = [System.Collections.Generic.List[string]]::new() }
      $assetsByRoster[$rosterId].Add((Get-PlayerLabel -PlayerId $property.Name -PlayersById $PlayersById)) | Out-Null
    }
  }

  foreach ($pick in @(Get-PropertyValue $Transaction "draft_picks")) {
    $receivingRosterId = Get-IntValue (Get-PropertyValue $pick "owner_id")
    if ($receivingRosterId -le 0) { $receivingRosterId = Get-IntValue (Get-PropertyValue $pick "roster_id") }
    if ($receivingRosterId -le 0) { continue }
    if (-not $assetsByRoster.ContainsKey($receivingRosterId)) { $assetsByRoster[$receivingRosterId] = [System.Collections.Generic.List[string]]::new() }
    $season = Get-StringValue (Get-PropertyValue $pick "season")
    if (-not $season) { $season = "Future" }
    $round = Get-IntValue (Get-PropertyValue $pick "round")
    $originalRosterId = Get-IntValue (Get-PropertyValue $pick "roster_id")
    $originalText = if ($originalRosterId -gt 0) { ", original roster $originalRosterId" } else { "" }
    $assetsByRoster[$receivingRosterId].Add("$season $(Get-Ordinal $round)-round pick$originalText") | Out-Null
  }

  foreach ($faab in @(Get-PropertyValue $Transaction "waiver_budget")) {
    $receivingRosterId = Get-IntValue (Get-PropertyValue $faab "receiver")
    $amount = Get-IntValue (Get-PropertyValue $faab "amount")
    if ($receivingRosterId -le 0 -or $amount -le 0) { continue }
    if (-not $assetsByRoster.ContainsKey($receivingRosterId)) { $assetsByRoster[$receivingRosterId] = [System.Collections.Generic.List[string]]::new() }
    $assetsByRoster[$receivingRosterId].Add("$amount FAAB") | Out-Null
  }

  $fields = [System.Collections.Generic.List[object]]::new()
  foreach ($rosterId in @($assetsByRoster.Keys | Sort-Object)) {
    $teamName = if ($RosterNames.ContainsKey($rosterId)) { $RosterNames[$rosterId] } else { "Roster $rosterId" }
    $assets = @($assetsByRoster[$rosterId])
    $value = if ($assets.Count -gt 0) { ($assets | ForEach-Object { "- $_" }) -join "`n" } else { "Details unavailable from Sleeper" }
    if ($value.Length -gt 1024) { $value = $value.Substring(0, 1021).TrimEnd() + "..." }
    $fields.Add(@{
      name = "$teamName receives"
      value = $value
      inline = $false
    }) | Out-Null
  }
  return @($fields)
}

function New-TradePayload {
  param(
    [object]$Trade,
    [hashtable]$RosterNames,
    [hashtable]$PlayersById,
    [string]$WebsiteUrl
  )

  $leagueName = Convert-ToPlainDiscordText $Trade.leagueName 90
  $recordId = Convert-ToPlainDiscordText $Trade.leagueRecordId 20
  $format = Get-StringValue $Trade.format
  $color = switch ($format) {
    "dynasty" { 0x9B59B6 }
    "keeper" { 0x27AE60 }
    "bracket" { 0xC0392B }
    "chopped" { 0xE67E22 }
    "comanager" { 0x3498DB }
    default { 0x5865F2 }
  }
  $fields = Get-TradeAssetFields -Transaction $Trade.transaction -RosterNames $RosterNames -PlayersById $PlayersById

  $embed = @{
    title = "Trade Accepted - $leagueName"
    url = "https://sleeper.com/leagues/$($Trade.sleeperLeagueId)"
    description = "A completed trade was recorded in **$leagueName** ($recordId)."
    color = $color
    fields = $fields
    footer = @{ text = "VBP Trade Tracker | $recordId | Sleeper transaction $($Trade.transactionId)" }
    timestamp = Get-UnixTimestampIso ([long]$Trade.created)
  }
  if ($WebsiteUrl) {
    $embed.author = @{ name = "VBP Fantasy Network"; url = $WebsiteUrl }
  }
  return @{
    username = "VBP Trade Tracker"
    allowed_mentions = @{ parse = @() }
    embeds = @($embed)
  }
}

if (-not (Test-Path -LiteralPath $LeaguesPath)) { throw "Could not find league data at '$LeaguesPath'." }
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Could not find trade tracker config at '$ConfigPath'." }

$leagueData = Get-Content -LiteralPath $LeaguesPath -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$state = Get-StateRoot -Path $StatePath
$channelId = Get-StringValue (Get-PropertyValue $config "channelId")
$websiteUrl = Get-StringValue (Get-PropertyValue $config "websiteUrl")
$transactionWeeks = @((Get-PropertyValue $config "transactionWeeks") | ForEach-Object { Get-IntValue $_ } | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
$maxPostsPerRun = Get-IntValue (Get-PropertyValue $config "maxPostsPerRun")
if ($maxPostsPerRun -le 0) { $maxPostsPerRun = 10 }

if ($channelId -notmatch '^\d+$') { throw "Trade tracker channelId must be numeric." }
if ($transactionWeeks.Count -eq 0) { throw "Trade tracker config must include at least one transaction week." }

$configuredIds = @(if ($null -ne $LeagueRecordIds -and @($LeagueRecordIds).Count -gt 0) {
  $LeagueRecordIds | ForEach-Object { (Get-StringValue $_).ToUpperInvariant() } | Where-Object { $_ } | Sort-Object -Unique
} else {
  (Get-PropertyValue $config "leagueRecordIds") | ForEach-Object { (Get-StringValue $_).ToUpperInvariant() } | Where-Object { $_ } | Sort-Object -Unique
})
if (@($configuredIds).Count -eq 0) { throw "Trade tracker config must include leagueRecordIds." }

$leaguesById = @{}
foreach ($league in @($leagueData.leagues)) {
  $id = (Get-StringValue $league.id).ToUpperInvariant()
  if ($id) { $leaguesById[$id] = $league }
}
$missingIds = @($configuredIds | Where-Object { -not $leaguesById.ContainsKey($_) })
if (@($missingIds).Count -gt 0) { throw "Unknown configured league record IDs: $($missingIds -join ', ')." }

$tradesById = @{}
$fetchErrors = [System.Collections.Generic.List[string]]::new()
foreach ($leagueRecordId in $configuredIds) {
  $league = $leaguesById[$leagueRecordId]
  $sleeperLeagueId = Get-StringValue $league.sleeperLeagueId
  if (-not $sleeperLeagueId) {
    $fetchErrors.Add("$leagueRecordId has no Sleeper league ID.") | Out-Null
    continue
  }

  foreach ($week in $transactionWeeks) {
    try {
      $transactions = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$sleeperLeagueId/transactions/$week")
      foreach ($transaction in $transactions) {
        $type = (Get-StringValue (Get-PropertyValue $transaction "type")).ToLowerInvariant()
        $status = (Get-StringValue (Get-PropertyValue $transaction "status")).ToLowerInvariant()
        if ($type -ne "trade" -or $status -notin @("complete", "completed")) { continue }
        $transactionId = Get-StringValue (Get-PropertyValue $transaction "transaction_id")
        if (-not $transactionId) { continue }
        $created = 0L
        [void][long]::TryParse((Get-StringValue (Get-PropertyValue $transaction "created")), [ref]$created)
        $tradesById[$transactionId] = [pscustomobject]@{
          transactionId = $transactionId
          created = $created
          leagueRecordId = $leagueRecordId
          sleeperLeagueId = $sleeperLeagueId
          leagueName = Get-StringValue $league.name
          format = (Get-StringValue $league.format).ToLowerInvariant()
          transaction = $transaction
        }
      }
    } catch {
      $fetchErrors.Add("$leagueRecordId Week ${week}: $($_.Exception.Message)") | Out-Null
    }
  }
}

if ($fetchErrors.Count -gt 0) {
  throw "Trade tracker Sleeper fetch failed; state and Discord were left untouched. $($fetchErrors -join ' | ')"
}

$allTrades = @($tradesById.Values | Sort-Object created, transactionId)
$isInitialized = [bool](Get-PropertyValue $state "initialized")
if (-not $isInitialized -and -not $IncludeHistorical) {
  $bootstrapResult = [pscustomobject]@{
    action = if ($DryRun) { "dry-run-bootstrap" } else { "bootstrapped" }
    configuredLeagues = $configuredIds.Count
    historicalTradesRecorded = $allTrades.Count
    historicalTradesPosted = 0
    channelId = $channelId
  }

  if (-not $DryRun) {
    foreach ($trade in $allTrades) {
      Add-StateTransaction -State $state -Trade $trade -MessageId "" -Disposition "bootstrap-existing"
    }
    Set-StateProperty -State $state -Name channelId -Value $channelId
    Set-StateProperty -State $state -Name initialized -Value $true
    Save-StateRoot -Path $StatePath -State $state
  }

  if ($PassThru) { $bootstrapResult } else {
    Write-Host ("Trade tracker {0}: {1} existing trade(s) would be recorded without posting across {2} leagues." -f $bootstrapResult.action, $allTrades.Count, $configuredIds.Count)
  }
  exit 0
}

$newTrades = @($allTrades | Where-Object { -not (Test-StateHasTransaction -State $state -TransactionId $_.transactionId) })
$queuedTrades = @($newTrades | Select-Object -First $maxPostsPerRun)
if ($queuedTrades.Count -eq 0) {
  $currentResult = [pscustomobject]@{
    action = if ($DryRun) { "dry-run-current" } else { "current" }
    configuredLeagues = $configuredIds.Count
    tradesFound = $allTrades.Count
    newTrades = 0
    channelId = $channelId
  }
  if ($PassThru) { $currentResult } else { Write-Host "Trade tracker is current; no new completed trades were found." }
  exit 0
}

$playersById = @{}
$players = Invoke-JsonGet -Uri "https://api.sleeper.app/v1/players/nfl"
foreach ($property in $players.PSObject.Properties) { $playersById[$property.Name] = $property.Value }

$leagueContext = @{}
$payloadEntries = [System.Collections.Generic.List[object]]::new()
foreach ($trade in $queuedTrades) {
  if (-not $leagueContext.ContainsKey($trade.leagueRecordId)) {
    $users = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$($trade.sleeperLeagueId)/users")
    $rosters = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$($trade.sleeperLeagueId)/rosters")
    $leagueContext[$trade.leagueRecordId] = Get-RosterNameMap -SleeperLeagueId $trade.sleeperLeagueId -Users $users -Rosters $rosters
  }
  $payload = New-TradePayload -Trade $trade -RosterNames $leagueContext[$trade.leagueRecordId] -PlayersById $playersById -WebsiteUrl $websiteUrl
  $payloadEntries.Add([pscustomobject]@{ trade = $trade; payload = $payload }) | Out-Null
}

if ($DryRun) {
  $dryRunResult = [pscustomobject]@{
    action = "dry-run"
    configuredLeagues = $configuredIds.Count
    tradesFound = $allTrades.Count
    newTrades = $newTrades.Count
    queuedTrades = $queuedTrades.Count
    deferredTrades = [math]::Max($newTrades.Count - $queuedTrades.Count, 0)
    channelId = $channelId
    payloads = @($payloadEntries)
  }
  if ($PassThru) { $dryRunResult } else {
    Write-Host ("DRY RUN Trade Tracker: {0} new trade(s), {1} queued, {2} deferred." -f $newTrades.Count, $queuedTrades.Count, $dryRunResult.deferredTrades)
    $payloadEntries | ForEach-Object { Write-Output ($_.payload | ConvertTo-Json -Depth 12) }
  }
  exit 0
}

$resolvedWebhookUrl = Resolve-WebhookUrl -DirectUrl $WebhookUrl -PrivateConfigPath $WebhookConfigPath
if ([string]::IsNullOrWhiteSpace($resolvedWebhookUrl)) {
  throw "Trade tracker webhook is not configured. Set DISCORD_WEBHOOK_TRADE_TRACKER or add channels.trade-tracker to the private webhook file."
}
$webhookInfo = Invoke-JsonGet -Uri $resolvedWebhookUrl
$webhookChannelId = Get-StringValue (Get-PropertyValue $webhookInfo "channel_id")
$webhookId = Get-StringValue (Get-PropertyValue $webhookInfo "id")
if ($webhookChannelId -ne $channelId) {
  throw "The trade tracker webhook points to channel '$webhookChannelId', not configured channel '$channelId'."
}
$savedWebhookId = Get-StringValue (Get-PropertyValue $state "webhookId")
if ($savedWebhookId -and $savedWebhookId -ne $webhookId) {
  throw "The trade tracker state belongs to a different Discord webhook. Clear the saved webhook state only when intentionally replacing it."
}

Set-StateProperty -State $state -Name channelId -Value $channelId
Set-StateProperty -State $state -Name webhookId -Value $webhookId
Set-StateProperty -State $state -Name initialized -Value $true

$postedCount = 0
foreach ($payloadEntry in $payloadEntries) {
  $postUri = Get-WebhookUri -BaseUrl $resolvedWebhookUrl -Query @{ wait = "true" }
  $response = Invoke-DiscordPost -Uri $postUri -Payload $payloadEntry.payload
  $messageId = Get-StringValue (Get-PropertyValue $response "id")
  if (-not $messageId) { throw "Discord did not return a message ID for trade '$($payloadEntry.trade.transactionId)'." }
  Add-StateTransaction -State $state -Trade $payloadEntry.trade -MessageId $messageId -Disposition "posted"
  Save-StateRoot -Path $StatePath -State $state
  $postedCount++
}

$result = [pscustomobject]@{
  action = "posted"
  configuredLeagues = $configuredIds.Count
  tradesFound = $allTrades.Count
  newTrades = $newTrades.Count
  postedTrades = $postedCount
  deferredTrades = [math]::Max($newTrades.Count - $postedCount, 0)
  channelId = $channelId
}

if ($PassThru) {
  $result
} else {
  Write-Host ("Trade tracker posted {0} completed trade(s) to channel {1}; {2} deferred." -f $postedCount, $channelId, $result.deferredTrades)
}
