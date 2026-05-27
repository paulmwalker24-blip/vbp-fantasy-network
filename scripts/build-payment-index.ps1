param(
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$ExportDirectory = "data/private/payments/exports",
  [string]$OutputDirectory = "reports/private/payments",
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Text { param([AllowNull()][object]$Value) return ([string]$Value).Trim() }

$leagues = @(Get-Content -LiteralPath $LeaguesJsonPath -Raw | ConvertFrom-Json | Select-Object -ExpandProperty leagues)
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
  New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$rows = @($leagues | ForEach-Object {
  $id = (Get-Text $_.id).ToUpperInvariant()
  $individualExports = @(Get-ChildItem -LiteralPath $ExportDirectory -Filter ("{0}-*.csv" -f $id) -File -ErrorAction SilentlyContinue)
  $sourceType = "No export imported"
  $sourcePath = ""
  $workflow = "Import individual LeagueSafe CSV"
  if ($individualExports.Count -gt 0) {
    $sourceType = if ($individualExports.Count -eq 1) { "Individual export" } else { "Individual exports ($($individualExports.Count))" }
    $sourcePath = (@($individualExports | Select-Object -ExpandProperty FullName) -join "; ")
    $workflow = "Generic reconciliation ready"
  } elseif ((Get-Text $_.format) -eq "bestball" -and (Test-Path -LiteralPath "data/private/leaguesafe-bbu-current.csv")) {
    $sourceType = "Shared BBU export"
    $sourcePath = "data/private/leaguesafe-bbu-current.csv"
    $workflow = "Use BBU pooled reconciliation"
  } elseif ((Get-Text $_.format) -eq "bracket" -and (Test-Path -LiteralPath "data/private/leaguesafe-bracket-current.csv")) {
    $sourceType = "Shared Bracket export"
    $sourcePath = "data/private/leaguesafe-bracket-current.csv"
    $workflow = "Use bracket pooled reconciliation"
  } elseif ($id -eq "BG1" -and (Test-Path -LiteralPath "data/private/leaguesafe-gauntlet-current.csv")) {
    $sourceType = "Legacy BG1 export"
    $sourcePath = "data/private/leaguesafe-gauntlet-current.csv"
    $workflow = "Import into generic folder when refreshed"
  }
  [pscustomobject]@{
    leagueId = $id
    leagueName = Get-Text $_.name
    format = Get-Text $_.format
    buyIn = Get-Text $_.buyIn
    status = Get-Text $_.status
    sleeperLeagueId = Get-Text $_.sleeperLeagueId
    paymentSource = $sourceType
    sourcePath = $sourcePath
    workflow = $workflow
  }
})

$csvPath = Join-Path $OutputDirectory "league-payment-index.csv"
$markdownPath = Join-Path $OutputDirectory "README.md"
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$coveredCount = @($rows | Where-Object { $_.paymentSource -ne "No export imported" }).Count
$individualCount = @($rows | Where-Object { $_.paymentSource -like "Individual export*" }).Count
$lines = @(
  "# Payment Center",
  "",
  "This private report indexes stored LeagueSafe exports against the leagues in ``data/leagues.json``.",
  "",
  "- League records: $($rows.Count)",
  "- Records with an individual or shared stored export: $coveredCount",
  "- Individual exports ready for generic reconciliation: $individualCount",
  "",
  "| League | Name | Payment Source | Workflow |",
  "| --- | --- | --- | --- |"
)
foreach ($row in $rows) {
  $lines += "| $($row.leagueId) | $($row.leagueName) | $($row.paymentSource) | $($row.workflow) |"
}
$lines | Set-Content -LiteralPath $markdownPath -Encoding UTF8

$result = [pscustomobject]@{
  leagueCount = $rows.Count
  coveredCount = $coveredCount
  individualCount = $individualCount
  csvPath = $csvPath
  markdownPath = $markdownPath
}
if ($PassThru) {
  $result
} else {
  Write-Host "Payment index written to $markdownPath"
  Write-Host "Leagues indexed: $($result.leagueCount)"
  Write-Host "Records with stored payment exports: $($result.coveredCount)"
}
