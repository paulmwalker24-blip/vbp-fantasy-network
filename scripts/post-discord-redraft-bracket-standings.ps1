param(
  [string]$LedgerPath = "data/bracket-ledger.json",
  [string]$ConfigPath = "data/discord-redraft-bracket-standings-config.json",
  [string]$StatePath = "data/discord-redraft-bracket-standings-state.json",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_REDRAFT_BRACKET_STANDINGS,
  [switch]$ForceRefresh,
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

function Get-DoubleValue {
  param([AllowNull()][object]$Value)
  $parsed = 0.0
  if ([double]::TryParse((Get-StringValue $Value), [ref]$parsed)) { return $parsed }
  return 0.0
}

function Get-CentralTime {
  $zone = $null
  foreach ($zoneId in @("America/Chicago", "Central Standard Time")) {
    try {
      $zone = [System.TimeZoneInfo]::FindSystemTimeZoneById($zoneId)
      break
    } catch {
      continue
    }
  }
  if ($null -eq $zone) { throw "Could not resolve the America/Chicago time zone." }
  return [System.TimeZoneInfo]::ConvertTime([datetimeoffset]::UtcNow, $zone)
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

function Get-EntryKey {
  param([AllowNull()][object]$Entry)

  if ($null -eq $Entry) { return "" }
  return "{0}:{1}:{2}" -f `
    (Get-StringValue (Get-PropertyValue $Entry "leagueRecordId")), `
    (Get-StringValue (Get-PropertyValue $Entry "ownerId")), `
    (Get-StringValue (Get-PropertyValue $Entry "rosterId"))
}

function Get-RecordGames {
  param([AllowNull()][object]$Record)

  $parts = @((Get-StringValue $Record) -split '-')
  $games = 0
  foreach ($part in $parts) { $games += Get-IntValue $part }
  return $games
}

function Get-TeamDisplayName {
  param([AllowNull()][object]$Entry)

  $teamName = Convert-ToPlainDiscordText (Get-PropertyValue $Entry "teamName") 30
  if ($teamName) { return $teamName }
  $displayName = Convert-ToPlainDiscordText (Get-PropertyValue $Entry "displayName") 30
  if ($displayName) { return $displayName }
  return "Unknown Team"
}

function Get-StateRoot {
  param([string]$Path)

  if (Test-Path -LiteralPath $Path) {
    $loaded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -ne $loaded) {
      if (-not $loaded.PSObject.Properties["messages"]) {
        $loaded | Add-Member -NotePropertyName messages -NotePropertyValue ([pscustomobject]@{})
      }
      return $loaded
    }
  }

  return [pscustomobject]@{
    version = 1
    channelId = ""
    webhookId = ""
    groupId = ""
    snapshotKey = ""
    signature = ""
    hasPublishedStandings = $false
    messages = [pscustomobject]@{}
    updatedAt = ""
  }
}

function Save-StateRoot {
  param(
    [string]$Path,
    [object]$State
  )

  $State.updatedAt = [datetimeoffset]::UtcNow.ToString("o")
  $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path
}

function Get-StateMessageId {
  param(
    [object]$State,
    [string]$Key
  )

  $entry = Get-PropertyValue (Get-PropertyValue $State "messages") $Key
  return Get-StringValue (Get-PropertyValue $entry "messageId")
}

function Set-StateMessage {
  param(
    [object]$State,
    [string]$Key,
    [string]$MessageId
  )

  $entry = [pscustomobject]@{
    messageId = $MessageId
    updatedAt = [datetimeoffset]::UtcNow.ToString("o")
  }
  $messages = Get-PropertyValue $State "messages"
  if ($messages.PSObject.Properties[$Key]) {
    $messages.$Key = $entry
  } else {
    $messages | Add-Member -NotePropertyName $Key -NotePropertyValue $entry
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

function Invoke-DiscordJson {
  param(
    [string]$Uri,
    [object]$Payload,
    [ValidateSet("Post", "Patch")][string]$Method = "Post"
  )

  $body = $Payload | ConvertTo-Json -Depth 12 -Compress
  foreach ($attempt in 1..4) {
    try {
      return Invoke-RestMethod -Uri $Uri -Method $Method -ContentType "application/json" -Body $body
    } catch {
      $statusCode = 0
      $responseBody = ""
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      }
      if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace([string]$_.ErrorDetails.Message)) {
        $responseBody = [string]$_.ErrorDetails.Message
      }

      if ($attempt -ge 4 -or ($statusCode -ne 429 -and $statusCode -lt 500)) {
        if ($responseBody) { throw ("Discord request failed with HTTP {0}: {1}" -f $statusCode, $responseBody) }
        throw
      }

      $delaySeconds = [math]::Min([math]::Pow(2, $attempt), 30)
      if ($statusCode -eq 429 -and $_.Exception.Response.Headers) {
        $retryAfter = Get-StringValue $_.Exception.Response.Headers["Retry-After"]
        $parsedDelay = 0.0
        if ([double]::TryParse($retryAfter, [ref]$parsedDelay)) {
          $delaySeconds = [math]::Min([math]::Max([math]::Ceiling($parsedDelay), 1), 30)
        }
      }
      Start-Sleep -Seconds $delaySeconds
    }
  }
}

function Invoke-DiscordGet {
  param([string]$Uri)

  foreach ($attempt in 1..4) {
    try {
      return Invoke-RestMethod -Uri $Uri
    } catch {
      $statusCode = 0
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      }
      if ($attempt -ge 4 -or ($statusCode -ne 429 -and $statusCode -lt 500)) { throw }

      $delaySeconds = [math]::Min([math]::Pow(2, $attempt), 30)
      if ($statusCode -eq 429 -and $_.Exception.Response.Headers) {
        $retryAfter = Get-StringValue $_.Exception.Response.Headers["Retry-After"]
        $parsedDelay = 0.0
        if ([double]::TryParse($retryAfter, [ref]$parsedDelay)) {
          $delaySeconds = [math]::Min([math]::Max([math]::Ceiling($parsedDelay), 1), 30)
        }
      }
      Start-Sleep -Seconds $delaySeconds
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

function Get-Sha256 {
  param([string]$Value)

  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return (($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join '')
  } finally {
    $algorithm.Dispose()
  }
}

function Assert-EmbedLimits {
  param([object]$Embed)

  $title = Get-StringValue (Get-PropertyValue $Embed "title")
  $description = Get-StringValue (Get-PropertyValue $Embed "description")
  if ($title.Length -gt 256) { throw "Discord embed title exceeds 256 characters." }
  if ($description.Length -gt 4096) { throw "Discord embed description exceeds 4096 characters." }

  $total = $title.Length + $description.Length
  foreach ($field in @(Get-PropertyValue $Embed "fields")) {
    $name = Get-StringValue (Get-PropertyValue $field "name")
    $value = Get-StringValue (Get-PropertyValue $field "value")
    if ($name.Length -gt 256) { throw "Discord embed field name exceeds 256 characters." }
    if ($value.Length -gt 1024) { throw "Discord embed field value exceeds 1024 characters." }
    $total += $name.Length + $value.Length
  }
  $footer = Get-PropertyValue $Embed "footer"
  $total += (Get-StringValue (Get-PropertyValue $footer "text")).Length
  if ($total -gt 6000) { throw "Discord embed text exceeds the 6000-character message limit." }
}

function New-DiscordPayload {
  param([object]$Embed)

  Assert-EmbedLimits -Embed $Embed
  return @{
    username = "VBP Bracket Standings"
    allowed_mentions = @{ parse = @() }
    embeds = @($Embed)
  }
}

if (-not (Test-Path -LiteralPath $LedgerPath)) { throw "Could not find bracket ledger at '$LedgerPath'." }
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Could not find standings config at '$ConfigPath'." }

$ledger = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$groupId = Get-StringValue $config.groupId
$channelId = Get-StringValue $config.channelId
$websiteUrl = Get-StringValue $config.websiteUrl
$expectedLeagueIds = @($config.leagueRecordIds | ForEach-Object { (Get-StringValue $_).ToUpperInvariant() })
$expectedTeamCount = Get-IntValue $config.expectedTeamCount

if ($channelId -notmatch '^\d+$') { throw "Standings channelId must be numeric." }
if ($expectedLeagueIds.Count -eq 0) { throw "Standings config must include leagueRecordIds." }
if ($expectedTeamCount -le 0) { throw "Standings config must include a positive expectedTeamCount." }

$group = @($ledger.groups | Where-Object { (Get-StringValue $_.groupId) -eq $groupId } | Select-Object -First 1)
if ($group.Count -eq 0) { throw "Could not find bracket group '$groupId' in '$LedgerPath'." }
$group = $group[0]

$snapshots = @($group.leagueSnapshots)
$actualLeagueIds = @($snapshots | ForEach-Object { (Get-StringValue $_.leagueRecordId).ToUpperInvariant() } | Sort-Object -Unique)
$missingLeagueIds = @($expectedLeagueIds | Where-Object { $actualLeagueIds -notcontains $_ })
$unexpectedLeagueIds = @($actualLeagueIds | Where-Object { $expectedLeagueIds -notcontains $_ })
if ($missingLeagueIds.Count -gt 0 -or $unexpectedLeagueIds.Count -gt 0 -or $snapshots.Count -ne $expectedLeagueIds.Count) {
  throw "The refreshed bracket ledger does not contain exactly the five configured divisions. Existing Discord standings were left untouched."
}

foreach ($snapshot in $snapshots) {
  if (@($snapshot.standings).Count -ne 12) {
    throw ("{0} does not contain exactly 12 tracked teams. Existing Discord standings were left untouched." -f (Get-StringValue $snapshot.localLeagueName))
  }
}

$overallStandings = @($group.overallStandings | Sort-Object { Get-IntValue $_.rank })
if ($overallStandings.Count -ne $expectedTeamCount) {
  throw "The refreshed bracket ledger contains $($overallStandings.Count) teams instead of $expectedTeamCount. Existing Discord standings were left untouched."
}

$recordGameCounts = @($overallStandings | ForEach-Object { Get-RecordGames $_.record } | Sort-Object -Unique)
$completedWeek = if ($recordGameCounts.Count -eq 1) { [int]$recordGameCounts[0] } else { 0 }
$hasMeaningfulStandings = @($overallStandings | Where-Object {
  (Get-RecordGames $_.record) -gt 0 -or (Get-DoubleValue $_.pointsFor) -gt 0
}).Count -gt 0
$seasonDataReady = [bool](Get-PropertyValue $group "seasonDataReady")
$seedingReady = [bool](Get-PropertyValue $group "seedingReady")
$standingsReady = $seasonDataReady -and $seedingReady -and $hasMeaningfulStandings
$state = Get-StateRoot -Path $StatePath
$hasPublishedStandings = [bool](Get-PropertyValue $state "hasPublishedStandings")
if (-not $standingsReady -and $hasPublishedStandings) {
  throw "The refreshed ledger is not ready, so the last known good Discord standings were preserved."
}

$centralNow = Get-CentralTime
$snapshotKey = $centralNow.ToString("yyyy-MM-dd")
$timestamp = [datetimeoffset]::UtcNow.ToString("o")
$groupLabel = Convert-ToPlainDiscordText (Get-PropertyValue $group "label") 80
if (-not $groupLabel) { $groupLabel = "VBP Redraft Bracket" }

$divisionWinnerKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$playoffSeedByKey = @{}
foreach ($seedEntry in @($group.divisionWinners)) {
  [void]$divisionWinnerKeys.Add((Get-EntryKey $seedEntry.team))
}
foreach ($seedEntry in @($group.playoffField)) {
  $key = Get-EntryKey $seedEntry.team
  if ($key) { $playoffSeedByKey[$key] = Get-IntValue $seedEntry.seed }
}

$divisionCounts = @{}
foreach ($leagueId in $expectedLeagueIds) { $divisionCounts[$leagueId] = 0 }
foreach ($seedEntry in @($group.playoffField)) {
  $leagueId = (Get-StringValue $seedEntry.team.leagueRecordId).ToUpperInvariant()
  if ($divisionCounts.ContainsKey($leagueId)) { $divisionCounts[$leagueId]++ }
}

$snapshotById = @{}
foreach ($snapshot in $snapshots) {
  $snapshotById[(Get-StringValue $snapshot.leagueRecordId).ToUpperInvariant()] = $snapshot
}

$payloadEntries = [System.Collections.Generic.List[object]]::new()
$overviewDescription = if ($standingsReady) {
  $periodLabel = if ($completedWeek -gt 0) { "through Week $completedWeek" } else { "for the Tuesday snapshot dated $($centralNow.ToString('MMMM d, yyyy'))" }
  "Official combined standings $periodLabel. Rankings use record first, followed by points for to two decimals."
} else {
  "The official combined 1-60 standings will activate after Sleeper records completed regular-season games across all five divisions. This card updates automatically every Tuesday at 1:00 AM Central."
}

$overviewFields = [System.Collections.Generic.List[object]]::new()
$overviewFields.Add(@{
  name = "Snapshot"
  value = if ($standingsReady) {
    "$expectedTeamCount teams tracked across five divisions.`nUpdated $($centralNow.ToString('dddd, MMMM d, yyyy h:mm tt')) CT."
  } else {
    "$expectedTeamCount teams are configured across five divisions.`nCurrent status: preseason standings are not live yet."
  }
  inline = $false
}) | Out-Null

if ($standingsReady) {
  $representationLines = @($expectedLeagueIds | ForEach-Object {
    $snapshot = $snapshotById[$_]
    "$(Convert-ToPlainDiscordText $snapshot.localLeagueName 24): $($divisionCounts[$_]) projected playoff teams"
  })
  $overviewFields.Add(@{
    name = "Projected Playoff Field"
    value = "Seeds 1-5: division leaders`nSeeds 6-30: record and points qualifiers`nSeeds 31-32: points-for wild cards"
    inline = $false
  }) | Out-Null
  $overviewFields.Add(@{
    name = "Division Representation"
    value = ($representationLines -join "`n")
    inline = $false
  }) | Out-Null

  $cutLineSeeds = @($group.playoffField | Where-Object { (Get-IntValue $_.seed) -in @(30, 31, 32) } | Sort-Object { Get-IntValue $_.seed })
  $cutLineLines = @($cutLineSeeds | ForEach-Object {
    $seed = Get-IntValue $_.seed
    $team = $_.team
    $label = if ($seed -eq 30) { "Seed 30 - last direct qualifier" } else { "Seed $seed - wild card" }
    "${label}: $(Get-TeamDisplayName $team) - $(Convert-ToPlainDiscordText $team.localLeagueName 18) - $($team.wins)-$($team.losses)-$($team.ties) - $('{0:N2}' -f (Get-DoubleValue $team.pointsFor)) PF"
  })
  $nextWildCardTeam = @($group.bubbleTeams | Select-Object -First 1)
  if ($nextWildCardTeam.Count -gt 0) {
    $team = $nextWildCardTeam[0]
    $cutLineLines += "Next wild-card team: $(Get-TeamDisplayName $team) - $(Convert-ToPlainDiscordText $team.localLeagueName 18) - $($team.wins)-$($team.losses)-$($team.ties) - $('{0:N2}' -f (Get-DoubleValue $team.pointsFor)) PF"
  }
  $overviewFields.Add(@{
    name = "Current Cut Line"
    value = ($cutLineLines -join "`n")
    inline = $false
  }) | Out-Null
} else {
  $statusLines = @($expectedLeagueIds | ForEach-Object {
    $snapshot = $snapshotById[$_]
    $status = Convert-ToPlainDiscordText $snapshot.status 24
    if (-not $status) { $status = "waiting" }
    "$(Convert-ToPlainDiscordText $snapshot.localLeagueName 24): $status"
  })
  $overviewFields.Add(@{
    name = "Division Status"
    value = ($statusLines -join "`n")
    inline = $false
  }) | Out-Null
}

$overviewEmbed = @{
  title = "Redraft Bracket - Weekly Standings"
  url = $websiteUrl
  description = $overviewDescription
  color = if ($standingsReady) { 0xC0392B } else { 0x5865F2 }
  fields = @($overviewFields)
  footer = @{ text = if ($standingsReady) { "Projected positions are current, not clinched, until officially locked." } else { "No sample or placeholder rankings are published to Discord." } }
  timestamp = $timestamp
}
$payloadEntries.Add([pscustomobject]@{ key = "overview"; payload = (New-DiscordPayload $overviewEmbed) }) | Out-Null

if ($standingsReady) {
  foreach ($range in @(
    @{ key = "ranks-1-20"; start = 1; end = 20 },
    @{ key = "ranks-21-40"; start = 21; end = 40 },
    @{ key = "ranks-41-60"; start = 41; end = 60 }
  )) {
    $lines = @($overallStandings | Where-Object {
      (Get-IntValue $_.rank) -ge $range.start -and (Get-IntValue $_.rank) -le $range.end
    } | ForEach-Object {
      $rank = Get-IntValue $_.rank
      $key = Get-EntryKey $_
      $status = if ($divisionWinnerKeys.Contains($key)) {
        "Division Leader"
      } elseif ($playoffSeedByKey.ContainsKey($key) -and [int]$playoffSeedByKey[$key] -le 30) {
        "In"
      } elseif ($playoffSeedByKey.ContainsKey($key)) {
        "Wild Card"
      } else {
        "Out"
      }
      "{0:D2}. {1} - {2} - {3} - {4:N2} PF - {5}" -f `
        $rank, `
        (Get-TeamDisplayName $_), `
        (Convert-ToPlainDiscordText $_.leagueName 18), `
        (Convert-ToPlainDiscordText $_.record 12), `
        (Get-DoubleValue $_.pointsFor), `
        $status
    })

    $rangeEmbed = @{
      title = "Combined Standings - Ranks $($range.start)-$($range.end)"
      url = $websiteUrl
      description = ($lines -join "`n")
      color = if ($range.start -eq 1) { 0xC0392B } elseif ($range.start -eq 21) { 0xF39C12 } else { 0x7F8C8D }
      footer = @{ text = "Record is the first tiebreaker; points for is shown to two decimals." }
      timestamp = $timestamp
    }
    $payloadEntries.Add([pscustomobject]@{ key = $range.key; payload = (New-DiscordPayload $rangeEmbed) }) | Out-Null
  }
}

$signatureSource = [pscustomobject]@{
  snapshotKey = $snapshotKey
  standingsReady = $standingsReady
  completedWeek = $completedWeek
  rows = @($overallStandings | ForEach-Object {
    [pscustomobject]@{
      rank = Get-IntValue $_.rank
      teamName = Get-StringValue $_.teamName
      leagueRecordId = Get-StringValue $_.leagueRecordId
      record = Get-StringValue $_.record
      pointsFor = Get-DoubleValue $_.pointsFor
    }
  })
}
$signature = Get-Sha256 ($signatureSource | ConvertTo-Json -Depth 6 -Compress)
$requiredMessageKeys = @($payloadEntries | ForEach-Object { $_.key })
$allMessagesExist = @($requiredMessageKeys | Where-Object { [string]::IsNullOrWhiteSpace((Get-StateMessageId -State $state -Key $_)) }).Count -eq 0

if (-not $ForceRefresh -and $allMessagesExist -and (Get-StringValue $state.signature) -eq $signature) {
  $result = [pscustomobject]@{
    action = "current"
    standingsReady = $standingsReady
    completedWeek = $completedWeek
    snapshotKey = $snapshotKey
    messageCount = $requiredMessageKeys.Count
    payloads = @($payloadEntries)
  }
  if ($PassThru) { $result } else { Write-Host "Redraft Bracket standings are already current for $snapshotKey." }
  exit 0
}

if ($DryRun) {
  $result = [pscustomobject]@{
    action = "dry-run"
    standingsReady = $standingsReady
    completedWeek = $completedWeek
    snapshotKey = $snapshotKey
    messageCount = $requiredMessageKeys.Count
    payloads = @($payloadEntries)
  }
  if ($PassThru) { $result } else {
    Write-Host ("DRY RUN Redraft Bracket standings: {0} message(s); standings ready: {1}; completed week: {2}." -f $requiredMessageKeys.Count, $standingsReady, $completedWeek)
    $payloadEntries | ForEach-Object { Write-Output ($_.payload | ConvertTo-Json -Depth 12) }
  }
  exit 0
}

if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { throw "DISCORD_WEBHOOK_REDRAFT_BRACKET_STANDINGS is not configured." }
$webhookInfo = Invoke-DiscordGet -Uri $WebhookUrl
$webhookChannelId = Get-StringValue $webhookInfo.channel_id
$webhookId = Get-StringValue $webhookInfo.id
if ($webhookChannelId -ne $channelId) {
  throw "The Redraft Bracket standings webhook points to channel '$webhookChannelId', not configured channel '$channelId'."
}
$savedWebhookId = Get-StringValue (Get-PropertyValue $state "webhookId")
if ($savedWebhookId -and $savedWebhookId -ne $webhookId) {
  throw "The standings state belongs to a different Discord webhook. Clear the saved message state before intentionally replacing the webhook."
}

Set-StateProperty -State $state -Name channelId -Value $channelId
Set-StateProperty -State $state -Name webhookId -Value $webhookId
Set-StateProperty -State $state -Name groupId -Value $groupId

$createdCount = 0
$updatedCount = 0
foreach ($payloadEntry in $payloadEntries) {
  $key = Get-StringValue $payloadEntry.key
  $messageId = Get-StateMessageId -State $state -Key $key
  $created = $false

  if ($messageId) {
    try {
      Invoke-DiscordJson -Uri ("{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $messageId) -Payload $payloadEntry.payload -Method Patch | Out-Null
    } catch {
      if ($_.Exception.Message -notmatch 'HTTP 404') { throw }
      $messageId = ""
    }
  }

  if (-not $messageId) {
    $response = Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $WebhookUrl -Query @{ wait = "true" }) -Payload $payloadEntry.payload
    $messageId = Get-StringValue $response.id
    if (-not $messageId) { throw "Discord did not return a message ID for standings card '$key'." }
    $created = $true
  }

  Set-StateMessage -State $state -Key $key -MessageId $messageId
  Save-StateRoot -Path $StatePath -State $state
  if ($created) { $createdCount++ } else { $updatedCount++ }
}

Set-StateProperty -State $state -Name snapshotKey -Value $snapshotKey
Set-StateProperty -State $state -Name signature -Value $signature
if ($standingsReady) { Set-StateProperty -State $state -Name hasPublishedStandings -Value $true }
Save-StateRoot -Path $StatePath -State $state

$result = [pscustomobject]@{
  action = if ($createdCount -gt 0 -and $updatedCount -gt 0) { "created-and-updated" } elseif ($createdCount -gt 0) { "created" } else { "updated" }
  standingsReady = $standingsReady
  completedWeek = $completedWeek
  snapshotKey = $snapshotKey
  messageCount = $requiredMessageKeys.Count
  createdCount = $createdCount
  updatedCount = $updatedCount
  payloads = @($payloadEntries)
}

if ($PassThru) {
  $result
} else {
  Write-Host ("Redraft Bracket standings {0}: {1} message(s), Week {2}, snapshot {3}." -f $result.action, $result.messageCount, $completedWeek, $snapshotKey)
}
