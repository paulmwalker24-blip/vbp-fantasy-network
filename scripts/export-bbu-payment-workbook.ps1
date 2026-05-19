param(
  [string]$CsvDirectory = "reports/private/bbu-payment-reconciliation",
  [string]$OutputPath = "reports/private/bbu-payment-reconciliation/bbu-payment-tracker.xlsx",
  [switch]$Open
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Convert-ToColumnLetter {
  param(
    [int]$ColumnNumber
  )

  $letter = ""
  while ($ColumnNumber -gt 0) {
    $mod = ($ColumnNumber - 1) % 26
    $letter = [char](65 + $mod) + $letter
    $ColumnNumber = [math]::Floor(($ColumnNumber - $mod) / 26)
  }

  return $letter
}

function Set-WorkbookSheetStyle {
  param(
    [object]$Workbook,
    [string]$SheetName,
    [string]$CsvPath,
    [hashtable]$Options
  )

  if (-not (Test-Path -LiteralPath $CsvPath)) {
    return $null
  }

  $sheet = if ($Workbook.Worksheets.Count -eq 1 -and $Workbook.Worksheets.Item(1).UsedRange.Count -eq 1 -and [string]::IsNullOrWhiteSpace([string]$Workbook.Worksheets.Item(1).Cells.Item(1,1).Text)) {
    $Workbook.Worksheets.Item(1)
  } else {
    $Workbook.Worksheets.Add([System.Type]::Missing, $Workbook.Worksheets.Item($Workbook.Worksheets.Count))
  }

  $sheet.Name = $SheetName
  $rows = @(Import-Csv -LiteralPath $CsvPath)

  if ($rows.Count -eq 0) {
    $sheet.Cells.Item(1, 1) = "No rows yet"
    $sheet.Columns.AutoFit() | Out-Null
    return $sheet
  }

  $headers = @($rows[0].PSObject.Properties.Name)
  for ($columnIndex = 0; $columnIndex -lt $headers.Count; $columnIndex++) {
    $sheet.Cells.Item(1, $columnIndex + 1) = $headers[$columnIndex]
  }

  for ($rowIndex = 0; $rowIndex -lt $rows.Count; $rowIndex++) {
    for ($columnIndex = 0; $columnIndex -lt $headers.Count; $columnIndex++) {
      $sheet.Cells.Item($rowIndex + 2, $columnIndex + 1) = [string](Get-PropertyValue $rows[$rowIndex] $headers[$columnIndex])
    }
  }

  $lastRow = $rows.Count + 1
  $lastColumn = $headers.Count
  $usedRange = $sheet.Range($sheet.Cells.Item(1, 1), $sheet.Cells.Item($lastRow, $lastColumn))

  $tableName = (($SheetName -replace '[^A-Za-z0-9]', '') + "Table")
  $listObject = $sheet.ListObjects.Add(1, $usedRange, $null, 1)
  $listObject.Name = $tableName
  $listObject.TableStyle = "TableStyleMedium2"

  $sheet.Activate() | Out-Null
  $sheet.Application.ActiveWindow.SplitRow = 1
  $sheet.Application.ActiveWindow.FreezePanes = $true
  $sheet.Application.ActiveWindow.DisplayGridlines = $false

  $headerRange = $sheet.Range($sheet.Cells.Item(1, 1), $sheet.Cells.Item(1, $lastColumn))
  $headerRange.Font.Bold = $true
  $headerRange.Font.Color = 16777215
  $headerRange.Interior.Color = 39423
  $headerRange.VerticalAlignment = -4108

  $usedRange.Font.Name = "Aptos"
  $usedRange.Font.Size = 10
  $usedRange.VerticalAlignment = -4160
  $usedRange.WrapText = $false
  $usedRange.Columns.AutoFit() | Out-Null

  foreach ($moneyColumn in @($Options.moneyColumns)) {
    $columnPosition = [array]::IndexOf($headers, $moneyColumn) + 1
    if ($columnPosition -gt 0) {
      $sheet.Columns.Item($columnPosition).NumberFormat = "$#,##0.00"
    }
  }

  foreach ($wideColumn in @($Options.wideColumns)) {
    $columnPosition = [array]::IndexOf($headers, $wideColumn) + 1
    if ($columnPosition -gt 0) {
      $sheet.Columns.Item($columnPosition).ColumnWidth = 34
      $sheet.Columns.Item($columnPosition).WrapText = $true
    }
  }

  foreach ($compactColumn in @($Options.compactColumns)) {
    $columnPosition = [array]::IndexOf($headers, $compactColumn) + 1
    if ($columnPosition -gt 0) {
      $sheet.Columns.Item($columnPosition).ColumnWidth = 12
    }
  }

  $statusColumnName = [string]$Options.statusColumn
  $statusColumn = [array]::IndexOf($headers, $statusColumnName) + 1
  $leagueColorColumnName = if ($Options.ContainsKey("leagueColorColumn")) { [string]$Options.leagueColorColumn } else { "" }
  $leagueColorColumn = [array]::IndexOf($headers, $leagueColorColumnName) + 1
  if ($statusColumn -gt 0) {
    for ($row = 2; $row -le $lastRow; $row++) {
      $value = [string]$sheet.Cells.Item($row, $statusColumn).Text
      $rowRange = $sheet.Range($sheet.Cells.Item($row, 1), $sheet.Cells.Item($row, $lastColumn))

      switch -Regex ($value) {
        "Possible paid match|Matched|Paid even|Paid" {
          $rowRange.Interior.Color = 13434828
          break
        }
        "Needs|Unmatched|Owes|NotPaid|Waiting assignment" {
          $rowRange.Interior.Color = 10092543
          break
        }
        "Extra|Partial|review" {
          $rowRange.Interior.Color = 10086143
          break
        }
      }
    }
  }

  if ($leagueColorColumn -gt 0) {
    $leagueColors = @{
      BBU1 = 14277081
      BBU2 = 13434879
      BBU3 = 13434828
      BBU4 = 10086143
      BBU5 = 10092543
      RDB1 = 14277081
      RDB2 = 13434879
      RDB3 = 13434828
      RDB4 = 10086143
      RDB5 = 10092543
    }

    for ($row = 2; $row -le $lastRow; $row++) {
      $leagueValue = [string]$sheet.Cells.Item($row, $leagueColorColumn).Text
      if ($leagueColors.ContainsKey($leagueValue)) {
        $sheet.Cells.Item($row, $leagueColorColumn).Interior.Color = $leagueColors[$leagueValue]
        $sheet.Cells.Item($row, $leagueColorColumn).Font.Bold = $true
      }
    }
  }

  if ($Options.ContainsKey("hidden") -and $Options.hidden) {
    $sheet.Visible = 0
  }

  $usedRange.Borders.LineStyle = 1
  $usedRange.Borders.Color = 14277081

  $sheet.Rows.Item(1).RowHeight = 24
  $sheet.Columns.AutoFit() | Out-Null

  foreach ($wideColumn in @($Options.wideColumns)) {
    $columnPosition = [array]::IndexOf($headers, $wideColumn) + 1
    if ($columnPosition -gt 0) {
      $sheet.Columns.Item($columnPosition).ColumnWidth = 34
    }
  }

  if (-not ($Options.ContainsKey("hidden") -and $Options.hidden)) {
    $sheet.Activate() | Out-Null
    $sheet.Range("A2").Select() | Out-Null
  }
  return $sheet
}

$resolvedCsvDirectory = Resolve-Path -LiteralPath $CsvDirectory
$resolvedOutputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($resolvedOutputDirectory) -and -not (Test-Path -LiteralPath $resolvedOutputDirectory)) {
  New-Item -ItemType Directory -Path $resolvedOutputDirectory | Out-Null
}

$excel = $null
$workbook = $null

try {
  $excel = New-Object -ComObject Excel.Application
  $excel.Visible = $false
  $excel.DisplayAlerts = $false

  $workbook = $excel.Workbooks.Add()
  while ($workbook.Worksheets.Count -gt 1) {
    $workbook.Worksheets.Item($workbook.Worksheets.Count).Delete()
  }

  $sheetDefinitions = @(
    @{
      name = "BBU Tracker"
      csv = "commissioner-tracker.csv"
      options = @{
        statusColumn = "Status"
        leagueColorColumn = "BBU"
        moneyColumns = @("Paid")
        wideColumns = @("Sleeper Name", "LeagueSafe Name", "LeagueSafe Email", "Notes")
        compactColumns = @("BBU", "Assignment", "Roster Slot", "Paid", "Status", "Match")
      }
    },
    @{
      name = "Bracket Tracker"
      csv = "..\redraft-bracket-payment-reconciliation\commissioner-tracker.csv"
      options = @{
        statusColumn = "Status"
        leagueColorColumn = "Bracket"
        moneyColumns = @("Paid")
        wideColumns = @("Division", "Sleeper Name", "LeagueSafe Name", "LeagueSafe Email", "Notes")
        compactColumns = @("Bracket", "Draft", "Assignment", "Roster Slot", "Paid", "Status", "Match")
      }
    },
    @{
      name = "Bracket Paid Not Assigned"
      csv = "..\redraft-bracket-payment-reconciliation\paid-not-assigned.csv"
      options = @{
        statusColumn = "Status"
        moneyColumns = @("Paid")
        wideColumns = @("LeagueSafe Name", "LeagueSafe Email", "Notes")
        compactColumns = @("Paid", "Status")
      }
    },
    @{
      name = "Paid Not Assigned"
      csv = "paid-not-assigned.csv"
      options = @{
        statusColumn = "Status"
        leagueColorColumn = "Possible BBU"
        moneyColumns = @("Paid")
        wideColumns = @("LeagueSafe Name", "LeagueSafe Email", "Matched Person", "Possible Sleeper", "Notes")
        compactColumns = @("Paid", "Possible BBU", "Possible Assignment", "Match", "Status")
      }
    },
    @{
      name = "Action Tracker"
      csv = "bbu-action-tracker.csv"
      options = @{
        statusColumn = "actionStatus"
        hidden = $true
        moneyColumns = @("buyIn", "leagueSafePaid", "leagueSafeOwes")
        wideColumns = @("leagueName", "sleeperTeamName", "leagueSafeOwnerCandidate", "leagueSafeEmailCandidate", "matchConfidence", "commissionerNotes")
        compactColumns = @("leagueId", "buyIn", "assignmentStatus", "rosterId", "leagueSafePaid", "leagueSafeOwes", "actionStatus")
      }
    },
    @{
      name = "Person Summary"
      csv = "person-summary.csv"
      options = @{
        statusColumn = "paymentStatus"
        hidden = $true
        moneyColumns = @("amountDue", "matchedPaid", "balance")
        wideColumns = @("personName", "bbuEntries")
        compactColumns = @("entryCount", "amountDue", "matchedPaid", "balance")
      }
    },
    @{
      name = "Sleeper Entries"
      csv = "sleeper-entries.csv"
      options = @{
        statusColumn = "matchStatus"
        hidden = $true
        moneyColumns = @("buyIn")
        wideColumns = @("leagueName", "teamName", "sleeperDisplayName", "personName")
        compactColumns = @("leagueId", "buyIn", "assignmentStatus", "rosterId")
      }
    },
    @{
      name = "LeagueSafe Export"
      csv = "leaguesafe-export.csv"
      options = @{
        statusColumn = "status"
        hidden = $true
        moneyColumns = @("entryFee", "paid", "owes", "paid")
        wideColumns = @("owner", "ownerEmail", "notes")
        compactColumns = @("entryFee", "paid", "owes", "status", "leagueRecordId")
      }
    },
    @{
      name = "Unmatched Payments"
      csv = "unmatched-payments.csv"
      options = @{
        statusColumn = "matchStatus"
        hidden = $true
        moneyColumns = @("amount")
        wideColumns = @("payerName", "payerEmail", "notes")
        compactColumns = @("amount", "status")
      }
    }
  )

  foreach ($definition in $sheetDefinitions) {
    $csvPath = Join-Path $resolvedCsvDirectory $definition.csv
    Set-WorkbookSheetStyle -Workbook $workbook -SheetName $definition.name -CsvPath $csvPath -Options $definition.options | Out-Null
  }

  $workbook.Worksheets.Item("BBU Tracker").Activate() | Out-Null
  $workbook.SaveAs((Join-Path (Resolve-Path -LiteralPath (Split-Path -Parent $OutputPath)) (Split-Path -Leaf $OutputPath)), 51)
  $workbook.Close($true)
  $workbook = $null
} finally {
  if ($null -ne $workbook) {
    $workbook.Close($false)
  }

  if ($null -ne $excel) {
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
  }
}

Write-Host "BBU payment workbook written to $OutputPath"

if ($Open) {
  Start-Process -FilePath $OutputPath
}
