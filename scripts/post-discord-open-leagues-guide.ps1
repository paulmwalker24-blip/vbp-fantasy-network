param(
  [string]$JsonPath = "data/leagues.json",
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "open-leagues-guide",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_URL,
  [switch]$DryRun,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ObjectPropertyValue {
  param([AllowNull()][object]$InputObject, [string]$Name)
  if ($null -eq $InputObject) { return $null }
  $property = $InputObject.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
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
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
      New-Item -ItemType Directory -Path $directory | Out-Null
    }
  }

  $entry = [pscustomobject]@{ messageId = $MessageId; updatedAt = (Get-Date).ToString("s") }
  if ($state.PSObject.Properties[$Key]) {
    $state.$Key = $entry
  } else {
    $state | Add-Member -NotePropertyName $Key -NotePropertyValue $entry
  }
  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path
}

function Group-LeagueNamesByStatus {
  param(
    [object[]]$Leagues,
    [string[]]$Formats,
    [string[]]$Statuses
  )

  $formatSet = @{}
  foreach ($format in $Formats) { $formatSet[$format] = $true }
  $statusSet = @{}
  foreach ($status in $Statuses) { $statusSet[$status] = $true }

  return @($Leagues | Where-Object {
    $format = ([string]$_.format).Trim().ToLowerInvariant()
    $status = ([string]$_.status).Trim().ToLowerInvariant()
    $formatSet.ContainsKey($format) -and $statusSet.ContainsKey($status)
  } | Sort-Object { [string]$_.id } | ForEach-Object { [string]$_.name })
}

function Format-LeagueList {
  param([string[]]$Names)
  if (-not $Names -or $Names.Count -eq 0) { return "None currently listed." }
  return (($Names | ForEach-Object { "- $_" }) -join "`n")
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find league data file at '$JsonPath'."
}

$siteUrl = $AssetBaseUrl.TrimEnd('/')
$timestamp = (Get-Date).ToUniversalTime().ToString("o")
$leaguePayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $JsonPath).Path -Raw | ConvertFrom-Json
$leagues = @($leaguePayload.leagues)

$fullSeasonalNames = Group-LeagueNamesByStatus -Leagues $leagues -Formats @("redraft", "redraft32", "comanager", "chopped") -Statuses @("full")
$fullDynastyNames = Group-LeagueNamesByStatus -Leagues $leagues -Formats @("dynasty", "dynastybracket", "keeper") -Statuses @("full")
$fullBestBallNames = Group-LeagueNamesByStatus -Leagues $leagues -Formats @("bestball", "gauntlet") -Statuses @("full")

$introDescription = @(
  "This is the format guide for VBP league openings.",
  "",
  "Use this post to understand the league types. Use the live webhook boards below it for current openings, assigned counts, paid-count notes, and active join links.",
  "",
  "Full or established leagues may be listed here as proof of network activity, but full leagues do not include join details. Current join links belong in the live openings posts below.",
  "",
  "**Main hub:** $siteUrl/"
) -join "`n"

$seasonalDescription = @(
  "**Standard Redraft**",
  "12-team seasonal leagues using VBP Progressive PPR. Lineup is 1 QB, 2 RB, 2 WR, 1 TE, and 2 FLEX with 6 bench spots and `$200 FAAB.",
  "",
  "**32-Team Redraft**",
  "A deeper single-season field with 32 teams, 7 starters, and 4 bench spots. Lineup is 1 RB, 2 WR, 3 FLEX, and 1 SUPER FLEX. QB is only required through the SUPER FLEX.",
  "",
  "**Co-Manager Redraft**",
  "A 12-team front-office format where each team has 2-3 co-managers. Uses 0.5 PPR, TE premium, 6-point passing TDs, Superflex, 5 bench spots, 1 IR, and a 3RR slow draft.",
  "",
  "**Chopped**",
  "An 18-team elimination redraft where weekly survival matters. Uses Progressive PPR, 1 QB, 2 RB, 2 WR, 1 TE, 2 FLEX, and `$200 FAAB."
) -join "`n"

$bracketDescription = @(
  "**Redraft Bracket**",
  "A 60-team tournament made of five separate 12-team redraft divisions. Each division drafts and plays locally, then the best 32 teams feed one shared single-elimination playoff bracket.",
  "",
  "Roster is 15 players. Lineup is 1 QB, 2 RB, 2 WR, 1 TE, 1 FLEX, and 1 SUPER FLEX with 6 bench spots and `$200 FAAB. Fast and slow draft rooms may be available.",
  "",
  "**Dynasty Bracket**",
  "A 48-team dynasty network made of four 12-team divisions. Each division is its own dynasty league, while 16 teams qualify for one shared Dynasty Bracket playoff.",
  "",
  "Lineup is 1 QB, 2 RB, 2 WR, 1 TE, 3 FLEX, and 1 SUPERFLEX with 13 bench, 4 taxi, and 4 IR. Startup draft is 3RR, with current season plus the next two seasons due up front."
) -join "`n"

$dynastyDescription = @(
  "**Standard Dynasty**",
  "Full long-term roster control in a 12-team Superflex dynasty league. Uses VBP Progressive PPR, 1 QB, 2 RB, 2 WR, 1 TE, 3 FLEX, and 1 SUPERFLEX.",
  "",
  "DYN8 and later use a 31-round startup, then cut to 27 total players after preseason. Future seasons use 4-round rookie drafts. New startups require current season plus the next two seasons paid up front.",
  "",
  "**Keeper**",
  "A middle ground between redraft and dynasty. Each team may keep up to 3 players each offseason.",
  "",
  "Drafted players cost two rounds earlier each keeper season. Undrafted players start at a 10th-round keeper cost. Keeper leagues use a 3RR draft and require two seasons due up front."
) -join "`n"

$bestBallDescription = @(
  "**Best Ball Union**",
  "10-team draft-and-hold best ball rooms. Normally fast 90-second snake drafts. Roster is 18 players.",
  "",
  "Lineup is 1 QB, 2 RB, 2 WR, 1 TE, and 2 FLEX with 9 bench spots. Uses Progressive PPR and a weekly median matchup. No waivers, trades, pickups, or weekly lineup setting after the draft.",
  "",
  "**Best Ball Gauntlet**",
  "A 24-team micro best ball challenge. Current open-room versions may use compact 5-player or 6-player roster builds depending on the specific room.",
  "",
  "Core concept is draft-only best ball: no waivers, trades, pickups, or lineup setting.",
  "",
  "**Pick'em**",
  "A low-maintenance NFL picks contest. It is against the spread, not a straight winner pool. No draft, no fantasy roster, no waivers, no lineups, and no trades."
) -join "`n"

$fullDescription = @(
  "**Full / Established Seasonal Rooms**",
  (Format-LeagueList -Names $fullSeasonalNames),
  "",
  "**Full / Established Dynasty or Keeper Rooms**",
  (Format-LeagueList -Names $fullDynastyNames),
  "",
  "**Full / Established Best Ball Rooms**",
  (Format-LeagueList -Names $fullBestBallNames),
  "",
  "Full rooms are listed only for context. Use the live openings posts below for current joinable rooms."
) -join "`n"

$joinDescription = @(
  "Use the live status boards below this guide.",
  "",
  "Those posts show current openings, assigned spots, active rooms, current join links, rules links, and whether a room is full, drafting, or still recruiting.",
  "",
  "If you are not sure where to start, reply or DM with:",
  "",
  "1. Redraft, dynasty, best ball, bracket, keeper, chopped, or Pick'em",
  "2. Fast draft or slow draft preference, if it matters",
  "3. Buy-in range",
  "4. Simple seasonal play or a long-term league",
  "",
  "I will point you to the best current fit."
) -join "`n"

$payloadObject = @{
  content = ""
  embeds = @(
    @{
      title = "VBP League Openings Guide"
      url = "$siteUrl/"
      description = $introDescription
      color = 0x5865F2
      thumbnail = @{ url = "$siteUrl/assets/images/sleeper-thumbnail-general.png" }
      footer = @{ text = "Format guide first, live opening boards below" }
      timestamp = $timestamp
    },
    @{
      title = "Seasonal Redraft Formats"
      description = $seasonalDescription
      color = 0x2F80ED
      footer = @{ text = "Live join links stay in the status boards below" }
      timestamp = $timestamp
    },
    @{
      title = "Bracket Formats"
      description = $bracketDescription
      color = 0x27AE60
      footer = @{ text = "Tournament formats with separate league rooms" }
      timestamp = $timestamp
    },
    @{
      title = "Dynasty and Keeper Formats"
      description = $dynastyDescription
      color = 0x9B51E0
      footer = @{ text = "Long-term formats and carryover decisions" }
      timestamp = $timestamp
    },
    @{
      title = "Best Ball and Specialty Formats"
      description = $bestBallDescription
      color = 0xF2994A
      footer = @{ text = "Low-maintenance and specialty formats" }
      timestamp = $timestamp
    },
    @{
      title = "Full / Established Rooms"
      description = $fullDescription
      color = 0x828282
      footer = @{ text = "No join details for full leagues" }
      timestamp = $timestamp
    },
    @{
      title = "How To Use This Channel"
      description = $joinDescription
      color = 0xF2C94C
      footer = @{ text = "Use the live boards below this guide for current openings" }
      timestamp = $timestamp
    }
  )
}

$payload = $payloadObject | ConvertTo-Json -Depth 8
$result = [pscustomobject]@{
  embeds = @($payloadObject.embeds)
  fullSeasonalRooms = @($fullSeasonalNames)
  fullDynastyRooms = @($fullDynastyNames)
  fullBestBallRooms = @($fullBestBallNames)
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
      Write-Warning ("Could not update stored Discord open-leagues guide message {0}; posting a new guide instead. {1}" -f $existingMessageId, $_.Exception.Message)
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
  if ($DryRun) { Write-Host "Dry run only. Set DISCORD_WEBHOOK_URL or pass -WebhookUrl to post the open-leagues guide into Discord." }
  else { Write-Host ("Discord open-leagues guide {0}: {1}" -f $result.action, $result.messageId) }
}
