param([switch]$Publish)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/discord-bbu-rest.ps1"
$config=Get-Content data/discord-bbu-bot-config.json -Raw|ConvertFrom-Json
$audit=Get-Content data/bbu-weekly-high-scores.json -Raw|ConvertFrom-Json
$rows=@(Import-Csv ("reports/bbu-weekly-scores-{0}.csv" -f $audit.season))
$statePath='data/discord-bbu-overall-high-scorer-state.json'
$board=@()
if($audit.leagueRecordIds.Count -ne 15 -or $rows.Count -ne 150*$audit.throughWeek){throw 'Incomplete 15-room audit.'}
foreach($n in 1..15){
 $id="BBU$n"; $source=@($audit.leagues|Where-Object leagueRecordId -eq $id)
 if($source.Count -ne 1){throw "Missing $id"}
 $lid=[string]$source[0].sleeperLeagueId
 $rosters=Invoke-RestMethod "https://api.sleeper.app/v1/league/$lid/rosters" -TimeoutSec 40
 if($rosters.Count -ne 10){throw "Missing rosters: $id"}
 foreach($roster in $rosters){
  $scores=@($rows|Where-Object {$_.leagueRecordId -eq $id -and [int]$_.rosterId -eq [int]$roster.roster_id})
  if($scores.Count -ne $audit.throughWeek -or @($scores.week|Sort-Object -Unique).Count -ne $audit.throughWeek){throw 'Incomplete roster weeks.'}
  $total=[decimal]0
  foreach($week in 1..$audit.throughWeek){
   $entry=@($scores|Where-Object {[int]$_.week -eq $week}); if($entry.Count -ne 1){throw 'Duplicate/missing week.'}
   $total+=[decimal]$entry[0].points
  }
  $official=[decimal]$roster.settings.fpts+([decimal]$roster.settings.fpts_decimal/100)
  if([math]::Abs($total-$official)-gt [decimal]0.01){throw "Audit/live total mismatch $id roster $($roster.roster_id): audit $total, live $official. Refresh/review the audit before publishing."}
  $entry=$scores[0]
  if(-not $entry.manager -or [string]$roster.owner_id -ne [string]$entry.ownerId){throw 'Current owner changed; review identity before publishing.'}
  $board+=[pscustomobject]@{leagueRecordId=$id;sleeperLeagueId=$lid;rosterId=[int]$roster.roster_id;manager=$entry.manager;teamName=$entry.teamName;points=$total;sourceUrl="https://api.sleeper.app/v1/league/$lid/rosters"}
 }
 Write-Host "Verified $id season totals against live Sleeper rosters."
}
if($board.Count -ne 150){throw 'Expected 150 season totals.'}
$sorted=@($board|Sort-Object @{Expression={$_.points};Descending=$true},@{Expression={[int]($_.leagueRecordId -replace '\D','')}},rosterId)
$top=@($sorted|Where-Object {$_.points -ge $sorted[19].points})
$verifiedAt=(Get-Date).ToUniversalTime().ToString('o')
@{season=$audit.season;throughWeek=$audit.throughWeek;verifiedAt=$verifiedAt;teamCount=150;leagueCount=15;overallPrize=415;entries=$sorted}|ConvertTo-Json -Depth 7|Set-Content data/bbu-overall-high-scorer.json
$lines=@();$i=0;$rank=0;$previous=$null
foreach($entry in $top){$i++;if($null -eq $previous -or $entry.points -ne $previous){$rank=$i};$previous=$entry.points;$name=$entry.manager-replace '[*_`~|<>\[\]]','';$lines+=('**{0}. {1} — {2:N2}** · [{3}, roster {4}]({5})' -f $rank,$name,$entry.points,$entry.leagueRecordId,$entry.rosterId,$entry.sourceUrl)}
$description="**`$415 overall season high-score prize**`n**Standings through Week $($audit.throughWeek) | BBU1–BBU15 | 150 teams**`n`n"+($lines-join "`n")+"`n`n**How this race works:** The single team with the highest cumulative score through Week 17 wins the overall prize, after Sleeper stat corrections. Current positions are provisional; this is a season-points board, independent of win-loss records and power rankings.`n`n**Verification:** Every total matches the audited Weeks 1–$($audit.throughWeek) scores and live Sleeper roster season totals. Open an entry's source link and find its ``roster_id``; total points = ``fpts`` + ``fpts_decimal`` / 100. Tied scores share rank; ties at 20th are included. Final tied-champion handling requires commissioner review.`n`nWeekly `$5 awards and weekly Top 5 posts: <#$($config.channels.weeklyHighScore)>."
if($description.Length -gt 4096){throw 'Card exceeds Discord limit.'}
$payload=@{content='';allowed_mentions=@{parse=@()};embeds=@(@{title="Best Ball Union — Overall High Scorer | Top 20";description=$description;color=15844367;footer=@{text='2026 | Official season points | $415 overall prize'};timestamp=$verifiedAt})}
if(-not $Publish){$description;return}
$botToken=$env:DISCORD_BBU_BOT_TOKEN
if(-not $botToken -and (Test-Path data/private/discord-bbu-bot.json)){$botToken=(Get-Content data/private/discord-bbu-bot.json -Raw|ConvertFrom-Json).DISCORD_BBU_BOT_TOKEN}
if(-not $botToken){throw 'DISCORD_BBU_BOT_TOKEN is required for publication.'}
$headers=@{Authorization=('Bot '+$botToken)};$ua=$config.userAgent;$base='https://discord.com/api/v10'
function DiscordGet($path){Invoke-BbuDiscordRequest -Uri ($base+$path) -Headers $headers -UserAgent $ua}
$me=DiscordGet '/users/@me';if($me.id -ne $config.applicationId){throw 'Wrong bot.'}
$channel=DiscordGet ('/channels/'+$config.channels.overallHighScorer)
if($channel.guild_id -ne $config.guildId -or $channel.parent_id -ne '1540207040339644516' -or $channel.name -ne 'overall-high-scorer' -or $channel.type -ne 0){throw 'Wrong destination.'}
$uri=$base+'/channels/'+$channel.id+'/messages';$method='Post'
if(Test-Path $statePath){$state=Get-Content $statePath -Raw|ConvertFrom-Json;if($state.channelId -ne $channel.id -or $state.botId -ne $me.id){throw 'State identity mismatch.'};$old=DiscordGet ('/channels/'+$channel.id+'/messages/'+$state.messageId);if($old.author.id -ne $me.id){throw 'Message not owned by BBU Bot.'};$uri+='/'+$state.messageId;$method='Patch'}
# Avoid automatic POST retries: inspect uncertain responses before retrying.
$body=$payload|ConvertTo-Json -Depth 10 -Compress
$message=Invoke-BbuDiscordRequest -Uri $uri -Method $method -Headers $headers -UserAgent $ua -Body ([Text.Encoding]::UTF8.GetBytes($body))
if(-not $message.id){throw 'Discord did not return a message ID.'}
@{channelId=[string]$channel.id;botId=[string]$me.id;messageId=[string]$message.id;throughWeek=$audit.throughWeek;updatedAt=$verifiedAt}|ConvertTo-Json|Set-Content $statePath
$readback=DiscordGet ('/channels/'+$channel.id+'/messages/'+$message.id)
if($readback.author.id -ne $me.id -or $readback.embeds[0].description -ne $description){throw 'Readback mismatch.'}
Write-Host ('Verified overall standings: https://discord.com/channels/'+$config.guildId+'/'+$channel.id+'/'+$message.id)
