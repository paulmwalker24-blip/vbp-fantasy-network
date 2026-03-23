param(
  [Parameter(Mandatory = $true)]
  [string]$BeforePath,

  [string]$AfterPath = "data/leagues.json",

  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-LeagueArray {
  param(
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Could not find league data file at '$Path'."
  }

  $payload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $Path).Path -Raw | ConvertFrom-Json
  $leagues = if ($payload -is [System.Array]) { @($payload) } else { @($payload.leagues) }

  if (-not $leagues) {
    throw "The JSON file at '$Path' does not contain a leagues array."
  }

  return $leagues
}

function Convert-ToComparableString {
  param(
    [AllowNull()]
    [object]$Value
  )

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [string]) {
    return $Value
  }

  if ($Value -is [ValueType]) {
    return [string]$Value
  }

  return ($Value | ConvertTo-Json -Compress -Depth 10)
}

function Format-DisplayValue {
  param(
    [AllowNull()]
    [object]$Value
  )

  if ($null -eq $Value) {
    return "<null>"
  }

  if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
    return "<empty>"
  }

  if ($Value -is [string]) {
    return $Value
  }

  if ($Value -is [ValueType]) {
    return [string]$Value
  }

  return ($Value | ConvertTo-Json -Compress -Depth 10)
}

$beforeLeagues = Resolve-LeagueArray -Path $BeforePath
$afterLeagues = Resolve-LeagueArray -Path $AfterPath

$beforeById = @{}
foreach ($league in $beforeLeagues) {
  $beforeById[[string]$league.id] = $league
}

$afterById = @{}
foreach ($league in $afterLeagues) {
  $afterById[[string]$league.id] = $league
}

$added = [System.Collections.Generic.List[object]]::new()
$removed = [System.Collections.Generic.List[object]]::new()
$changed = [System.Collections.Generic.List[object]]::new()

$allIds = @($beforeById.Keys + $afterById.Keys | Sort-Object -Unique)

foreach ($leagueId in $allIds) {
  $beforeLeague = $beforeById[$leagueId]
  $afterLeague = $afterById[$leagueId]

  if ($null -eq $beforeLeague) {
    $added.Add([pscustomobject]@{
      id = $leagueId
      name = [string]$afterLeague.name
      format = [string]$afterLeague.format
      status = [string]$afterLeague.status
    }) | Out-Null
    continue
  }

  if ($null -eq $afterLeague) {
    $removed.Add([pscustomobject]@{
      id = $leagueId
      name = [string]$beforeLeague.name
      format = [string]$beforeLeague.format
      status = [string]$beforeLeague.status
    }) | Out-Null
    continue
  }

  $fieldChanges = [System.Collections.Generic.List[object]]::new()
  $propertyNames = @(
    $beforeLeague.PSObject.Properties.Name +
    $afterLeague.PSObject.Properties.Name |
    Sort-Object -Unique
  )

  foreach ($propertyName in $propertyNames) {
    if ($propertyName -eq "id") {
      continue
    }

    $beforeValue = if ($beforeLeague.PSObject.Properties.Match($propertyName).Count -gt 0) {
      $beforeLeague.PSObject.Properties[$propertyName].Value
    } else {
      $null
    }

    $afterValue = if ($afterLeague.PSObject.Properties.Match($propertyName).Count -gt 0) {
      $afterLeague.PSObject.Properties[$propertyName].Value
    } else {
      $null
    }

    if ((Convert-ToComparableString $beforeValue) -ne (Convert-ToComparableString $afterValue)) {
      $fieldChanges.Add([pscustomobject]@{
        field = $propertyName
        before = Format-DisplayValue $beforeValue
        after = Format-DisplayValue $afterValue
      }) | Out-Null
    }
  }

  if ($fieldChanges.Count -gt 0) {
    $changed.Add([pscustomobject]@{
      id = $leagueId
      name = [string]$afterLeague.name
      format = [string]$afterLeague.format
      fieldChanges = @($fieldChanges)
    }) | Out-Null
  }
}

$report = [pscustomobject]@{
  beforePath = $BeforePath
  afterPath = $AfterPath
  checkedAt = (Get-Date).ToString("s")
  beforeCount = $beforeLeagues.Count
  afterCount = $afterLeagues.Count
  addedCount = $added.Count
  removedCount = $removed.Count
  changedCount = $changed.Count
  added = @($added)
  removed = @($removed)
  changed = @($changed)
}

if ($PassThru) {
  $report
} else {
  Write-Host ("League data diff: {0} added, {1} removed, {2} changed" -f $report.addedCount, $report.removedCount, $report.changedCount)

  foreach ($entry in $added) {
    Write-Host ("ADDED {0}: {1} | {2} | {3}" -f $entry.id, $entry.name, $entry.format, $entry.status)
  }

  foreach ($entry in $removed) {
    Write-Host ("REMOVED {0}: {1} | {2} | {3}" -f $entry.id, $entry.name, $entry.format, $entry.status)
  }

  foreach ($entry in $changed) {
    $changeSummary = @($entry.fieldChanges | ForEach-Object {
      "{0} ({1} -> {2})" -f $_.field, $_.before, $_.after
    }) -join "; "

    Write-Host ("CHANGED {0}: {1}" -f $entry.id, $changeSummary)
  }

  if ($report.addedCount -eq 0 -and $report.removedCount -eq 0 -and $report.changedCount -eq 0) {
    Write-Host "No league data changes detected."
  }
}
