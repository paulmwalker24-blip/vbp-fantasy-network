param(
  [string]$LeagueDataPath = "data/leagues.json",
  [string]$ConfigPath = "data/discord-division-leaders-config.json",
  [string]$StatePath = "data/discord-division-leaders-state.json",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_DIVISION_LEADERS,
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

function Get-PointsFor {
  param([AllowNull()][object]$Settings)
  $whole = Get-DoubleValue (Get-PropertyValue $Settings "fpts")
  $decimal = Get-IntValue (Get-PropertyValue $Settings "fpts_decimal")
  return [math]::Round($whole + ($decimal / 100.0), 2)
}

function Get-TeamName {
  param([object]$Roster, [hashtable]$UserById)
  $metadataName = Get-StringValue (Get-PropertyValue (Get-PropertyValue $Roster "metadata") "team_name")
  if ($metadataName) { return Convert-ToPlainDiscordText $metadataName 48 }

  $ownerId = Get-StringValue (Get-PropertyValue $Roster "owner_id")
  if ($ownerId -and $UserById.ContainsKey($ownerId)) {
    $user = $UserById[$ownerId]
    $displayName = Get-StringValue (Get-PropertyValue $user "display_name")
    if ($displayName) { return Convert-ToPlainDiscordText $displayName 48 }
    $username = Get-StringValue (Get-PropertyValue $user "username")
    if ($username) { return Convert-ToPlainDiscordText $username 48 }
  }
  return "Team $(Get-IntValue (Get-PropertyValue $Roster 'roster_id'))"
}

function Get-State {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $loaded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -ne $loaded) { return $loaded }
  }
  return [pscustomobject]@{
    version = 1
    channelId = ""
    webhookId = ""
    groupId = ""
    signature = ""
    messageId = ""
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
  $json = $State | ConvertTo-Json -Depth 6
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
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Could not find division-leaders config at '$ConfigPath'." }

$leagueData = Get-Content -LiteralPath $LeagueDataPath -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$channelId = Get-StringValue $config.channelId
$groupId = Get-StringValue $config.groupId
$websiteUrl = Get-StringValue $config.websiteUrl
$leagueRecordIds = @($config.leagueRecordIds | ForEach-Object { (Get-StringValue $_).ToUpperInvariant() })
$divisionNames = $config.divisionNames
$expectedTeams = Get-IntValue $config.expectedTeamsPerDivision

if ($channelId -notmatch '^\d+$') { throw "Division-leaders channelId must be numeric." }
if ($leagueRecordIds.Count -ne 13 -or @($leagueRecordIds | Sort-Object -Unique).Count -ne 13) {
  throw "Division-leaders config must contain thirteen unique BBU league IDs."
}
if ($expectedTeams -ne 10) { throw "Division-leaders config must expect 10 teams per BBU division." }

$leagueByRecordId = @{}
foreach ($recordId in $leagueRecordIds) {
  $matches = @($leagueData.leagues | Where-Object { (Get-StringValue $_.id).ToUpperInvariant() -eq $recordId })
  if ($matches.Count -ne 1) { throw "League data must contain exactly one '$recordId' record." }
  if ((Get-StringValue (Get-PropertyValue $matches[0] "format")).ToLowerInvariant() -ne "bestball") {
    throw "League '$recordId' is not a Best Ball Union division."
  }
  if ((Get-StringValue (Get-PropertyValue $matches[0] "sleeperLeagueId")) -notmatch '^\d+$') {
    throw "League '$recordId' does not have a valid Sleeper league ID."
  }
  if (-not (Get-StringValue (Get-PropertyValue $divisionNames $recordId))) {
    throw "Division-leaders config is missing the display name for '$recordId'."
  }
  $leagueByRecordId[$recordId] = $matches[0]
}

$leaderRows = [System.Collections.Generic.List[object]]::new()
foreach ($recordId in $leagueRecordIds) {
  $leagueRecord = (@($leagueData.leagues | Where-Object {
    (Get-StringValue (Get-PropertyValue -InputObject $_ -Name "id")).ToUpperInvariant() -eq $recordId
  }))[0]
  $sleeperLeagueId = Get-StringValue (Get-PropertyValue -InputObject $leagueRecord -Name "sleeperLeagueId")
  $league = Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$sleeperLeagueId"
  $rosters = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$sleeperLeagueId/rosters")
  $users = @(Invoke-JsonGet -Uri "https://api.sleeper.app/v1/league/$sleeperLeagueId/users")
  if ((Get-StringValue $league.league_id) -ne $sleeperLeagueId) { throw "Sleeper returned the wrong league for '$recordId'." }

  $ownedRosters = @($rosters | Where-Object { Get-StringValue $_.owner_id })
  if ($ownedRosters.Count -ne $expectedTeams) {
    throw "Division '$recordId' has $($ownedRosters.Count) owner-filled rosters instead of $expectedTeams. The existing Discord post was preserved."
  }

  $userById = @{}
  foreach ($user in $users) {
    $userId = Get-StringValue $user.user_id
    if ($userId) { $userById[$userId] = $user }
  }

  $standings = @($ownedRosters | ForEach-Object {
    $settings = Get-PropertyValue $_ "settings"
    $wins = Get-IntValue (Get-PropertyValue $settings "wins")
    $losses = Get-IntValue (Get-PropertyValue $settings "losses")
    $ties = Get-IntValue (Get-PropertyValue $settings "ties")
    $games = $wins + $losses + $ties
    [pscustomobject]@{
      rosterId = Get-IntValue $_.roster_id
      teamName = Get-TeamName -Roster $_ -UserById $userById
      wins = $wins
      losses = $losses
      ties = $ties
      games = $games
      recordPct = if ($games -gt 0) { ($wins + (0.5 * $ties)) / $games } else { 0.0 }
      pointsFor = Get-PointsFor -Settings $settings
    }
  } | Sort-Object `
    @{ Expression = { $_.recordPct }; Descending = $true }, `
    @{ Expression = { $_.pointsFor }; Descending = $true }, `
    @{ Expression = { $_.wins }; Descending = $true }, `
    @{ Expression = { $_.ties }; Descending = $true }, `
    @{ Expression = { $_.teamName }; Descending = $false }, `
    @{ Expression = { $_.rosterId }; Descending = $false })

  $hasResults = @($standings | Where-Object { $_.games -gt 0 -or $_.pointsFor -gt 0 }).Count -gt 0
  $leader = if ($hasResults) { $standings[0] } else { $null }
  $leaderRows.Add([pscustomobject]@{
    leagueRecordId = $recordId
    divisionName = Get-StringValue (Get-PropertyValue $divisionNames $recordId)
    sleeperLeagueId = $sleeperLeagueId
    hasResults = $hasResults
    teamName = if ($leader) { $leader.teamName } else { "" }
    rosterId = if ($leader) { $leader.rosterId } else { 0 }
    wins = if ($leader) { $leader.wins } else { 0 }
    losses = if ($leader) { $leader.losses } else { 0 }
    ties = if ($leader) { $leader.ties } else { 0 }
    pointsFor = if ($leader) { $leader.pointsFor } else { 0.0 }
  }) | Out-Null
}

$centralNow = Get-CentralTime
$fields = @($leaderRows | ForEach-Object {
  $value = if ($_.hasResults) {
    $record = if ($_.ties -gt 0) { "$($_.wins)-$($_.losses)-$($_.ties)" } else { "$($_.wins)-$($_.losses)" }
    "**$(Convert-ToPlainDiscordText $_.teamName 48)**`nRecord: $record  |  PF: $('{0:N2}' -f $_.pointsFor)"
  } else {
    "No leader established yet`nRecord: 0-0  |  PF: 0.00"
  }
  @{ name = $_.divisionName; value = $value; inline = $false }
})

$activeLeaderCount = @($leaderRows | Where-Object { $_.hasResults }).Count
$embed = @{
  title = "Best Ball Union - Division Leaders"
  url = $websiteUrl
  description = if ($activeLeaderCount -gt 0) {
    "Current first-place team in each BBU division. Record is ranked first, followed by points for."
  } else {
    "Division leaders will appear after completed regular-season results are available."
  }
  color = if ($activeLeaderCount -gt 0) { 0xC0392B } else { 0x5865F2 }
  fields = $fields
  footer = @{ text = "Live Sleeper standings | Refreshes daily at 2:10 PM Central" }
  timestamp = [datetimeoffset]::UtcNow.ToString("o")
}
Assert-EmbedLimits -Embed $embed
$payload = @{
  username = "VBP Best Ball Union"
  allowed_mentions = @{ parse = @() }
  embeds = @($embed)
}

$signatureSource = [pscustomobject]@{
  snapshotDate = $centralNow.ToString("yyyy-MM-dd")
  leaders = @($leaderRows | ForEach-Object {
    [pscustomobject]@{
      leagueRecordId = $_.leagueRecordId
      rosterId = $_.rosterId
      teamName = $_.teamName
      wins = $_.wins
      losses = $_.losses
      ties = $_.ties
      pointsFor = $_.pointsFor
    }
  })
}
$signature = Get-Sha256 ($signatureSource | ConvertTo-Json -Depth 6 -Compress)
$state = Get-State -Path $StatePath
$messageId = Get-StringValue $state.messageId

if (-not $ForceRefresh -and $messageId -and (Get-StringValue $state.signature) -eq $signature) {
  $result = [pscustomobject]@{ action = "current"; leaderCount = $activeLeaderCount; messageId = $messageId; payload = $payload }
  if ($PassThru) { $result } else { Write-Host "Discord division leaders are already current for $($centralNow.ToString('yyyy-MM-dd'))." }
  exit 0
}

if ($DryRun) {
  $result = [pscustomobject]@{ action = "dry-run"; leaderCount = $activeLeaderCount; messageId = $messageId; leaders = @($leaderRows); payload = $payload }
  if ($PassThru) { $result } else {
    Write-Host ("DRY RUN BBU division leaders: {0} active leader(s) across thirteen divisions." -f $activeLeaderCount)
    Write-Output ($payload | ConvertTo-Json -Depth 12)
  }
  exit 0
}

if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { throw "DISCORD_WEBHOOK_DIVISION_LEADERS is not configured." }
$webhookInfo = Invoke-JsonGet -Uri $WebhookUrl
$webhookChannelId = Get-StringValue $webhookInfo.channel_id
$webhookId = Get-StringValue $webhookInfo.id
if ($webhookChannelId -ne $channelId) {
  throw "The division-leaders webhook points to channel '$webhookChannelId', not configured channel '$channelId'."
}
$savedWebhookId = Get-StringValue $state.webhookId
if ($savedWebhookId -and $savedWebhookId -ne $webhookId) {
  throw "The division-leaders state belongs to a different Discord webhook."
}

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
  $postUri = "{0}?wait=true" -f $WebhookUrl.TrimEnd('/')
  $response = Invoke-DiscordJson -Uri $postUri -Payload $payload
  $messageId = Get-StringValue $response.id
  if (-not $messageId) { throw "Discord did not return a message ID for the division-leaders card." }
  $created = $true
}

Set-StateProperty -State $state -Name channelId -Value $channelId
Set-StateProperty -State $state -Name webhookId -Value $webhookId
Set-StateProperty -State $state -Name groupId -Value $groupId
Set-StateProperty -State $state -Name signature -Value $signature
Set-StateProperty -State $state -Name messageId -Value $messageId
Save-State -Path $StatePath -State $state

$result = [pscustomobject]@{
  action = if ($created) { "created" } else { "updated" }
  leaderCount = $activeLeaderCount
  messageId = $messageId
  leaders = @($leaderRows)
  payload = $payload
}
if ($PassThru) { $result }
else { Write-Host ("Discord BBU division leaders {0}: {1} active leader(s) across thirteen divisions." -f $result.action, $activeLeaderCount) }
