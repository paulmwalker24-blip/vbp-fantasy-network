param([switch]$Publish)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Use PowerShell 7 for the UTF-8 score-card scripts.
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Run this script with pwsh (PowerShell 7).' }
$nfl = Invoke-RestMethod https://api.sleeper.app/v1/state/nfl -TimeoutSec 30
if ([string]$nfl.season -ne '2026') { throw 'Review BBU season configuration before refreshing a different season.' }
$throughWeek = switch ([string]$nfl.season_type) {
  'regular' { [Math]::Min(17, [int]$nfl.leg - 1) }
  'post' { 17 }
  'off' { 17 }
  default { 0 }
}
if ($throughWeek -lt 1) { throw 'No completed regular-season weeks are available.' }

& "$PSScriptRoot/verify-bbu-weekly-high-scores.ps1" -ThroughWeek $throughWeek -Season '2026'
# Validate all three outputs, including all 150 live cumulative totals, before any sends.
& "$PSScriptRoot/post-discord-bbu-weekly-high-scores.ps1" | Out-Null
& "$PSScriptRoot/post-discord-bbu-overall-high-scorer.ps1" | Out-Null
& "$PSScriptRoot/post-discord-bbu-high-scorer.ps1" -DryRun | Out-Null
if ($Publish) {
  if (-not $env:DISCORD_WEBHOOK_BBU_HIGH_SCORER) { throw 'DISCORD_WEBHOOK_BBU_HIGH_SCORER is required for the combined weekly summary.' }
  & "$PSScriptRoot/post-discord-bbu-high-scorer.ps1"
  & "$PSScriptRoot/post-discord-bbu-weekly-high-scores.ps1" -Publish
  & "$PSScriptRoot/post-discord-bbu-overall-high-scorer.ps1" -Publish
} else {
  Write-Host "Validated BBU weekly summary, weekly cards, and overall standings through Week $throughWeek. No Discord messages sent."
}
