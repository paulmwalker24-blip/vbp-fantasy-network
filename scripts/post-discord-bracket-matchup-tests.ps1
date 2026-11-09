param(
  [string]$LedgerPath = 'tmp/bracket-playoffs-preview.json',
  [string]$StatePath = 'data/discord-bracket-matchups-state.json',
  [string]$PreviewPath = 'tmp/bracket-matchup-tests-preview.json',
  [string]$WebhookConfigPath = 'data/private/discord-webhooks.json',
  [string]$ChannelId = '1569380664799920278',
  [ValidateRange(1,31)][int]$StartSeed = 1,
  [switch]$AllMatchups,
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_REDRAFT_BRACKET_PLAYOFFS,
  [switch]$LockedField,
  [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Value($Object, [string]$Name) {
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}
function Clean-Text($Value, [int]$Limit = 50) {
  $text = [regex]::Replace([string]$Value, '[\r\n*_~`>|@]', ' ').Trim()
  if ($text.Length -gt $Limit) { return $text.Substring(0, $Limit - 3) + '...' }
  return $text
}
function Read-Sleeper([string]$Path) {
  try {
    $response = Invoke-RestMethod -Uri "https://api.sleeper.app/v1/$Path" -TimeoutSec 45
    if ($response -is [array]) { foreach ($item in $response) { Write-Output $item } } else { return $response }
  }
  catch { throw "Sleeper read failed for $Path. No incomplete matchup will be published." }
}
function Save-State {
  $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}
function Send-Discord([string]$Uri, [hashtable]$Payload, [string]$Method) {
  foreach ($attempt in 1..4) {
    try {
      Start-Sleep -Milliseconds 1200
      return Invoke-RestMethod -Uri $Uri -Method $Method -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Depth 12)))
    }
    catch {
      $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
      # A 429 explicitly rejects the request, so waiting and retrying cannot duplicate a post.
      if ($status -eq 429 -and $attempt -lt 4) {
        $delay = 5.0
        try { $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json; $delay = [math]::Ceiling([double]$errorBody.retry_after) + 1 } catch { }
        if ($delay -gt 60) { throw "Discord rate limit requires $delay seconds. Saved state preserved; resume later." }
        Write-Host "Discord rate limit: waiting $delay seconds before retrying the rejected request."
        Start-Sleep -Seconds ([math]::Max(1, $delay))
        continue
      }
      throw "Discord request failed (HTTP $status). Inspect the forum and saved state before retrying; ambiguous requests are not automatically retried."
    }
  }
}
function Read-DiscordMessage([string]$Uri) {
  foreach ($attempt in 1..4) {
    try {
      Start-Sleep -Milliseconds 1200
      return Invoke-RestMethod -Uri $Uri
    } catch {
      $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
      if ($attempt -lt 4 -and ($status -eq 429 -or $status -ge 500 -or $status -eq 0)) {
        Start-Sleep -Seconds 5
        continue
      }
      throw "Discord readback failed (HTTP $status); saved state preserved."
    }
  }
}

# Reuse the overview's complete-group, fresh-snapshot, unique-seed and tie validation.
& "$PSScriptRoot/post-discord-bracket-playoff-round.ps1" -LedgerPath $LedgerPath -LockedField:$LockedField -DryRun
$group = (Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json).groups | Where-Object groupId -eq 'BRACKET-2026-1'
$field = @($group.playoffField | Sort-Object seed)
$nfl = Read-Sleeper 'state/nfl'
if ($nfl.season -ne '2026' -or $nfl.season_type -ne 'regular' -or [int]$nfl.week -lt 1 -or [int]$nfl.week -gt 18) {
  throw 'Expected an active 2026 regular-season week for the playoff preview.'
}
$week = [int]$nfl.week
$showScores = $week -ge 13
New-Item -ItemType Directory -Path 'tmp' -Force | Out-Null
$cachePath = 'tmp/bracket-nfl-players.json'
if (-not (Test-Path -LiteralPath $cachePath) -or ((Get-Date) - (Get-Item -LiteralPath $cachePath).LastWriteTime).TotalHours -gt 24) {
  $playerData = Read-Sleeper 'players/nfl'
  $playerData | ConvertTo-Json -Depth 12 -Compress | Set-Content -LiteralPath $cachePath -Encoding UTF8
} else { $playerData = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json }
$cache = @{}
$plans = @()
$pairs = if ($AllMatchups) { @(foreach ($seed in 1..15) { ,@($seed, (31 - $seed)) }; ,@(31,32)) } else { @(@(1,30), @(2,29), @(3,28), @(31,32)) }
foreach ($pair in $pairs) {
  $entries = @($field[$pair[0] - 1], $field[$pair[1] - 1])
  $teamPayloads = @()
  $scoreboardTeams = @()
  foreach ($entry in $entries) {
    $team = $entry.team
    $leagueId = [string]$team.sleeperLeagueId
    if (-not $cache.ContainsKey($leagueId)) {
      $league = Read-Sleeper "league/$leagueId"
      if ($league.season -ne '2026') { throw 'League season mismatch.' }
      $cache[$leagueId] = @{
        league = $league
        rosters = @(Read-Sleeper "league/$leagueId/rosters")
        matchups = if ($showScores) { @(Read-Sleeper "league/$leagueId/matchups/13") } else { @() }
      }
    }
    $source = $cache[$leagueId]
    $roster = @($source.rosters | Where-Object roster_id -eq $team.rosterId)
    if ($roster.Count -ne 1 -or [string]$roster[0].owner_id -ne [string]$team.ownerId) { throw 'Missing or changed roster owner; refresh the preview.' }
    $roster = $roster[0]
    $matchup = $null
    if ($showScores) {
      $matches = @($source.matchups | Where-Object roster_id -eq $team.rosterId)
      if ($matches.Count -ne 1) { throw 'Missing Week 13 matchup data.' }
      $matchup = $matches[0]
    }
    $name = Clean-Text $(if ($team.teamName) { $team.teamName } else { $team.displayName }) 40
    $scoreboardScore = if ($showScores) { '{0:N2}' -f $matchup.points } else { '--' }
    $scoreboardTeams += "**#$($entry.seed) $name** - $scoreboardScore"
    $slots = @($source.league.roster_positions | Where-Object { $_ -notin @('BN','IR','TAXI') })
    $starters = if ($showScores) { @($matchup.starters) } else { @($roster.starters) }
    if ($starters.Count -ne $slots.Count) { throw 'Starter slots do not match the league lineup.' }
    $lines = @("## #$($entry.seed) $name", "$($team.localLeagueName) | Record: $($team.wins)-$($team.losses)-$($team.ties)")
    if ($showScores) {
      if ($null -eq (Get-Value $matchup 'points')) { throw 'Sleeper did not supply a Week 13 team score.' }
      $lines += "### Week 13 score: $('{0:N2}' -f $matchup.points)"
    }
    $lines += @("[View team in Sleeper](https://sleeper.com/leagues/$leagueId/team/$($team.rosterId))", '', '**STARTERS**')
    for ($i = 0; $i -lt $starters.Count; $i++) {
      $id = [string]$starters[$i]
      if ($id -eq '0' -or -not $id) { $lines += "$($slots[$i]) | Empty slot"; continue }
      $player = Get-Value $playerData $id
      $playerName = if ($player) { Clean-Text "$($player.first_name) $($player.last_name)" 35 } else { "Player $id" }
      $line = "$($slots[$i]) | $playerName"
      if ($showScores) {
        $points = Get-Value (Get-Value $matchup 'players_points') $id
        if ($null -eq $points) {
          $starterPoints = @(Get-Value $matchup 'starters_points')
          if ($starterPoints.Count -eq $starters.Count) { $points = $starterPoints[$i] }
        }
        $score = if ($null -eq $points) { '--' } else { '{0:N2}' -f [double]$points }
        $line += " | **$score**"
      }
      $lines += $line
    }
    # Before Week 13, use current roster starters and do not fetch or display weekly scores.
    $reserve = @($roster.reserve | Where-Object { $_ })
    $taxi = @((Get-Value $roster 'taxi') | Where-Object { $_ })
    foreach ($section in @('BENCH','IR','TAXI')) {
      $ids = if ($section -eq 'IR') { $reserve } elseif ($section -eq 'TAXI') { $taxi } else {
        @($roster.players | Where-Object { $_ -notin $starters -and $_ -notin $reserve -and $_ -notin $taxi })
      }
      if (@($ids).Count -eq 0) { continue }
      $lines += @('', "**$section**")
      foreach ($id in $ids) {
        $player = Get-Value $playerData ([string]$id)
        $playerName = if ($player) { Clean-Text "$($player.first_name) $($player.last_name)" 35 } else { "Player $id" }
        $position = if ($player) { [string]$player.position } else { '?' }
        $lines += "$position | $playerName"
      }
    }
    $lines += @('', "-# Roster snapshot $((Get-Date).ToString('MMM d, h:mm tt')) CT")
    $content = $lines -join "`n"
    if ($content.Length -gt 2000) { throw 'Team message exceeds 2000 characters.' }
    $teamPayloads += @{ username = 'VBP Bracket Playoffs'; content = $content; embeds = @(); allowed_mentions = @{ parse = @() }; flags = 4 }
  }
  $wildcard = $pair[0] -eq 31
  # Stable seed-pair titles remain accurate when projected teams change each Tuesday.
  $title = if ($wildcard) { 'Wild Card Play-In | #31 vs #32' } else { 'Round 1 | #{0} vs #{1}' -f $pair[0], $pair[1] }
  $scoreNote = if ($showScores) { 'Week 13 scores | Tuesday refresh' } else { 'Scores begin Week 13.' }
  $fieldLabel = if ($LockedField) { 'Locked' } else { 'Projected' }
  $intro = "## SCORE`n`n$($scoreboardTeams -join "`n`n")`n`n-# $fieldLabel $(if ($wildcard) {'Wild Card Play-In'} else {'Round 1'}) | $scoreNote"
  $plans += @{ key = "2026-round1-$($pair[0])-$($pair[1])"; threadName = $title; intro = @{username='VBP Bracket Playoffs'; content=$intro; embeds=@(); flags=4; allowed_mentions=@{parse=@()}}; teams=$teamPayloads }
}
# Build and validate every plan before any Discord mutation.
$plans | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $PreviewPath -Encoding UTF8
if ($DryRun) { Write-Host "Validated $($plans.Count) matchups, $($plans.Count * 2) team messages, Week $week. Preview: $PreviewPath"; return }
$webhook = $WebhookUrl
if (-not $webhook) {
  $config = Get-Content -LiteralPath $WebhookConfigPath -Raw | ConvertFrom-Json
  $webhook = [string]$config.channels.'redraft-bracket-playoffs'
}
if ($webhook -notmatch '^https://discord\.com/api(?:/v\d+)?/webhooks/\d+/[A-Za-z0-9_-]+$') { throw 'Invalid playoff webhook URL.' }
try { $info = Invoke-RestMethod -Uri $webhook } catch { throw 'Webhook verification failed.' }
if ([string]$info.channel_id -ne $ChannelId) { throw 'Wrong playoff forum channel.' }
$state = if (Test-Path -LiteralPath $StatePath) { Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json } else {
  [pscustomobject]@{ channelId=$ChannelId; webhookId=[string]$info.id; posts=[pscustomobject]@{} }
}
if ($state.channelId -ne $ChannelId -or $state.webhookId -ne [string]$info.id) { throw 'Saved test state belongs to a different webhook/channel.' }
foreach ($plan in $plans) {
  $seedNumber = [int](($plan.key -split '-')[-2])
  if ($seedNumber -lt $StartSeed) { continue }
  $saved = Get-Value $state.posts $plan.key
  if (-not $saved) {
    $payload = $plan.intro.Clone(); $payload.thread_name = $plan.threadName
    $response = Send-Discord "${webhook}?wait=true" $payload 'Post'
    if (-not $response.id -or -not $response.channel_id) { throw 'No thread/message ID returned. Inspect Discord before retrying.' }
    $saved = [pscustomobject]@{ threadId=[string]$response.channel_id; messageId=[string]$response.id; teamMessageIds=@('','') }
    $state.posts | Add-Member -NotePropertyName $plan.key -NotePropertyValue $saved
    Save-State
  } else { Send-Discord "$webhook/messages/$($saved.messageId)?thread_id=$($saved.threadId)" $plan.intro 'Patch' | Out-Null }
  $introReadback = Read-DiscordMessage "$webhook/messages/$($saved.messageId)?thread_id=$($saved.threadId)"
  if ($introReadback.content -ne $plan.intro.content -or @($introReadback.embeds).Count -ne 0) { throw 'Scoreboard message readback mismatch.' }
  foreach ($i in 0..1) {
    $messageId = $saved.teamMessageIds[$i]
    if ($messageId) {
      $existing = Read-DiscordMessage "$webhook/messages/${messageId}?thread_id=$($saved.threadId)"
      # Discord cannot change a message's sender name on edit. Migrate old team-name
      # senders once so changing projected seeds never leaves a different owner's name.
      if ($existing.author.username -ne 'VBP Bracket Playoffs') {
        $response = Send-Discord "${webhook}?wait=true&thread_id=$($saved.threadId)" $plan.teams[$i] 'Post'
        if (-not $response.id) { throw 'No migrated team message ID returned.' }
        $pending = @(@((Get-Value $saved 'obsoleteMessageIds')) | Where-Object { $_ })
        $saved | Add-Member -NotePropertyName obsoleteMessageIds -NotePropertyValue @($pending + $messageId) -Force
        $saved.teamMessageIds[$i] = [string]$response.id
        Save-State
        $messageId = [string]$response.id
      }
    }
    if ($messageId) {
      Send-Discord "$webhook/messages/${messageId}?thread_id=$($saved.threadId)" $plan.teams[$i] 'Patch' | Out-Null
    } else {
      $response = Send-Discord "${webhook}?wait=true&thread_id=$($saved.threadId)" $plan.teams[$i] 'Post'
      if (-not $response.id) { throw 'No team message ID returned. Inspect Discord before retrying.' }
      $saved.teamMessageIds[$i] = [string]$response.id
      Save-State
    }
    $readback = Read-DiscordMessage "$webhook/messages/$($saved.teamMessageIds[$i])?thread_id=$($saved.threadId)"
    if ($readback.content -ne $plan.teams[$i].content -or @($readback.embeds).Count -ne 0) { throw 'Team message readback mismatch.' }
  }
  foreach ($obsolete in @((Get-Value $saved 'obsoleteMessageIds')) | Where-Object { $_ }) {
    if ($obsolete -in $saved.teamMessageIds) { throw 'Refusing to remove a current roster message.' }
    Send-Discord "$webhook/messages/${obsolete}?thread_id=$($saved.threadId)" @{} 'Delete' | Out-Null
    $saved.obsoleteMessageIds = @($saved.obsoleteMessageIds | Where-Object { $_ -ne $obsolete })
    Save-State
  }
  Write-Host "Verified $($plan.threadName) | thread $($saved.threadId)"
}
