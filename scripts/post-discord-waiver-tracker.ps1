param(
  [string]$LeaguesPath = "data/leagues.json",
  [string]$ConfigPath = "data/discord-waiver-tracker-config.json",
  [string]$StatePath = "data/discord-waiver-tracker-state.json",
  [string]$WebhookConfigPath = "data/private/discord-webhooks.json",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_WAIVER_TRACKER,
  [string[]]$LeagueRecordIds,
  [switch]$IncludeHistorical,
  [switch]$DryRun,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PropertyValue {
  param([AllowNull()][object]$InputObject, [string]$Name)
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
  param([AllowNull()][object]$Value, [int]$MaximumLength = 90)
  $text = Get-StringValue $Value
  $text = [regex]::Replace($text, '[\r\n\t]+', ' ')
  $text = [regex]::Replace($text, '[*_~`>|]', '')
  $text = [regex]::Replace($text, '\s{2,}', ' ').Trim()
  if ($MaximumLength -gt 3 -and $text.Length -gt $MaximumLength) {
    return ($text.Substring(0, $MaximumLength - 3).TrimEnd() + "...")
  }
  return $text
}

function Set-StateProperty {
  param([object]$State, [string]$Name, [AllowNull()][object]$Value)
  if ($State.PSObject.Properties[$Name]) { $State.$Name = $Value }
  else { $State | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
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

function Save-StateRoot {
  param([string]$Path, [object]$State)
  Set-StateProperty -State $State -Name updatedAt -Value ([datetimeoffset]::UtcNow.ToString("o"))
  $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path
}

function Test-StateHasTransaction {
  param([object]$State, [string]$TransactionId)
  $transactions = Get-PropertyValue $State "transactions"
  return $null -ne $transactions.PSObject.Properties[$TransactionId]
}

function Add-StateTransaction {
  param([object]$State, [object]$Activity, [string]$MessageId, [string]$Disposition)
  $entry = [pscustomobject]@{
    leagueRecordId = Get-StringValue $Activity.leagueRecordId
    sleeperLeagueId = Get-StringValue $Activity.sleeperLeagueId
    transactionId = Get-StringValue $Activity.transactionId
    transactionType = Get-StringValue $Activity.transactionType
    created = [long]$Activity.created
    messageId = $MessageId
    disposition = $Disposition
    recordedAt = [datetimeoffset]::UtcNow.ToString("o")
  }
  (Get-PropertyValue $State "transactions") | Add-Member -NotePropertyName $Activity.transactionId -NotePropertyValue $entry -Force
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
    }
    catch {
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
  param([string]$Uri, [object]$Payload)
  $body = $Payload | ConvertTo-Json -Depth 12 -Compress
  foreach ($attempt in 1..4) {
    try { return Invoke-RestMethod -Uri $Uri -Method Post -ContentType "application/json" -Body $body }
    catch {
      $statusCode = 0
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      }
      if ($attempt -ge 4 -or ($statusCode -lt 500 -and $statusCode -ne 429)) { throw }
      Start-Sleep -Seconds ([math]::Min([math]::Pow(2, $attempt), 20))
    }
  }
}

function Resolve-WebhookUrl {
  param([string]$DirectUrl, [string]$PrivateConfigPath)
  if (-not [string]::IsNullOrWhiteSpace($DirectUrl)) { return $DirectUrl.Trim() }
  if (-not (Test-Path -LiteralPath $PrivateConfigPath)) { return "" }
  $privateConfig = Get-Content -LiteralPath $PrivateConfigPath -Raw | ConvertFrom-Json
  return Get-StringValue (Get-PropertyValue (Get-PropertyValue $privateConfig "channels") "waiver-tracker")
}

function Get-WebhookUri {
  param([string]$BaseUrl, [hashtable]$Query)
  $pairs = @($Query.GetEnumerator() | Sort-Object Name | ForEach-Object {
    "{0}={1}" -f [uri]::EscapeDataString([string]$_.Name), [uri]::EscapeDataString([string]$_.Value)
  })
  if ($pairs.Count -eq 0) { return $BaseUrl }
  $separator = if ($BaseUrl.Contains("?")) { "&" } else { "?" }
  return ("{0}{1}{2}" -f $BaseUrl.TrimEnd('/'), $separator, ($pairs -join "&"))
}

function Get-UnixTimestampIso {
  param([long]$Milliseconds)
  if ($Milliseconds -le 0) { return [datetimeoffset]::UtcNow.ToString("o") }
  $epoch = [datetimeoffset]::new(1970, 1, 1, 0, 0, 0, [timespan]::Zero)
  return $epoch.AddMilliseconds($Milliseconds).ToString("o")
}

function Get-PlayerLabel {
  param([string]$PlayerId, [hashtable]$PlayersById)
  if (-not $PlayersById.ContainsKey($PlayerId)) { return "Player $PlayerId" }
  $player = $PlayersById[$PlayerId]
  $name = Get-StringValue (Get-PropertyValue $player "full_name")
  if (-not $name) {
    $name = @(
      Get-StringValue (Get-PropertyValue $player "first_name")
      Get-StringValue (Get-PropertyValue $player "last_name")
    ) | Where-Object { $_ }
    $name = $name -join " "
  }
  if (-not $name) { $name = "Player $PlayerId" }
  $position = Get-StringValue (Get-PropertyValue $player "position")
  $team = Get-StringValue (Get-PropertyValue $player "team")
  $meta = @($position, $team | Where-Object { $_ }) -join " - "
  if ($meta) { return "$name ($meta)" }
  return $name
}

function Get-RosterNameMap {
  param([object[]]$Users, [object[]]$Rosters)
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
    $name = Get-StringValue (Get-PropertyValue $metadata "team_name")
    if (-not $name) { $name = Get-StringValue (Get-PropertyValue $user "display_name") }
    if (-not $name) { $name = Get-StringValue (Get-PropertyValue $user "username") }
    if (-not $name) { $name = "Roster $rosterId" }
    if ($rosterId -gt 0) { $lookup[$rosterId] = Convert-ToPlainDiscordText $name 70 }
  }
  return $lookup
}

function Get-TransactionPlayers {
  param([object]$Transaction, [string]$PropertyName, [hashtable]$PlayersById)
  $result = [System.Collections.Generic.List[string]]::new()
  $playerMap = Get-PropertyValue $Transaction $PropertyName
  if ($null -ne $playerMap) {
    foreach ($property in $playerMap.PSObject.Properties) {
      $result.Add((Get-PlayerLabel -PlayerId $property.Name -PlayersById $PlayersById)) | Out-Null
    }
  }
  return @($result)
}

function New-WaiverPayload {
  param([object]$Activity, [hashtable]$RosterNames, [hashtable]$PlayersById, [string]$WebsiteUrl)
  $transaction = $Activity.transaction
  $adds = @(Get-TransactionPlayers -Transaction $transaction -PropertyName "adds" -PlayersById $PlayersById)
  $drops = @(Get-TransactionPlayers -Transaction $transaction -PropertyName "drops" -PlayersById $PlayersById)
  $rosterId = 0
  $addMap = Get-PropertyValue $transaction "adds"
  if ($null -ne $addMap) {
    $firstAdd = @($addMap.PSObject.Properties | Select-Object -First 1)
    if ($firstAdd.Count -gt 0) { $rosterId = Get-IntValue $firstAdd[0].Value }
  }
  if ($rosterId -le 0) {
    $rosterId = Get-IntValue (@(Get-PropertyValue $transaction "roster_ids" | Select-Object -First 1))
  }
  $teamName = if ($RosterNames.ContainsKey($rosterId)) { $RosterNames[$rosterId] } else { "Roster $rosterId" }
  $isWaiver = $Activity.transactionType -eq "waiver"
  $isDropOnly = -not $isWaiver -and $adds.Count -eq 0 -and $drops.Count -gt 0
  $activityName = if ($isWaiver) { "Waiver Claim" } elseif ($isDropOnly) { "Roster Drop" } else { "Free-Agent Pickup" }
  $settings = Get-PropertyValue $transaction "settings"
  $waiverBid = Get-IntValue (Get-PropertyValue $settings "waiver_bid")
  $method = if ($isWaiver -and $waiverBid -gt 0) { "$waiverBid FAAB" } elseif ($isWaiver) { "Waiver priority" } elseif ($isDropOnly) { "Drop only" } else { "Free agent" }
  $fields = [System.Collections.Generic.List[object]]::new()
  $addedText = if ($adds.Count -gt 0) { ($adds | ForEach-Object { "- $_" }) -join "`n" } else { "No added player reported" }
  $fields.Add(@{ name = "Added"; value = $addedText; inline = $false }) | Out-Null
  if ($drops.Count -gt 0) {
    $fields.Add(@{ name = "Dropped"; value = (($drops | ForEach-Object { "- $_" }) -join "`n"); inline = $false }) | Out-Null
  }
  $fields.Add(@{ name = "Method"; value = $method; inline = $true }) | Out-Null
  $recordId = Convert-ToPlainDiscordText $Activity.leagueRecordId 20
  $leagueName = Convert-ToPlainDiscordText $Activity.leagueName 80
  $embed = @{
    title = "$activityName - $teamName"
    url = "https://sleeper.com/leagues/$($Activity.sleeperLeagueId)"
    description = "Completed in **$leagueName** ($recordId)."
    color = if ($isWaiver) { 0x2ECC71 } else { 0x3498DB }
    fields = @($fields)
    footer = @{ text = "VBP Waiver Wire | $recordId | Sleeper transaction $($Activity.transactionId)" }
    timestamp = Get-UnixTimestampIso ([long]$Activity.created)
  }
  if ($WebsiteUrl) { $embed.author = @{ name = "VBP Fantasy Network"; url = $WebsiteUrl } }
  return @{ username = "VBP Waiver Wire"; allowed_mentions = @{ parse = @() }; embeds = @($embed) }
}

if (-not (Test-Path -LiteralPath $LeaguesPath)) { throw "Could not find league data at '$LeaguesPath'." }
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Could not find waiver tracker config at '$ConfigPath'." }

$leagueData = Get-Content -LiteralPath $LeaguesPath -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$state = Get-StateRoot -Path $StatePath
$channelId = Get-StringValue (Get-PropertyValue $config "channelId")
$websiteUrl = Get-StringValue (Get-PropertyValue $config "websiteUrl")
$transactionWeeks = @((Get-PropertyValue $config "transactionWeeks") | ForEach-Object { Get-IntValue $_ } | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
$maxPostsPerRun = Get-IntValue (Get-PropertyValue $config "maxPostsPerRun")
if ($maxPostsPerRun -le 0) { $maxPostsPerRun = 15 }
if ($channelId -notmatch '^\d+$') { throw "Waiver tracker channelId must be numeric." }
if ($transactionWeeks.Count -eq 0) { throw "Waiver tracker config must include at least one transaction week." }

$configuredIds = @(if ($null -ne $LeagueRecordIds -and @($LeagueRecordIds).Count -gt 0) {
  $LeagueRecordIds | ForEach-Object { (Get-StringValue $_).ToUpperInvariant() } | Where-Object { $_ } | Sort-Object -Unique
} else {
  (Get-PropertyValue $config "leagueRecordIds") | ForEach-Object { (Get-StringValue $_).ToUpperInvariant() } | Where-Object { $_ } | Sort-Object -Unique
})
if ($configuredIds.Count -eq 0) { throw "Waiver tracker config must include leagueRecordIds." }

$leaguesById = @{}
foreach ($league in @($leagueData.leagues)) {
  $id = (Get-StringValue $league.id).ToUpperInvariant()
  if ($id) { $leaguesById[$id] = $league }
}
$missingIds = @($configuredIds | Where-Object { -not $leaguesById.ContainsKey($_) })
if ($missingIds.Count -gt 0) { throw "Unknown configured league record IDs: $($missingIds -join ', ')." }

$activitiesById = @{}
$fetchErrors = [System.Collections.Generic.List[string]]::new()
foreach ($leagueRecordId in $configuredIds) {
  $league = $leaguesById[$leagueRecordId]
  $sleeperLeagueId = Get-StringValue $league.sleeperLeagueId
  if (-not $sleeperLeagueId) { $fetchErrors.Add("$leagueRecordId has no Sleeper league ID.") | Out-Null; continue }
  foreach ($week in $transactionWeeks) {
    try {
      foreach ($transaction in @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$sleeperLeagueId/transactions/$week")) {
        $type = (Get-StringValue (Get-PropertyValue $transaction "type")).ToLowerInvariant()
        $status = (Get-StringValue (Get-PropertyValue $transaction "status")).ToLowerInvariant()
        if ($type -notin @("waiver", "free_agent") -or $status -notin @("complete", "completed")) { continue }
        $transactionId = Get-StringValue (Get-PropertyValue $transaction "transaction_id")
        if (-not $transactionId) { continue }
        $created = 0L
        [void][long]::TryParse((Get-StringValue (Get-PropertyValue $transaction "created")), [ref]$created)
        $activitiesById[$transactionId] = [pscustomobject]@{
          transactionId = $transactionId
          transactionType = $type
          created = $created
          leagueRecordId = $leagueRecordId
          sleeperLeagueId = $sleeperLeagueId
          leagueName = Get-StringValue $league.name
          transaction = $transaction
        }
      }
    } catch { $fetchErrors.Add("$leagueRecordId Week ${week}: $($_.Exception.Message)") | Out-Null }
  }
}
if ($fetchErrors.Count -gt 0) { throw "Waiver tracker Sleeper fetch failed; state and Discord were left untouched. $($fetchErrors -join ' | ')" }

$allActivities = @($activitiesById.Values | Sort-Object created, transactionId)
$isInitialized = [bool](Get-PropertyValue $state "initialized")
if (-not $isInitialized -and -not $IncludeHistorical) {
  if (-not $DryRun) {
    foreach ($activity in $allActivities) { Add-StateTransaction -State $state -Activity $activity -MessageId "" -Disposition "bootstrap-existing" }
    Set-StateProperty -State $state -Name channelId -Value $channelId
    Set-StateProperty -State $state -Name initialized -Value $true
    Save-StateRoot -Path $StatePath -State $state
  }
  $result = [pscustomobject]@{ action = if ($DryRun) { "dry-run-bootstrap" } else { "bootstrapped" }; configuredLeagues = $configuredIds.Count; historicalTransactionsRecorded = $allActivities.Count; historicalTransactionsPosted = 0; channelId = $channelId }
  if ($PassThru) { $result } else { Write-Host "Waiver tracker $($result.action): $($allActivities.Count) existing transaction(s) found across $($configuredIds.Count) leagues; none posted." }
  exit 0
}

$newActivities = @($allActivities | Where-Object { -not (Test-StateHasTransaction -State $state -TransactionId $_.transactionId) })
$queuedActivities = @($newActivities | Select-Object -First $maxPostsPerRun)
if ($queuedActivities.Count -eq 0) {
  $result = [pscustomobject]@{ action = if ($DryRun) { "dry-run-current" } else { "current" }; configuredLeagues = $configuredIds.Count; transactionsFound = $allActivities.Count; newTransactions = 0; channelId = $channelId }
  if ($PassThru) { $result } else { Write-Host "Waiver tracker is current; no new completed claims or pickups were found." }
  exit 0
}

$playersById = @{}
$players = Invoke-JsonGet -Uri "https://api.sleeper.app/v1/players/nfl"
foreach ($property in $players.PSObject.Properties) { $playersById[$property.Name] = $property.Value }
$leagueContext = @{}
$payloadEntries = [System.Collections.Generic.List[object]]::new()
foreach ($activity in $queuedActivities) {
  if (-not $leagueContext.ContainsKey($activity.leagueRecordId)) {
    $users = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$($activity.sleeperLeagueId)/users")
    $rosters = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$($activity.sleeperLeagueId)/rosters")
    $leagueContext[$activity.leagueRecordId] = Get-RosterNameMap -Users $users -Rosters $rosters
  }
  $payload = New-WaiverPayload -Activity $activity -RosterNames $leagueContext[$activity.leagueRecordId] -PlayersById $playersById -WebsiteUrl $websiteUrl
  $payloadEntries.Add([pscustomobject]@{ activity = $activity; payload = $payload }) | Out-Null
}

if ($DryRun) {
  $result = [pscustomobject]@{ action = "dry-run"; configuredLeagues = $configuredIds.Count; transactionsFound = $allActivities.Count; newTransactions = $newActivities.Count; queuedTransactions = $queuedActivities.Count; deferredTransactions = [math]::Max($newActivities.Count - $queuedActivities.Count, 0); channelId = $channelId; payloads = @($payloadEntries) }
  if ($PassThru) { $result } else { Write-Host "DRY RUN Waiver Tracker: $($newActivities.Count) new transaction(s), $($queuedActivities.Count) queued."; $payloadEntries | ForEach-Object { Write-Output ($_.payload | ConvertTo-Json -Depth 12) } }
  exit 0
}

$resolvedWebhookUrl = Resolve-WebhookUrl -DirectUrl $WebhookUrl -PrivateConfigPath $WebhookConfigPath
if ([string]::IsNullOrWhiteSpace($resolvedWebhookUrl)) { throw "Waiver tracker webhook is not configured. Set DISCORD_WEBHOOK_WAIVER_TRACKER or add channels.waiver-tracker to the private webhook file." }
$webhookInfo = Invoke-JsonGet -Uri $resolvedWebhookUrl
$webhookChannelId = Get-StringValue (Get-PropertyValue $webhookInfo "channel_id")
$webhookId = Get-StringValue (Get-PropertyValue $webhookInfo "id")
if ($webhookChannelId -ne $channelId) { throw "The waiver tracker webhook points to channel '$webhookChannelId', not configured channel '$channelId'." }
$savedWebhookId = Get-StringValue (Get-PropertyValue $state "webhookId")
if ($savedWebhookId -and $savedWebhookId -ne $webhookId) { throw "The waiver tracker state belongs to a different Discord webhook." }
Set-StateProperty -State $state -Name channelId -Value $channelId
Set-StateProperty -State $state -Name webhookId -Value $webhookId
Set-StateProperty -State $state -Name initialized -Value $true

$postedCount = 0
foreach ($entry in $payloadEntries) {
  $response = Invoke-DiscordPost -Uri (Get-WebhookUri -BaseUrl $resolvedWebhookUrl -Query @{ wait = "true" }) -Payload $entry.payload
  $messageId = Get-StringValue (Get-PropertyValue $response "id")
  if (-not $messageId) { throw "Discord did not return a message ID for waiver transaction '$($entry.activity.transactionId)'." }
  Add-StateTransaction -State $state -Activity $entry.activity -MessageId $messageId -Disposition "posted"
  Save-StateRoot -Path $StatePath -State $state
  $postedCount++
}

$result = [pscustomobject]@{ action = "posted"; configuredLeagues = $configuredIds.Count; transactionsFound = $allActivities.Count; newTransactions = $newActivities.Count; postedTransactions = $postedCount; deferredTransactions = [math]::Max($newActivities.Count - $postedCount, 0); channelId = $channelId }
if ($PassThru) { $result } else { Write-Host "Waiver tracker posted $postedCount completed transaction(s) to channel $channelId." }
