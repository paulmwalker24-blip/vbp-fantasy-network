param(
  [string]$RankingsPath = "data/power-rankings.json",
  [string]$ConfigPath = "data/discord-best-ball-union-power-rankings-config.json",
  [string]$StatePath = "data/discord-best-ball-union-power-rankings-state.json",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_BEST_BALL_UNION_POWER_RANKINGS,
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
  $text = [regex]::Replace($text, '[*_~`>|#\[\]]', '')
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
    hasPublishedRankings = $false
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
  $json = $State | ConvertTo-Json -Depth 8
  $absolutePath = [System.IO.Path]::GetFullPath($Path)
  [System.IO.File]::WriteAllText($absolutePath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
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

  $fields = @(Get-PropertyValue $Embed "fields")
  if ($fields.Count -gt 25) { throw "Discord embed contains more than 25 fields." }
  $total = $title.Length + $description.Length
  foreach ($field in $fields) {
    $name = Get-StringValue (Get-PropertyValue $field "name")
    $value = Get-StringValue (Get-PropertyValue $field "value")
    if ($name.Length -gt 256) { throw "Discord embed field name exceeds 256 characters." }
    if ($value.Length -gt 1024) { throw "Discord embed field value exceeds 1024 characters." }
    $total += $name.Length + $value.Length
  }
  $footerText = Get-StringValue (Get-PropertyValue (Get-PropertyValue $Embed "footer") "text")
  if ($footerText.Length -gt 2048) { throw "Discord embed footer exceeds 2048 characters." }
  $total += $footerText.Length
  if ($total -gt 6000) { throw "Discord embed text exceeds the 6000-character message limit." }
}

function New-DiscordPayload {
  param([object]$Embed)

  Assert-EmbedLimits -Embed $Embed
  return @{
    username = "VBP Power Rankings"
    allowed_mentions = @{ parse = @() }
    embeds = @($Embed)
  }
}

function Get-DivisionStatusLabel {
  param([AllowNull()][object]$League)

  $statuses = @((Get-PropertyValue $League "draftStatuses") | ForEach-Object { (Get-StringValue $_).ToLowerInvariant() })
  if ($statuses.Count -gt 0 -and @($statuses | Where-Object { $_ -ne "complete" }).Count -eq 0) { return "Complete" }
  if (@($statuses | Where-Object { $_ -in @("drafting", "paused") }).Count -gt 0) { return "In progress" }
  if (@($statuses | Where-Object { $_ -eq "pre_draft" }).Count -gt 0) { return "Not started" }
  return "Waiting"
}

function Get-SnapshotLabel {
  param([AllowNull()][object]$Snapshot)

  $season = Convert-ToPlainDiscordText (Get-PropertyValue $Snapshot "season") 12
  $seasonType = (Get-StringValue (Get-PropertyValue $Snapshot "seasonType")).ToLowerInvariant()
  $week = Get-IntValue (Get-PropertyValue $Snapshot "week")
  if (-not $season) { return "Current roster snapshot" }
  switch ($seasonType) {
    "pre" { return "$season Preseason" }
    "regular" {
      if ($week -gt 0) { return "$season Week $week" }
      return "$season Regular Season"
    }
    "post" { return "$season Postseason" }
    default { return "$season roster snapshot" }
  }
}

if (-not (Test-Path -LiteralPath $RankingsPath)) { throw "Could not find power rankings at '$RankingsPath'." }
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Could not find power-ranking config at '$ConfigPath'." }

$rankingsData = Get-Content -LiteralPath $RankingsPath -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$channelId = Get-StringValue (Get-PropertyValue $config "channelId")
$groupId = Get-StringValue (Get-PropertyValue $config "groupId")
$websiteUrl = Get-StringValue (Get-PropertyValue $config "websiteUrl")
$expectedLeagueIds = @((Get-PropertyValue $config "leagueRecordIds") | ForEach-Object { (Get-StringValue $_).ToUpperInvariant() })
$expectedTeamCount = Get-IntValue (Get-PropertyValue $config "expectedTeamCount")
$topCount = Get-IntValue (Get-PropertyValue $config "topCount")
$divisionNames = Get-PropertyValue $config "divisionNames"

if ($channelId -notmatch '^\d+$') { throw "Power-ranking channelId must be numeric." }
if (-not $groupId) { throw "Power-ranking config must include groupId." }
if ($expectedLeagueIds.Count -ne 13 -or @($expectedLeagueIds | Sort-Object -Unique).Count -ne 13) {
  throw "Power-ranking config must contain thirteen unique Best Ball Union league IDs."
}
if ($expectedTeamCount -ne 130) { throw "Power-ranking config must expect exactly 130 teams." }
if ($topCount -ne 25) { throw "Power-ranking config must publish a combined Top 25." }
foreach ($leagueId in $expectedLeagueIds) {
  if (-not (Get-StringValue (Get-PropertyValue $divisionNames $leagueId))) {
    throw "Power-ranking config is missing a division name for '$leagueId'."
  }
}

$allLeagues = @(Get-PropertyValue $rankingsData "leagues")
$leagueById = @{}
foreach ($leagueId in $expectedLeagueIds) {
  $matches = @($allLeagues | Where-Object { (Get-StringValue (Get-PropertyValue $_ "leagueRecordId")).ToUpperInvariant() -eq $leagueId })
  if ($matches.Count -ne 1) {
    throw "The refreshed power-ranking data must contain exactly one '$leagueId' league. Existing Discord rankings were left untouched."
  }
  if ((Get-StringValue (Get-PropertyValue $matches[0] "format")).ToLowerInvariant() -ne "bestball") {
    throw "League '$leagueId' is not marked as Best Ball Union data. Existing Discord rankings were left untouched."
  }
  $leagueById[$leagueId] = $matches[0]
}

$rankingsReady = $true
$combinedRows = [System.Collections.Generic.List[object]]::new()
foreach ($leagueId in $expectedLeagueIds) {
  $league = $leagueById[$leagueId]
  $statuses = @((Get-PropertyValue $league "draftStatuses") | ForEach-Object { (Get-StringValue $_).ToLowerInvariant() })
  $allDraftsComplete = $statuses.Count -gt 0 -and @($statuses | Where-Object { $_ -ne "complete" }).Count -eq 0
  $draftReady = [bool](Get-PropertyValue (Get-PropertyValue $league "draftReadiness") "ready")
  $publish = [bool](Get-PropertyValue $league "publish")
  $leagueRows = @(Get-PropertyValue $league "rankings")
  if (-not $allDraftsComplete -or -not $draftReady -or -not $publish -or $leagueRows.Count -ne 10) {
    $rankingsReady = $false
    continue
  }

  $seenRosterIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($row in $leagueRows) {
    $rosterId = Get-StringValue (Get-PropertyValue $row "rosterId")
    $teamName = Get-StringValue (Get-PropertyValue $row "teamName")
    $score = Get-DoubleValue (Get-PropertyValue $row "score")
    if (-not $rosterId -or -not $seenRosterIds.Add($rosterId)) {
      throw "League '$leagueId' contains a missing or duplicate roster ID. Existing Discord rankings were left untouched."
    }
    if (-not $teamName) { throw "League '$leagueId' contains a ranking without a team name." }
    if ($score -lt 0 -or $score -gt 100) { throw "League '$leagueId' contains a score outside the 0-100 range." }

    $combinedRows.Add([pscustomobject]@{
      leagueRecordId = $leagueId
      divisionName = Get-StringValue (Get-PropertyValue $divisionNames $leagueId)
      rosterId = $rosterId
      ownerId = Get-StringValue (Get-PropertyValue $row "ownerId")
      teamName = $teamName
      score = $score
      pointsFor = Get-DoubleValue (Get-PropertyValue (Get-PropertyValue $row "record") "pointsFor")
    }) | Out-Null
  }
}

if ($rankingsReady -and $combinedRows.Count -ne $expectedTeamCount) {
  throw "The refreshed Best Ball Union rankings contain $($combinedRows.Count) teams instead of $expectedTeamCount. Existing Discord rankings were left untouched."
}

$state = Get-StateRoot -Path $StatePath
$hasPublishedRankings = [bool](Get-PropertyValue $state "hasPublishedRankings")
if (-not $rankingsReady -and $hasPublishedRankings) {
  throw "The refreshed ranking data is incomplete, so the last known good Discord Top 25 was preserved."
}

$centralNow = Get-CentralTime
$snapshotKey = $centralNow.ToString("yyyy-MM-dd")
$snapshotLabel = Get-SnapshotLabel (Get-PropertyValue $rankingsData "snapshot")
$timestamp = [datetimeoffset]::UtcNow.ToString("o")
$fields = [System.Collections.Generic.List[object]]::new()
$topRows = @()

if ($rankingsReady) {
  $sortedRows = @($combinedRows | Sort-Object `
    @{ Expression = { Get-DoubleValue $_.score }; Descending = $true }, `
    @{ Expression = { Get-DoubleValue $_.pointsFor }; Descending = $true }, `
    @{ Expression = { Get-StringValue $_.teamName } }, `
    @{ Expression = { Get-StringValue $_.divisionName } }, `
    @{ Expression = { Get-IntValue $_.rosterId } })
  $topRows = @($sortedRows | Select-Object -First $topCount)

  foreach ($rangeStart in @(1, 6, 11, 16, 21)) {
    $rangeEnd = $rangeStart + 4
    $lines = [System.Collections.Generic.List[string]]::new()
    for ($rank = $rangeStart; $rank -le $rangeEnd; $rank++) {
      $row = $topRows[$rank - 1]
      $lines.Add(("{0:D2}. {1} - {2} - {3:N1} / 100" -f `
        $rank, `
        (Convert-ToPlainDiscordText $row.teamName 32), `
        (Convert-ToPlainDiscordText $row.divisionName 16), `
        (Get-DoubleValue $row.score))) | Out-Null
    }
    $fields.Add(@{
      name = "Ranks $rangeStart-$rangeEnd"
      value = ($lines -join "`n")
      inline = $false
    }) | Out-Null
  }
} else {
  $statusLines = @($expectedLeagueIds | ForEach-Object {
    $divisionName = Convert-ToPlainDiscordText (Get-PropertyValue $divisionNames $_) 24
    "${divisionName}: $(Get-DivisionStatusLabel $leagueById[$_])"
  })
  $fields.Add(@{
    name = "Division Draft Status"
    value = ($statusLines -join "`n")
    inline = $false
  }) | Out-Null
  $fields.Add(@{
    name = "What Happens Next"
    value = "After all thirteen room drafts finish, the 130 teams are graded together and the combined Top 25 replaces this card automatically."
    inline = $false
  }) | Out-Null
}

$embed = @{
  title = "Best Ball Union - Power Rankings"
  url = $websiteUrl
  description = if ($rankingsReady) {
    "Combined Top 25 across BBU1-BBU13. Current locked-roster strength snapshot: $snapshotLabel."
  } else {
    "The combined Top 25 will activate only after all thirteen BBU room drafts are complete. Partial and sample rankings are never published."
  }
  color = if ($rankingsReady) { 0xC0392B } else { 0x5865F2 }
  fields = @($fields)
  footer = @{ text = if ($rankingsReady) {
    "Scores are locked-roster strength grades, not projected standings. Updated every Tuesday at 1:45 AM Central."
  } else {
    "Room drafts are still in progress. Checked every Tuesday at 1:45 AM Central."
  } }
  timestamp = $timestamp
}
$payload = New-DiscordPayload $embed

$signatureSource = [pscustomobject]@{
  snapshotKey = $snapshotKey
  rankingsReady = $rankingsReady
  statuses = @($expectedLeagueIds | ForEach-Object {
    [pscustomobject]@{
      leagueRecordId = $_
      draftStatuses = @((Get-PropertyValue $leagueById[$_] "draftStatuses") | ForEach-Object { Get-StringValue $_ })
      publish = [bool](Get-PropertyValue $leagueById[$_] "publish")
      rankingCount = @(Get-PropertyValue $leagueById[$_] "rankings").Count
    }
  })
  rows = @(for ($index = 0; $index -lt $topRows.Count; $index++) {
    [pscustomobject]@{
      rank = $index + 1
      leagueRecordId = Get-StringValue $topRows[$index].leagueRecordId
      rosterId = Get-StringValue $topRows[$index].rosterId
      teamName = Get-StringValue $topRows[$index].teamName
      score = Get-DoubleValue $topRows[$index].score
    }
  })
}
$signature = Get-Sha256 ($signatureSource | ConvertTo-Json -Depth 8 -Compress)
$messageId = Get-StateMessageId -State $state -Key "main"

if (-not $ForceRefresh -and $messageId -and (Get-StringValue $state.signature) -eq $signature) {
  $result = [pscustomobject]@{
    action = "current"
    rankingsReady = $rankingsReady
    snapshotKey = $snapshotKey
    rankingCount = $topRows.Count
    messageId = $messageId
    payload = $payload
  }
  if ($PassThru) { $result } else { Write-Host "Best Ball Union power rankings are already current for $snapshotKey." }
  exit 0
}

if ($DryRun) {
  $result = [pscustomobject]@{
    action = "dry-run"
    rankingsReady = $rankingsReady
    snapshotKey = $snapshotKey
    rankingCount = $topRows.Count
    messageId = $messageId
    payload = $payload
  }
  if ($PassThru) { $result } else {
    Write-Host ("DRY RUN Best Ball Union power rankings: ready: {0}; Top 25 rows: {1}." -f $rankingsReady, $topRows.Count)
    Write-Output ($payload | ConvertTo-Json -Depth 12)
  }
  exit 0
}

if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { throw "DISCORD_WEBHOOK_BEST_BALL_UNION_POWER_RANKINGS is not configured." }
$webhookInfo = Invoke-DiscordGet -Uri $WebhookUrl
$webhookChannelId = Get-StringValue (Get-PropertyValue $webhookInfo "channel_id")
$webhookId = Get-StringValue (Get-PropertyValue $webhookInfo "id")
if ($webhookChannelId -ne $channelId) {
  throw "The Best Ball Union power-ranking webhook points to channel '$webhookChannelId', not configured channel '$channelId'."
}
$savedWebhookId = Get-StringValue (Get-PropertyValue $state "webhookId")
if ($savedWebhookId -and $savedWebhookId -ne $webhookId) {
  throw "The power-ranking state belongs to a different Discord webhook. Clear the saved message state before intentionally replacing the webhook."
}

Set-StateProperty -State $state -Name channelId -Value $channelId
Set-StateProperty -State $state -Name webhookId -Value $webhookId
Set-StateProperty -State $state -Name groupId -Value $groupId

$action = "updated"
if ($messageId) {
  try {
    Invoke-DiscordJson -Uri ("{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $messageId) -Payload $payload -Method Patch | Out-Null
  } catch {
    if ($_.Exception.Message -notmatch 'HTTP 404') { throw }
    $messageId = ""
  }
}

if (-not $messageId) {
  $response = Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $WebhookUrl -Query @{ wait = "true" }) -Payload $payload
  $messageId = Get-StringValue (Get-PropertyValue $response "id")
  if (-not $messageId) { throw "Discord did not return a message ID for the Best Ball Union power-ranking card." }
  $action = "created"
}

Set-StateMessage -State $state -Key "main" -MessageId $messageId
Save-StateRoot -Path $StatePath -State $state
Set-StateProperty -State $state -Name snapshotKey -Value $snapshotKey
Set-StateProperty -State $state -Name signature -Value $signature
if ($rankingsReady) { Set-StateProperty -State $state -Name hasPublishedRankings -Value $true }
Save-StateRoot -Path $StatePath -State $state

$result = [pscustomobject]@{
  action = $action
  rankingsReady = $rankingsReady
  snapshotKey = $snapshotKey
  rankingCount = $topRows.Count
  messageId = $messageId
  payload = $payload
}

if ($PassThru) {
  $result
} else {
  Write-Host ("Best Ball Union power rankings {0}: ready: {1}; Top 25 rows: {2}; snapshot: {3}." -f $action, $rankingsReady, $topRows.Count, $snapshotKey)
}
