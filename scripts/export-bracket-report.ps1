param(
  [string]$LedgerPath = "data/bracket-ledger.json",
  [string]$GroupId = "BRACKET-2026-1",
  [string]$WeekLabel = "",
  [string]$OutputPath = "",
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-StringValue {
  param(
    [AllowNull()]
    [object]$Value
  )

  return ([string]$Value).Trim()
}

function Get-PropertyValue {
  param(
    [AllowNull()]
    [object]$Object,
    [string]$PropertyName
  )

  if ($null -eq $Object) {
    return $null
  }

  if ($Object.PSObject.Properties.Match($PropertyName).Count -gt 0) {
    return $Object.PSObject.Properties[$PropertyName].Value
  }

  return $null
}

function Get-EntryKey {
  param(
    [string]$LeagueRecordId,
    [string]$OwnerId,
    [AllowNull()]
    [object]$RosterId
  )

  return ("{0}|{1}|{2}" -f (Get-StringValue $LeagueRecordId), (Get-StringValue $OwnerId), (Get-StringValue $RosterId))
}

function Format-RecordDisplay {
  param(
    [string]$Record
  )

  $parts = @(($Record -split "-") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
  if ($parts.Count -ge 3) {
    if ($parts[2] -eq "0") {
      return ("{0}-{1}" -f $parts[0], $parts[1])
    }

    return ("{0}-{1}-{2}" -f $parts[0], $parts[1], $parts[2])
  }

  return (Get-StringValue $Record)
}

function Resolve-Group {
  param(
    [AllowNull()]
    [object[]]$Groups,
    [string]$TargetGroupId
  )

  foreach ($group in @($Groups)) {
    if ((Get-StringValue (Get-PropertyValue $group "groupId")) -eq (Get-StringValue $TargetGroupId)) {
      return $group
    }
  }

  return $null
}

if (-not (Test-Path -LiteralPath $LedgerPath)) {
  throw "Could not find bracket ledger at '$LedgerPath'."
}

$ledger = Get-Content -LiteralPath (Resolve-Path -LiteralPath $LedgerPath).Path -Raw | ConvertFrom-Json
$group = Resolve-Group -Groups @($ledger.groups) -TargetGroupId $GroupId

if ($null -eq $group) {
  throw "Could not find bracket group '$GroupId' in '$LedgerPath'."
}

$overallStandings = @($group.overallStandings)
$playoffField = @($group.playoffField)
$divisionWinners = @($group.divisionWinners)
$leagueSnapshots = @($group.leagueSnapshots)
$leagueRecordIds = @($group.leagueRecordIds)
$seasonDataReady = [bool](Get-PropertyValue $group "seasonDataReady")
$seedingReady = [bool](Get-PropertyValue $group "seedingReady")
$groupLabel = Get-StringValue (Get-PropertyValue $group "label")
$groupNotes = Get-StringValue (Get-PropertyValue $group "notes")
$lastSyncedAt = Get-StringValue (Get-PropertyValue $group "lastSyncedAt")

$leagueNamesById = @{}
foreach ($snapshot in $leagueSnapshots) {
  $leagueRecordId = Get-StringValue (Get-PropertyValue $snapshot "leagueRecordId")
  if ([string]::IsNullOrWhiteSpace($leagueRecordId)) {
    continue
  }

  $leagueNamesById[$leagueRecordId] = Get-StringValue (Get-PropertyValue $snapshot "localLeagueName")
}

$divisionWinnerKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$playoffSeedByKey = @{}
foreach ($entry in $divisionWinners) {
  $team = Get-PropertyValue $entry "team"
  $key = Get-EntryKey `
    -LeagueRecordId (Get-StringValue (Get-PropertyValue $team "leagueRecordId")) `
    -OwnerId (Get-StringValue (Get-PropertyValue $team "ownerId")) `
    -RosterId (Get-PropertyValue $team "rosterId")
  [void]$divisionWinnerKeys.Add($key)
}

foreach ($entry in $playoffField) {
  $team = Get-PropertyValue $entry "team"
  $key = Get-EntryKey `
    -LeagueRecordId (Get-StringValue (Get-PropertyValue $team "leagueRecordId")) `
    -OwnerId (Get-StringValue (Get-PropertyValue $team "ownerId")) `
    -RosterId (Get-PropertyValue $team "rosterId")
  $playoffSeedByKey[$key] = [int](Get-PropertyValue $entry "seed")
}

$playoffCountsByLeague = @{}
foreach ($leagueRecordId in $leagueRecordIds) {
  $playoffCountsByLeague[(Get-StringValue $leagueRecordId)] = 0
}

foreach ($entry in $playoffField) {
  $team = Get-PropertyValue $entry "team"
  $leagueRecordId = Get-StringValue (Get-PropertyValue $team "leagueRecordId")
  if ([string]::IsNullOrWhiteSpace($leagueRecordId)) {
    continue
  }

  if (-not $playoffCountsByLeague.ContainsKey($leagueRecordId)) {
    $playoffCountsByLeague[$leagueRecordId] = 0
  }

  $playoffCountsByLeague[$leagueRecordId]++
}

$lines = [System.Collections.Generic.List[string]]::new()

$reportTitle = if ([string]::IsNullOrWhiteSpace($WeekLabel)) {
  "Combined Group Report"
} else {
  ("{0} Group Report" -f (Get-StringValue $WeekLabel))
}

$lines.Add("VBP BRACKET REDRAFT") | Out-Null
$lines.Add($reportTitle) | Out-Null
$lines.Add(("Group: {0}" -f (Get-StringValue (Get-PropertyValue $group "groupId")))) | Out-Null

if (-not [string]::IsNullOrWhiteSpace($groupLabel)) {
  $lines.Add(("Label: {0}" -f $groupLabel)) | Out-Null
}

if (-not [string]::IsNullOrWhiteSpace($lastSyncedAt)) {
  $lines.Add(("Last Synced: {0}" -f $lastSyncedAt)) | Out-Null
}

if (-not [string]::IsNullOrWhiteSpace($groupNotes)) {
  $lines.Add(("Status: {0}" -f $groupNotes)) | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("DIVISION PLAYOFF COUNTS") | Out-Null

foreach ($leagueRecordId in $leagueRecordIds) {
  $resolvedLeagueRecordId = Get-StringValue $leagueRecordId
  $leagueName = if ($leagueNamesById.ContainsKey($resolvedLeagueRecordId)) {
    $leagueNamesById[$resolvedLeagueRecordId]
  } else {
    $resolvedLeagueRecordId
  }

  $count = if ($playoffCountsByLeague.ContainsKey($resolvedLeagueRecordId)) {
    [int]$playoffCountsByLeague[$resolvedLeagueRecordId]
  } else {
    0
  }

  $lines.Add(("{0}: {1} team{2}" -f $leagueName, $count, $(if ($count -eq 1) { "" } else { "s" }))) | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add(("FULL COMBINED STANDINGS ({0} teams currently tracked)" -f @($overallStandings).Count)) | Out-Null

foreach ($entry in $overallStandings) {
  $rank = Get-PropertyValue $entry "rank"
  $teamName = Get-StringValue (Get-PropertyValue $entry "teamName")
  $leagueName = Get-StringValue (Get-PropertyValue $entry "leagueName")
  $record = Format-RecordDisplay -Record (Get-StringValue (Get-PropertyValue $entry "record"))
  $pointsForDisplay = Get-StringValue (Get-PropertyValue $entry "pointsForDisplay")
  $key = Get-EntryKey `
    -LeagueRecordId (Get-StringValue (Get-PropertyValue $entry "leagueRecordId")) `
    -OwnerId (Get-StringValue (Get-PropertyValue $entry "ownerId")) `
    -RosterId (Get-PropertyValue $entry "rosterId")

  $statusLabel = "Out"
  if ($divisionWinnerKeys.Contains($key)) {
    $statusLabel = "Division Leader"
  } elseif ($playoffSeedByKey.ContainsKey($key)) {
    $seed = [int]$playoffSeedByKey[$key]
    if ($seed -le 30) {
      $statusLabel = "In"
    } else {
      $statusLabel = "Wild Card"
    }
  }

  $lines.Add(("{0}. {1} | {2} | {3} | {4} PF | {5}" -f $rank, $teamName, $leagueName, $record, $pointsForDisplay, $statusLabel)) | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("NOTES") | Out-Null
$lines.Add("- Division counts reflect how many teams from each bracket league are currently inside the tracked playoff field.") | Out-Null
$lines.Add("- Status labels are `Division Leader`, `In`, `Wild Card`, or `Out`.") | Out-Null
$lines.Add("- `Division Leader` is reserved for the five current league winners ranked into Seeds 1-5.") | Out-Null
$lines.Add("- `In` covers Seeds 6-30, and `Wild Card` covers Seeds 31-32.") | Out-Null
$lines.Add("- Points for are shown to two decimals.") | Out-Null
if (-not $seasonDataReady -or -not $seedingReady) {
  $lines.Add("- This report is currently provisional because the grouped bracket season data is not fully ready yet.") | Out-Null
}

$reportText = [string]::Join([Environment]::NewLine, $lines)

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  Set-Content -LiteralPath $OutputPath -Value $reportText
}

if ($PassThru) {
  [pscustomobject]@{
    groupId = Get-StringValue (Get-PropertyValue $group "groupId")
    weekLabel = Get-StringValue $WeekLabel
    outputPath = Get-StringValue $OutputPath
    lineCount = $lines.Count
    reportText = $reportText
  }
} else {
  Write-Output $reportText
}
