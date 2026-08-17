param(
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$ConfigPath = "data/discord-draft-pulse-config.json",
  [string]$StatePath = "data/discord-draft-pulse-state.json",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_DRAFT_PULSE,
  [switch]$ForceRefresh,
  [switch]$DryRun
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
  return ($text -replace '([\`*_{}\[\]()<>#+\-.!|~>])', '\$1')
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
  return ($seasonDrafts | Sort-Object { Get-IntValue $_.created } | Select-Object -Last 1)
}

function Get-PlayerName {
  param([object]$Pick)

  $metadata = Get-ObjectPropertyValue $Pick "metadata"
  $firstName = Get-StringValue (Get-ObjectPropertyValue $metadata "first_name")
  $lastName = Get-StringValue (Get-ObjectPropertyValue $metadata "last_name")
  $fullName = ("{0} {1}" -f $firstName, $lastName).Trim()
  if (-not [string]::IsNullOrWhiteSpace($fullName)) { return $fullName }

  $playerId = Get-StringValue (Get-ObjectPropertyValue $Pick "player_id")
  if (-not [string]::IsNullOrWhiteSpace($playerId)) { return $playerId }
  return "Unknown Player"
}

function Get-PlayerPosition {
  param([object]$Pick)

  $metadata = Get-ObjectPropertyValue $Pick "metadata"
  $position = (Get-StringValue (Get-ObjectPropertyValue $metadata "position")).ToUpperInvariant()
  if ([string]::IsNullOrWhiteSpace($position)) { return "-" }
  return $position
}

function Get-PlayerTeam {
  param([object]$Pick)

  $metadata = Get-ObjectPropertyValue $Pick "metadata"
  return (Get-StringValue (Get-ObjectPropertyValue $metadata "team")).ToUpperInvariant()
}

function Get-PlayerKey {
  param([object]$Pick)

  $playerId = Get-StringValue (Get-ObjectPropertyValue $Pick "player_id")
  if (-not [string]::IsNullOrWhiteSpace($playerId)) { return $playerId }
  return (Get-PlayerName $Pick).ToLowerInvariant()
}

function Format-PickLocation {
  param(
    [int]$PickNumber,
    [int]$TeamCount
  )

  if ($PickNumber -le 0 -or $TeamCount -le 0) { return "-" }
  $round = [math]::Floor(($PickNumber - 1) / $TeamCount) + 1
  $slot = (($PickNumber - 1) % $TeamCount) + 1
  return ("{0}.{1:D2} (#{2})" -f $round, $slot, $PickNumber)
}

function Join-LimitedLines {
  param(
    [string[]]$Lines,
    [int]$Limit = 1000,
    [string]$Fallback = "No qualifying differences yet."
  )

  if ($null -eq $Lines -or $Lines.Count -eq 0) { return $Fallback }
  $accepted = [System.Collections.Generic.List[string]]::new()
  $length = 0
  foreach ($line in $Lines) {
    $addition = if ($accepted.Count -eq 0) { $line.Length } else { $line.Length + 1 }
    if (($length + $addition) -gt $Limit) {
      $accepted.Add("...")
      break
    }
    $accepted.Add($line)
    $length += $addition
  }
  return ($accepted -join "`n")
}

function Get-PositionRuns {
  param(
    [object]$Division,
    [int]$MinimumLength
  )

  $runs = [System.Collections.Generic.List[object]]::new()
  $currentPosition = ""
  $startPick = 0
  $endPick = 0
  $length = 0

  foreach ($pick in @($Division.completedPicks | Sort-Object pickNo)) {
    $position = Get-StringValue $pick.position
    if ($position -eq $currentPosition -and $pick.pickNo -eq ($endPick + 1)) {
      $length++
      $endPick = $pick.pickNo
      continue
    }

    if ($length -ge $MinimumLength) {
      $runs.Add([pscustomobject]@{
        division = $Division.division
        position = $currentPosition
        length = $length
        startPick = $startPick
        endPick = $endPick
      })
    }

    $currentPosition = $position
    $startPick = $pick.pickNo
    $endPick = $pick.pickNo
    $length = 1
  }

  if ($length -ge $MinimumLength) {
    $runs.Add([pscustomobject]@{
      division = $Division.division
      position = $currentPosition
      length = $length
      startPick = $startPick
      endPick = $endPick
    })
  }

  return @($runs)
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

function Save-PulseState {
  param(
    [string]$Path,
    [object]$State
  )

  $State.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
  $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path
}

if (-not (Test-Path -LiteralPath $LeaguesJsonPath)) { throw "Could not find league data at '$LeaguesJsonPath'." }
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Could not find Draft Pulse config at '$ConfigPath'." }

$leaguePayload = Get-Content -LiteralPath $LeaguesJsonPath -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$channelId = Get-StringValue $config.channelId
$analysisVersion = Get-IntValue $config.analysisVersion
$wantedIds = @($config.leagueRecordIds | ForEach-Object { (Get-StringValue $_).ToUpperInvariant() })
$divisionLabels = $config.divisionLabels

if ($channelId -notmatch '^\d+$') { throw "Draft Pulse channelId must be numeric." }
if ($wantedIds.Count -eq 0) { throw "Draft Pulse config must include leagueRecordIds." }

$leagueRecords = @($leaguePayload.leagues | Where-Object {
  $id = (Get-StringValue $_.id).ToUpperInvariant()
  $wantedIds -contains $id
})

$divisions = [System.Collections.Generic.List[object]]::new()
foreach ($leagueRecord in $leagueRecords) {
  $leagueRecordId = (Get-StringValue $leagueRecord.id).ToUpperInvariant()
  $sleeperLeagueId = Get-StringValue $leagueRecord.sleeperLeagueId
  if ([string]::IsNullOrWhiteSpace($sleeperLeagueId)) { continue }

  $labelProperty = $divisionLabels.PSObject.Properties[$leagueRecordId]
  $division = if ($labelProperty) { Get-StringValue $labelProperty.Value } else { Get-StringValue $leagueRecord.name }
  $draftsResponse = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/drafts" -f $sleeperLeagueId)
  $drafts = @(Convert-ToFlatObjectArray $draftsResponse)
  if ($drafts.Count -eq 0) { continue }

  $draft = Get-LatestDraft -Drafts $drafts -Season (Get-StringValue $leagueRecord.sleeperSeason)
  $draftId = Get-StringValue $draft.draft_id
  $teamCount = Get-IntValue (Get-ObjectPropertyValue (Get-ObjectPropertyValue $draft "settings") "teams")
  if ($teamCount -le 0) { $teamCount = Get-IntValue $leagueRecord.teams }

  $picksResponse = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/draft/{0}/picks" -f $draftId)
  $picks = @(Convert-ToFlatObjectArray $picksResponse | Sort-Object { Get-IntValue $_.pick_no })
  $completedRounds = if ($teamCount -gt 0) { [math]::Floor($picks.Count / $teamCount) } else { 0 }
  $completedPickCount = $completedRounds * $teamCount
  $completedPicks = [System.Collections.Generic.List[object]]::new()

  foreach ($pick in $picks) {
    $pickNo = Get-IntValue $pick.pick_no
    if ($pickNo -le 0 -or $pickNo -gt $completedPickCount) { continue }
    $completedPicks.Add([pscustomobject]@{
      playerKey = Get-PlayerKey $pick
      playerName = Get-PlayerName $pick
      position = Get-PlayerPosition $pick
      nflTeam = Get-PlayerTeam $pick
      pickNo = $pickNo
      division = $division
      leagueRecordId = $leagueRecordId
    })
  }

  $divisions.Add([pscustomobject]@{
    leagueRecordId = $leagueRecordId
    division = $division
    draftId = $draftId
    draftStatus = Get-StringValue $draft.status
    teamCount = $teamCount
    completedRounds = [int]$completedRounds
    completedPicks = @($completedPicks)
  })
}

$divisions = @($divisions | Sort-Object { [array]::IndexOf($wantedIds, $_.leagueRecordId) })
if ($divisions.Count -eq 0) { throw "No configured Sleeper drafts were found for Draft Pulse." }

$roundSignatureParts = @($divisions | ForEach-Object {
  "{0}:{1}:{2}" -f $_.leagueRecordId, $_.draftId, $_.completedRounds
})
$roundSignature = "v{0}|{1}" -f $analysisVersion, ($roundSignatureParts -join '|')
$activeDivisions = @($divisions | Where-Object { $_.completedRounds -gt 0 })
$commonRounds = if ($activeDivisions.Count -gt 0) {
  [int](($activeDivisions | Measure-Object -Property completedRounds -Minimum).Minimum)
} else { 0 }
$commonTeamCount = if ($activeDivisions.Count -gt 0) { [int]$activeDivisions[0].teamCount } else { 0 }
$commonDepth = $commonRounds * $commonTeamCount

$occurrences = @{}
foreach ($division in $activeDivisions) {
  foreach ($pick in $division.completedPicks) {
    if (-not $occurrences.ContainsKey($pick.playerKey)) {
      $occurrences[$pick.playerKey] = [System.Collections.Generic.List[object]]::new()
    }
    $occurrences[$pick.playerKey].Add($pick)
  }
}

$minComparableDrafts = [math]::Max((Get-IntValue $config.minComparableDrafts), 2)
$minPickRange = [math]::Max((Get-IntValue $config.minPickRange), 1)
$rangeItems = [System.Collections.Generic.List[object]]::new()
$uniqueItems = [System.Collections.Generic.List[object]]::new()

foreach ($entry in $occurrences.GetEnumerator()) {
  $items = @($entry.Value | Sort-Object pickNo)
  if ($items.Count -ge $minComparableDrafts) {
    $earliest = $items[0]
    $latest = $items[-1]
    $range = [int]$latest.pickNo - [int]$earliest.pickNo
    if ($range -ge $minPickRange) {
      $rangeItems.Add([pscustomobject]@{
        playerName = $earliest.playerName
        position = $earliest.position
        earliest = $earliest
        latest = $latest
        range = $range
        comparedDrafts = $items.Count
      })
    }
  } elseif ($items.Count -eq 1 -and $commonDepth -gt 0 -and $items[0].pickNo -le $commonDepth) {
    $uniqueItems.Add($items[0])
  }
}

$rangeLines = @($rangeItems |
  Sort-Object @{ Expression = "range"; Descending = $true }, @{ Expression = { $_.earliest.pickNo }; Descending = $false } |
  Select-Object -First (Get-IntValue $config.maxRangeItems) |
  ForEach-Object {
    $player = Escape-DiscordText $_.playerName
    $position = Escape-DiscordText $_.position
    $earlyDivision = Escape-DiscordText $_.earliest.division
    $lateDivision = Escape-DiscordText $_.latest.division
    $earlyPick = Format-PickLocation -PickNumber $_.earliest.pickNo -TeamCount $commonTeamCount
    $latePick = Format-PickLocation -PickNumber $_.latest.pickNo -TeamCount $commonTeamCount
    "$player ($position) - $earlyDivision $earlyPick to $lateDivision $latePick | $($_.range)-pick range"
  })

$uniqueLines = @($uniqueItems |
  Sort-Object pickNo |
  Select-Object -First (Get-IntValue $config.maxUniqueItems) |
  ForEach-Object {
    $player = Escape-DiscordText $_.playerName
    $position = Escape-DiscordText $_.position
    $division = Escape-DiscordText $_.division
    $pick = Format-PickLocation -PickNumber $_.pickNo -TeamCount $commonTeamCount
    "$player ($position) - $division $pick"
  })

$progressLines = @($divisions | ForEach-Object {
  if ($_.completedRounds -gt 0) {
    "$($_.division): $($_.completedRounds) completed rounds"
  } else {
    "$($_.division): waiting for Round 1"
  }
})

$positionLines = @()
if ($commonDepth -gt 0) {
  $positionLines = @($activeDivisions | ForEach-Object {
    $division = $_
    $commonPicks = @($division.completedPicks | Where-Object { $_.pickNo -le $commonDepth })
    $counts = @{}
    foreach ($position in @("QB", "RB", "WR", "TE")) {
      $counts[$position] = @($commonPicks | Where-Object { $_.position -eq $position }).Count
    }
    "$($division.division): QB $($counts.QB) | RB $($counts.RB) | WR $($counts.WR) | TE $($counts.TE)"
  })
}

$allRuns = [System.Collections.Generic.List[object]]::new()
$minPositionRun = [math]::Max((Get-IntValue $config.minPositionRun), 2)
foreach ($division in $activeDivisions) {
  foreach ($run in @(Get-PositionRuns -Division $division -MinimumLength $minPositionRun)) {
    $allRuns.Add($run)
  }
}
$runLines = @($allRuns |
  Sort-Object @{ Expression = "length"; Descending = $true }, @{ Expression = "startPick"; Descending = $false } |
  Select-Object -First (Get-IntValue $config.maxRunItems) |
  ForEach-Object {
    "$($_.division): $($_.length) straight $($_.position)s, Picks $($_.startPick)-$($_.endPick)"
  })

$commonDepthLabel = if ($commonDepth -gt 0) { "through Pick #$commonDepth ($commonRounds rounds)" } else { "once multiple drafts complete a round" }
$payload = @{
  content = ""
  allowed_mentions = @{ parse = @() }
  embeds = @(
    @{
      title = "Redraft Bracket Draft Pulse"
      description = "A neutral comparison of Titan, Apex, Iron, Vanguard, and Dominion. This post refreshes after full rounds are completed."
      color = 0x5865F2
      fields = @(
        @{ name = "Draft Progress"; value = (Join-LimitedLines -Lines $progressLines); inline = $false },
        @{ name = "Biggest Player Draft Ranges"; value = (Join-LimitedLines -Lines $rangeLines); inline = $false },
        @{ name = "Unique Early Selections"; value = (Join-LimitedLines -Lines $uniqueLines -Fallback "No selections are unique within the shared comparison depth yet."); inline = $false },
        @{ name = "Position Mix $commonDepthLabel"; value = (Join-LimitedLines -Lines $positionLines -Fallback "Position comparison begins after the active drafts complete a shared round."); inline = $false },
        @{ name = "Notable Position Runs"; value = (Join-LimitedLines -Lines $runLines -Fallback "No position run has reached $minPositionRun consecutive picks yet."); inline = $false }
      )
      footer = @{ text = "VBP Draft Pulse | Earlier and later describe draft position, not pick quality" }
      timestamp = (Get-Date).ToUniversalTime().ToString("o")
    }
  )
}

if ($DryRun) {
  Write-Output ("DRY RUN Draft Pulse: {0}; shared depth: {1}; player ranges: {2}; unique early selections: {3}; position runs: {4}." -f $roundSignature, $commonDepth, $rangeLines.Count, $uniqueLines.Count, $runLines.Count)
  Write-Output ($payload | ConvertTo-Json -Depth 12)
  exit 0
}

if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { throw "DISCORD_WEBHOOK_DRAFT_PULSE is not configured." }
$webhookInfo = Invoke-RestMethod -Uri $WebhookUrl
$webhookChannelId = Get-StringValue $webhookInfo.channel_id
$webhookId = Get-StringValue $webhookInfo.id
if ($webhookChannelId -ne $channelId) {
  throw "The Draft Pulse webhook points to channel '$webhookChannelId', not configured channel '$channelId'."
}

$state = if (Test-Path -LiteralPath $StatePath) {
  Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
} else {
  [pscustomobject]@{ version = 1; channelId = $channelId; webhookId = ""; messageId = ""; roundSignature = ""; updatedAt = "" }
}

$messageId = Get-StringValue (Get-ObjectPropertyValue $state "messageId")
$savedSignature = Get-StringValue (Get-ObjectPropertyValue $state "roundSignature")
if (-not $ForceRefresh -and -not [string]::IsNullOrWhiteSpace($messageId) -and $savedSignature -eq $roundSignature) {
  Write-Output "Draft Pulse is already current for completed rounds: $roundSignature"
  exit 0
}

$createdNewMessage = $false
if ([string]::IsNullOrWhiteSpace($messageId)) {
  $response = Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $WebhookUrl -Query @{ wait = "true" }) -Payload $payload
  $messageId = Get-StringValue $response.id
  $createdNewMessage = $true
} else {
  $messageUri = "{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $messageId
  try {
    Invoke-DiscordJson -Uri $messageUri -Payload $payload -Method Patch | Out-Null
  } catch {
    if ($_.Exception.Message -notmatch 'HTTP 404') { throw }
    $response = Invoke-DiscordJson -Uri (Get-WebhookUri -BaseUrl $WebhookUrl -Query @{ wait = "true" }) -Payload $payload
    $messageId = Get-StringValue $response.id
    $createdNewMessage = $true
  }
}

$state.channelId = $channelId
$state.webhookId = $webhookId
$state.messageId = $messageId
$state.roundSignature = $roundSignature
Save-PulseState -Path $StatePath -State $state

$action = if ($createdNewMessage) { "created" } else { "updated" }
Write-Output "Draft Pulse $action message $messageId for completed rounds: $roundSignature"
