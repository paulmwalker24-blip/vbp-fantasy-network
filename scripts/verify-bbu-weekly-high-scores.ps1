param([int]$ThroughWeek = 9, [string]$Season = '2026')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($ThroughWeek -lt 1 -or $ThroughWeek -gt 17) { throw 'ThroughWeek must be 1-17.' }
function Prop($o, $n) { if ($null -ne $o -and $o.PSObject.Properties[$n]) { return $o.$n }; return $null }
function Fetch($url) { $response = Invoke-RestMethod -Uri $url -TimeoutSec 45; foreach ($item in $response) { Write-Output $item } }
$local = (Get-Content data/leagues.json -Raw | ConvertFrom-Json).leagues
$ids = @(1..15 | ForEach-Object { "BBU$_" })
$all = @(); $rooms = @(); $sources = @()
$rawDir = "tmp/bbu-weekly-audit-$Season"
New-Item -ItemType Directory -Force $rawDir | Out-Null
foreach ($id in $ids) {
  $record = @($local | Where-Object id -eq $id)
  if ($record.Count -ne 1 -or -not $record[0].sleeperLeagueId) { throw "Missing/duplicate league: $id" }
  $lid = [string]$record[0].sleeperLeagueId
  $base = "https://api.sleeper.app/v1/league/$lid"
  $league = Fetch $base
  if ([string]$league.season -ne $Season -or [int]$league.total_rosters -ne 10 -or [int]$league.settings.best_ball -ne 1) { throw "Unexpected league architecture: $id" }
  $rosters = @(Fetch "$base/rosters"); $users = @(Fetch "$base/users")
  if ($rosters.Count -ne 10) { throw "Expected 10 rosters: $id" }
  $sources += [pscustomobject]@{leagueRecordId=$id;sleeperLeagueId=$lid;name=$league.name}
  @{league=$league;rosters=$rosters;users=$users} | ConvertTo-Json -Depth 35 | Set-Content "$rawDir/$id-context.json"
  for ($week=1; $week -le $ThroughWeek; $week++) {
    $url = "$base/matchups/$week"; $scores = @(Fetch $url)
    $scores | ConvertTo-Json -Depth 35 | Set-Content "$rawDir/$id-week-$week.json"
    if ($scores.Count -ne 10 -or @($scores.roster_id | Sort-Object -Unique).Count -ne 10) { throw "Incomplete/duplicate matchups: $id week $week" }
    $entries = foreach ($m in $scores) {
      $roster = @($rosters | Where-Object roster_id -eq $m.roster_id)
      if ($roster.Count -ne 1 -or $null -eq (Prop $m 'points')) { throw "Missing roster/score: $id week $week" }
      $user = $users | Where-Object user_id -eq $roster[0].owner_id | Select-Object -First 1
      $owner = [string](Prop $user 'display_name'); $team = [string](Prop (Prop $user 'metadata') 'team_name')
      if (-not $team) { $team=$owner }; if (-not $team) { $team="Roster $($m.roster_id)" }
      $custom = Prop $m 'custom_points'
      if ($null -ne $custom) { throw "Commissioner score override needs review: $id week $week roster $($m.roster_id)" }
      $value = [decimal]$m.points
      if ($value -lt 0) { throw "Negative score needs review: $id week $week" }
      [pscustomobject]@{week=$week;leagueRecordId=$id;sleeperLeagueId=$lid;rosterId=[int]$m.roster_id;ownerId=[string]$roster[0].owner_id;manager=$owner;teamName=$team;points=$value;sourceUrl=$url;identityBasis='Current Sleeper roster owner; historical ownership not inferred'}
    }
    if (($entries | Measure-Object points -Maximum).Maximum -le 0) { throw "All-zero week: $id week $week" }
    $max = ($entries | Measure-Object points -Maximum).Maximum
    $rooms += [pscustomobject]@{week=$week;leagueRecordId=$id;highScore=$max;winners=@($entries | Where-Object points -eq $max)}
    $all += $entries
  }
  Write-Host "Verified $id : $ThroughWeek weeks, $($ThroughWeek*10) team scores."
}
$weeks = foreach ($week in 1..$ThroughWeek) {
  $entries = @($all | Where-Object week -eq $week)
  if ($entries.Count -ne 150 -or @($entries.leagueRecordId | Sort-Object -Unique).Count -ne 15) { throw "Incomplete union week $week" }
  $max = ($entries | Measure-Object points -Maximum).Maximum
  $winners = @($entries | Where-Object points -eq $max)
  if (@($winners | Where-Object { -not $_.manager -or -not $_.ownerId }).Count) { throw "Winner identity unresolved: week $week" }
  [pscustomobject]@{week=$week;status='verified';leagueCount=15;teamScoreCount=150;highScore=$max;prizePool=5;prizePerWinner=(5/[decimal]$winners.Count);paymentStatus='not-recorded';winners=$winners}
}
$payload = [ordered]@{season=$Season;verifiedAt=(Get-Date).ToUniversalTime().ToString('o');throughWeek=$ThroughWeek;leagueRecordIds=$ids;leagues=$sources;scoreCount=$all.Count;methodology='Official Sleeper matchup.points; complete 15-room coverage; exact score ties share one $5 weekly award. Verification does not mark payment issued. Current owner identity requires review if ownership changed.';weeks=@($weeks);roomHighScores=$rooms}
New-Item -ItemType Directory -Force reports | Out-Null
$payload | ConvertTo-Json -Depth 15 | Set-Content data/bbu-weekly-high-scores.json
$all | Export-Csv "reports/bbu-weekly-scores-$Season.csv" -NoTypeInformation
$lines = @("# BBU weekly high-score audit — $Season",'',"Verified all 15 rooms for Weeks 1-$ThroughWeek : $($all.Count) team scores. Each weekly prize is `$5 total; ties split it. Payment status is not recorded. Names identify current roster owners; historical ownership requires commissioner review if changed.",'','| Week | Manager | Team | Room | Score | Prize | Status |','| --- | --- | --- | --- | --- | --- | --- |')
foreach ($w in $weeks) { foreach ($winner in $w.winners) { $name=$winner.manager.Replace('|','/'); $team=$winner.teamName.Replace('|','/'); $lines += ('| {0} | {1} | {2} | {3} | {4:F2} | ${5:F2} | Verified; payment not recorded |' -f $w.week,$name,$team,$winner.leagueRecordId,$w.highScore,$w.prizePerWinner) } }
$lines += @('','## Every room, every week','','| Week | Room | High scorer(s) | Score |','| --- | --- | --- | --- |')
foreach ($r in ($rooms | Sort-Object week,{[int]($_.leagueRecordId -replace '\D','')})) { $names=($r.winners | ForEach-Object {$_.manager.Replace('|','/')}) -join ', '; $lines+=('| {0} | {1} | {2} | {3:F2} |' -f $r.week,$r.leagueRecordId,$names,$r.highScore) }
$lines | Set-Content "reports/bbu-weekly-high-scores-$Season.md"
$weeks | ForEach-Object { [pscustomobject]@{week=$_.week;winners=($_.winners.manager -join ', ');rooms=($_.winners.leagueRecordId -join ', ');score=$_.highScore;prizePerWinner=$_.prizePerWinner} } | Format-Table
