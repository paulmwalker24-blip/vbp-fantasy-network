param(
  [Parameter(Mandatory = $true)]
  [string]$LeagueRecordId,

  [Parameter(Mandatory = $true)]
  [string]$SleeperInput,

  [string]$JsonPath = "data/leagues.json",

  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-SleeperInviteLeagueId {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InviteUrl
  )

  try {
    $response = Invoke-WebRequest -Uri $InviteUrl -UseBasicParsing
  } catch {
    throw "Could not load Sleeper invite page '$InviteUrl': $($_.Exception.Message)"
  }

  $content = [string]$response.Content
  foreach ($pattern in @(
    'league_id\\":\\"(\d+)',
    '"league_id":"(\d+)"',
    'league_id["\\]?\s*:\s*["\\]?(\d+)'
  )) {
    $match = [regex]::Match($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
      return $match.Groups[1].Value
    }
  }

  throw "Could not resolve a Sleeper league ID from invite page '$InviteUrl'."
}

function Get-SleeperLeagueId {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $trimmed = $Value.Trim()

  if ($trimmed -match '^\d+$') {
    return $trimmed
  }

  $patterns = @(
    'sleeper\.com/leagues/(\d+)',
    'sleeper\.com/i/[^/\s?]+/(\d+)',
    'league/(\d+)'
  )

  foreach ($pattern in $patterns) {
    $match = [regex]::Match($trimmed, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
      return $match.Groups[1].Value
    }
  }

  if ($trimmed -match 'sleeper\.com/i/[^/\s?]+(?:[/?#]|$)') {
    return Resolve-SleeperInviteLeagueId -InviteUrl $trimmed
  }

  throw "Could not parse a Sleeper league ID from '$Value'."
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find league data file at '$JsonPath'."
}

$parsedId = Get-SleeperLeagueId -Value $SleeperInput
$jsonFullPath = (Resolve-Path -LiteralPath $JsonPath).Path
$payload = Get-Content -LiteralPath $jsonFullPath -Raw | ConvertFrom-Json

if (-not $payload.leagues) {
  throw "The JSON file at '$JsonPath' does not contain a 'leagues' array."
}

$target = $payload.leagues | Where-Object { $_.id -eq $LeagueRecordId } | Select-Object -First 1

if (-not $target) {
  throw "Could not find league record '$LeagueRecordId' in '$JsonPath'."
}

$oldValue = [string]$target.sleeperLeagueId
$target.sleeperLeagueId = $parsedId

$payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonFullPath

$summary = [pscustomobject]@{
  leagueRecordId = $LeagueRecordId
  oldSleeperLeagueId = $oldValue
  newSleeperLeagueId = $parsedId
  jsonPath = $JsonPath
}

if ($PassThru) {
  $summary
} else {
  Write-Host ("Updated {0}: sleeperLeagueId '{1}' -> '{2}'" -f $LeagueRecordId, $oldValue, $parsedId)
}
