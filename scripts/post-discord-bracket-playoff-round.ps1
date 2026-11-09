param(
  [string]$LedgerPath = "tmp/bracket-playoffs-preview.json",
  [string]$WebhookConfigPath = "data/private/discord-webhooks.json",
  [string]$WebhookKey = "redraft-bracket-playoffs",
  [string]$ChannelId = "1569380664799920278",
  [string]$StatePath = "data/discord-bracket-playoffs-state.json",
  [string]$PreviewPath = "tmp/bracket-playoffs-round1-preview.json",
  [switch]$DryRun,
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_REDRAFT_BRACKET_PLAYOFFS,
  [switch]$LockedField
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TeamKey($Team) { return "$($Team.leagueRecordId):$($Team.rosterId)" }
function Get-TeamText($Team) {
  $name = if ($Team.teamName) { [string]$Team.teamName } else { [string]$Team.displayName }
  $name = [regex]::Replace($name, '[\r\n*_~`>|@]', ' ').Trim()
  if ($name.Length -gt 50) { $name = $name.Substring(0, 47) + '...' }
  return "**$name** ($($Team.localLeagueName))`n$($Team.wins)-$($Team.losses)-$($Team.ties) | $('{0:N2}' -f $Team.pointsFor) PF"
}

$ledger = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$groups = @($ledger.groups | Where-Object groupId -eq 'BRACKET-2026-1')
if ($groups.Count -ne 1) { throw 'Expected exactly one BRACKET-2026-1 group.' }
$group = $groups[0]
if ($group.season -ne '2026' -or -not $group.seasonDataReady -or -not $group.seedingReady) {
  throw 'The 2026 bracket group is not ready.'
}
$snapshots = @($group.leagueSnapshots)
$ids = @($snapshots.leagueRecordId | Sort-Object -Unique)
if ($snapshots.Count -ne 5 -or ($ids -join ',') -ne 'RDB1,RDB2,RDB3,RDB4,RDB5') {
  throw 'Expected exactly RDB1 through RDB5.'
}
foreach ($snapshot in $snapshots) {
  if (@($snapshot.standings).Count -ne 12 -or $snapshot.status -ne 'in_season') {
    throw 'Each division must contain 12 teams and be in season.'
  }
}
$teams = @($snapshots | ForEach-Object { $_.standings })
if (@($teams | ForEach-Object { Get-TeamKey $_ } | Sort-Object -Unique).Count -ne 60) {
  throw 'Expected 60 unique league/roster entries.'
}
$age = (Get-Date) - [datetime]$group.lastSyncedAt
if ($LockedField) {
  $marker = $ledger.PSObject.Properties['playoffFieldLocked']
  $recordCounts = @($teams | ForEach-Object { $_.wins + $_.losses + $_.ties } | Sort-Object -Unique)
  if (-not $marker -or -not $marker.Value -or $recordCounts.Count -ne 1 -or $recordCounts[0] -ne 12) { throw 'A locked playoff field requires the saved final Week 12 snapshot.' }
} elseif ($age.TotalHours -gt 2 -or $age.TotalMinutes -lt -5) { throw 'Refresh the separate preview ledger before publishing (maximum age: two hours).' }
$field = @($group.playoffField | Sort-Object seed)
if ($field.Count -ne 32 -or (($field.seed -join ',') -ne ((1..32) -join ',')) -or
  @($field | ForEach-Object { Get-TeamKey $_.team } | Sort-Object -Unique).Count -ne 32) {
  throw 'Expected exactly 32 distinct teams seeded 1 through 32.'
}
# Exact record/PF ties require the constitution's Max Points For review.
$ties = @($teams | Group-Object recordPct, pointsFor | Where-Object Count -gt 1)
if ($ties.Count -gt 0) { throw 'Exact record/points ties require commissioner Max Points For review before posting.' }

$lines = if ($LockedField) { @('## 2026 Round 1 - Playoff Matchups', 'Final field from the completed 12-game regular season.', '') } else { @('## 2026 Round 1 - Projected Matchups', 'If the playoffs started from this snapshot. Seeds are not locked.', '') }
function Get-OverviewName($Entry) {
  $name = if ($Entry.team.teamName) { [string]$Entry.team.teamName } else { [string]$Entry.team.displayName }
  $name = [regex]::Replace($name, '[\r\n*_~`>|@]', ' ').Trim()
  if ($name.Length -gt 28) { $name = $name.Substring(0, 25) + '...' }
  return "#$($Entry.seed) $name ($($Entry.team.localLeagueName))"
}
foreach ($seed in 1..15) {
  $opponent = 31 - $seed
  $lines += "$(Get-OverviewName $field[$seed - 1]) vs $(Get-OverviewName $field[$opponent - 1])"
}
$lines += @('', '**Wild Card Play-In**', "$(Get-OverviewName $field[30]) vs $(Get-OverviewName $field[31])", '', '**Next round:** Reorder the 15 winners by original seed. Insert the wildcard winner at #9 to face #8. Play 1 vs 16 through 8 vs 9, then keep the bracket fixed.', '', "Snapshot: $($group.lastSyncedAt) CT | Week 13 pairings")
$content = $lines -join "`n"
if ($content.Length -gt 2000) { throw 'Overview exceeds Discord plain-text limit.' }
$payload = @{ username = 'VBP Bracket Playoffs'; content = $content; allowed_mentions = @{ parse = @() }; embeds = @(); flags = 4 }
$directory = Split-Path -Parent $PreviewPath
if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
$payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $PreviewPath -Encoding UTF8
if ($DryRun) {
  Write-Host "Preview ready: 15 main matchups + 1 wildcard; $($content.Length) plain-text characters. $PreviewPath"
  return
}

$webhook = $WebhookUrl
if (-not $webhook) {
  $config = Get-Content -LiteralPath $WebhookConfigPath -Raw | ConvertFrom-Json
  $webhookProperty = $config.channels.PSObject.Properties[$WebhookKey]
  if (-not $webhookProperty) { throw 'The private playoff webhook is not configured.' }
  $webhook = [string]$webhookProperty.Value
}
if ($webhook -notmatch '^https://discord\.com/api(?:/v\d+)?/webhooks/\d+/[A-Za-z0-9_-]+$') { throw 'Invalid Discord webhook URL.' }
try { $info = Invoke-RestMethod -Uri $webhook } catch { throw 'Could not verify the playoff webhook. No post was attempted.' }
if ([string]$info.channel_id -ne $ChannelId) { throw 'Webhook channel does not match the intended playoff forum.' }
$state = if (Test-Path -LiteralPath $StatePath) { Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json } else { $null }
if ($state) {
  if ($state.channelId -ne $ChannelId -or $state.webhookId -ne [string]$info.id -or $state.roundKey -ne '2026-round1') {
    throw 'Saved playoff state belongs to a different destination or round.'
  }
  $uri = "$webhook/messages/$($state.messageId)?thread_id=$($state.threadId)"
  try { Invoke-RestMethod -Uri $uri -Method Patch -ContentType 'application/json' -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12))) | Out-Null }
  catch { throw 'Could not update the saved playoff post. No replacement was created.' }
} else {
  $payload.thread_name = '2026 Playoffs - Round 1 - Projected Matchups'
  try { $message = Invoke-RestMethod -Uri "${webhook}?wait=true" -Method Post -ContentType 'application/json' -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12))) }
  catch { throw 'Discord create request failed. Check the forum before retrying; no automatic retry was attempted.' }
  if (-not $message.id -or -not $message.channel_id) { throw 'Missing Discord message/thread IDs. Check the forum before retrying.' }
  $state = [pscustomobject]@{ roundKey = '2026-round1'; channelId = $ChannelId; webhookId = [string]$info.id; messageId = [string]$message.id; threadId = [string]$message.channel_id; guildId = [string]$info.guild_id; updatedAt = '' }
}
$state.updatedAt = [datetimeoffset]::UtcNow.ToString('o')
$state | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding UTF8
# Read back the actual Discord message before reporting success.
try { $verified = Invoke-RestMethod -Uri "$webhook/messages/$($state.messageId)?thread_id=$($state.threadId)" }
catch { throw 'Post was saved, but Discord readback failed. Use saved state to inspect it.' }
if ([string]$verified.id -ne $state.messageId -or $verified.content -ne $content -or @($verified.embeds).Count -ne 0) { throw 'Discord readback did not match the expected plain-text overview.' }
Write-Host "Verified playoff forum post: https://discord.com/channels/$($state.guildId)/$($state.threadId)/$($state.messageId)"
