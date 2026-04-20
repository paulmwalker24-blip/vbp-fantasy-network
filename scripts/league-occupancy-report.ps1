param(
  [string]$JsonPath = "data/leagues.json",
  [switch]$OpenOnly,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function To-Number {
  param(
    [AllowNull()]
    [object]$Value
  )

  $cleaned = [string]$Value
  $cleaned = $cleaned -replace '[$,%\s]', ''
  $cleaned = $cleaned -replace ',', ''

  $parsed = 0
  if ([double]::TryParse($cleaned, [ref]$parsed)) {
    return [int][math]::Floor($parsed)
  }

  return 0
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find league data file at '$JsonPath'."
}

$jsonFullPath = (Resolve-Path -LiteralPath $JsonPath).Path
$payload = Get-Content -LiteralPath $jsonFullPath -Raw | ConvertFrom-Json

if (-not $payload.leagues) {
  throw "The JSON file at '$JsonPath' does not contain a 'leagues' array."
}

$rows = foreach ($league in $payload.leagues) {
  $status = ([string]$league.status).Trim().ToLowerInvariant()
  if ($OpenOnly -and $status -ne "open") {
    continue
  }

  $teams = To-Number $league.teams
  $filled = To-Number $league.filled
  $sleeperFilled = if ($league.PSObject.Properties.Match('sleeperFilled').Count -gt 0) { To-Number $league.sleeperFilled } else { $null }

  [pscustomobject]@{
    id = [string]$league.id
    name = [string]$league.name
    format = [string]$league.format
    status = $status
    filled = $filled
    teams = $teams
    spotsLeft = [math]::Max($teams - $filled, 0)
    sleeperFilled = $sleeperFilled
  }
}

$report = [pscustomobject]@{
  jsonPath = $JsonPath
  generatedAt = (Get-Date).ToString("s")
  leagueCount = @($rows).Count
  leagues = @($rows)
}

if ($PassThru) {
  $report
} else {
  foreach ($row in $rows) {
    $suffix = if ($null -ne $row.sleeperFilled) {
      " | Sleeper owner count {0}" -f $row.sleeperFilled
    } else {
      ""
    }

    Write-Host ("{0} | {1} | {2}/{3} filled | {4} left | {5}{6}" -f $row.id, $row.name, $row.filled, $row.teams, $row.spotsLeft, $row.status, $suffix)
  }
}
