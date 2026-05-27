param(
  [Parameter(Mandatory = $true)]
  [string]$LeagueRecordId,
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$IdentityPath = "data/private/manager-identities.json",
  [string]$PaymentStatusOverridesPath = "data/private/payment-status-overrides.json",
  [string[]]$ExportPaths,
  [string]$OutputRoot = "reports/private/payments",
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
function Get-Key {
  param([AllowNull()][object]$Value)
  return ((Get-Text $Value).ToLowerInvariant() -replace '[^a-z0-9]', '')
}
function Convert-ToDecimal {
  param([AllowNull()][object]$Value)
  $raw = (Get-Text $Value) -replace '[$,]', ''
  if (-not $raw) { return [decimal]0 }
  $parsed = [decimal]0
  if ([decimal]::TryParse($raw, [ref]$parsed)) { return $parsed }
  return [decimal]0
}
function Convert-ToArray {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return @($Value) }
  $wrapped = Get-Property $Value "value"
  if ($null -ne $wrapped) { return @(Convert-ToArray $wrapped) }
  return @($Value)
}
function Format-Money {
  param([AllowNull()][object]$Value)
  return ('$' + ("{0:N2}" -f (Convert-ToDecimal $Value)))
}
function Get-PaymentStatusOverride {
  param([string]$LeagueId, [object]$Payment, [object[]]$Overrides)
  foreach ($override in $Overrides) {
    if ((Get-Text (Get-Property $override "leagueRecordId")).ToUpperInvariant() -ne $LeagueId) { continue }
    $owner = Get-Key (Get-Property $override "leagueSafeOwner")
    $email = Get-Key (Get-Property $override "leagueSafeEmail")
    if (($owner -and $owner -eq (Get-Key $Payment.Owner)) -or ($email -and $email -eq (Get-Key $Payment.OwnerEmail))) {
      return $override
    }
  }
  return $null
}

$leagues = @(Get-Content -LiteralPath $LeaguesJsonPath -Raw | ConvertFrom-Json | Select-Object -ExpandProperty leagues)
$league = @($leagues | Where-Object { (Get-Text $_.id) -eq $LeagueRecordId.Trim() }) | Select-Object -First 1
if ($null -eq $league) {
  throw "League record not found in ${LeaguesJsonPath}: $LeagueRecordId"
}

$leagueId = (Get-Text $league.id).ToUpperInvariant()
$sleeperLeagueId = Get-Text $league.sleeperLeagueId
if (-not $sleeperLeagueId) {
  throw "$leagueId does not have a Sleeper league ID."
}

if (-not $ExportPaths -or $ExportPaths.Count -eq 0) {
  $ExportPaths = @(Get-ChildItem -LiteralPath "data/private/payments/exports" -Filter ("{0}-*.csv" -f $leagueId) -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
}
if (-not $ExportPaths -or $ExportPaths.Count -eq 0) {
  throw "No LeagueSafe export found for $leagueId. Import it first with scripts/import-leaguesafe-export.ps1."
}

$paymentRows = @($ExportPaths | ForEach-Object {
  $path = $_
  if (-not (Test-Path -LiteralPath $path)) {
    throw "LeagueSafe export not found: $path"
  }
  Import-Csv -LiteralPath $path | Where-Object { (Get-Text $_.IsCommish) -ne "True" } | ForEach-Object {
    [pscustomobject]@{
      Owner = Get-Text $_.Owner
      OwnerEmail = Get-Text $_.OwnerEmail
      Paid = Convert-ToDecimal $_.Paid
      Owes = Convert-ToDecimal $_.Owes
      Status = Get-Text $_.Status
      SourceExport = Split-Path -Leaf $path
    }
  }
})
$paymentStatusDocument = if (Test-Path -LiteralPath $PaymentStatusOverridesPath) { Get-Content -LiteralPath $PaymentStatusOverridesPath -Raw | ConvertFrom-Json } else { '{ "entries": [] }' | ConvertFrom-Json }
$paymentStatusOverrides = @(Get-Property $paymentStatusDocument "entries")
$rawPayments = @($paymentRows | Group-Object { if (Get-Key $_.OwnerEmail) { Get-Key $_.OwnerEmail } else { Get-Key $_.Owner } } | ForEach-Object {
  $items = @($_.Group)
  $paid = [decimal](@($items | Measure-Object -Property Paid -Sum).Sum)
  $owes = [decimal](@($items | Measure-Object -Property Owes -Sum).Sum)
  $payment = [pscustomobject]@{
    Owner = Get-Text $items[0].Owner
    OwnerEmail = Get-Text $items[0].OwnerEmail
    Paid = $paid
    Owes = $owes
    Status = if ($owes -gt 0) { "Owes" } elseif ($paid -gt 0) { "Paid" } else { Get-Text $items[0].Status }
    SourceExports = (@($items | Select-Object -ExpandProperty SourceExport -Unique) -join "; ")
  }
  $override = Get-PaymentStatusOverride -LeagueId $leagueId -Payment $payment -Overrides $paymentStatusOverrides
  $payment | Add-Member -NotePropertyName ManualStatus -NotePropertyValue (Get-Text (Get-Property $override "status"))
  $payment | Add-Member -NotePropertyName ManualNote -NotePropertyValue (Get-Text (Get-Property $override "note"))
  $payment | Add-Member -NotePropertyName ExcludeFromRosterMatch -NotePropertyValue ([bool](Get-Property $override "excludeFromRosterMatch"))
  $payment
})
$matchablePayments = @($rawPayments | Where-Object { -not $_.ExcludeFromRosterMatch })
$identityDocument = if (Test-Path -LiteralPath $IdentityPath) { Get-Content -LiteralPath $IdentityPath -Raw | ConvertFrom-Json } else { '{ "people": [] }' | ConvertFrom-Json }
$people = @(Get-Property $identityDocument "people")
$peopleBySleeperId = @{}
$paymentsByPersonId = @{}
foreach ($person in $people) {
  $personId = Get-Text (Get-Property $person "personId")
  foreach ($sleeperUser in @(Get-Property $person "sleeperUsers")) {
    $userId = Get-Key (Get-Property $sleeperUser "userId")
    if ($userId) { $peopleBySleeperId[$userId] = $person }
  }
  foreach ($payer in @(Get-Property $person "leagueSafeIdentities")) {
    $payerName = Get-Key (Get-Property $payer "payerName")
    $payerEmail = Get-Key (Get-Property $payer "payerEmail")
    foreach ($payment in $matchablePayments) {
      if (($payerName -and $payerName -eq (Get-Key $payment.Owner)) -or ($payerEmail -and $payerEmail -eq (Get-Key $payment.OwnerEmail))) {
        $paymentsByPersonId[$personId] = $payment
      }
    }
  }
}

$users = @(Convert-ToArray (Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/users" -f $sleeperLeagueId) -Method Get))
$rosters = @(Convert-ToArray (Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/rosters" -f $sleeperLeagueId) -Method Get))
$usersById = @{}
foreach ($user in $users) {
  $usersById[(Get-Text (Get-Property $user "user_id"))] = $user
}

$memberRows = [System.Collections.Generic.List[object]]::new()
$matchedPaymentOwners = @{}
$assignedOwnerIds = @{}
foreach ($roster in $rosters) {
  $ownerId = Get-Text (Get-Property $roster "owner_id")
  if (-not $ownerId) { continue }
  $assignedOwnerIds[$ownerId] = $true
  $user = $usersById[$ownerId]
  $displayName = Get-Text (Get-Property $user "display_name")
  $teamName = Get-Text (Get-Property (Get-Property $user "metadata") "team_name")
  $person = if ($peopleBySleeperId.ContainsKey((Get-Key $ownerId))) { $peopleBySleeperId[(Get-Key $ownerId)] } else { $null }
  $personId = if ($person) { Get-Text (Get-Property $person "personId") } else { "" }
  $payment = if ($personId -and $paymentsByPersonId.ContainsKey($personId)) { $paymentsByPersonId[$personId] } else { $null }
  $match = if ($payment) { "Identity ledger" } else { "" }

  if (-not $payment) {
    $keys = @((Get-Key $displayName), (Get-Key $teamName)) | Where-Object { $_ }
    foreach ($candidate in $matchablePayments) {
      if ($matchedPaymentOwners.ContainsKey((Get-Key $candidate.Owner))) { continue }
      if ($keys -contains (Get-Key $candidate.Owner)) {
        $payment = $candidate
        $match = "Exact name"
        break
      }
    }
  }
  if (-not $payment) {
    $candidateKeys = @((Get-Key $displayName), (Get-Key $teamName)) | Where-Object { $_.Length -ge 5 }
    foreach ($candidate in $matchablePayments) {
      if ($matchedPaymentOwners.ContainsKey((Get-Key $candidate.Owner))) { continue }
      $payerKey = Get-Key $candidate.Owner
      foreach ($candidateKey in $candidateKeys) {
        if ($payerKey.Length -ge 5 -and ($payerKey.Contains($candidateKey) -or $candidateKey.Contains($payerKey))) {
          $payment = $candidate
          $match = "Name-fragment candidate - verify"
          break
        }
      }
      if ($payment) { break }
    }
  }

  if ($payment) {
    $matchedPaymentOwners[(Get-Key $payment.Owner)] = $true
  }
  $paid = if ($payment) { Convert-ToDecimal $payment.Paid } else { [decimal]0 }
  $owes = if ($payment) { Convert-ToDecimal $payment.Owes } else { [decimal]0 }
  $manualStatus = if ($payment) { Get-Text $payment.ManualStatus } else { "" }
  $manualNote = if ($payment) { Get-Text $payment.ManualNote } else { "" }
  $status = if (-not $payment) { "Needs payment match" }
    elseif ($manualStatus) { $manualStatus }
    elseif ($match -match "verify") { "Review candidate match" }
    elseif ($owes -gt 0) { "Matched - owes payment" }
    elseif ($paid -gt 0) { "Matched - paid" }
    else { "Matched - review payment" }
  $memberRows.Add([pscustomobject]@{
    leagueId = $leagueId
    leagueName = Get-Text $league.name
    rosterId = Get-Text (Get-Property $roster "roster_id")
    sleeperName = $displayName
    sleeperTeamName = $teamName
    sleeperUserId = $ownerId
    leagueSafeOwner = if ($payment) { Get-Text $payment.Owner } else { "" }
    leagueSafeEmail = if ($payment) { Get-Text $payment.OwnerEmail } else { "" }
    paid = if ($payment) { $paid } else { "" }
    owes = if ($payment) { $owes } else { "" }
    paymentStatus = if ($payment) { Get-Text $payment.Status } else { "" }
    sourceExports = if ($payment) { Get-Text $payment.SourceExports } else { "" }
    reconciliationStatus = $status
    matchMethod = $match
    notes = $manualNote
  }) | Out-Null
}

foreach ($user in $users) {
  $userId = Get-Text (Get-Property $user "user_id")
  if ($assignedOwnerIds.ContainsKey($userId)) { continue }
  $memberRows.Add([pscustomobject]@{
    leagueId = $leagueId
    leagueName = Get-Text $league.name
    rosterId = ""
    sleeperName = Get-Text (Get-Property $user "display_name")
    sleeperTeamName = Get-Text (Get-Property (Get-Property $user "metadata") "team_name")
    sleeperUserId = $userId
    leagueSafeOwner = ""
    leagueSafeEmail = ""
    paid = ""
    owes = ""
    paymentStatus = ""
    sourceExports = ""
    reconciliationStatus = "Member - no roster assignment"
    matchMethod = ""
    notes = ""
  }) | Out-Null
}

$unmatchedPayments = @($rawPayments | Where-Object { -not $matchedPaymentOwners.ContainsKey((Get-Key $_.Owner)) } | ForEach-Object {
  [pscustomobject]@{
    leagueSafeOwner = Get-Text $_.Owner
    leagueSafeEmail = Get-Text $_.OwnerEmail
    paid = Convert-ToDecimal $_.Paid
    owes = Convert-ToDecimal $_.Owes
    paymentStatus = Get-Text $_.Status
    sourceExports = Get-Text $_.SourceExports
    status = if (Get-Text $_.ManualStatus) { Get-Text $_.ManualStatus } else { "No Sleeper match confirmed" }
    notes = Get-Text $_.ManualNote
  }
})

$outputDirectory = Join-Path $OutputRoot $leagueId
if (-not (Test-Path -LiteralPath $outputDirectory)) {
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$trackerPath = Join-Path $outputDirectory "tracker.csv"
$unmatchedPath = Join-Path $outputDirectory "unmatched-leaguesafe-rows.csv"
$summaryPath = Join-Path $outputDirectory "summary.md"
$memberRows | Sort-Object @{Expression={if ($_.rosterId) {[int]$_.rosterId} else {999}}} | Export-Csv -LiteralPath $trackerPath -NoTypeInformation -Encoding UTF8
$unmatchedPayments | Export-Csv -LiteralPath $unmatchedPath -NoTypeInformation -Encoding UTF8

$paidMatches = @($memberRows | Where-Object { $_.reconciliationStatus -eq "Matched - paid" }).Count
$reviewMatches = @($memberRows | Where-Object { $_.reconciliationStatus -eq "Review candidate match" }).Count
$needsMatches = @($memberRows | Where-Object { $_.reconciliationStatus -eq "Needs payment match" }).Count
$manualFollowUps = @($unmatchedPayments | Where-Object { (Get-Text $_.notes) }).Count
$summaryLines = @(
  "# $leagueId Payment Reconciliation",
  "",
  "- League: $(Get-Text $league.name)",
  "- LeagueSafe exports included: $($ExportPaths.Count)",
  "- Sleeper assigned rosters: $(@($memberRows | Where-Object { $_.rosterId }).Count)",
  "- Confirmed paid matches: $paidMatches",
  "- Candidate matches needing verification: $reviewMatches",
  "- Assigned rosters needing payment match: $needsMatches",
  "- LeagueSafe rows not matched to a Sleeper roster: $($unmatchedPayments.Count)",
  "- Manual payment follow-ups: $manualFollowUps",
  "",
  "Use ``tracker.csv`` to review the roster-by-roster payment cross-reference and ``unmatched-leaguesafe-rows.csv`` to resolve remaining payer aliases."
)
Set-Content -LiteralPath $summaryPath -Value $summaryLines -Encoding UTF8

$result = [pscustomobject]@{
  leagueRecordId = $leagueId
  exportCount = $ExportPaths.Count
  outputDirectory = $outputDirectory
  trackerPath = $trackerPath
  unmatchedPath = $unmatchedPath
  assignedRosters = @($memberRows | Where-Object { $_.rosterId }).Count
  confirmedPaidMatches = $paidMatches
  reviewMatches = $reviewMatches
  needsPaymentMatch = $needsMatches
  unmatchedLeagueSafeRows = $unmatchedPayments.Count
  manualPaymentFollowUps = $manualFollowUps
}

if ($PassThru) {
  $result
} else {
  Write-Host "Payment reconciliation written to $outputDirectory"
  Write-Host "Confirmed paid matches: $paidMatches"
  Write-Host "Candidate matches needing verification: $reviewMatches"
  Write-Host "Assigned rosters needing payment match: $needsMatches"
  Write-Host "Unmatched LeagueSafe rows: $($unmatchedPayments.Count)"
  Write-Host "Manual payment follow-ups: $manualFollowUps"
}
