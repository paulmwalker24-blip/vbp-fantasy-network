param(
  [ValidateSet("new", "update")]
  [string]$Mode,

  [string]$LeagueType,
  [string]$LeagueRecordId,
  [string]$SleeperInput,
  [string]$SleeperSeason,
  [string]$PublicLeagueName,
  [string]$Division,
  [string]$BuyIn,
  [string]$TeamCount,
  [string]$FilledSpots,
  [string]$Status,
  [string]$InviteLink,
  [string]$LeagueSafeLink,
  [string]$ConstitutionPage,
  [string]$Notes,
  [string]$JsonPath = "data/leagues.json",
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$validFormats = @("redraft", "dynasty", "bestball", "bracket", "keeper", "chopped")
$validStatuses = @("open", "full", "coming-soon")

function Normalize-Format {
  param([string]$Value)

  $normalized = ($Value -replace '\s+', '').Trim().ToLowerInvariant()
  switch ($normalized) {
    "redraft" { return "redraft" }
    "dynasty" { return "dynasty" }
    "bestball" { return "bestball" }
    "bestballunion" { return "bestball" }
    "bracket" { return "bracket" }
    "bracketredraft" { return "bracket" }
    "keeper" { return "keeper" }
    "chopped" { return "chopped" }
    default { throw "Unsupported format '$Value'." }
  }
}

function Get-SleeperLeagueId {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ""
  }

  $trimmed = $Value.Trim()
  if ($trimmed -match '^\d+$') {
    return $trimmed
  }

  foreach ($pattern in @(
    'sleeper\.com/leagues/(\d+)',
    'sleeper\.com/i/[^/\s?]+/(\d+)',
    'league/(\d+)'
  )) {
    $match = [regex]::Match($trimmed, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
      return $match.Groups[1].Value
    }
  }

  throw "Could not parse a Sleeper league ID from '$Value'."
}

function Get-NextLeagueId {
  param(
    [string]$Format,
    [object[]]$Leagues
  )

  $prefixByFormat = @{
    redraft = "RD"
    dynasty = "DYN"
    bestball = "BBU"
    bracket = "RDB"
    keeper = "KP"
    chopped = "CH"
  }

  $prefix = $prefixByFormat[$Format]
  $maxSuffix = 0

  foreach ($league in $Leagues) {
    $id = [string]$league.id
    if ($id -match ("^{0}(\d+)$" -f [regex]::Escape($prefix))) {
      $suffix = [int]$matches[1]
      if ($suffix -gt $maxSuffix) {
        $maxSuffix = $suffix
      }
    }
  }

  return "{0}{1}" -f $prefix, ($maxSuffix + 1)
}

function Prompt-Value {
  param(
    [string]$Label,
    [string]$Default = ""
  )

  if ([string]::IsNullOrWhiteSpace($Default)) {
    return Read-Host $Label
  }

  $value = Read-Host ("{0} [{1}]" -f $Label, $Default)
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $Default
  }

  return $value
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find league data file at '$JsonPath'."
}

$jsonFullPath = (Resolve-Path -LiteralPath $JsonPath).Path
$payload = Get-Content -LiteralPath $jsonFullPath -Raw | ConvertFrom-Json

if (-not $payload.leagues) {
  throw "The JSON file at '$JsonPath' does not contain a 'leagues' array."
}

if ([string]::IsNullOrWhiteSpace($Mode)) {
  $Mode = Prompt-Value -Label "Mode (new/update)" -Default "new"
}

$Mode = $Mode.Trim().ToLowerInvariant()
if ($Mode -notin @("new", "update")) {
  throw "Mode must be 'new' or 'update'."
}

if ([string]::IsNullOrWhiteSpace($LeagueType)) {
  $LeagueType = Prompt-Value -Label "League type" -Default "redraft"
}

$LeagueType = Normalize-Format -Value $LeagueType

if ($Mode -eq "new") {
  if ([string]::IsNullOrWhiteSpace($LeagueRecordId)) {
    $LeagueRecordId = Get-NextLeagueId -Format $LeagueType -Leagues $payload.leagues
  }

  $target = $null
  $target = [pscustomobject]@{
    id = $LeagueRecordId
    sleeperLeagueId = ""
    sleeperSeason = ""
    name = ""
    format = $LeagueType
    division = ""
    buyIn = 0
    teams = 0
    filled = 0
    status = "open"
    inviteLink = ""
    leagueSafeLink = ""
    constitutionPage = ""
    notes = ""
    lastUpdated = ""
  }
  $payload.leagues += $target
} else {
  if ([string]::IsNullOrWhiteSpace($LeagueRecordId)) {
    $LeagueRecordId = Prompt-Value -Label "League record ID to update"
  }

  $target = $payload.leagues | Where-Object { $_.id -eq $LeagueRecordId } | Select-Object -First 1
  if (-not $target) {
    throw "Could not find existing league record '$LeagueRecordId'."
  }
}

if ([string]::IsNullOrWhiteSpace($PublicLeagueName)) {
  $PublicLeagueName = Prompt-Value -Label "Public league name" -Default ([string]$target.name)
}

if (-not $PublicLeagueName.Trim()) {
  throw "Public league name is required."
}

if ([string]::IsNullOrWhiteSpace($SleeperInput)) {
  $SleeperInput = Prompt-Value -Label "Sleeper league URL or ID" -Default ([string]$target.sleeperLeagueId)
}

if ([string]::IsNullOrWhiteSpace($SleeperSeason)) {
  $SleeperSeason = Prompt-Value -Label "Sleeper season" -Default ([string]$target.sleeperSeason)
}

if ([string]::IsNullOrWhiteSpace($Division)) {
  $Division = Prompt-Value -Label "Division / draft type" -Default ([string]$target.division)
}

if ([string]::IsNullOrWhiteSpace($BuyIn)) {
  $BuyIn = Prompt-Value -Label "Buy-in" -Default ([string]$target.buyIn)
}

if ([string]::IsNullOrWhiteSpace($TeamCount)) {
  $TeamCount = Prompt-Value -Label "Team count" -Default ([string]$target.teams)
}

if ([string]::IsNullOrWhiteSpace($FilledSpots)) {
  $FilledSpots = Prompt-Value -Label "Filled spots" -Default ([string]$target.filled)
}

if ([string]::IsNullOrWhiteSpace($Status)) {
  $Status = Prompt-Value -Label "Status (open/full/coming-soon)" -Default ([string]$target.status)
}

if ([string]::IsNullOrWhiteSpace($InviteLink)) {
  $InviteLink = Prompt-Value -Label "Invite link" -Default ([string]$target.inviteLink)
}

if ([string]::IsNullOrWhiteSpace($LeagueSafeLink)) {
  $LeagueSafeLink = Prompt-Value -Label "LeagueSafe link" -Default ([string]$target.leagueSafeLink)
}

if ([string]::IsNullOrWhiteSpace($ConstitutionPage)) {
  $ConstitutionPage = Prompt-Value -Label "Constitution page" -Default ([string]$target.constitutionPage)
}

if ([string]::IsNullOrWhiteSpace($Notes)) {
  $Notes = Prompt-Value -Label "Notes" -Default ([string]$target.notes)
}

$parsedSleeperLeagueId = Get-SleeperLeagueId -Value $SleeperInput
$normalizedStatus = $Status.Trim().ToLowerInvariant()

if ($normalizedStatus -notin $validStatuses) {
  throw "Status must be one of: $($validStatuses -join ', ')."
}

$target.id = $LeagueRecordId
$target.sleeperLeagueId = $parsedSleeperLeagueId
$target.sleeperSeason = $SleeperSeason.Trim()
$target.name = $PublicLeagueName.Trim()
$target.format = $LeagueType
$target.division = $Division.Trim()
$target.buyIn = [int]([double]$BuyIn)
$target.teams = [int]([double]$TeamCount)
$target.filled = [int]([double]$FilledSpots)
$target.status = $normalizedStatus
$target.inviteLink = $InviteLink.Trim()
$target.leagueSafeLink = $LeagueSafeLink.Trim()
$target.constitutionPage = $ConstitutionPage.Trim()
$target.notes = $Notes.Trim()

$payload.leagues | Sort-Object {
  $formatRank = $validFormats.IndexOf(([string]$_.format).ToLowerInvariant())
  if ($formatRank -lt 0) { 999 } else { $formatRank }
}, {
  if (([string]$_.id) -match '(\d+)$') { [int]$matches[1] } else { 9999 }
} | ForEach-Object {
  # preserve sorted order back into the payload array
} | Out-Null

$payload.leagues = @($payload.leagues | Sort-Object {
  $formatRank = $validFormats.IndexOf(([string]$_.format).ToLowerInvariant())
  if ($formatRank -lt 0) { 999 } else { $formatRank }
}, {
  if (([string]$_.id) -match '(\d+)$') { [int]$matches[1] } else { 9999 }
})

$payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonFullPath

$validatorPath = Join-Path $PSScriptRoot "validate-leagues-json.ps1"
$validationReport = $null
if (Test-Path -LiteralPath $validatorPath) {
  $validationReport = & $validatorPath -JsonPath $JsonPath -PassThru
}

$result = [pscustomobject]@{
  mode = $Mode
  id = $LeagueRecordId
  format = $LeagueType
  sleeperLeagueId = $parsedSleeperLeagueId
  validationErrorCount = if ($validationReport) { $validationReport.errorCount } else { 0 }
  validationWarningCount = if ($validationReport) { $validationReport.warningCount } else { 0 }
  jsonPath = $JsonPath
}

if ($PassThru) {
  $result
} else {
  Write-Host ("Saved league record {0} ({1})" -f $LeagueRecordId, $LeagueType)
  if ($validationReport) {
    Write-Host ("Validation result: {0} error(s), {1} warning(s)" -f $validationReport.errorCount, $validationReport.warningCount)
  }
}
