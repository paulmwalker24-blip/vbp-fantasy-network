param(
  [Parameter(Mandatory = $true)]
  [string]$LeagueRecordId,
  [Parameter(Mandatory = $true)]
  [string]$SourcePath,
  [string]$PaymentPeriod = "current",
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$OutputDirectory = "data/private/payments/exports",
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToDecimal {
  param([AllowNull()][object]$Value)

  $raw = ([string]$Value).Trim() -replace '[$,]', ''
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [decimal]0
  }

  $parsed = [decimal]0
  if ([decimal]::TryParse($raw, [ref]$parsed)) {
    return $parsed
  }

  return [decimal]0
}

if (-not (Test-Path -LiteralPath $SourcePath)) {
  throw "Source LeagueSafe export not found: $SourcePath"
}
if ($PaymentPeriod -notmatch '^[A-Za-z0-9-]+$') {
  throw "PaymentPeriod may contain only letters, digits, and hyphens."
}

$leagues = @(Get-Content -LiteralPath $LeaguesJsonPath -Raw | ConvertFrom-Json | Select-Object -ExpandProperty leagues)
$league = @($leagues | Where-Object { ([string]$_.id).Trim() -eq $LeagueRecordId.Trim() }) | Select-Object -First 1
if ($null -eq $league) {
  throw "League record not found in ${LeaguesJsonPath}: $LeagueRecordId"
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
  New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$normalizedId = ([string]$league.id).Trim().ToUpperInvariant()
$outputPath = Join-Path $OutputDirectory ("{0}-{1}.csv" -f $normalizedId, $PaymentPeriod.ToLowerInvariant())
Copy-Item -LiteralPath $SourcePath -Destination $outputPath -Force

$rows = @(Import-Csv -LiteralPath $outputPath)
if ($rows.Count -gt 0 -and $rows[0].PSObject.Properties.Match("Owner").Count -eq 0) {
  throw "The imported file does not appear to be a LeagueSafe payment-details CSV: $SourcePath"
}

$nonCommissionerRows = @($rows | Where-Object { ([string]$_.IsCommish).Trim() -ne "True" })
$paidRows = @($nonCommissionerRows | Where-Object { (Convert-ToDecimal $_.Paid) -gt 0 })
$unpaidRows = @($nonCommissionerRows | Where-Object { (Convert-ToDecimal $_.Owes) -gt 0 })
$summary = [pscustomobject]@{
  leagueRecordId = $normalizedId
  leagueName = ([string]$league.name).Trim()
  paymentPeriod = $PaymentPeriod.ToLowerInvariant()
  sourcePath = $SourcePath
  outputPath = $outputPath
  participantRows = $nonCommissionerRows.Count
  paidRows = $paidRows.Count
  unpaidRows = $unpaidRows.Count
  paidTotal = [decimal](@($paidRows | Measure-Object -Property Paid -Sum).Sum)
  owedTotal = [decimal](@($unpaidRows | Measure-Object -Property Owes -Sum).Sum)
}

if ($PassThru) {
  $summary
} else {
  Write-Host "Saved LeagueSafe export for $normalizedId to $outputPath"
  Write-Host "Participant rows: $($summary.participantRows)"
  Write-Host "Paid rows: $($summary.paidRows)"
  Write-Host "Unpaid rows: $($summary.unpaidRows)"
  Write-Host ("Paid total: $" + ("{0:N2}" -f $summary.paidTotal))
  Write-Host ("Owed total: $" + ("{0:N2}" -f $summary.owedTotal))
}
