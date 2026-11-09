param(
  [string]$LedgerPath = 'data/bracket-ledger.json',
  [string]$FieldPath = 'data/bracket-playoff-field-2026.json',
  [string]$OverviewStatePath = 'data/discord-bracket-playoffs-state.json',
  [string]$MatchupStatePath = 'data/discord-bracket-matchups-state.json',
  [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ledger = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$groups = @($ledger.groups | Where-Object groupId -eq 'BRACKET-2026-1')
if ($groups.Count -ne 1) { throw 'Expected exactly one 2026 bracket group.' }
$group = $groups[0]
$teams = @($group.leagueSnapshots | ForEach-Object { $_.standings })
$games = @($teams | ForEach-Object { $_.wins + $_.losses + $_.ties } | Sort-Object -Unique)
if ($teams.Count -ne 60 -or $games.Count -ne 1) { throw 'Playoff refresh requires all 60 teams with equal completed games.' }
$locked = $false
$effectivePath = $LedgerPath
if (Test-Path -LiteralPath $FieldPath) {
  $final = Get-Content -LiteralPath $FieldPath -Raw | ConvertFrom-Json
  if (-not $final.playoffFieldLocked) { throw 'Saved final-field marker is missing.' }
  $effectivePath = $FieldPath
  $locked = $true
} elseif ($games[0] -eq 12) {
  # Validate the final snapshot (including exact record/PF ties) before persisting it.
  & "$PSScriptRoot/post-discord-bracket-playoff-round.ps1" -LedgerPath $LedgerPath -DryRun
  $ledger | Add-Member -NotePropertyName playoffFieldLocked -NotePropertyValue $true -Force
  if (-not $DryRun) {
    $ledger | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $FieldPath -Encoding UTF8
    $effectivePath = $FieldPath
    $locked = $true
  }
} elseif ($games[0] -gt 12) {
  throw 'Final Week 12 field is missing. Refusing to rebuild playoff seeds from later results.'
}
New-Item -ItemType Directory -Path 'tmp' -Force | Out-Null
# Build every team message before editing the overview or matchup posts.
& "$PSScriptRoot/post-discord-bracket-matchup-tests.ps1" -LedgerPath $effectivePath -StatePath $MatchupStatePath -AllMatchups -LockedField:$locked -DryRun
if ($DryRun) { return }
& "$PSScriptRoot/post-discord-bracket-playoff-round.ps1" -LedgerPath $effectivePath -StatePath $OverviewStatePath -LockedField:$locked
& "$PSScriptRoot/post-discord-bracket-matchup-tests.ps1" -LedgerPath $effectivePath -StatePath $MatchupStatePath -AllMatchups -LockedField:$locked
