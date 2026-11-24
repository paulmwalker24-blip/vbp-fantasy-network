param([switch]$Publish)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/discord-bbu-rest.ps1"
$ledger=Get-Content data/bbu-weekly-high-scores.json -Raw|ConvertFrom-Json
$config=Get-Content data/discord-bbu-bot-config.json -Raw|ConvertFrom-Json
$rows=@(Import-Csv ("reports/bbu-weekly-scores-{0}.csv" -f $ledger.season))
$statePath='data/discord-bbu-weekly-high-scores-state.json'
if($ledger.leagueRecordIds.Count -ne 15 -or $rows.Count -ne (150*$ledger.throughWeek) -or $ledger.scoreCount -ne $rows.Count -or $ledger.weeks.Count -ne $ledger.throughWeek){throw 'Incomplete 15-room audit.'}
foreach($n in 1..15){if("BBU$n" -notin $ledger.leagueRecordIds){throw "Missing BBU$n"}}
function Clean([string]$value){return ($value -replace '[*_`~|<>\[\]]','')}
$cards=@()
foreach($week in 1..$ledger.throughWeek){
  $verified=@($ledger.weeks|Where-Object week -eq $week)
  $entries=@($rows|Where-Object {[int]$_.week -eq $week})
  if($verified.Count -ne 1 -or $verified[0].status -ne 'verified' -or $entries.Count -ne 150 -or $verified[0].leagueCount -ne 15 -or $verified[0].teamScoreCount -ne 150){throw "Incomplete week $week"}
  foreach($id in $ledger.leagueRecordIds){
    $room=@($entries|Where-Object leagueRecordId -eq $id)
    if($room.Count -ne 10 -or @($room.rosterId|Sort-Object -Unique).Count -ne 10){throw "Incomplete $id week $week"}
    $source=@($ledger.leagues|Where-Object leagueRecordId -eq $id)
    if($source.Count -ne 1){throw 'League source missing.'}
    $raw=@(Get-Content ("tmp/bbu-weekly-audit-{0}/{1}-week-{2}.json" -f $ledger.season,$id,$week) -Raw|ConvertFrom-Json)
    if($raw.Count -ne 10){throw 'Raw score coverage missing.'}
    foreach($entry in $room){
      $match=@($raw|Where-Object {[int]$_.roster_id -eq [int]$entry.rosterId})
      $expectedUrl="https://api.sleeper.app/v1/league/$($source[0].sleeperLeagueId)/matchups/$week"
      if($match.Count -ne 1 -or [decimal]$match[0].points -ne [decimal]$entry.points -or $entry.sourceUrl -ne $expectedUrl -or $entry.sleeperLeagueId -ne $source[0].sleeperLeagueId){throw 'CSV/raw score or source mismatch.'}
    }
  }
  $sorted=@($entries|Sort-Object @{Expression={[decimal]$_.points};Descending=$true},@{Expression={[int]($_.leagueRecordId -replace '\D','')}},@{Expression={[int]$_.rosterId}})
  if([decimal]$sorted[0].points -ne [decimal]$verified[0].highScore){throw 'Winner ledger mismatch.'}
  $cutoff=[decimal]$sorted[4].points
  $top=@($sorted|Where-Object {[decimal]$_.points -ge $cutoff})
  $lines=@(); $position=0; $rank=0; $previous=$null
  foreach($entry in $top){
    if(-not $entry.manager){throw 'Top-five manager unresolved.'}
    $position++; $points=[decimal]$entry.points
    if($null -eq $previous -or $points -ne $previous){$rank=$position}; $previous=$points
    $award=''
    if($points -eq [decimal]$verified[0].highScore){
      if(-not @($verified[0].winners|Where-Object {$_.leagueRecordId -eq $entry.leagueRecordId -and [int]$_.rosterId -eq [int]$entry.rosterId}).Count){throw 'Winner identity mismatch.'}
      $award=(' — **${0:F2} weekly winner**' -f [decimal]$verified[0].prizePerWinner)
    }
    $lines+=('**{0}. {1} — {2:F2}**{3}' -f $rank,(Clean $entry.manager),$points,$award)
    $lines+=('[{0} · roster {1} · Sleeper score source]({2})' -f $entry.leagueRecordId,$entry.rosterId,$entry.sourceUrl)
  }
  $description="**Top 5 across BBU1–BBU15 — all 150 team scores compared.**`n`n"+($lines -join "`n")+"`n`n**How to check:** Open a score-source link and find the matching ``roster_id``; ``points`` is the official Sleeper team total. Ties share rank; ties at fifth are included. Only the weekly highest score earns the Union's `$5 prize; tied winners split it.`n`nScores verified as of the timestamp below; later Sleeper stat corrections may change results. Names reflect current roster owners. **Prize payment not recorded.**"
  if($description.Length -gt 4096){throw 'Discord card too long.'}
  $cards+=@{week=$week;payload=@{content='';allowed_mentions=@{parse=@()};embeds=@(@{title="Best Ball Union — Week $week Top 5 | $($ledger.season)";description=$description;color=3066993;footer=@{text='15 rooms | 150 scores checked | Source: Sleeper matchup API'};timestamp=$ledger.verifiedAt})}}
}
if(-not $Publish){foreach($card in $cards){$card.payload.embeds[0].title; $card.payload.embeds[0].description; ''}; return}
$botToken=$env:DISCORD_BBU_BOT_TOKEN
if(-not $botToken -and (Test-Path data/private/discord-bbu-bot.json)){$botToken=(Get-Content data/private/discord-bbu-bot.json -Raw|ConvertFrom-Json).DISCORD_BBU_BOT_TOKEN}
if(-not $botToken){throw 'DISCORD_BBU_BOT_TOKEN is required for publication.'}
$headers=@{Authorization=('Bot '+$botToken)}; $ua=$config.userAgent; $base='https://discord.com/api/v10'
function DiscordGet($path){Invoke-BbuDiscordRequest -Uri ($base+$path) -Headers $headers -UserAgent $ua}
$me=DiscordGet '/users/@me'
if([string]$me.id -ne [string]$config.applicationId){throw 'Wrong bot credential.'}
$channel=DiscordGet ('/channels/'+$config.channels.weeklyHighScore)
if([string]$channel.guild_id -ne [string]$config.guildId -or $channel.name -ne 'weekly-high-score'){throw 'Wrong destination.'}
$state=[pscustomobject]@{channelId=[string]$channel.id;botId=[string]$me.id;season=[string]$ledger.season;throughWeek=$ledger.throughWeek;messages=[pscustomobject]@{};updatedAt=''}
if(Test-Path $statePath){
  $saved=Get-Content $statePath -Raw|ConvertFrom-Json
  if([string]$saved.channelId -ne [string]$channel.id -or [string]$saved.botId -ne [string]$me.id -or [string]$saved.season -ne [string]$ledger.season){throw 'Saved state mismatch.'}
  if($saved.PSObject.Properties['messages']){$state.messages=$saved.messages}
  elseif($saved.PSObject.Properties['messageId']){$state.messages|Add-Member -NotePropertyName 'week1' -NotePropertyValue ([string]$saved.messageId)}
}
# Preflight ownership for every saved post before editing any message.
foreach($property in $state.messages.PSObject.Properties){$existing=DiscordGet ('/channels/'+$channel.id+'/messages/'+$property.Value); if([string]$existing.author.id -ne [string]$me.id){throw 'Saved post is not owned by BBU Bot.'}}
foreach($card in $cards){
  $key='week'+$card.week; $uri=$base+'/channels/'+$channel.id+'/messages'; $method='Post'
  if($state.messages.PSObject.Properties[$key]){$uri+='/'+$state.messages.$key; $method='Patch'}
  $body=$card.payload|ConvertTo-Json -Depth 10 -Compress
  # No automatic POST retry: inspect uncertain results before retrying.
  $message=Invoke-BbuDiscordRequest -Uri $uri -Method $method -Headers $headers -UserAgent $ua -Body ([Text.Encoding]::UTF8.GetBytes($body))
  if(-not $message.id){throw 'Discord did not return a message ID.'}
  if($state.messages.PSObject.Properties[$key]){$state.messages.$key=[string]$message.id}else{$state.messages|Add-Member -NotePropertyName $key -NotePropertyValue ([string]$message.id)}
  $state.updatedAt=(Get-Date).ToUniversalTime().ToString('o'); $state|ConvertTo-Json -Depth 8|Set-Content $statePath
  $readback=DiscordGet ('/channels/'+$channel.id+'/messages/'+$message.id)
  if([string]$readback.author.id -ne [string]$me.id -or $readback.embeds[0].title -ne $card.payload.embeds[0].title -or $readback.embeds[0].description -ne $card.payload.embeds[0].description){throw 'Discord readback mismatch.'}
  Write-Host ('Verified Week '+$card.week+': https://discord.com/channels/'+$config.guildId+'/'+$channel.id+'/'+$message.id)
  Start-Sleep -Milliseconds 500
}
