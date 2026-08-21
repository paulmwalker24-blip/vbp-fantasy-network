param(
  [string]$LeaguesPath = "data/leagues.json",
  [string]$ConfigPath = "data/discord-waiver-tracker-config.json",
  [string]$StatePath = "data/discord-waiver-tracker-state.json",
  [string]$WebhookConfigPath = "data/private/discord-webhooks.json",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_WAIVER_TRACKER,
  [string[]]$LeagueRecordIds,
  [switch]$IncludeHistorical,
  [switch]$MigrateIndividualMessages,
  [switch]$ForceRefresh,
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
      if (-not $loaded.PSObject.Properties["groups"]) {
        $loaded | Add-Member -NotePropertyName groups -NotePropertyValue ([pscustomobject]@{})
      }
      if (-not $loaded.PSObject.Properties["initialized"]) {
        $loaded | Add-Member -NotePropertyName initialized -NotePropertyValue $false
      }
      return $loaded
    }
  }
  return [pscustomobject]@{
    version = 3
    channelId = ""
    webhookId = ""
    initialized = $false
    transactions = [pscustomobject]@{}
    groups = [pscustomobject]@{}
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
    week = [int]$Activity.week
    created = [long]$Activity.created
    messageId = $MessageId
    disposition = $Disposition
    recordedAt = [datetimeoffset]::UtcNow.ToString("o")
  }
  (Get-PropertyValue $State "transactions") | Add-Member -NotePropertyName $Activity.transactionId -NotePropertyValue $entry -Force
}

function Get-GroupKey {
  param([object]$Activity)
  return ("week-{0}" -f [int]$Activity.week)
}

function Get-StateGroup {
  param([object]$State, [string]$GroupKey)
  $groups = Get-PropertyValue $State "groups"
  $property = $groups.PSObject.Properties[$GroupKey]
  if ($property) { return $property.Value }
  return $null
}

function Set-StateGroup {
  param([object]$State, [object]$Group, [string]$MessageId, [string]$Signature)
  $first = @($Group.activities | Select-Object -First 1)[0]
  $entry = [pscustomobject]@{
    groupKey = Get-StringValue $Group.groupKey
    week = [int]$first.week
    messageId = $MessageId
    signature = $Signature
    divisions = @($Group.activities | ForEach-Object { Get-StringValue $_.leagueRecordId } | Sort-Object -Unique)
    transactionIds = @($Group.activities | ForEach-Object { Get-StringValue $_.transactionId })
    updatedAt = [datetimeoffset]::UtcNow.ToString("o")
  }
  (Get-PropertyValue $State "groups") | Add-Member -NotePropertyName $Group.groupKey -NotePropertyValue $entry -Force
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

function Invoke-DiscordPatch {
  param([string]$Uri, [object]$Payload)
  $body = $Payload | ConvertTo-Json -Depth 12 -Compress
  foreach ($attempt in 1..4) {
    try { return Invoke-RestMethod -Uri $Uri -Method Patch -ContentType "application/json" -Body $body }
    catch {
      $statusCode = 0
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $statusCode = [int]$_.Exception.Response.StatusCode }
      if ($attempt -ge 4 -or ($statusCode -lt 500 -and $statusCode -ne 429)) { throw }
      Start-Sleep -Seconds ([math]::Min([math]::Pow(2, $attempt), 20))
    }
  }
}

function Invoke-DiscordDelete {
  param([string]$Uri)
  foreach ($attempt in 1..4) {
    try { Invoke-RestMethod -Uri $Uri -Method Delete | Out-Null; return }
    catch {
      $statusCode = 0
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $statusCode = [int]$_.Exception.Response.StatusCode }
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

function Get-WaiverActivityDetails {
  param([object]$Activity, [hashtable]$RosterNamesByLeague, [hashtable]$PlayersById)
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
  $rosterNames = if ($RosterNamesByLeague.ContainsKey($Activity.leagueRecordId)) { $RosterNamesByLeague[$Activity.leagueRecordId] } else { @{} }
  $teamName = if ($rosterNames.ContainsKey($rosterId)) { $rosterNames[$rosterId] } else { "Roster $rosterId" }
  $isWaiver = $Activity.transactionType -eq "waiver"
  $isDropOnly = -not $isWaiver -and $adds.Count -eq 0 -and $drops.Count -gt 0
  $activityName = if ($isWaiver) { "Waiver Claim" } elseif ($isDropOnly) { "Roster Drop" } else { "Free-Agent Pickup" }
  $settings = Get-PropertyValue $transaction "settings"
  $waiverBid = Get-IntValue (Get-PropertyValue $settings "waiver_bid")
  $method = if ($isWaiver -and $waiverBid -gt 0) { "$waiverBid FAAB" } elseif ($isWaiver) { "Waiver priority" } elseif ($isDropOnly) { "Drop only" } else { "Free agent" }
  return [pscustomobject]@{
    activity = $Activity
    teamName = $teamName
    leagueName = Convert-ToPlainDiscordText $Activity.leagueName 60
    activityName = $activityName
    waiverBid = $waiverBid
    method = $method
    adds = $adds
    drops = $drops
  }
}

function New-WaiverGroupPayload {
  param(
    [object]$Group,
    [hashtable]$RosterNamesByLeague,
    [hashtable]$PlayersById,
    [object[]]$ConfiguredLeagues,
    [string]$WebsiteUrl
  )
  $activities = @($Group.activities | Sort-Object created, transactionId)
  $first = $activities[0]
  $week = [int]$first.week
  $details = @($activities | ForEach-Object { Get-WaiverActivityDetails -Activity $_ -RosterNamesByLeague $RosterNamesByLeague -PlayersById $PlayersById })
  $activeDivisionCount = @($activities | ForEach-Object { $_.leagueRecordId } | Sort-Object -Unique).Count
  $refreshUnix = [datetimeoffset]::UtcNow.ToUnixTimeSeconds()

  $topClaimLines = @($details |
    Where-Object { $_.waiverBid -gt 0 -and $_.adds.Count -gt 0 } |
    Sort-Object @{ Expression = "waiverBid"; Descending = $true }, @{ Expression = { $_.activity.created }; Descending = $false } |
    Select-Object -First 5 |
    ForEach-Object {
      "**$($_.adds[0])** - $($_.waiverBid) FAAB | $($_.teamName) ($($_.leagueName))"
    })
  if ($topClaimLines.Count -eq 0) { $topClaimLines = @("No successful FAAB bids recorded yet.") }

  $divisionLines = [System.Collections.Generic.List[string]]::new()
  foreach ($league in @($ConfiguredLeagues | Sort-Object name)) {
    $leagueId = Get-StringValue $league.id
    $leagueName = Convert-ToPlainDiscordText $league.name 50
    $divisionDetails = @($details | Where-Object { $_.activity.leagueRecordId -eq $leagueId })
    if ($divisionDetails.Count -eq 0) {
      $divisionLines.Add("**${leagueName}:** No completed activity") | Out-Null
      continue
    }
    $topDivisionClaim = @($divisionDetails | Where-Object { $_.waiverBid -gt 0 -and $_.adds.Count -gt 0 } | Sort-Object waiverBid -Descending | Select-Object -First 1)
    $highlight = if ($topDivisionClaim.Count -gt 0) { " | Top: $($topDivisionClaim[0].adds[0]) ($($topDivisionClaim[0].waiverBid) FAAB)" } else { "" }
    $divisionLines.Add("**${leagueName}:** $($divisionDetails.Count) move(s)$highlight") | Out-Null
  }

  $embed = @{
    title = "Week $week VBP Waiver Wire Recap"
    url = $WebsiteUrl
    description = "$($activities.Count) completed move(s) across $activeDivisionCount division(s). Last checked <t:${refreshUnix}:R>."
    color = 0x2ECC71
    fields = @(
      @{ name = "Top FAAB Claims"; value = ($topClaimLines -join "`n"); inline = $false },
      @{ name = "Division Snapshot"; value = ($divisionLines -join "`n"); inline = $false }
    )
    footer = @{ text = "VBP Waiver Wire | Updates daily at 2:00 PM Central" }
    timestamp = [datetimeoffset]::UtcNow.ToString("o")
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
          week = $week
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
$activityGroups = [System.Collections.Generic.List[object]]::new()
foreach ($grouping in @($allActivities | Group-Object { Get-GroupKey $_ })) {
  $activities = @($grouping.Group | Sort-Object created, transactionId)
  $signature = (@($activities | ForEach-Object { Get-StringValue $_.transactionId }) -join ":")
  $activityGroups.Add([pscustomobject]@{
    groupKey = Get-StringValue $grouping.Name
    activities = $activities
    signature = $signature
  }) | Out-Null
}
$activityGroups = @($activityGroups | Sort-Object { [int]$_.activities[0].week }, { Get-StringValue $_.activities[0].leagueName })
$isInitialized = [bool](Get-PropertyValue $state "initialized")
if (-not $isInitialized -and -not $IncludeHistorical) {
  if (-not $DryRun) {
    foreach ($activity in $allActivities) { Add-StateTransaction -State $state -Activity $activity -MessageId "" -Disposition "bootstrap-existing" }
    foreach ($group in $activityGroups) { Set-StateGroup -State $state -Group $group -MessageId "" -Signature $group.signature }
    Set-StateProperty -State $state -Name version -Value 3
    Set-StateProperty -State $state -Name channelId -Value $channelId
    Set-StateProperty -State $state -Name initialized -Value $true
    Save-StateRoot -Path $StatePath -State $state
  }
  $result = [pscustomobject]@{ action = if ($DryRun) { "dry-run-bootstrap" } else { "bootstrapped" }; configuredLeagues = $configuredIds.Count; historicalTransactionsRecorded = $allActivities.Count; historicalTransactionsPosted = 0; channelId = $channelId }
  if ($PassThru) { $result } else { Write-Host "Waiver tracker $($result.action): $($allActivities.Count) existing transaction(s) found across $($configuredIds.Count) leagues; none posted." }
  exit 0
}

$newActivities = @($allActivities | Where-Object { -not (Test-StateHasTransaction -State $state -TransactionId $_.transactionId) })
$changedGroups = @($activityGroups | Where-Object {
  $savedGroup = Get-StateGroup -State $state -GroupKey $_.groupKey
  $savedMessageId = Get-StringValue (Get-PropertyValue $savedGroup "messageId")
  $savedSignature = Get-StringValue (Get-PropertyValue $savedGroup "signature")
  $ForceRefresh -or (-not $savedMessageId) -or $savedSignature -ne $_.signature
})
$queuedGroups = @($changedGroups | Select-Object -First $maxPostsPerRun)
if ($queuedGroups.Count -eq 0) {
  $result = [pscustomobject]@{ action = if ($DryRun) { "dry-run-current" } else { "current" }; configuredLeagues = $configuredIds.Count; transactionsFound = $allActivities.Count; newTransactions = $newActivities.Count; weeklySummaries = $activityGroups.Count; changedSummaries = 0; channelId = $channelId }
  if ($PassThru) { $result } else { Write-Host "Waiver tracker is current; all weekly division summaries match Sleeper." }
  exit 0
}

$playersById = @{}
$players = Invoke-JsonGet -Uri "https://api.sleeper.app/v1/players/nfl"
foreach ($property in $players.PSObject.Properties) { $playersById[$property.Name] = $property.Value }
$leagueContext = @{}
$payloadEntries = [System.Collections.Generic.List[object]]::new()
foreach ($group in $queuedGroups) {
  foreach ($activityLeague in @($group.activities | Group-Object leagueRecordId | ForEach-Object { $_.Group[0] })) {
    if (-not $leagueContext.ContainsKey($activityLeague.leagueRecordId)) {
      $users = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$($activityLeague.sleeperLeagueId)/users")
      $rosters = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$($activityLeague.sleeperLeagueId)/rosters")
      $leagueContext[$activityLeague.leagueRecordId] = Get-RosterNameMap -Users $users -Rosters $rosters
    }
  }
  $configuredLeagues = @($configuredIds | ForEach-Object { $leaguesById[$_] })
  $payload = New-WaiverGroupPayload -Group $group -RosterNamesByLeague $leagueContext -PlayersById $playersById -ConfiguredLeagues $configuredLeagues -WebsiteUrl $websiteUrl
  $payloadEntries.Add([pscustomobject]@{ group = $group; payload = $payload }) | Out-Null
}

if ($DryRun) {
  $result = [pscustomobject]@{ action = "dry-run"; configuredLeagues = $configuredIds.Count; transactionsFound = $allActivities.Count; newTransactions = $newActivities.Count; weeklySummaries = $activityGroups.Count; changedSummaries = $changedGroups.Count; queuedSummaries = $queuedGroups.Count; deferredSummaries = [math]::Max($changedGroups.Count - $queuedGroups.Count, 0); channelId = $channelId; payloads = @($payloadEntries) }
  if ($PassThru) { $result } else { Write-Host "DRY RUN Waiver Tracker: $($changedGroups.Count) weekly division summary message(s) need creation or refresh."; $payloadEntries | ForEach-Object { Write-Output ($_.payload | ConvertTo-Json -Depth 12) } }
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
Set-StateProperty -State $state -Name version -Value 3

$createdCount = 0
$updatedCount = 0
$deletedCount = 0
foreach ($entry in $payloadEntries) {
  $group = $entry.group
  $savedGroup = Get-StateGroup -State $state -GroupKey $group.groupKey
  $messageId = Get-StringValue (Get-PropertyValue $savedGroup "messageId")
  $individualMessageIds = [System.Collections.Generic.List[string]]::new()
  if (-not $messageId -and $MigrateIndividualMessages) {
    foreach ($activity in $group.activities) {
      $savedTransaction = Get-PropertyValue (Get-PropertyValue $state "transactions") $activity.transactionId
      $savedTransactionMessageId = Get-StringValue (Get-PropertyValue $savedTransaction "messageId")
      if ($savedTransactionMessageId -and -not $individualMessageIds.Contains($savedTransactionMessageId)) {
        $individualMessageIds.Add($savedTransactionMessageId) | Out-Null
      }
    }
    if ($individualMessageIds.Count -gt 0) { $messageId = $individualMessageIds[0] }
  }

  if ($messageId) {
    $messageUri = "{0}/messages/{1}" -f $resolvedWebhookUrl.TrimEnd('/'), [uri]::EscapeDataString($messageId)
    $response = Invoke-DiscordPatch -Uri $messageUri -Payload $entry.payload
    $updatedCount++
  } else {
    $response = Invoke-DiscordPost -Uri (Get-WebhookUri -BaseUrl $resolvedWebhookUrl -Query @{ wait = "true" }) -Payload $entry.payload
    $messageId = Get-StringValue (Get-PropertyValue $response "id")
    if (-not $messageId) { throw "Discord did not return a message ID for waiver group '$($group.groupKey)'." }
    $createdCount++
  }

  foreach ($oldMessageId in @($individualMessageIds | Where-Object { $_ -ne $messageId })) {
    $deleteUri = "{0}/messages/{1}" -f $resolvedWebhookUrl.TrimEnd('/'), [uri]::EscapeDataString($oldMessageId)
    Invoke-DiscordDelete -Uri $deleteUri
    $deletedCount++
  }
  foreach ($activity in $group.activities) { Add-StateTransaction -State $state -Activity $activity -MessageId $messageId -Disposition "included-in-weekly-summary" }
  Set-StateGroup -State $state -Group $group -MessageId $messageId -Signature $group.signature
  Save-StateRoot -Path $StatePath -State $state
}

$validGroupKeys = @($activityGroups | ForEach-Object { $_.groupKey })
$stateGroups = Get-PropertyValue $state "groups"
foreach ($property in @($stateGroups.PSObject.Properties)) {
  if ($property.Name -notin $validGroupKeys) { $stateGroups.PSObject.Properties.Remove($property.Name) }
}
Save-StateRoot -Path $StatePath -State $state

$result = [pscustomobject]@{ action = "updated"; configuredLeagues = $configuredIds.Count; transactionsFound = $allActivities.Count; newTransactions = $newActivities.Count; weeklySummaries = $activityGroups.Count; createdSummaries = $createdCount; updatedSummaries = $updatedCount; removedIndividualMessages = $deletedCount; deferredSummaries = [math]::Max($changedGroups.Count - $queuedGroups.Count, 0); channelId = $channelId }
if ($PassThru) { $result } else { Write-Host "Waiver tracker created $createdCount and updated $updatedCount weekly division summary message(s); removed $deletedCount superseded individual posts." }
