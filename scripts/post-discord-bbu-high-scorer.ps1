param(
  [string]$StatePath='data/discord-bbu-high-scorer-state.json',
  [string]$WebhookUrl=$env:DISCORD_WEBHOOK_BBU_HIGH_SCORER,
  [switch]$DryRun,
  [switch]$ForceRefresh,
  [switch]$PassThru
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. "$PSScriptRoot/discord-bbu-rest.ps1"
$audit=Get-Content data/bbu-weekly-high-scores.json -Raw|ConvertFrom-Json
$config=Get-Content data/discord-bbu-bot-config.json -Raw|ConvertFrom-Json
$state=Get-Content $StatePath -Raw|ConvertFrom-Json
if($audit.leagueRecordIds.Count -ne 15 -or $audit.scoreCount -ne 150*$audit.throughWeek -or $audit.weeks.Count -ne $audit.throughWeek){throw 'Incomplete 15-room weekly audit.'}
if([string]$state.channelId -ne [string]$config.channels.weeklyHighScore -or [string]$state.season -ne [string]$audit.season -or -not $state.messageId){throw 'Combined summary state mismatch.'}
$fields=@();$history=@()
foreach($week in 1..$audit.throughWeek){
  $rows=@($audit.weeks|Where-Object week -eq $week)
  if($rows.Count -ne 1 -or $rows[0].status -ne 'verified' -or $rows[0].teamScoreCount -ne 150 -or $rows[0].leagueCount -ne 15 -or @($rows[0].winners).Count -lt 1){throw "Incomplete summary week $week"}
  $row=$rows[0]
  $lines=@(foreach($winner in $row.winners){
    $name=[string]$winner.manager -replace '[\r\n*_`~|<>\[\]()]',''
    if($name.Length -gt 60){$name=$name.Substring(0,60)}
    '**'+$name+'** - '+$winner.leagueRecordId+' - '+('{0:N2}' -f [decimal]$row.highScore)+' points'
  })
  $value=$lines -join "`n"
  if($value.Length -gt 1024){throw "Week $week summary exceeds Discord field limit."}
  $fields+=@{name="Week $week";value=$value;inline=$false}
  $history+=@{week=$week;score=$row.highScore;winners=@($row.winners|ForEach-Object {@{leagueRecordId=$_.leagueRecordId;rosterId=$_.rosterId;teamName=$_.manager}})}
}
[array]::Reverse($fields)
$embed=@{title='Best Ball Union - Weekly High Scorers';description="Weekly winners through Week $($audit.throughWeek) across all 15 rooms and 150 teams (BBU1-BBU15). Exact ties split the weekly `$5 award. Prize payment not recorded.";fields=$fields;color=12663211;footer=@{text='All 15 BBU rooms | Verified Sleeper matchup scores'};timestamp=$audit.verifiedAt}
$size=$embed.title.Length+$embed.description.Length+$embed.footer.text.Length
foreach($field in $fields){$size+=$field.name.Length+$field.value.Length}
if($fields.Count -gt 25 -or $size -gt 6000){throw 'Combined summary exceeds Discord limits.'}
$payload=@{content='';allowed_mentions=@{parse=@()};embeds=@($embed)}
if($DryRun){if($PassThru){$payload}else{$payload|ConvertTo-Json -Depth 10};return}
if(-not $WebhookUrl){throw 'DISCORD_WEBHOOK_BBU_HIGH_SCORER is required for the combined weekly summary.'}
$ua=$config.userAgent
$info=Invoke-BbuDiscordRequest -Uri $WebhookUrl -Headers @{} -UserAgent $ua
if([string]$info.channel_id -ne [string]$state.channelId -or [string]$info.id -ne [string]$state.webhookId){throw 'Combined summary webhook ownership mismatch.'}
$uri=$WebhookUrl.TrimEnd('/')+'/messages/'+$state.messageId
$old=Invoke-BbuDiscordRequest -Uri $uri -Headers @{} -UserAgent $ua
if([string]$old.webhook_id -ne [string]$state.webhookId){throw 'Combined summary message is owned by another webhook.'}
$body=[Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Depth 10 -Compress))
Invoke-BbuDiscordRequest -Uri $uri -Method Patch -Headers @{} -UserAgent $ua -Body $body|Out-Null
$readback=Invoke-BbuDiscordRequest -Uri $uri -Headers @{} -UserAgent $ua
if($readback.embeds[0].description -ne $embed.description -or $readback.embeds[0].fields.Count -ne $fields.Count){throw 'Combined weekly summary readback mismatch.'}
for($i=0;$i -lt $fields.Count;$i++){
  if($readback.embeds[0].fields[$i].name -ne $fields[$i].name -or $readback.embeds[0].fields[$i].value -ne $fields[$i].value){throw 'Combined weekly summary winner readback mismatch.'}
}
$state.completedWeek=$audit.throughWeek;$state.weeklyHighScores=$history;$state.updatedAt=[datetimeoffset]::UtcNow.ToString('o')
$state.signature='audited-15-room-week-'+$audit.throughWeek
$state|ConvertTo-Json -Depth 10|Set-Content $StatePath
Write-Host ('Verified combined weekly summary through Week '+$audit.throughWeek+': https://discord.com/channels/'+$config.guildId+'/'+$state.channelId+'/'+$state.messageId)
