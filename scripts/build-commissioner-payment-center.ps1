param(
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$IdentityPath = "data/private/manager-identities.json",
  [string]$PaymentIndexPath = "reports/private/payments/league-payment-index.csv",
  [string]$GenericReportRoot = "reports/private/payments",
  [string]$BbuTrackerPath = "reports/private/bbu-payment-reconciliation/commissioner-tracker.csv",
  [string]$BracketTrackerPath = "reports/private/redraft-bracket-payment-reconciliation/commissioner-tracker.csv",
  [string]$GauntletPaymentPath = "data/private/leaguesafe-gauntlet-payments.csv",
  [string]$OutputRoot = "PAYMENT-CENTER",
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Text { param([AllowNull()][object]$Value) return ([string]$Value).Trim() }
function Get-Property {
  param([AllowNull()][object]$Value, [string]$Name)
  if ($null -ne $Value -and $Value.PSObject.Properties.Match($Name).Count -gt 0) {
    return $Value.PSObject.Properties[$Name].Value
  }
  return $null
}
function Join-TextValues {
  param([AllowNull()][object[]]$Values)
  return (@($Values | ForEach-Object { Get-Text $_ } | Where-Object { $_ } | Select-Object -Unique) -join "; ")
}
function Get-SafeFileName {
  param([string]$Value)
  return (($Value -replace '[^A-Za-z0-9 -]', '') -replace '\s+', '-').Trim("-")
}
function Convert-ToMarkdownText {
  param([AllowNull()][object]$Value)
  $text = Get-Text $Value
  if (-not $text) { return "-" }
  return ($text -replace '\|', '\|')
}
function Format-MoneyDisplay {
  param([AllowNull()][object]$Value)
  $text = Get-Text $Value
  if (-not $text) { return "-" }
  $amount = [decimal]0
  if ([decimal]::TryParse($text, [ref]$amount)) {
    return ('$' + ("{0:N2}" -f $amount))
  }
  return $text
}

$leagues = @(Get-Content -LiteralPath $LeaguesJsonPath -Raw | ConvertFrom-Json | Select-Object -ExpandProperty leagues)
$identityDocument = if (Test-Path -LiteralPath $IdentityPath) { Get-Content -LiteralPath $IdentityPath -Raw | ConvertFrom-Json } else { '{ "people": [] }' | ConvertFrom-Json }
$people = @(Get-Property $identityDocument "people")
$paymentIndex = if (Test-Path -LiteralPath $PaymentIndexPath) { @(Import-Csv -LiteralPath $PaymentIndexPath) } else { @() }

$leagueFolder = Join-Path $OutputRoot "LEAGUES"
$csvRoot = Join-Path $OutputRoot "CSV-EXPORTS"
$csvLeagueFolder = Join-Path $csvRoot "LEAGUES"
foreach ($directory in @($leagueFolder, $csvLeagueFolder)) {
  if (-not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }
}

$masterRows = @($people | Sort-Object name | ForEach-Object {
  $sleeperUsers = @(Get-Property $_ "sleeperUsers")
  $payerRows = @(Get-Property $_ "leagueSafeIdentities")
  [pscustomobject]@{
    confirmedName = Get-Text (Get-Property $_ "name")
    personId = Get-Text (Get-Property $_ "personId")
    sleeperNames = Join-TextValues @($sleeperUsers | ForEach-Object { Get-Property $_ "displayName" })
    sleeperUserIds = Join-TextValues @($sleeperUsers | ForEach-Object { Get-Property $_ "userId" })
    leagueSafeNames = Join-TextValues @($payerRows | ForEach-Object { Get-Property $_ "payerName" })
    leagueSafeEmails = Join-TextValues @($payerRows | ForEach-Object { Get-Property $_ "payerEmail" })
    notes = Get-Text (Get-Property $_ "notes")
  }
})
$masterCsvPath = Join-Path $csvRoot "MASTER-CONFIRMED-MANAGERS.csv"
$masterRows | Export-Csv -LiteralPath $masterCsvPath -NoTypeInformation -Encoding UTF8
$masterPath = Join-Path $OutputRoot "MASTER-CONFIRMED-MANAGERS.md"
$masterLines = @(
  "# Master Confirmed Managers",
  "",
  "Confirmed Sleeper-to-LeagueSafe identity matches that can be reused when a manager enters another league.",
  "",
  "| Manager | Sleeper Name | LeagueSafe Name | Notes |",
  "| --- | --- | --- | --- |"
)
foreach ($manager in $masterRows) {
  $masterLines += "| $(Convert-ToMarkdownText $manager.confirmedName) | $(Convert-ToMarkdownText $manager.sleeperNames) | $(Convert-ToMarkdownText $manager.leagueSafeNames) | $(Convert-ToMarkdownText $manager.notes) |"
}
$masterLines | Set-Content -LiteralPath $masterPath -Encoding UTF8

$indexRows = [System.Collections.Generic.List[object]]::new()
foreach ($league in $leagues) {
  $leagueId = (Get-Text $league.id).ToUpperInvariant()
  $leagueName = Get-Text $league.name
  $fileStem = "{0} - {1}" -f $leagueId, (Get-SafeFileName $leagueName)
  $leagueFileName = "$fileStem.md"
  $csvFileName = "$fileStem.csv"
  $leaguePath = Join-Path $leagueFolder $leagueFileName
  $csvPath = Join-Path $csvLeagueFolder $csvFileName
  $source = ""
  $sheetRows = @()
  $unmatchedRows = @()

  $genericTrackerPath = Join-Path (Join-Path $GenericReportRoot $leagueId) "tracker.csv"
  if (Test-Path -LiteralPath $genericTrackerPath) {
    $source = "Single-league reconciliation"
    $sheetRows = @(Import-Csv -LiteralPath $genericTrackerPath | ForEach-Object {
      [pscustomobject]@{
        leagueId = $leagueId
        leagueName = $leagueName
        sleeperName = Get-Text $_.sleeperName
        sleeperUserId = Get-Text $_.sleeperUserId
        rosterSlot = Get-Text $_.rosterId
        leagueSafeName = Get-Text $_.leagueSafeOwner
        leagueSafeEmail = Get-Text $_.leagueSafeEmail
        paid = Get-Text $_.paid
        owes = Get-Text $_.owes
        status = Get-Text $_.reconciliationStatus
        matchMethod = Get-Text $_.matchMethod
        notes = Get-Text $_.notes
      }
    })
    $genericUnmatchedPath = Join-Path (Join-Path $GenericReportRoot $leagueId) "unmatched-leaguesafe-rows.csv"
    if (Test-Path -LiteralPath $genericUnmatchedPath) {
      $unmatchedRows = @(Import-Csv -LiteralPath $genericUnmatchedPath)
    }
  } elseif ((Get-Text $league.format) -eq "bestball" -and (Test-Path -LiteralPath $BbuTrackerPath)) {
    $source = "Shared Best Ball Union tracker"
    $sheetRows = @(Import-Csv -LiteralPath $BbuTrackerPath | Where-Object { (Get-Text $_.BBU) -eq $leagueId } | ForEach-Object {
      [pscustomobject]@{
        leagueId = $leagueId
        leagueName = $leagueName
        sleeperName = Get-Text $_.'Sleeper Name'
        sleeperUserId = Get-Text $_.'Sleeper User ID'
        rosterSlot = Get-Text $_.'Roster Slot'
        leagueSafeName = Get-Text $_.'LeagueSafe Name'
        leagueSafeEmail = Get-Text $_.'LeagueSafe Email'
        paid = Get-Text $_.Paid
        owes = ""
        status = Get-Text $_.Status
        matchMethod = Get-Text $_.Match
        notes = Get-Text $_.Notes
      }
    })
  } elseif ((Get-Text $league.format) -eq "bracket" -and (Test-Path -LiteralPath $BracketTrackerPath)) {
    $source = "Shared Redraft Bracket tracker"
    $sheetRows = @(Import-Csv -LiteralPath $BracketTrackerPath | Where-Object { (Get-Text $_.Bracket) -eq $leagueId } | ForEach-Object {
      [pscustomobject]@{
        leagueId = $leagueId
        leagueName = $leagueName
        sleeperName = Get-Text $_.'Sleeper Name'
        sleeperUserId = Get-Text $_.'Sleeper User ID'
        rosterSlot = Get-Text $_.'Roster Slot'
        leagueSafeName = Get-Text $_.'LeagueSafe Name'
        leagueSafeEmail = Get-Text $_.'LeagueSafe Email'
        paid = Get-Text $_.Paid
        owes = ""
        status = Get-Text $_.Status
        matchMethod = Get-Text $_.Match
        notes = Get-Text $_.Notes
      }
    })
  } elseif ($leagueId -eq "BG1" -and (Test-Path -LiteralPath $GauntletPaymentPath)) {
    $source = "LeagueSafe paid rows only; Sleeper cross-reference not yet generated"
    $sheetRows = @(Import-Csv -LiteralPath $GauntletPaymentPath | ForEach-Object {
      [pscustomobject]@{
        leagueId = $leagueId
        leagueName = $leagueName
        sleeperName = ""
        sleeperUserId = ""
        rosterSlot = ""
        leagueSafeName = Get-Text $_.payerName
        leagueSafeEmail = Get-Text $_.payerEmail
        paid = Get-Text $_.amount
        owes = ""
        status = "Paid row imported; needs roster match"
        matchMethod = ""
        notes = Get-Text $_.notes
      }
    })
  }

  if ($sheetRows.Count -eq 0) {
    $source = "No payment reconciliation imported yet"
    $sheetRows = @([pscustomobject]@{
      leagueId = $leagueId
      leagueName = $leagueName
      sleeperName = ""
      sleeperUserId = ""
      rosterSlot = ""
      leagueSafeName = ""
      leagueSafeEmail = ""
      paid = ""
      owes = ""
      status = "Import LeagueSafe export to populate this sheet"
      matchMethod = ""
      notes = ""
    })
  }

  $sheetRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
  $assignedRows = @($sheetRows | Where-Object { (Get-Text $_.sleeperName) })
  $paidRows = @($assignedRows | Where-Object { (Get-Text $_.status) -match 'paid' -and (Get-Text $_.status) -notmatch 'possible|review|candidate' })
  $actionRows = @($assignedRows | Where-Object { (Get-Text $_.status) -ne "Matched - paid" })
  $paidTotal = [decimal]0
  $owedTotal = [decimal]0
  foreach ($row in $sheetRows) {
    $amount = [decimal]0
    if ([decimal]::TryParse((Get-Text $row.paid), [ref]$amount)) { $paidTotal += $amount }
    if ([decimal]::TryParse((Get-Text $row.owes), [ref]$amount)) { $owedTotal += $amount }
  }
  foreach ($row in $unmatchedRows) {
    $amount = [decimal]0
    if ([decimal]::TryParse((Get-Text $row.paid), [ref]$amount)) { $paidTotal += $amount }
    if ([decimal]::TryParse((Get-Text $row.owes), [ref]$amount)) { $owedTotal += $amount }
  }
  $leagueLines = @(
    "# $leagueId - $leagueName",
    "",
    "- Format: $(Get-Text $league.format)",
    "- League status: $(Get-Text $league.status)",
    "- Payment source: $source",
    "- Sleeper entries shown: $($assignedRows.Count)",
    "- Imported paid total: $(Format-MoneyDisplay $paidTotal)",
    "- Imported owed total: $(Format-MoneyDisplay $owedTotal)",
    "",
    "## Needs Attention",
    ""
  )
  if ($actionRows.Count -eq 0) {
    $leagueLines += "No unresolved entries in the current tracker."
  } else {
    $leagueLines += "| Sleeper Manager | LeagueSafe Name | Paid | Owes | Status | Match Note |"
    $leagueLines += "| --- | --- | ---: | ---: | --- | --- |"
    foreach ($row in $actionRows) {
      $leagueLines += "| $(Convert-ToMarkdownText $row.sleeperName) | $(Convert-ToMarkdownText $row.leagueSafeName) | $(Format-MoneyDisplay $row.paid) | $(Format-MoneyDisplay $row.owes) | $(Convert-ToMarkdownText $row.status) | $(Convert-ToMarkdownText $row.matchMethod) |"
    }
  }
  $leagueLines += @(
    "",
    "## Paid / Matched",
    ""
  )
  if ($paidRows.Count -eq 0) {
    $leagueLines += "No confirmed paid matches in the current tracker."
  } else {
    $leagueLines += "| Sleeper Manager | LeagueSafe Name | Paid | Match |"
    $leagueLines += "| --- | --- | ---: | --- |"
    foreach ($row in $paidRows) {
      $leagueLines += "| $(Convert-ToMarkdownText $row.sleeperName) | $(Convert-ToMarkdownText $row.leagueSafeName) | $(Format-MoneyDisplay $row.paid) | $(Convert-ToMarkdownText $row.matchMethod) |"
    }
  }
  $leagueLines += @(
    "",
    "## Unmatched LeagueSafe Entries",
    ""
  )
  if ($unmatchedRows.Count -eq 0) {
    $leagueLines += "No separate unmatched LeagueSafe rows are currently stored for this league."
  } else {
    $leagueLines += "| LeagueSafe Name | Paid | Owes | Status | Notes |"
    $leagueLines += "| --- | ---: | ---: | --- | --- |"
    foreach ($row in $unmatchedRows) {
      $leagueLines += "| $(Convert-ToMarkdownText $row.leagueSafeOwner) | $(Format-MoneyDisplay $row.paid) | $(Format-MoneyDisplay $row.owes) | $(Convert-ToMarkdownText $row.status) | $(Convert-ToMarkdownText $row.notes) |"
    }
  }
  $leagueLines += @(
    "",
    "## Full Tracker",
    "",
    "| Slot | Sleeper Manager | LeagueSafe Name | Paid | Owes | Status |",
    "| ---: | --- | --- | ---: | ---: | --- |"
  )
  foreach ($row in $sheetRows) {
    $leagueLines += "| $(Convert-ToMarkdownText $row.rosterSlot) | $(Convert-ToMarkdownText $row.sleeperName) | $(Convert-ToMarkdownText $row.leagueSafeName) | $(Format-MoneyDisplay $row.paid) | $(Format-MoneyDisplay $row.owes) | $(Convert-ToMarkdownText $row.status) |"
  }
  $leagueLines += @(
    "",
    "Spreadsheet export: ``..\CSV-EXPORTS\LEAGUES\$csvFileName``"
  )
  $leagueLines | Set-Content -LiteralPath $leaguePath -Encoding UTF8
  $paymentSource = @($paymentIndex | Where-Object { (Get-Text $_.leagueId) -eq $leagueId } | Select-Object -First 1)
  $indexRows.Add([pscustomobject]@{
    leagueId = $leagueId
    leagueName = $leagueName
    format = Get-Text $league.format
    status = Get-Text $league.status
    paymentSource = if ($paymentSource.Count) { Get-Text $paymentSource[0].paymentSource } else { $source }
    leagueFile = "LEAGUES\$leagueFileName"
    csvFile = "CSV-EXPORTS\LEAGUES\$csvFileName"
    sheetStatus = $source
  }) | Out-Null
}

$indexCsvPath = Join-Path $csvRoot "ALL-LEAGUES-PAYMENT-INDEX.csv"
$indexRows | Export-Csv -LiteralPath $indexCsvPath -NoTypeInformation -Encoding UTF8
$indexPath = Join-Path $OutputRoot "ALL-LEAGUES-PAYMENT-INDEX.md"
$indexLines = @(
  "# All Leagues Payment Index",
  "",
  "| League | Name | Format | Source | Readable Sheet |",
  "| --- | --- | --- | --- | --- |"
)
foreach ($row in $indexRows) {
  $indexLines += "| $($row.leagueId) | $(Convert-ToMarkdownText $row.leagueName) | $($row.format) | $(Convert-ToMarkdownText $row.paymentSource) | [$($row.leagueId)](./$($row.leagueFile -replace '\\', '/')) |"
}
$indexLines | Set-Content -LiteralPath $indexPath -Encoding UTF8

$startPath = Join-Path $OutputRoot "START-HERE.md"
$readySheets = @($indexRows | Where-Object { $_.sheetStatus -notmatch "^No payment" }).Count
$lines = @(
  "# VBP Payment Center",
  "",
  "Open this folder for private commissioner payment tracking. These files contain manager and payment information and should not be published.",
  "",
  "## Main Files",
  "",
  "- ``ALL-LEAGUES-PAYMENT-INDEX.md`` - readable list of every league with links to each league page.",
  "- ``MASTER-CONFIRMED-MANAGERS.md`` - readable confirmed Sleeper/LeagueSafe identity master list.",
  "- ``LEAGUES\`` - readable Markdown payment page for each league record.",
  "- ``CSV-EXPORTS\`` - spreadsheet versions for sorting or opening in Excel.",
  "",
  "## Current Coverage",
  "",
  "- League sheets created: $($indexRows.Count)",
  "- League sheets with existing payment/tracker content: $readySheets",
  "- Confirmed manager identities saved: $($masterRows.Count)",
  "",
  "League pages with no payment input yet contain a reminder until the corresponding LeagueSafe export is imported and reconciled."
)
$lines | Set-Content -LiteralPath $startPath -Encoding UTF8

# Remove the former CSV-first presentation after the Markdown pages and exports are written.
foreach ($oldPath in @(
  (Join-Path $OutputRoot "ALL-LEAGUES-PAYMENT-INDEX.csv"),
  (Join-Path $OutputRoot "MASTER-CONFIRMED-MANAGERS.csv")
)) {
  if (Test-Path -LiteralPath $oldPath) { Remove-Item -LiteralPath $oldPath -Force }
}
Get-ChildItem -LiteralPath $leagueFolder -Filter "*.csv" -File -ErrorAction SilentlyContinue | Remove-Item -Force

$result = [pscustomobject]@{
  outputRoot = $OutputRoot
  startHerePath = $startPath
  indexPath = $indexPath
  masterManagerPath = $masterPath
  csvExportRoot = $csvRoot
  leagueSheetCount = $indexRows.Count
  populatedLeagueSheetCount = $readySheets
  confirmedManagerCount = $masterRows.Count
}
if ($PassThru) {
  $result
} else {
  Write-Host "Commissioner payment center written to $OutputRoot"
  Write-Host "League sheets created: $($result.leagueSheetCount)"
  Write-Host "Confirmed managers listed: $($result.confirmedManagerCount)"
}
