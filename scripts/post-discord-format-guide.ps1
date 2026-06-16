param(
  [Parameter(Mandatory = $true)]
  [string]$FormatKey,
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "",
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

function Get-FormatGuideConfig {
  param([string]$Key)

  switch ($Key.Trim().ToLowerInvariant()) {
    "redraft" {
      return [pscustomobject]@{
        key = "redraft"
        title = "Standard Redraft Guide"
        summary = "Seasonal VBP redraft leagues for managers who want one clean yearly league."
        bestFor = "Managers who want active waivers, trades, weekly lineup decisions, and a normal season-long playoff race."
        basics = @("Typical size: 12 teams", "Scoring: VBP Progressive PPR", "Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 2 FLEX", "Bench: 6", "Waivers: `$200 FAAB")
        rulesPage = "redraft-constitution.html"
        image = "constitution-redraft.png"
        color = 0xC0392B
      }
    }
    "redraft32" {
      return [pscustomobject]@{
        key = "redraft32"
        title = "32-Team Redraft Guide"
        summary = "A single-season 32-team field with scarce player supply and deeper lineup decisions."
        bestFor = "Managers who want a deeper redraft challenge without dynasty carryover."
        basics = @("Size: 32 teams", "Roster: 7 starters, 4 bench", "Lineup: 1 RB, 2 WR, 3 FLEX, 1 SUPER FLEX", "QB is only required through the SUPER FLEX", "Waivers: `$200 FAAB")
        rulesPage = "32-team-redraft-constitution.html"
        image = "constitution-32-team-redraft.png"
        color = 0x2F80ED
      }
    }
    "comanager" {
      return [pscustomobject]@{
        key = "comanager"
        title = "Co-Manager Redraft Guide"
        summary = "A front-office redraft format where every team has 2-3 co-managers."
        bestFor = "Friends, couples, siblings, coworkers, or group-chat partners who want to draft and manage one team together."
        basics = @("Size: 12 teams", "Team control: 2-3 co-managers per team", "Scoring: 0.5 PPR, TE premium, 6-point passing TDs", "Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 2 FLEX, 1 SUPER FLEX", "Bench/reserve: 5 bench, 1 IR", "Draft: 3RR slow draft")
        rulesPage = "co-manager-constitution.html"
        image = "constitution-co-manager.png"
        color = 0x27AE60
      }
    }
    "bracket" {
      return [pscustomobject]@{
        key = "bracket"
        title = "Redraft Bracket Guide"
        summary = "A 60-team tournament made of five separate 12-team redraft divisions feeding one shared playoff bracket."
        bestFor = "Managers who want a normal Sleeper redraft room plus a larger cross-division tournament."
        basics = @("Total field: 60 teams", "Divisions: five 12-team redraft rooms", "Overall playoff: 32-team single-elimination bracket", "Scoring: VBP Progressive PPR", "Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 1 FLEX, 1 SUPER FLEX", "Bench: 6", "Waivers: `$200 FAAB", "Draft rooms: fast and slow divisions may be available")
        rulesPage = "bracket-constitution.html"
        image = "constitution-bracket.png"
        color = 0x27AE60
      }
    }
    "dynastybracket" {
      return [pscustomobject]@{
        key = "dynastybracket"
        title = "Dynasty Bracket Guide"
        summary = "A 48-team dynasty network made of four separate 12-team divisions feeding one shared playoff bracket."
        bestFor = "Dynasty managers who want long-term roster building inside a larger network tournament."
        basics = @("Total field: 48 teams", "Divisions: four 12-team dynasty leagues", "Overall playoff: 16-team shared bracket", "Scoring: VBP Progressive PPR with Superflex", "Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 3 FLEX, 1 SUPERFLEX", "Bench/taxi/IR: 13 bench, 4 taxi, 4 IR", "Draft: 3RR startup", "Payment model: current season plus next two seasons due up front")
        rulesPage = "dynasty-bracket-constitution.html"
        image = "constitution-dynasty-bracket.png"
        color = 0x9B51E0
      }
    }
    "dynasty" {
      return [pscustomobject]@{
        key = "dynasty"
        title = "Standard Dynasty Guide"
        summary = "A 12-team long-term dynasty format with full roster continuity."
        bestFor = "Managers who want multi-year roster building, rookie drafts, trades, and future-pick strategy."
        basics = @("Size: 12 teams", "Scoring: VBP Progressive PPR with Superflex", "Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 3 FLEX, 1 SUPERFLEX", "DYN8 and later: 31-round startup, then cut to 27 total players after preseason", "Future seasons: 4-round rookie drafts", "New startups require current season plus next two seasons paid up front")
        rulesPage = "dynasty-constitution.html"
        image = "constitution-dynasty.png"
        color = 0x9B51E0
      }
    }
    "keeper" {
      return [pscustomobject]@{
        key = "keeper"
        title = "Keeper Guide"
        summary = "A middle ground between redraft and dynasty with limited player carryover."
        bestFor = "Managers who want yearly redraft energy with a small amount of long-term roster planning."
        basics = @("Size: 12 teams", "Keepers: up to 3 players per offseason", "Drafted players cost two rounds earlier each keeper season", "Undrafted players start at a 10th-round keeper cost", "Draft: 3RR", "Payment model: two seasons due up front")
        rulesPage = "keeper-constitution.html"
        image = "constitution-keeper.png"
        color = 0xF2C94C
      }
    }
    "bestball" {
      return [pscustomobject]@{
        key = "bestball"
        title = "Best Ball Union Guide"
        summary = "10-team draft-and-hold best ball rooms connected by a Union-wide high-score prize."
        bestFor = "Managers who want to draft, then avoid waivers, trades, and weekly lineup setting."
        basics = @("Size: 10 teams per room", "Draft: normally fast 90-second snake", "Roster: 18 players", "Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 2 FLEX", "Bench: 9", "Scoring: VBP Progressive PPR with weekly median matchup", "No waivers, trades, pickups, or weekly lineup setting after draft")
        rulesPage = "bestball-constitution.html"
        image = "constitution-bestball-union.png"
        color = 0x2F80ED
      }
    }
    "bbg" {
      return [pscustomobject]@{
        key = "bbg"
        title = "Best Ball Gauntlet Guide"
        summary = "A 24-team micro best ball challenge with compact rosters and uncomfortable draft decisions."
        bestFor = "Managers who want a small-buy-in best ball format where every roster spot matters."
        basics = @("Size: 24 teams", "Format: doubleheader micro best ball", "Current open-room versions may use compact 5-player or 6-player roster builds", "Core concept: draft-only best ball", "No waivers, trades, pickups, or lineup setting")
        rulesPage = "bestball-gauntlet-constitution.html"
        image = "constitution-bestball-gauntlet.png"
        color = 0xF2994A
      }
    }
    "chopped" {
      return [pscustomobject]@{
        key = "chopped"
        title = "Chopped Guide"
        summary = "An elimination-style redraft where weekly survival matters as much as total scoring."
        bestFor = "Managers who want pressure every week and a different survival-style format."
        basics = @("Size: 18 teams", "Scoring: VBP Progressive PPR", "Lineup: 1 QB, 2 RB, 2 WR, 1 TE, 2 FLEX", "Waivers: `$200 FAAB", "Weekly survival follows the posted elimination rules")
        rulesPage = "chopped-constitution.html"
        image = "constitution-chopped.png"
        color = 0xEB5757
      }
    }
    "pickem" {
      return [pscustomobject]@{
        key = "pickem"
        title = "Pick'em Guide"
        summary = "A low-maintenance NFL picks contest based on spreads rather than fantasy rosters."
        bestFor = "Managers who want a season-long football contest with no draft, waivers, or lineup management."
        basics = @("Format: NFL picks against the spread", "No fantasy roster", "No draft, waivers, lineups, or trades", "Standings are based on Sleeper's Pick'em scoring")
        rulesPage = "pickem-constitution.html"
        image = "constitution-pickem.png"
        color = 0x56CCF2
      }
    }
    "sacrifice" {
      return [pscustomobject]@{
        key = "sacrifice"
        title = "Sacrifice Redraft Guide"
        summary = "A test redraft format where a team's highest-scoring starter must be sacrificed during the season."
        bestFor = "Managers who like experimental formats and roster-management chaos."
        basics = @("Format: seasonal redraft test league", "Standard roster management with a sacrifice mechanic", "During the sacrifice window, each team's highest-scoring starter must be dropped under the posted rules")
        rulesPage = "sacrifice-redraft-constitution.html"
        image = "constitution-sacrifice.png"
        color = 0xBB6BD9
      }
    }
    default {
      throw "Unsupported format key '$Key'."
    }
  }
}

$config = Get-FormatGuideConfig -Key $FormatKey
if ([string]::IsNullOrWhiteSpace($StateKey)) {
  $StateKey = ("{0}-guide" -f $config.key)
}

$siteUrl = $AssetBaseUrl.TrimEnd('/')
$timestamp = (Get-Date).ToUniversalTime().ToString("o")
$rulesUrl = ("{0}/{1}" -f $siteUrl, $config.rulesPage)
$imageUrl = ("{0}/assets/images/{1}" -f $siteUrl, $config.image)
$basics = (($config.basics | ForEach-Object { "- $_" }) -join "`n")

$description = @(
  $config.summary,
  "",
  "**Best for**",
  $config.bestFor,
  "",
  "**Format basics**",
  $basics,
  "",
  "**How this channel works**",
  "Full leagues may be listed below for context only. Full leagues do not include join links or recruiting instructions.",
  "Current openings, assigned counts, paid-count notes, draft status, and active join links appear in the live status board underneath this guide.",
  "",
  "**Rules:** $rulesUrl"
) -join "`n"

$payloadObject = @{
  content = ""
  embeds = @(
    @{
      title = $config.title
      url = $rulesUrl
      description = $description
      color = $config.color
      thumbnail = @{ url = $imageUrl }
      footer = @{ text = "Format guide. Live openings board should sit below this post." }
      timestamp = $timestamp
    }
  )
}

$payload = $payloadObject | ConvertTo-Json -Depth 8
$result = [pscustomobject]@{
  formatKey = $config.key
  embeds = @($payloadObject.embeds)
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
      Write-Warning ("Could not update stored Discord {0} guide message {1}; posting a new guide instead. {2}" -f $config.key, $existingMessageId, $_.Exception.Message)
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
  if ($DryRun) { Write-Host ("Dry run only for {0}. Set DISCORD_WEBHOOK_URL or pass -WebhookUrl to post this guide into Discord." -f $config.title) }
  else { Write-Host ("Discord {0} guide {1}: {2}" -f $config.key, $result.action, $result.messageId) }
}
