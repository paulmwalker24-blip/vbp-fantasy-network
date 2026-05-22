param(
  [Parameter(Mandatory = $true)]
  [string]$SourcePath,
  [string]$RawOutputPath = "data/private/leaguesafe-gauntlet-current.csv",
  [string]$PaymentsOutputPath = "data/private/leaguesafe-gauntlet-payments.csv",
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToDecimal {
  param([AllowNull()][object]$Value)
  $raw = ([string]$Value).Trim() -replace '[$,]', ''
  if ([string]::IsNullOrWhiteSpace($raw)) { return [decimal]0 }
  $parsed = [decimal]0
  if ([decimal]::TryParse($raw, [ref]$parsed)) { return $parsed }
  return [decimal]0
}

if (-not (Test-Path -LiteralPath $SourcePath)) {
  throw "Source LeagueSafe export not found: $SourcePath"
}

foreach ($path in @($RawOutputPath, $PaymentsOutputPath)) {
  $directory = Split-Path -Parent $path
  if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
  }
}

Copy-Item -LiteralPath $SourcePath -Destination $RawOutputPath -Force

$rows = @(Import-Csv -LiteralPath $RawOutputPath)
$payments = @($rows | ForEach-Object {
  $paid = Convert-ToDecimal $_.Paid
  if ($paid -gt 0) {
    [pscustomobject]@{
      paymentId = "LS-BG-$($_.OwnerId)"
      leagueGroup = "Best Ball Gauntlet"
      leagueRecordId = "BG1"
      payerName = $_.Owner
      payerEmail = $_.OwnerEmail
      amount = $paid
      date = ""
      status = $_.Status
      notes = "LeagueSafe OwnerId $($_.OwnerId); EntryFee $($_.EntryFee); Owes $($_.Owes)"
      personId = ""
    }
  }
})

$payments | Export-Csv -LiteralPath $PaymentsOutputPath -NoTypeInformation -Encoding UTF8

$summary = [pscustomobject]@{
  sourcePath = $SourcePath
  rawOutputPath = $RawOutputPath
  paymentsOutputPath = $PaymentsOutputPath
  totalRows = $rows.Count
  paidRows = $payments.Count
  notPaidRows = @($rows | Where-Object { $_.Status -eq "NotPaid" }).Count
  paidTotal = [decimal](@($payments | Measure-Object -Property amount -Sum).Sum)
}

if ($PassThru) {
  $summary
} else {
  Write-Host "Saved raw Best Ball Gauntlet LeagueSafe export to $RawOutputPath"
  Write-Host "Wrote normalized paid rows to $PaymentsOutputPath"
  Write-Host "Total rows: $($summary.totalRows)"
  Write-Host "Paid rows: $($summary.paidRows)"
  Write-Host "Not paid rows: $($summary.notPaidRows)"
  Write-Host ("Paid total: $" + ("{0:N2}" -f $summary.paidTotal))
}
