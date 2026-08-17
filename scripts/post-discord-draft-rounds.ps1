param(
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$ConfigPath = "data/discord-draft-round-config.json",
  [string]$WebhookConfigPath = "",
  [string]$StatePath = "data/discord-draft-round-state.json",
  [string[]]$LeagueRecordIds = @(),
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_URL,
  [switch]$IncludeCompletedDrafts,
  [switch]$InitializeThreads,
  [switch]$ForceRefresh,
  [switch]$DryRun,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ObjectPropertyValue {
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

function Convert-ToFlatObjectArray {
  param([AllowNull()][object]$Value)

  if ($null -eq $Value) { return }
  foreach ($item in @($Value)) {
    if ($item -is [System.Array]) {
      foreach ($nestedItem in $item) { Write-Output $nestedItem }
    } else {
      Write-Output $item
    }
  }
}

function Escape-DiscordText {
  param([AllowNull()][object]$Value)

  $text = Get-StringValue $Value
  if ([string]::IsNullOrWhiteSpace($text)) { return "" }
  return ($text -replace '([\\`*_{}\[\]()<>#+\-.!|~>])', '\$1')
}

function Get-StateRoot {
  param([string]$Path)

  if (Test-Path -LiteralPath $Path) {
    $loaded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -ne $loaded) {
      if (-not $loaded.PSObject.Properties["leagues"]) {
        $loaded | Add-Member -NotePropertyName leagues -NotePropertyValue ([pscustomobject]@{})
      }
      return $loaded
    }
  }

  return [pscustomobject]@{
    version = 1
    updatedAt = ""
    leagues = [pscustomobject]@{}
  }
}

function Save-StateRoot {
  param(
    [string]$Path,
    [object]$State
  )

  $State.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
  }
  $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path
}

function New-LeagueState {
  param(
    [string]$LeagueRecordId,
    [string]$SleeperDraftId
  )

  return [pscustomobject]@{
    leagueRecordId = $LeagueRecordId
    sleeperDraftId = $SleeperDraftId
    webhookId = ""
    threadId = ""
    starterMessageId = ""
    threadMode = ""
    threadReady = $false
    displayMode = ""
    teamMessages = [pscustomobject]@{}
    postedRounds = @()
    finalPosted = $false
    updatedAt = ""
  }
}

function Get-LeagueWebhookUrl {
  param(
    [string]$LeagueRecordId,
    [object]$Config,
    [AllowNull()][object]$PrivateWebhookConfig,
    [string]$DefaultWebhookUrl
  )

  $destinations = Get-ObjectPropertyValue $Config "leagueDestinations"
  $destination = Get-ObjectPropertyValue $destinations $LeagueRecordId
  if ($null -ne $destination) {
    $environmentName = Get-StringValue (Get-ObjectPropertyValue $destination "webhookEnv")
    if (-not [string]::IsNullOrWhiteSpace($environmentName)) {
      $environmentUrl = Get-StringValue ([Environment]::GetEnvironmentVariable($environmentName))
      if (-not [string]::IsNullOrWhiteSpace($environmentUrl)) { return $environmentUrl }
    }

    $privateKey = Get-StringValue (Get-ObjectPropertyValue $destination "webhookKey")
    $privateChannels = Get-ObjectPropertyValue $PrivateWebhookConfig "channels"
    if (-not [string]::IsNullOrWhiteSpace($privateKey) -and $null -ne $privateChannels) {
      $privateUrl = Get-StringValue (Get-ObjectPropertyValue $privateChannels $privateKey)
      if (-not [string]::IsNullOrWhiteSpace($privateUrl)) { return $privateUrl }
    }
  }

  return (Get-StringValue $DefaultWebhookUrl)
}

function Set-LeagueState {
  param(
    [object]$State,
    [string]$LeagueRecordId,
    [object]$LeagueState
  )

  if ($State.leagues.PSObject.Properties[$LeagueRecordId]) {
    $State.leagues.$LeagueRecordId = $LeagueState
  } else {
    $State.leagues | Add-Member -NotePropertyName $LeagueRecordId -NotePropertyValue $LeagueState
  }
}

function Get-TeamMessageState {
  param(
    [object]$LeagueState,
    [string]$TeamKey
  )

  $teamMessages = Get-ObjectPropertyValue $LeagueState "teamMessages"
  if ($null -eq $teamMessages) { return $null }
  return Get-ObjectPropertyValue $teamMessages $TeamKey
}

function Set-TeamMessageState {
  param(
    [object]$LeagueState,
    [string]$TeamKey,
    [string]$MessageId
  )

  $teamMessages = Get-ObjectPropertyValue $LeagueState "teamMessages"
  if ($null -eq $teamMessages) {
    $teamMessages = [pscustomobject]@{}
    if ($LeagueState.PSObject.Properties["teamMessages"]) {
      $LeagueState.teamMessages = $teamMessages
    } else {
      $LeagueState | Add-Member -NotePropertyName teamMessages -NotePropertyValue $teamMessages
    }
  }

  $entry = [pscustomobject]@{
    messageId = $MessageId
    updatedAt = (Get-Date).ToUniversalTime().ToString("o")
  }
  if ($teamMessages.PSObject.Properties[$TeamKey]) {
    $teamMessages.$TeamKey = $entry
  } else {
    $teamMessages | Add-Member -MemberType NoteProperty -Name ([string]$TeamKey) -Value $entry
  }
}

function Invoke-SleeperJson {
  param([string]$Uri)
  return Invoke-RestMethod -Uri $Uri
}

function Invoke-DiscordJson {
  param(
    [string]$Uri,
    [object]$Payload,
    [ValidateSet("Post", "Patch")]
    [string]$Method = "Post"
  )

  $body = $Payload | ConvertTo-Json -Depth 12 -Compress
  $attempt = 0
  while ($attempt -lt 4) {
    $attempt++
    try {
      return Invoke-RestMethod -Uri $Uri -Method $Method -ContentType "application/json" -Body $body
    } catch {
      $statusCode = 0
      $responseBody = ""
      if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace([string]$_.ErrorDetails.Message)) {
        $responseBody = [string]$_.ErrorDetails.Message
      }
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      }

      if ([string]::IsNullOrWhiteSpace($responseBody) -and $_.Exception.Response) {
        try {
          $responseStream = $_.Exception.Response.GetResponseStream()
          if ($responseStream) {
            $reader = New-Object System.IO.StreamReader($responseStream)
            $responseBody = $reader.ReadToEnd()
            $reader.Dispose()
          }
        } catch {
          $responseBody = ""
        }
      }

      if ($attempt -ge 4 -or ($statusCode -ne 429 -and $statusCode -lt 500)) {
        if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
          throw ("Discord request failed with HTTP {0}: {1}" -f $statusCode, $responseBody)
        }
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

      if ($attempt -ge 4 -and -not [string]::IsNullOrWhiteSpace($responseBody)) {
        throw ("Discord request failed with HTTP {0}: {1}" -f $statusCode, $responseBody)
      }
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
  $separator = if ($BaseUrl.Contains("?")) { "&" } else { "?" }
  return ("{0}{1}{2}" -f $BaseUrl.TrimEnd('/'), $separator, ($pairs -join "&"))
}

function Get-LatestDraft {
  param(
    [object[]]$Drafts,
    [string]$Season
  )

  $seasonDrafts = @($Drafts | Where-Object {
    [string]::IsNullOrWhiteSpace($Season) -or (Get-StringValue $_.season) -eq $Season
  })
  if ($seasonDrafts.Count -eq 0) { $seasonDrafts = @($Drafts) }
  return @($seasonDrafts | Sort-Object { [double](Get-ObjectPropertyValue $_ "created") } -Descending | Select-Object -First 1)[0]
}

function Get-ExpectedTeamCount {
  param(
    [object]$Draft,
    [object]$League
  )

  $settings = Get-ObjectPropertyValue $Draft "settings"
  $teams = Get-IntValue (Get-ObjectPropertyValue $settings "teams")
  if ($teams -le 0) { $teams = Get-IntValue (Get-ObjectPropertyValue $League "total_rosters") }
  return $teams
}

function Get-CompletedRounds {
  param(
    [object[]]$Picks,
    [int]$TeamCount,
    [int]$RoundCount
  )

  $completed = [System.Collections.Generic.List[int]]::new()
  if ($TeamCount -le 0) { return @() }

  for ($round = 1; $round -le $RoundCount; $round++) {
    $roundPicks = @($Picks | Where-Object {
      (Get-IntValue $_.round) -eq $round -and -not [string]::IsNullOrWhiteSpace((Get-StringValue $_.player_id))
    })
    $uniquePickCount = @($roundPicks | Select-Object -ExpandProperty pick_no -Unique).Count
    if ($uniquePickCount -lt $TeamCount) { break }
    $completed.Add($round) | Out-Null
  }

  return @($completed)
}

function Get-TeamDisplayName {
  param(
    [AllowNull()][object]$User,
    [AllowNull()][object]$Roster
  )

  $userMetadata = Get-ObjectPropertyValue $User "metadata"
  $rosterMetadata = Get-ObjectPropertyValue $Roster "metadata"
  $candidates = @(
    (Get-ObjectPropertyValue $userMetadata "team_name"),
    (Get-ObjectPropertyValue $rosterMetadata "team_name"),
    (Get-ObjectPropertyValue $User "display_name"),
    (Get-ObjectPropertyValue $User "username")
  )

  foreach ($candidate in $candidates) {
    $text = Get-StringValue $candidate
    if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
  }
  return "Unassigned Team"
}

function Get-TeamMaps {
  param(
    [string]$SleeperLeagueId,
    [object[]]$Users,
    [object[]]$Rosters
  )

  $usersById = @{}
  foreach ($user in $Users) {
    $userId = Get-StringValue $user.user_id
    if ($userId) { $usersById[$userId] = $user }
  }

  $byUserId = @{}
  $byRosterId = @{}
  foreach ($roster in $Rosters) {
    $ownerId = Get-StringValue $roster.owner_id
    $rosterId = Get-StringValue $roster.roster_id
    $user = if ($ownerId -and $usersById.ContainsKey($ownerId)) { $usersById[$ownerId] } else { $null }
    $displayName = Get-TeamDisplayName -User $user -Roster $roster
    if ($ownerId) { $byUserId[$ownerId] = $displayName }
    if ($rosterId) { $byRosterId[$rosterId] = $displayName }
  }

  foreach ($user in $Users) {
    $userId = Get-StringValue $user.user_id
    if ($userId -and -not $byUserId.ContainsKey($userId)) {
      $byUserId[$userId] = Get-TeamDisplayName -User $user -Roster $null
    }
  }

  return [pscustomobject]@{
    byUserId = $byUserId
    byRosterId = $byRosterId
  }
}

function Get-PickTeamName {
  param(
    [object]$Pick,
    [object]$TeamMaps
  )

  $rosterId = Get-StringValue $Pick.roster_id
  if ($rosterId -and $TeamMaps.byRosterId.ContainsKey($rosterId)) {
    return [string]$TeamMaps.byRosterId[$rosterId]
  }

  $pickedBy = Get-StringValue $Pick.picked_by
  if ($pickedBy -and $TeamMaps.byUserId.ContainsKey($pickedBy)) {
    return [string]$TeamMaps.byUserId[$pickedBy]
  }

  return "Unassigned Team"
}

function Get-PlayerLabel {
  param([object]$Pick)

  $metadata = Get-ObjectPropertyValue $Pick "metadata"
  $firstName = Get-StringValue (Get-ObjectPropertyValue $metadata "first_name")
  $lastName = Get-StringValue (Get-ObjectPropertyValue $metadata "last_name")
  $playerName = ("{0} {1}" -f $firstName, $lastName).Trim()
  if ([string]::IsNullOrWhiteSpace($playerName)) { $playerName = Get-StringValue $Pick.player_id }

  $details = @(
    (Get-StringValue (Get-ObjectPropertyValue $metadata "position")),
    (Get-StringValue (Get-ObjectPropertyValue $metadata "team"))
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  if (@($details).Count -gt 0) {
    return ("{0} ({1})" -f $playerName, ($details -join " | "))
  }
  return $playerName
}

function Split-DiscordLines {
  param(
    [string[]]$Lines,
    [int]$Limit = 3800
  )

  $chunks = [System.Collections.Generic.List[string]]::new()
  $current = [System.Collections.Generic.List[string]]::new()
  $currentLength = 0

  foreach ($line in $Lines) {
    $addition = if ($current.Count -eq 0) { $line.Length } else { $line.Length + 1 }
    if ($current.Count -gt 0 -and ($currentLength + $addition) -gt $Limit) {
      $chunks.Add(($current -join "`n")) | Out-Null
      $current = [System.Collections.Generic.List[string]]::new()
      $currentLength = 0
    }
    $current.Add($line) | Out-Null
    $currentLength += if ($current.Count -eq 1) { $line.Length } else { $line.Length + 1 }
  }

  if ($current.Count -gt 0) { $chunks.Add(($current -join "`n")) | Out-Null }
  return @($chunks)
}

function New-ThreadStarterPayload {
  param(
    [object]$LeagueRecord,
    [object]$Draft,
    [int]$TeamCount,
    [int]$RoundCount
  )

  $leagueName = Get-StringValue $LeagueRecord.name
  $leagueRecordId = Get-StringValue $LeagueRecord.id
  $season = Get-StringValue $Draft.season
  $draftType = Get-StringValue $Draft.type
  $draftId = Get-StringValue $Draft.draft_id
  $threadName = ("{0} - {1} - {2} Draft" -f $leagueRecordId, $leagueName, $season)
  if ($threadName.Length -gt 100) { $threadName = $threadName.Substring(0, 100) }

  return @{
    username = "VBP Draft Tracker"
    content = ("Draft updates for **{0}** will appear here after each full round is completed." -f (Escape-DiscordText $leagueName))
    thread_name = $threadName
    allowed_mentions = @{ parse = @() }
    embeds = @(@{
      title = ("{0} Draft Tracker" -f $leagueName)
      url = ("https://sleeper.com/draft/nfl/{0}" -f $draftId)
      description = @(
        "**League:** $leagueRecordId",
        "**Season:** $season",
        "**Draft:** $draftType | $TeamCount teams | $RoundCount rounds",
        "",
        "Each completed round will list the round pick, overall pick, team, and selected player."
      ) -join "`n"
      color = 0x173B57
      footer = @{ text = "VBP Fantasy Network | Sleeper draft data" }
      timestamp = (Get-Date).ToUniversalTime().ToString("o")
    })
  }
}

function New-TextChannelStarterPayload {
  param(
    [object]$LeagueRecord,
    [object]$Draft,
    [int]$TeamCount,
    [int]$RoundCount
  )

  $payload = New-ThreadStarterPayload -LeagueRecord $LeagueRecord -Draft $Draft -TeamCount $TeamCount -RoundCount $RoundCount
  $payload.Remove("thread_name")
  $payload.content = @(
    $payload.content,
    "",
    "Create a public Discord thread from this message once. The automated round-by-round updates will begin inside that thread."
  ) -join "`n"
  return $payload
}

function New-ThreadConnectionPayload {
  param([object]$LeagueRecord)

  $leagueName = Escape-DiscordText (Get-StringValue $LeagueRecord.name)
  return @{
    username = "VBP Draft Tracker"
    content = "Draft tracker connected for **$leagueName**. Completed round summaries will follow automatically."
    allowed_mentions = @{ parse = @() }
  }
}

function New-RoundPayloads {
  param(
    [object]$LeagueRecord,
    [object]$Draft,
    [object[]]$RoundPicks,
    [object]$TeamMaps,
    [int]$Round,
    [int]$TeamCount
  )

  $leagueName = Get-StringValue $LeagueRecord.name
  $draftId = Get-StringValue $Draft.draft_id
  $lines = foreach ($pick in @($RoundPicks | Sort-Object { Get-IntValue $_.pick_no })) {
    $overallPick = Get-IntValue $pick.pick_no
    $roundPick = $overallPick - (($Round - 1) * $TeamCount)
    $pickLabel = "{0}.{1:D2} (#{2})" -f $Round, $roundPick, $overallPick
    $teamName = Escape-DiscordText (Get-PickTeamName -Pick $pick -TeamMaps $TeamMaps)
    $playerLabel = Escape-DiscordText (Get-PlayerLabel -Pick $pick)
    "**$pickLabel** - $teamName - $playerLabel"
  }

  $chunks = @(Split-DiscordLines -Lines @($lines))
  for ($index = 0; $index -lt $chunks.Count; $index++) {
    $embed = @{
      title = if ($index -eq 0) { "Round $Round Complete - $leagueName" } else { "Round $Round Complete - continued" }
      url = ("https://sleeper.com/draft/nfl/{0}" -f $draftId)
      description = $chunks[$index]
      color = 0x2F80ED
      footer = @{ text = "VBP Draft Tracker | Sleeper is the source of record" }
      timestamp = (Get-Date).ToUniversalTime().ToString("o")
    }
    Write-Output @{
      username = "VBP Draft Tracker"
      allowed_mentions = @{ parse = @() }
      embeds = @($embed)
    }
  }
}

function New-TeamPayload {
  param(
    [object]$LeagueRecord,
    [object]$Draft,
    [string]$TeamName,
    [object[]]$TeamPicks,
    [int]$TeamCount,
    [int]$RoundCount,
    [int]$CompletedRound,
    [string]$DraftStatus
  )

  $leagueName = Get-StringValue $LeagueRecord.name
  $draftId = Get-StringValue $Draft.draft_id
  $safeTeamName = Escape-DiscordText $TeamName
  $pickLines = foreach ($pick in @($TeamPicks | Sort-Object { Get-IntValue $_.pick_no })) {
    $round = Get-IntValue $pick.round
    $overallPick = Get-IntValue $pick.pick_no
    $roundPick = $overallPick - (($round - 1) * $TeamCount)
    $pickLabel = "{0}.{1:D2} (#{2})" -f $round, $roundPick, $overallPick
    $playerLabel = Escape-DiscordText (Get-PlayerLabel -Pick $pick)
    "**$pickLabel** - $playerLabel"
  }

  $selectionText = if (@($pickLines).Count -gt 0) {
    @($pickLines) -join "`n"
  } else {
    "No selections recorded yet."
  }

  $statusText = if ($DraftStatus -eq "complete") {
    "Draft complete"
  } else {
    "Round $CompletedRound complete"
  }

  $title = $safeTeamName
  if ([string]::IsNullOrWhiteSpace($title)) { $title = "Unassigned Team" }
  if ($title.Length -gt 256) { $title = $title.Substring(0, 256) }

  return @{
    username = "VBP Draft Tracker"
    allowed_mentions = @{ parse = @() }
    embeds = @(@{
      title = $title
      url = ("https://sleeper.com/draft/nfl/{0}" -f $draftId)
      description = @(
        "**Draft progress:** $(@($TeamPicks).Count)/$RoundCount selections",
        "**Status:** $statusText",
        "",
        "**Selections**",
        $selectionText
      ) -join "`n"
      color = if ($DraftStatus -eq "complete") { 0x27AE60 } else { 0x2F80ED }
      footer = @{ text = "$leagueName | Team draft card" }
      timestamp = (Get-Date).ToUniversalTime().ToString("o")
    })
  }
}

function New-FinalPayload {
  param(
    [object]$LeagueRecord,
    [object]$Draft,
    [int]$RoundCount,
    [int]$PickCount
  )

  $leagueName = Get-StringValue $LeagueRecord.name
  $draftId = Get-StringValue $Draft.draft_id
  return @{
    username = "VBP Draft Tracker"
    content = ""
    allowed_mentions = @{ parse = @() }
    embeds = @(@{
      title = "Draft Complete - $leagueName"
      url = ("https://sleeper.com/draft/nfl/{0}" -f $draftId)
      description = "$RoundCount rounds and $PickCount selections are complete. The full draft board remains available on Sleeper."
      color = 0x27AE60
      footer = @{ text = "VBP Draft Tracker | Final" }
      timestamp = (Get-Date).ToUniversalTime().ToString("o")
    })
  }
}

if (-not (Test-Path -LiteralPath $LeaguesJsonPath)) {
  throw "Could not find league data at '$LeaguesJsonPath'."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
  throw "Could not find Discord draft tracker config at '$ConfigPath'."
}
$leaguePayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $LeaguesJsonPath).Path -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ConfigPath).Path -Raw | ConvertFrom-Json
$privateWebhookConfig = $null
if (-not [string]::IsNullOrWhiteSpace($WebhookConfigPath)) {
  if (-not (Test-Path -LiteralPath $WebhookConfigPath)) {
    throw "Could not find private Discord webhook config at '$WebhookConfigPath'."
  }
  $privateWebhookConfig = Get-Content -LiteralPath (Resolve-Path -LiteralPath $WebhookConfigPath).Path -Raw | ConvertFrom-Json
}
$expectedChannelId = Get-StringValue (Get-ObjectPropertyValue $config "channelId")
$channelMode = (Get-StringValue (Get-ObjectPropertyValue $config "channelMode")).ToLowerInvariant()
$displayMode = (Get-StringValue (Get-ObjectPropertyValue $config "displayMode")).ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($expectedChannelId)) {
  throw "Discord draft tracker config must include channelId."
}
if ($expectedChannelId -notmatch '^\d+$') {
  throw "Discord draft tracker channelId must be numeric."
}
if ($channelMode -notin @("forum", "text")) {
  throw "Discord draft tracker channelMode must be 'forum' or 'text'."
}
if ($displayMode -notin @("rounds", "teams")) {
  throw "Discord draft tracker displayMode must be 'rounds' or 'teams'."
}
$wantedIds = @{}
foreach ($id in @($LeagueRecordIds | ForEach-Object { ([string]$_) -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
  $wantedIds[$id.ToUpperInvariant()] = $true
}
if ($wantedIds.Count -eq 0) {
  foreach ($configuredId in @(Get-ObjectPropertyValue $config "leagueRecordIds")) {
    $normalizedId = (Get-StringValue $configuredId).ToUpperInvariant()
    if (-not [string]::IsNullOrWhiteSpace($normalizedId)) { $wantedIds[$normalizedId] = $true }
  }
}

$leagueRecords = @($leaguePayload.leagues | Where-Object {
  $id = (Get-StringValue $_.id).ToUpperInvariant()
  $status = (Get-StringValue $_.status).ToLowerInvariant()
  $format = (Get-StringValue $_.format).ToLowerInvariant()
  -not [string]::IsNullOrWhiteSpace((Get-StringValue $_.sleeperLeagueId)) -and
  $status -notin @("coming-soon", "postponed") -and
  $format -ne "pickem" -and
  ($wantedIds.Count -eq 0 -or $wantedIds.ContainsKey($id))
})

$state = Get-StateRoot -Path $StatePath
$results = [System.Collections.Generic.List[object]]::new()

foreach ($leagueRecord in $leagueRecords) {
  $leagueRecordId = Get-StringValue $leagueRecord.id
  $sleeperLeagueId = Get-StringValue $leagueRecord.sleeperLeagueId
  $leagueName = Get-StringValue $leagueRecord.name

  try {
    $leagueWebhookUrl = Get-LeagueWebhookUrl -LeagueRecordId $leagueRecordId -Config $config -PrivateWebhookConfig $privateWebhookConfig -DefaultWebhookUrl $WebhookUrl
    $webhookId = ""
    if (-not $DryRun) {
      if ([string]::IsNullOrWhiteSpace($leagueWebhookUrl)) {
        throw "No Discord webhook is configured for $leagueRecordId."
      }
      $webhookInfo = Invoke-RestMethod -Uri $leagueWebhookUrl
      $webhookChannelId = Get-StringValue (Get-ObjectPropertyValue $webhookInfo "channel_id")
      $webhookId = Get-StringValue (Get-ObjectPropertyValue $webhookInfo "id")
      if ($webhookChannelId -ne $expectedChannelId) {
        throw "The $leagueRecordId Discord webhook points to channel '$webhookChannelId', not the expected League Updates channel '$expectedChannelId'."
      }
    }

    $drafts = @(Convert-ToFlatObjectArray -Value (Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}/drafts" -f $sleeperLeagueId)))
    if ($drafts.Count -eq 0) {
      $results.Add([pscustomobject]@{ leagueRecordId = $leagueRecordId; leagueName = $leagueName; status = "skipped"; reason = "No Sleeper draft exists"; postedRounds = @() }) | Out-Null
      continue
    }

    $draft = Get-LatestDraft -Drafts $drafts -Season (Get-StringValue $leagueRecord.sleeperSeason)
    $draftId = Get-StringValue $draft.draft_id
    $draftStatus = (Get-StringValue $draft.status).ToLowerInvariant()
    $existingState = Get-ObjectPropertyValue $state.leagues $leagueRecordId
    $isTrackedDraft = $null -ne $existingState -and (Get-StringValue $existingState.sleeperDraftId) -eq $draftId

    if ($draftStatus -eq "complete" -and -not $isTrackedDraft -and -not $IncludeCompletedDrafts) {
      $results.Add([pscustomobject]@{ leagueRecordId = $leagueRecordId; leagueName = $leagueName; status = "skipped"; reason = "Completed historical draft; use -IncludeCompletedDrafts to backfill"; postedRounds = @() }) | Out-Null
      continue
    }

    $picks = @(Convert-ToFlatObjectArray -Value (Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/draft/{0}/picks" -f $draftId)))
    if ($picks.Count -eq 0) {
      if ($InitializeThreads) {
        $liveLeague = Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}" -f $sleeperLeagueId)
        $teamCount = Get-ExpectedTeamCount -Draft $draft -League $liveLeague
        $roundCount = Get-IntValue (Get-ObjectPropertyValue (Get-ObjectPropertyValue $draft "settings") "rounds")
        $leagueState = $existingState
        if (-not $isTrackedDraft) {
          $leagueState = New-LeagueState -LeagueRecordId $leagueRecordId -SleeperDraftId $draftId
          $leagueState.webhookId = $webhookId
          $leagueState.threadMode = $channelMode
          $leagueState.displayMode = $displayMode
          Set-LeagueState -State $state -LeagueRecordId $leagueRecordId -LeagueState $leagueState
        }

        $threadId = Get-StringValue $leagueState.threadId
        if ([string]::IsNullOrWhiteSpace($threadId)) {
          if ($DryRun) {
            $results.Add([pscustomobject]@{ leagueRecordId = $leagueRecordId; leagueName = $leagueName; sleeperDraftId = $draftId; draftStatus = $draftStatus; status = "dry-run"; reason = "Draft thread starter would be initialized before the first pick"; postedRounds = @(); threadId = "dry-run-thread" }) | Out-Null
            continue
          }

          $starterPayload = if ($channelMode -eq "forum") {
            New-ThreadStarterPayload -LeagueRecord $leagueRecord -Draft $draft -TeamCount $teamCount -RoundCount $roundCount
          } else {
            New-TextChannelStarterPayload -LeagueRecord $leagueRecord -Draft $draft -TeamCount $teamCount -RoundCount $roundCount
          }
          $starterResponse = Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $leagueWebhookUrl -Query @{ wait = "true" }) -Payload $starterPayload
          $starterMessageId = Get-StringValue $starterResponse.id
          $threadId = if ($channelMode -eq "forum") { Get-StringValue $starterResponse.channel_id } else { $starterMessageId }
          if ([string]::IsNullOrWhiteSpace($threadId)) { throw "Discord did not return a thread or starter-message ID for $leagueRecordId." }
          $leagueState.threadId = $threadId
          $leagueState.starterMessageId = $starterMessageId
          $leagueState.threadMode = $channelMode
          $leagueState.threadReady = ($channelMode -eq "forum")
          $leagueState.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
          Save-StateRoot -Path $StatePath -State $state

          $results.Add([pscustomobject]@{ leagueRecordId = $leagueRecordId; leagueName = $leagueName; sleeperDraftId = $draftId; draftStatus = $draftStatus; status = if ($channelMode -eq "text") { "thread-action-required" } else { "waiting" }; reason = if ($channelMode -eq "text") { "Create a public Discord thread from the saved starter message; team cards begin after Round 1 is complete" } else { "Draft thread initialized; waiting for the first complete round" }; postedRounds = @(); threadId = $threadId }) | Out-Null
          continue
        }

        $threadReadyValue = Get-ObjectPropertyValue $leagueState "threadReady"
        $threadReady = if ($null -eq $threadReadyValue) { $channelMode -eq "forum" } else { [bool]$threadReadyValue }
        if ($channelMode -eq "text" -and -not $threadReady) {
          if ($DryRun) {
            $results.Add([pscustomobject]@{ leagueRecordId = $leagueRecordId; leagueName = $leagueName; sleeperDraftId = $draftId; draftStatus = $draftStatus; status = "dry-run"; reason = "Existing pre-draft thread would be connected"; postedRounds = @(); threadId = $threadId }) | Out-Null
            continue
          }

          $connectionPayload = New-ThreadConnectionPayload -LeagueRecord $leagueRecord
          Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $leagueWebhookUrl -Query @{ wait = "true"; thread_id = $threadId }) -Payload $connectionPayload | Out-Null
          $leagueState.threadReady = $true
          $leagueState.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
          Save-StateRoot -Path $StatePath -State $state
          $results.Add([pscustomobject]@{ leagueRecordId = $leagueRecordId; leagueName = $leagueName; sleeperDraftId = $draftId; draftStatus = $draftStatus; status = "waiting"; reason = "Draft thread connected; waiting for the first complete round"; postedRounds = @(); threadId = $threadId }) | Out-Null
          continue
        }
      }
      $results.Add([pscustomobject]@{ leagueRecordId = $leagueRecordId; leagueName = $leagueName; status = "waiting"; reason = "No picks made yet"; postedRounds = @() }) | Out-Null
      continue
    }

    $liveLeague = Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}" -f $sleeperLeagueId)
    $teamCount = Get-ExpectedTeamCount -Draft $draft -League $liveLeague
    $roundCount = Get-IntValue (Get-ObjectPropertyValue (Get-ObjectPropertyValue $draft "settings") "rounds")
    if ($roundCount -le 0) { $roundCount = Get-IntValue (@($picks | Measure-Object -Property round -Maximum).Maximum) }
    $completedRounds = @(Get-CompletedRounds -Picks $picks -TeamCount $teamCount -RoundCount $roundCount)
    if ($completedRounds.Count -eq 0) {
      $results.Add([pscustomobject]@{ leagueRecordId = $leagueRecordId; leagueName = $leagueName; status = "waiting"; reason = "Current round is not complete"; postedRounds = @() }) | Out-Null
      continue
    }

    $leagueState = $existingState
    if (-not $isTrackedDraft) {
      $leagueState = New-LeagueState -LeagueRecordId $leagueRecordId -SleeperDraftId $draftId
      $leagueState.webhookId = $webhookId
      $leagueState.threadMode = $channelMode
      $leagueState.displayMode = $displayMode
      Set-LeagueState -State $state -LeagueRecordId $leagueRecordId -LeagueState $leagueState
    } else {
      $savedWebhookId = Get-StringValue (Get-ObjectPropertyValue $leagueState "webhookId")
      if (-not $DryRun -and -not [string]::IsNullOrWhiteSpace($savedWebhookId) -and $savedWebhookId -ne $webhookId) {
        throw "$leagueRecordId is already tied to a different Discord webhook. Use the original division webhook so its team cards remain editable."
      }
      if (-not $DryRun -and [string]::IsNullOrWhiteSpace($savedWebhookId)) {
        if ($leagueState.PSObject.Properties["webhookId"]) {
          $leagueState.webhookId = $webhookId
        } else {
          $leagueState | Add-Member -NotePropertyName webhookId -NotePropertyValue $webhookId
        }
        $leagueState.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        Save-StateRoot -Path $StatePath -State $state
      }
      $savedDisplayMode = (Get-StringValue (Get-ObjectPropertyValue $leagueState "displayMode")).ToLowerInvariant()
      if ([string]::IsNullOrWhiteSpace($savedDisplayMode)) { $savedDisplayMode = "rounds" }
      if ($savedDisplayMode -ne $displayMode) {
        if ($leagueState.PSObject.Properties["displayMode"]) {
          $leagueState.displayMode = $displayMode
        } else {
          $leagueState | Add-Member -NotePropertyName displayMode -NotePropertyValue $displayMode
        }
        if ($leagueState.PSObject.Properties["teamMessages"]) {
          $leagueState.teamMessages = [pscustomobject]@{}
        } else {
          $leagueState | Add-Member -NotePropertyName teamMessages -NotePropertyValue ([pscustomobject]@{})
        }
        $leagueState.postedRounds = @()
        $leagueState.finalPosted = $false
      }
    }

    $alreadyPosted = @{}
    foreach ($postedRound in @($leagueState.postedRounds)) { $alreadyPosted[(Get-IntValue $postedRound)] = $true }
    $newRounds = @($completedRounds | Where-Object { -not $alreadyPosted.ContainsKey([int]$_) })

    $needsTeamRefresh = $displayMode -eq "teams" -and [bool]$ForceRefresh
    if ($newRounds.Count -eq 0 -and -not $needsTeamRefresh -and -not ($draftStatus -eq "complete" -and -not [bool]$leagueState.finalPosted)) {
      $results.Add([pscustomobject]@{ leagueRecordId = $leagueRecordId; leagueName = $leagueName; status = "current"; reason = "No newly completed rounds"; postedRounds = @() }) | Out-Null
      continue
    }

    $threadId = Get-StringValue $leagueState.threadId
    if ([string]::IsNullOrWhiteSpace($threadId)) {
      if ($DryRun) {
        $threadId = "dry-run-thread"
      } else {
        $starterPayload = if ($channelMode -eq "forum") {
          New-ThreadStarterPayload -LeagueRecord $leagueRecord -Draft $draft -TeamCount $teamCount -RoundCount $roundCount
        } else {
          New-TextChannelStarterPayload -LeagueRecord $leagueRecord -Draft $draft -TeamCount $teamCount -RoundCount $roundCount
        }
        $starterResponse = Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $leagueWebhookUrl -Query @{ wait = "true" }) -Payload $starterPayload
        $starterMessageId = Get-StringValue $starterResponse.id
        $threadId = if ($channelMode -eq "forum") { Get-StringValue $starterResponse.channel_id } else { $starterMessageId }
        if ([string]::IsNullOrWhiteSpace($threadId)) { throw "Discord did not return a thread or starter-message ID for $leagueRecordId." }
        $leagueState.threadId = $threadId
        $leagueState.starterMessageId = $starterMessageId
        $leagueState.threadMode = $channelMode
        $leagueState.threadReady = ($channelMode -eq "forum")
        $leagueState.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        Save-StateRoot -Path $StatePath -State $state

        if ($channelMode -eq "text") {
          $results.Add([pscustomobject]@{
            leagueRecordId = $leagueRecordId
            leagueName = $leagueName
            sleeperDraftId = $draftId
            draftStatus = $draftStatus
            status = "thread-action-required"
            reason = "Create a public Discord thread from the saved starter message; the next run will connect and post completed rounds"
            postedRounds = @()
            threadId = $threadId
          }) | Out-Null
          continue
        }
      }
    }

    $savedThreadMode = (Get-StringValue (Get-ObjectPropertyValue $leagueState "threadMode")).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($savedThreadMode)) { $savedThreadMode = $channelMode }
    $threadReadyValue = Get-ObjectPropertyValue $leagueState "threadReady"
    $threadReady = if ($null -eq $threadReadyValue) { $savedThreadMode -eq "forum" } else { [bool]$threadReadyValue }
    if (-not $DryRun -and $savedThreadMode -eq "text" -and -not $threadReady) {
      try {
        $connectionPayload = New-ThreadConnectionPayload -LeagueRecord $leagueRecord
        Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $leagueWebhookUrl -Query @{ wait = "true"; thread_id = $threadId }) -Payload $connectionPayload | Out-Null
        $leagueState.threadReady = $true
        $leagueState.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        Save-StateRoot -Path $StatePath -State $state
      } catch {
        $results.Add([pscustomobject]@{
          leagueRecordId = $leagueRecordId
          leagueName = $leagueName
          sleeperDraftId = $draftId
          draftStatus = $draftStatus
          status = "thread-action-required"
          reason = "Create a public Discord thread from the saved starter message; no draft rounds were posted"
          postedRounds = @()
          threadId = $threadId
        }) | Out-Null
        continue
      }
    }

    $users = @(Convert-ToFlatObjectArray -Value (Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}/users" -f $sleeperLeagueId)))
    $rosters = @(Convert-ToFlatObjectArray -Value (Invoke-SleeperJson -Uri ("https://api.sleeper.app/v1/league/{0}/rosters" -f $sleeperLeagueId)))
    $teamMaps = Get-TeamMaps -SleeperLeagueId $sleeperLeagueId -Users $users -Rosters $rosters
    $postedThisRun = [System.Collections.Generic.List[int]]::new()

    if ($displayMode -eq "teams") {
      $completedRound = Get-IntValue (@($completedRounds | Measure-Object -Maximum).Maximum)
      $teamRows = foreach ($roster in $rosters) {
        $rosterId = Get-StringValue $roster.roster_id
        if ([string]::IsNullOrWhiteSpace($rosterId)) { continue }
        $ownerId = Get-StringValue $roster.owner_id
        $teamName = if ($teamMaps.byRosterId.ContainsKey($rosterId)) {
          [string]$teamMaps.byRosterId[$rosterId]
        } else {
          "Unassigned Team $rosterId"
        }
        $teamPicks = @($picks | Where-Object {
          $pickRosterId = Get-StringValue $_.roster_id
          $pickedBy = Get-StringValue $_.picked_by
          $pickRound = Get-IntValue $_.round
          $pickRound -le $completedRound -and (
            $pickRosterId -eq $rosterId -or ([string]::IsNullOrWhiteSpace($pickRosterId) -and $ownerId -and $pickedBy -eq $ownerId)
          )
        })
        $firstPick = if ($teamPicks.Count -gt 0) {
          Get-IntValue (@($teamPicks | Measure-Object -Property pick_no -Minimum).Minimum)
        } else {
          [int]::MaxValue
        }
        [pscustomobject]@{
          teamKey = $rosterId
          rosterId = $rosterId
          teamName = $teamName
          picks = $teamPicks
          firstPick = $firstPick
        }
      }
      $teamRows = @($teamRows | Sort-Object firstPick, { Get-IntValue $_.rosterId })
      if ($teamRows.Count -eq 0) { throw "No Sleeper rosters were available for team-card rendering." }

      foreach ($teamRow in $teamRows) {
        $teamPayload = New-TeamPayload -LeagueRecord $leagueRecord -Draft $draft -TeamName $teamRow.teamName -TeamPicks $teamRow.picks -TeamCount $teamCount -RoundCount $roundCount -CompletedRound $completedRound -DraftStatus $draftStatus
        $teamMessageState = Get-TeamMessageState -LeagueState $leagueState -TeamKey $teamRow.teamKey
        $messageId = if ($teamMessageState) { Get-StringValue $teamMessageState.messageId } else { "" }

        if ($DryRun) {
          if (-not $PassThru) {
            Write-Host ("DRY RUN {0}: {1} team card with {2}/{3} selections." -f $leagueRecordId, $teamRow.teamName, @($teamRow.picks).Count, $roundCount)
          }
        } elseif ([string]::IsNullOrWhiteSpace($messageId)) {
          $teamResponse = Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $leagueWebhookUrl -Query @{ wait = "true"; thread_id = $threadId }) -Payload $teamPayload
          $messageId = Get-StringValue $teamResponse.id
          if ([string]::IsNullOrWhiteSpace($messageId)) { throw "Discord did not return a team-card message ID for $($teamRow.teamName)." }
          Set-TeamMessageState -LeagueState $leagueState -TeamKey $teamRow.teamKey -MessageId $messageId
          $leagueState.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
          Save-StateRoot -Path $StatePath -State $state
        } else {
          $messageBaseUrl = "{0}/messages/{1}" -f $leagueWebhookUrl.TrimEnd('/'), $messageId
          Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $messageBaseUrl -Query @{ thread_id = $threadId }) -Payload $teamPayload -Method Patch | Out-Null
        }
      }

      foreach ($round in $newRounds) { $postedThisRun.Add([int]$round) | Out-Null }
      if (-not $DryRun) {
        $leagueState.postedRounds = @($completedRounds | Sort-Object -Unique)
        $leagueState.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        Save-StateRoot -Path $StatePath -State $state
      }
    } else {
      foreach ($round in $newRounds) {
        $roundPicks = @($picks | Where-Object { (Get-IntValue $_.round) -eq [int]$round })
        $roundPayloads = @(New-RoundPayloads -LeagueRecord $leagueRecord -Draft $draft -RoundPicks $roundPicks -TeamMaps $teamMaps -Round ([int]$round) -TeamCount $teamCount)

        if ($DryRun) {
          if (-not $PassThru) {
            Write-Host ("DRY RUN {0}: Round {1} complete ({2} picks)." -f $leagueRecordId, $round, $roundPicks.Count)
            foreach ($roundPayload in $roundPayloads) {
              foreach ($embed in @($roundPayload.embeds)) { Write-Host $embed.description }
            }
          }
        } else {
          foreach ($roundPayload in $roundPayloads) {
            Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $leagueWebhookUrl -Query @{ wait = "true"; thread_id = $threadId }) -Payload $roundPayload | Out-Null
          }
          $leagueState.postedRounds = @(@($leagueState.postedRounds) + [int]$round | Sort-Object -Unique)
          $leagueState.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
          Save-StateRoot -Path $StatePath -State $state
        }
        $postedThisRun.Add([int]$round) | Out-Null
      }
    }

    $allRoundsPosted = @($completedRounds | Where-Object { $_ -notin @($leagueState.postedRounds) }).Count -eq 0
    if ($DryRun) {
      $allRoundsPosted = @($completedRounds | Where-Object { $_ -notin @(@($leagueState.postedRounds) + @($postedThisRun)) }).Count -eq 0
    }

    $allConfiguredRoundsComplete = $roundCount -gt 0 -and $completedRounds.Count -ge $roundCount
    if ($draftStatus -eq "complete" -and $allConfiguredRoundsComplete -and $allRoundsPosted -and -not [bool]$leagueState.finalPosted) {
      $finalPayload = New-FinalPayload -LeagueRecord $leagueRecord -Draft $draft -RoundCount $roundCount -PickCount $picks.Count
      if ($DryRun) {
        if (-not $PassThru) { Write-Host ("DRY RUN {0}: Draft complete message." -f $leagueRecordId) }
      } else {
        Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $leagueWebhookUrl -Query @{ wait = "true"; thread_id = $threadId }) -Payload $finalPayload | Out-Null
        $leagueState.finalPosted = $true
        $leagueState.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        Save-StateRoot -Path $StatePath -State $state
      }
    }

    $results.Add([pscustomobject]@{
      leagueRecordId = $leagueRecordId
      leagueName = $leagueName
      sleeperDraftId = $draftId
      draftStatus = $draftStatus
      status = if ($DryRun) { "dry-run" } else { "posted" }
      reason = ""
      postedRounds = @($postedThisRun)
      threadId = if ($DryRun) { "" } else { $threadId }
    }) | Out-Null
  } catch {
    $results.Add([pscustomobject]@{
      leagueRecordId = $leagueRecordId
      leagueName = $leagueName
      status = "error"
      reason = $_.Exception.Message
      postedRounds = @()
    }) | Out-Null
    Write-Warning ("Draft tracker failed for {0}: {1}" -f $leagueRecordId, $_.Exception.Message)
  }
}

$result = [pscustomobject]@{
  checkedAt = (Get-Date).ToUniversalTime().ToString("o")
  dryRun = [bool]$DryRun
  leagueCount = $leagueRecords.Count
  results = @($results)
}

if ($PassThru) {
  $result
} else {
  $postedCount = @($results | Where-Object { $_.status -in @("posted", "dry-run", "thread-action-required") }).Count
  $errorCount = @($results | Where-Object { $_.status -eq "error" }).Count
  Write-Host ("Discord draft tracker complete. Eligible leagues: {0}; changed: {1}; errors: {2}." -f $leagueRecords.Count, $postedCount, $errorCount)
  if ($errorCount -gt 0) { exit 1 }
}
