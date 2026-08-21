param(
  [string]$LeagueDataPath = "data/leagues.json",
  [string]$ConfigPath = "data/discord-bbu-high-scorer-config.json",
  [string]$StatePath = "data/discord-bbu-high-scorer-state.json",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_BBU_HIGH_SCORER,
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
  param([AllowNull()][object]$Value, [int]$MaximumLength = 80)
  $text = Get-StringValue $Value
  $text = [regex]::Replace($text, '[\r\n\t]+', ' ')
  $text = [regex]::Replace($text, '[*_~`>|#\[\]]', '')
  $text = [regex]::Replace($text, '\s{2,}', ' ').Trim()
  if ($MaximumLength -gt 3 -and $text.Length -gt $MaximumLength) {
    return ($text.Substring(0, $MaximumLength - 3).TrimEnd() + "...")
  }
  return $text
}

function Invoke-JsonGet {
  param([string]$Uri)
  foreach ($attempt in 1..4) {
    try {
      $response = Invoke-RestMethod -Uri $Uri
      foreach ($item in @($response)) { Write-Output $item }
      return
    } catch {
      $statusCode = 0
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      }
      if ($attempt -ge 4 -or ($statusCode -ne 429 -and $statusCode -lt 500)) {
        throw "GET '$Uri' failed with HTTP $statusCode."
      }
      Start-Sleep -Seconds ([math]::Min([math]::Pow(2, $attempt), 30))
    }
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
      if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $responseBody = [string]$_.ErrorDetails.Message }
      if ($attempt -ge 4 -or ($statusCode -ne 429 -and $statusCode -lt 500)) {
        if ($responseBody) { throw ("Discord request failed with HTTP {0}: {1}" -f $statusCode, $responseBody) }
        throw
      }
      Start-Sleep -Seconds ([math]::Min([math]::Pow(2, $attempt), 30))
    }
  }
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

function Get-TeamName {
  param([object]$Roster, [hashtable]$UserById)
  $metadata = Get-PropertyValue -InputObject $Roster -Name "metadata"
  $metadataName = Get-StringValue (Get-PropertyValue -InputObject $metadata -Name "team_name")
  if ($metadataName) { return Convert-ToPlainDiscordText $metadataName 48 }

  $ownerId = Get-StringValue (Get-PropertyValue -InputObject $Roster -Name "owner_id")
  if ($ownerId -and $UserById.ContainsKey($ownerId)) {
    $user = $UserById[$ownerId]
    $displayName = Get-StringValue (Get-PropertyValue -InputObject $user -Name "display_name")
    if ($displayName) { return Convert-ToPlainDiscordText $displayName 48 }
    $username = Get-StringValue (Get-PropertyValue -InputObject $user -Name "username")
    if ($username) { return Convert-ToPlainDiscordText $username 48 }
  }
  return "Team $(Get-IntValue (Get-PropertyValue -InputObject $Roster -Name 'roster_id'))"
}

function Get-State {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $loaded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -ne $loaded) {
      if (-not $loaded.PSObject.Properties["weeklyHighScores"]) {
        $loaded | Add-Member -NotePropertyName weeklyHighScores -NotePropertyValue @()
      }
      return $loaded
    }
  }
  return [pscustomobject]@{
    version = 1
    channelId = ""
    webhookId = ""
    groupId = ""
    season = ""
    completedWeek = 0
    signature = ""
    messageId = ""
    weeklyHighScores = @()
    updatedAt = ""
  }
}

function Set-StateProperty {
  param([object]$State, [string]$Name, [AllowNull()][object]$Value)
  if ($State.PSObject.Properties[$Name]) { $State.$Name = $Value }
  else { $State | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Save-State {
  param([string]$Path, [object]$State)
  Set-StateProperty -State $State -Name updatedAt -Value ([datetimeoffset]::UtcNow.ToString("o"))
  $json = $State | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($Path),
    $json + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
  )
}

function Assert-EmbedLimits {
  param([object]$Embed)
  $title = Get-StringValue $Embed.title
  $description = Get-StringValue $Embed.description
  if ($title.Length -gt 256) { throw "Discord embed title exceeds 256 characters." }
  if ($description.Length -gt 4096) { throw "Discord embed description exceeds 4096 characters." }
  $fields = @($Embed.fields)
  if ($fields.Count -gt 25) { throw "Discord embed contains more than 25 fields." }
  $total = $title.Length + $description.Length
  foreach ($field in $fields) {
    $name = Get-StringValue $field.name
    $value = Get-StringValue $field.value
    if ($name.Length -gt 256 -or $value.Length -gt 1024) { throw "Discord embed field exceeds its text limit." }
    $total += $name.Length + $value.Length
  }
  $total += (Get-StringValue $Embed.footer.text).Length
  if ($total -gt 6000) { throw "Discord embed exceeds the 6000-character message limit." }
}

if (-not (Test-Path -LiteralPath $LeagueDataPath)) { throw "Could not find league data at '$LeagueDataPath'." }
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Could not find BBU high-scorer config at '$ConfigPath'." }

$leagueData = Get-Content -LiteralPath $LeagueDataPath -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$state = Get-State -Path $StatePath
$channelId = Get-StringValue $config.channelId
$groupId = Get-StringValue $config.groupId
$season = Get-StringValue $config.season
$websiteUrl = Get-StringValue $config.websiteUrl
$leagueRecordIds = @($config.leagueRecordIds | ForEach-Object { (Get-StringValue $_).ToUpperInvariant() })
$expectedTeams = Get-IntValue $config.expectedTeamsPerDivision
$maximumWeek = Get-IntValue $config.maximumWeek

if ($channelId -notmatch '^\d+$') { throw "BBU high-scorer channelId must be numeric." }
if ($season -notmatch '^\d{4}$') { throw "BBU high-scorer config must contain a four-digit season." }
if ($leagueRecordIds.Count -ne 13 -or @($leagueRecordIds | Sort-Object -Unique).Count -ne 13) {
  throw "BBU high-scorer config must contain thirteen unique league IDs."
}
if ($expectedTeams -ne 10) { throw "BBU high-scorer config must expect 10 teams per division." }
if ($maximumWeek -ne 17) { throw "BBU high-scorer config must track Weeks 1-17." }

$leagueLookup = @{}
foreach ($recordId in $leagueRecordIds) {
  $matches = @($leagueData.leagues | Where-Object {
    (Get-StringValue (Get-PropertyValue -InputObject $_ -Name "id")).ToUpperInvariant() -eq $recordId
  })
  if ($matches.Count -ne 1) { throw "League data must contain exactly one '$recordId' record." }
  $leagueRecord = $matches[0]
  if ((Get-StringValue (Get-PropertyValue -InputObject $leagueRecord -Name "format")).ToLowerInvariant() -ne "bestball") {
    throw "League '$recordId' is not a Best Ball Union division."
  }
  $sleeperLeagueId = Get-StringValue (Get-PropertyValue -InputObject $leagueRecord -Name "sleeperLeagueId")
  if ($sleeperLeagueId -notmatch '^\d+$') { throw "League '$recordId' does not have a valid Sleeper league ID." }
  $leagueLookup[$recordId] = [pscustomobject]@{ recordId = $recordId; sleeperLeagueId = $sleeperLeagueId }
}

$nflState = Invoke-JsonGet -Uri "https://api.sleeper.app/v1/state/nfl"
$nflSeason = Get-StringValue (Get-PropertyValue -InputObject $nflState -Name "season")
$seasonType = (Get-StringValue (Get-PropertyValue -InputObject $nflState -Name "season_type")).ToLowerInvariant()
$currentLeg = Get-IntValue (Get-PropertyValue -InputObject $nflState -Name "leg")
if ($nflSeason -ne $season) { throw "Sleeper NFL state is for season '$nflSeason', not configured season '$season'." }

$completedWeek = switch ($seasonType) {
  "regular" { [math]::Min([math]::Max($currentLeg - 1, 0), $maximumWeek); break }
  "post" { $maximumWeek; break }
  "off" { $maximumWeek; break }
  default { 0; break }
}

$historyByWeek = @{}
foreach ($row in @(Get-PropertyValue -InputObject $state -Name "weeklyHighScores")) {
  $week = Get-IntValue (Get-PropertyValue -InputObject $row -Name "week")
  if ($week -ge 1 -and $week -le $maximumWeek) { $historyByWeek[$week] = $row }
}

$weeksToRefresh = [System.Collections.Generic.List[int]]::new()
if ($completedWeek -gt 0) {
  foreach ($week in 1..$completedWeek) {
    if (-not $historyByWeek.ContainsKey($week) -or $week -eq $completedWeek) {
      $weeksToRefresh.Add($week) | Out-Null
    }
  }
}

if ($weeksToRefresh.Count -gt 0) {
  $teamByLeagueRoster = @{}
  foreach ($recordId in $leagueRecordIds) {
    $sleeperLeagueId = $leagueLookup[$recordId].sleeperLeagueId
    $rosters = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$sleeperLeagueId/rosters")
    $users = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$sleeperLeagueId/users")
    $ownedRosters = @($rosters | Where-Object { Get-StringValue (Get-PropertyValue -InputObject $_ -Name "owner_id") })
    if ($ownedRosters.Count -ne $expectedTeams) {
      throw "Division '$recordId' has $($ownedRosters.Count) owner-filled rosters instead of $expectedTeams. The existing Discord post was preserved."
    }

    $userById = @{}
    foreach ($user in $users) {
      $userId = Get-StringValue (Get-PropertyValue -InputObject $user -Name "user_id")
      if ($userId) { $userById[$userId] = $user }
    }
    foreach ($roster in $ownedRosters) {
      $rosterId = Get-IntValue (Get-PropertyValue -InputObject $roster -Name "roster_id")
      $teamByLeagueRoster["${recordId}:$rosterId"] = Get-TeamName -Roster $roster -UserById $userById
    }
  }

  foreach ($week in $weeksToRefresh) {
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($recordId in $leagueRecordIds) {
      $sleeperLeagueId = $leagueLookup[$recordId].sleeperLeagueId
      $matchups = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$sleeperLeagueId/matchups/$week")
      if ($matchups.Count -ne $expectedTeams) {
        throw "Division '$recordId' returned $($matchups.Count) Week $week matchup rows instead of $expectedTeams. The existing Discord post was preserved."
      }
      foreach ($matchup in $matchups) {
        $rosterId = Get-IntValue (Get-PropertyValue -InputObject $matchup -Name "roster_id")
        $teamKey = "${recordId}:$rosterId"
        if (-not $teamByLeagueRoster.ContainsKey($teamKey)) {
          throw "Division '$recordId' Week $week contains unknown roster '$rosterId'."
        }
        $candidates.Add([pscustomobject]@{
          leagueRecordId = $recordId
          rosterId = $rosterId
          teamName = $teamByLeagueRoster[$teamKey]
          score = [math]::Round((Get-DoubleValue (Get-PropertyValue -InputObject $matchup -Name "points")), 2)
        }) | Out-Null
      }
    }

    if ($candidates.Count -ne ($leagueRecordIds.Count * $expectedTeams)) {
      throw "Week $week contains $($candidates.Count) BBU scores instead of 130."
    }
    $highScore = ($candidates | Measure-Object -Property score -Maximum).Maximum
    if ((Get-DoubleValue $highScore) -le 0) {
      throw "Week $week has no positive BBU scores even though Sleeper marks it complete. The existing Discord post was preserved."
    }
    $winners = @($candidates | Where-Object { $_.score -eq $highScore } | Sort-Object teamName, leagueRecordId, rosterId | ForEach-Object {
      [pscustomobject]@{
        leagueRecordId = $_.leagueRecordId
        rosterId = $_.rosterId
        teamName = $_.teamName
      }
    })
    $historyByWeek[$week] = [pscustomobject]@{
      week = $week
      score = [math]::Round((Get-DoubleValue $highScore), 2)
      winners = $winners
    }
  }
}

$weeklyRows = @()
if ($completedWeek -gt 0) {
  $weeklyRows = @(
    foreach ($week in 1..$completedWeek) {
      if (-not $historyByWeek.ContainsKey($week)) {
        throw "Week $week is missing from the BBU high-scorer history."
      }
      $historyByWeek[$week]
    }
  )
}
$displayRows = @($weeklyRows | Sort-Object { Get-IntValue $_.week } -Descending)

$fields = [System.Collections.Generic.List[object]]::new()
if ($displayRows.Count -gt 0) {
  $displayRows | ForEach-Object {
    $row = $_
    $score = Get-DoubleValue (Get-PropertyValue -InputObject $row -Name "score")
    $winners = @((Get-PropertyValue -InputObject $row -Name "winners") | ForEach-Object {
      "**$(Convert-ToPlainDiscordText (Get-PropertyValue -InputObject $_ -Name 'teamName') 48)** - $(Get-StringValue (Get-PropertyValue -InputObject $_ -Name 'leagueRecordId'))"
    })
    $fields.Add(@{
      name = "Week $(Get-IntValue (Get-PropertyValue -InputObject $row -Name 'week')) - $('{0:N2}' -f $score) points"
      value = ($winners -join "`n")
      inline = $false
    }) | Out-Null
  }
} else {
  $fields.Add(@{
    name = "Season Status"
    value = "Weekly high scorers will appear after Week 1 scoring is complete."
    inline = $false
  }) | Out-Null
}

$centralNow = Get-CentralTime
$embed = @{
  title = "Best Ball Union - Weekly High Scorers"
  url = $websiteUrl
  description = if ($displayRows.Count -gt 0) {
    "The highest single-week score across all 130 teams in BBU1-BBU13. Exact ties are shown together."
  } else {
    "The weekly high-score board will activate when the 2026 regular season begins."
  }
  color = if ($displayRows.Count -gt 0) { 0xC0392B } else { 0x5865F2 }
  fields = @($fields)
  footer = @{ text = "One overall weekly high score across all 13 BBU rooms | Tuesdays at 2:20 PM Central" }
  timestamp = [datetimeoffset]::UtcNow.ToString("o")
}
Assert-EmbedLimits -Embed $embed
$payload = @{
  username = "VBP Best Ball Union"
  allowed_mentions = @{ parse = @() }
  embeds = @($embed)
}

$signatureSource = [pscustomobject]@{
  season = $season
  completedWeek = $completedWeek
  weeklyHighScores = $weeklyRows
}
$signature = Get-Sha256 ($signatureSource | ConvertTo-Json -Depth 8 -Compress)
$messageId = Get-StringValue (Get-PropertyValue -InputObject $state -Name "messageId")

if (-not $ForceRefresh -and $messageId -and (Get-StringValue $state.signature) -eq $signature) {
  $result = [pscustomobject]@{ action = "current"; completedWeek = $completedWeek; winnerWeeks = $weeklyRows.Count; messageId = $messageId; payload = $payload }
  if ($PassThru) { $result } else { Write-Host "Discord BBU high-scorer history is already current through Week $completedWeek." }
  exit 0
}

if ($DryRun) {
  $result = [pscustomobject]@{ action = "dry-run"; completedWeek = $completedWeek; winnerWeeks = $weeklyRows.Count; messageId = $messageId; weeklyHighScores = $weeklyRows; payload = $payload }
  if ($PassThru) { $result } else {
    Write-Host ("DRY RUN BBU high scorer: {0} completed week(s); {1} winner row(s)." -f $completedWeek, $weeklyRows.Count)
    Write-Output ($payload | ConvertTo-Json -Depth 12)
  }
  exit 0
}

if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { throw "DISCORD_WEBHOOK_BBU_HIGH_SCORER is not configured." }
$webhookInfo = Invoke-JsonGet -Uri $WebhookUrl
$webhookChannelId = Get-StringValue (Get-PropertyValue -InputObject $webhookInfo -Name "channel_id")
$webhookId = Get-StringValue (Get-PropertyValue -InputObject $webhookInfo -Name "id")
if ($webhookChannelId -ne $channelId) {
  throw "The BBU high-scorer webhook points to channel '$webhookChannelId', not configured channel '$channelId'."
}
$savedWebhookId = Get-StringValue (Get-PropertyValue -InputObject $state -Name "webhookId")
if ($savedWebhookId -and $savedWebhookId -ne $webhookId) { throw "The BBU high-scorer state belongs to a different Discord webhook." }

$created = $false
if ($messageId) {
  try {
    Invoke-DiscordJson -Uri ("{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $messageId) -Payload $payload -Method Patch | Out-Null
  } catch {
    if ($_.Exception.Message -notmatch 'HTTP 404') { throw }
    $messageId = ""
  }
}
if (-not $messageId) {
  $response = Invoke-DiscordJson -Uri ("{0}?wait=true" -f $WebhookUrl.TrimEnd('/')) -Payload $payload
  $messageId = Get-StringValue (Get-PropertyValue -InputObject $response -Name "id")
  if (-not $messageId) { throw "Discord did not return a message ID for the BBU high-scorer card." }
  $created = $true
}

Set-StateProperty -State $state -Name channelId -Value $channelId
Set-StateProperty -State $state -Name webhookId -Value $webhookId
Set-StateProperty -State $state -Name groupId -Value $groupId
Set-StateProperty -State $state -Name season -Value $season
Set-StateProperty -State $state -Name completedWeek -Value $completedWeek
Set-StateProperty -State $state -Name signature -Value $signature
Set-StateProperty -State $state -Name messageId -Value $messageId
Set-StateProperty -State $state -Name weeklyHighScores -Value $weeklyRows
Save-State -Path $StatePath -State $state

$result = [pscustomobject]@{
  action = if ($created) { "created" } else { "updated" }
  completedWeek = $completedWeek
  winnerWeeks = $weeklyRows.Count
  messageId = $messageId
  weeklyHighScores = $weeklyRows
  payload = $payload
}
if ($PassThru) { $result }
else { Write-Host ("Discord BBU high scorer {0}: history through Week {1}." -f $result.action, $completedWeek) }
