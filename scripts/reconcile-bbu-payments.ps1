param(
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$IdentityPath = "data/private/manager-identities.json",
  [string]$PaymentsCsvPath = "data/private/leaguesafe-payments.csv",
  [string]$OutputPath = "reports/private/bbu-payment-reconciliation.md",
  [string]$CsvOutputDirectory = "reports/private/bbu-payment-reconciliation",
  [string[]]$LeagueRecordIds,
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

function Normalize-Key {
  param(
    [AllowNull()]
    [object]$Value
  )

  return (Get-StringValue $Value).ToLowerInvariant()
}

function Format-Money {
  param(
    [decimal]$Amount
  )

  return ('$' + ("{0:N2}" -f $Amount))
}

function Convert-ToDecimal {
  param(
    [AllowNull()]
    [object]$Value
  )

  $raw = (Get-StringValue $Value) -replace '[$,]', ''
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [decimal]0
  }

  $parsed = [decimal]0
  if ([decimal]::TryParse($raw, [ref]$parsed)) {
    return $parsed
  }

  return [decimal]0
}

function Measure-DecimalSum {
  param(
    [object[]]$Items,
    [string]$PropertyName
  )

  $total = [decimal]0
  foreach ($item in @($Items)) {
    $total += Convert-ToDecimal (Get-PropertyValue $item $PropertyName)
  }

  return $total
}

function Convert-ToObjectArray {
  param(
    [AllowNull()]
    [object]$Value
  )

  if ($null -eq $Value) {
    return @()
  }

  if ($Value -is [System.Array]) {
    return @($Value)
  }

  $wrappedValue = Get-PropertyValue $Value "value"
  if ($null -ne $wrappedValue) {
    return @(Convert-ToObjectArray -Value $wrappedValue)
  }

  return @($Value)
}

function Read-JsonFile {
  param(
    [string]$Path,
    [string]$DefaultJson
  )

  if (Test-Path -LiteralPath $Path) {
    $raw = Get-Content -LiteralPath $Path -Raw
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
      return $raw | ConvertFrom-Json
    }
  }

  return $DefaultJson | ConvertFrom-Json
}

function Get-SleeperLeagueSnapshot {
  param(
    [object]$League
  )

  $leagueId = Get-StringValue $League.sleeperLeagueId
  $users = @()
  $rosters = @()

  if ([string]::IsNullOrWhiteSpace($leagueId)) {
    return [pscustomobject]@{
      users = @()
      rosters = @()
      error = "Missing sleeperLeagueId"
    }
  }

  try {
    $users = @(Convert-ToObjectArray -Value (Invoke-RestMethod -Uri "https://api.sleeper.app/v1/league/$leagueId/users" -Method Get))
    $rosters = @(Convert-ToObjectArray -Value (Invoke-RestMethod -Uri "https://api.sleeper.app/v1/league/$leagueId/rosters" -Method Get))
    return [pscustomobject]@{
      users = $users
      rosters = $rosters
      error = ""
    }
  } catch {
    return [pscustomobject]@{
      users = @()
      rosters = @()
      error = $_.Exception.Message
    }
  }
}

function Get-TeamName {
  param(
    [AllowNull()]
    [object]$User
  )

  if ($null -eq $User) {
    return ""
  }

  $metadata = Get-PropertyValue $User "metadata"
  $teamName = Get-PropertyValue $metadata "team_name"
  if (-not [string]::IsNullOrWhiteSpace((Get-StringValue $teamName))) {
    return Get-StringValue $teamName
  }

  $displayName = Get-PropertyValue $User "display_name"
  if (-not [string]::IsNullOrWhiteSpace((Get-StringValue $displayName))) {
    return Get-StringValue $displayName
  }

  return Get-StringValue (Get-PropertyValue $User "username")
}

function Add-PersonIndex {
  param(
    [hashtable]$Index,
    [string]$Key,
    [object]$Person
  )

  $normalized = Normalize-Key $Key
  if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $Index.ContainsKey($normalized)) {
    $Index[$normalized] = $Person
  }
}

$leaguesDocument = Read-JsonFile -Path $LeaguesJsonPath -DefaultJson '{ "leagues": [] }'
$identityDocument = Read-JsonFile -Path $IdentityPath -DefaultJson '{ "people": [] }'

$allLeagues = @($leaguesDocument.leagues)
$bbuLeagues = @($allLeagues | Where-Object { (Get-StringValue $_.format) -eq "bestball" })
if ($LeagueRecordIds -and $LeagueRecordIds.Count -gt 0) {
  $selected = @{}
  foreach ($recordId in $LeagueRecordIds) {
    $selected[(Normalize-Key $recordId)] = $true
  }
  $bbuLeagues = @($bbuLeagues | Where-Object { $selected.ContainsKey((Normalize-Key $_.id)) })
}

if ($bbuLeagues.Count -eq 0) {
  throw "No Best Ball Union league records found to reconcile."
}

$people = @($identityDocument.people)
$peopleById = @{}
$peopleBySleeperUserId = @{}
$peopleBySleeperUsername = @{}
$peopleByLeagueSafeEmail = @{}
$peopleByLeagueSafeName = @{}
$peopleByName = @{}

foreach ($person in $people) {
  $personId = Get-StringValue (Get-PropertyValue $person "personId")
  if (-not [string]::IsNullOrWhiteSpace($personId)) {
    $peopleById[$personId] = $person
  }

  Add-PersonIndex -Index $peopleByName -Key (Get-PropertyValue $person "name") -Person $person

  foreach ($sleeperUser in @((Get-PropertyValue $person "sleeperUsers"))) {
    Add-PersonIndex -Index $peopleBySleeperUserId -Key (Get-PropertyValue $sleeperUser "userId") -Person $person
    Add-PersonIndex -Index $peopleBySleeperUsername -Key (Get-PropertyValue $sleeperUser "username") -Person $person
    Add-PersonIndex -Index $peopleBySleeperUsername -Key (Get-PropertyValue $sleeperUser "displayName") -Person $person
  }

  foreach ($leagueSafeIdentity in @((Get-PropertyValue $person "leagueSafeIdentities"))) {
    Add-PersonIndex -Index $peopleByLeagueSafeName -Key (Get-PropertyValue $leagueSafeIdentity "payerName") -Person $person
    Add-PersonIndex -Index $peopleByLeagueSafeEmail -Key (Get-PropertyValue $leagueSafeIdentity "payerEmail") -Person $person
  }
}

$payments = @()
if (Test-Path -LiteralPath $PaymentsCsvPath) {
  $payments = @(Import-Csv -LiteralPath $PaymentsCsvPath | Where-Object {
    $leagueGroup = Normalize-Key (Get-PropertyValue $_ "leagueGroup")
    $leagueRecordId = Normalize-Key (Get-PropertyValue $_ "leagueRecordId")
    $status = Normalize-Key (Get-PropertyValue $_ "status")
    $isBestBall = $leagueGroup -match "bbu|best ball|bestball" -or $leagueRecordId -match "^bbu[0-9]+$"
    $isActivePayment = $status -notmatch "refund|void|cancel"
    $isBestBall -and $isActivePayment
  })
}

$sleeperEntries = [System.Collections.Generic.List[object]]::new()
$fetchErrors = [System.Collections.Generic.List[object]]::new()

foreach ($league in $bbuLeagues) {
  $snapshot = Get-SleeperLeagueSnapshot -League $league
  if (-not [string]::IsNullOrWhiteSpace($snapshot.error)) {
    $fetchErrors.Add([pscustomobject]@{
      leagueId = Get-StringValue $league.id
      name = Get-StringValue $league.name
      error = $snapshot.error
    }) | Out-Null
    continue
  }

  $usersById = @{}
  foreach ($user in @($snapshot.users)) {
    $userId = Get-StringValue (Get-PropertyValue $user "user_id")
    if (-not [string]::IsNullOrWhiteSpace($userId)) {
      $usersById[$userId] = $user
    }
  }

  foreach ($roster in @($snapshot.rosters)) {
    $ownerId = Get-StringValue (Get-PropertyValue $roster "owner_id")
    if ([string]::IsNullOrWhiteSpace($ownerId)) {
      continue
    }

    $user = $null
    if ($usersById.ContainsKey($ownerId)) {
      $user = $usersById[$ownerId]
    }

    $username = Get-StringValue (Get-PropertyValue $user "username")
    $displayName = Get-StringValue (Get-PropertyValue $user "display_name")
    $person = $null
    if ($peopleBySleeperUserId.ContainsKey((Normalize-Key $ownerId))) {
      $person = $peopleBySleeperUserId[(Normalize-Key $ownerId)]
    } elseif ($peopleBySleeperUsername.ContainsKey((Normalize-Key $username))) {
      $person = $peopleBySleeperUsername[(Normalize-Key $username)]
    } elseif ($peopleBySleeperUsername.ContainsKey((Normalize-Key $displayName))) {
      $person = $peopleBySleeperUsername[(Normalize-Key $displayName)]
    }

    $sleeperEntries.Add([pscustomobject]@{
      leagueId = Get-StringValue $league.id
      leagueName = Get-StringValue $league.name
      buyIn = Convert-ToDecimal $league.buyIn
      rosterId = Get-StringValue (Get-PropertyValue $roster "roster_id")
      assignmentStatus = "Assigned team"
      sleeperUserId = $ownerId
      username = $username
      displayName = $displayName
      teamName = Get-TeamName -User $user
      personId = if ($null -ne $person) { Get-StringValue (Get-PropertyValue $person "personId") } else { "" }
      personName = if ($null -ne $person) { Get-StringValue (Get-PropertyValue $person "name") } else { "" }
    }) | Out-Null
  }

  $entryOwnerIds = @{}
  foreach ($entry in @($sleeperEntries | Where-Object { $_.leagueId -eq (Get-StringValue $league.id) })) {
    $entryOwnerIds[(Normalize-Key $entry.sleeperUserId)] = $true
  }

  foreach ($user in @($snapshot.users)) {
    $userId = Get-StringValue (Get-PropertyValue $user "user_id")
    if ([string]::IsNullOrWhiteSpace($userId) -or $entryOwnerIds.ContainsKey((Normalize-Key $userId))) {
      continue
    }

    $username = Get-StringValue (Get-PropertyValue $user "username")
    $displayName = Get-StringValue (Get-PropertyValue $user "display_name")
    if ((Normalize-Key $displayName) -eq "vinsbropaul" -or (Normalize-Key $username) -eq "vinsbropaul") {
      continue
    }

    $person = $null
    if ($peopleBySleeperUserId.ContainsKey((Normalize-Key $userId))) {
      $person = $peopleBySleeperUserId[(Normalize-Key $userId)]
    } elseif ($peopleBySleeperUsername.ContainsKey((Normalize-Key $username))) {
      $person = $peopleBySleeperUsername[(Normalize-Key $username)]
    } elseif ($peopleBySleeperUsername.ContainsKey((Normalize-Key $displayName))) {
      $person = $peopleBySleeperUsername[(Normalize-Key $displayName)]
    }

    $sleeperEntries.Add([pscustomobject]@{
      leagueId = Get-StringValue $league.id
      leagueName = Get-StringValue $league.name
      buyIn = Convert-ToDecimal $league.buyIn
      rosterId = ""
      assignmentStatus = "Waiting assignment"
      sleeperUserId = $userId
      username = $username
      displayName = $displayName
      teamName = Get-TeamName -User $user
      personId = if ($null -ne $person) { Get-StringValue (Get-PropertyValue $person "personId") } else { "" }
      personName = if ($null -ne $person) { Get-StringValue (Get-PropertyValue $person "name") } else { "" }
    }) | Out-Null
  }
}

$paymentRows = [System.Collections.Generic.List[object]]::new()
foreach ($payment in $payments) {
  $person = $null
  $personId = Get-StringValue (Get-PropertyValue $payment "personId")
  $payerEmail = Get-StringValue (Get-PropertyValue $payment "payerEmail")
  $payerName = Get-StringValue (Get-PropertyValue $payment "payerName")

  if (-not [string]::IsNullOrWhiteSpace($personId) -and $peopleById.ContainsKey($personId)) {
    $person = $peopleById[$personId]
  } elseif ($peopleByLeagueSafeEmail.ContainsKey((Normalize-Key $payerEmail))) {
    $person = $peopleByLeagueSafeEmail[(Normalize-Key $payerEmail)]
  } elseif ($peopleByLeagueSafeName.ContainsKey((Normalize-Key $payerName))) {
    $person = $peopleByLeagueSafeName[(Normalize-Key $payerName)]
  } elseif ($peopleByName.ContainsKey((Normalize-Key $payerName))) {
    $person = $peopleByName[(Normalize-Key $payerName)]
  }

  $paymentRows.Add([pscustomobject]@{
    paymentId = Get-StringValue (Get-PropertyValue $payment "paymentId")
    leagueGroup = Get-StringValue (Get-PropertyValue $payment "leagueGroup")
    leagueRecordId = Get-StringValue (Get-PropertyValue $payment "leagueRecordId")
    payerName = $payerName
    payerEmail = $payerEmail
    amount = Convert-ToDecimal (Get-PropertyValue $payment "amount")
    date = Get-StringValue (Get-PropertyValue $payment "date")
    status = Get-StringValue (Get-PropertyValue $payment "status")
    notes = Get-StringValue (Get-PropertyValue $payment "notes")
    personId = if ($null -ne $person) { Get-StringValue (Get-PropertyValue $person "personId") } else { $personId }
    personName = if ($null -ne $person) { Get-StringValue (Get-PropertyValue $person "name") } else { "" }
    matched = $null -ne $person
  }) | Out-Null
}

$paidByPerson = @{}
$paidBySpecificLeague = @{}
foreach ($payment in @($paymentRows)) {
  if (-not [string]::IsNullOrWhiteSpace($payment.personId)) {
    if (-not $paidByPerson.ContainsKey($payment.personId)) {
      $paidByPerson[$payment.personId] = [decimal]0
    }
    $paidByPerson[$payment.personId] += $payment.amount
  }

  $leagueRecordId = Normalize-Key $payment.leagueRecordId
  if (-not [string]::IsNullOrWhiteSpace($leagueRecordId)) {
    if (-not $paidBySpecificLeague.ContainsKey($leagueRecordId)) {
      $paidBySpecificLeague[$leagueRecordId] = [decimal]0
    }
    $paidBySpecificLeague[$leagueRecordId] += $payment.amount
  }
}

$entriesByPerson = @{}
foreach ($entry in @($sleeperEntries)) {
  if (-not [string]::IsNullOrWhiteSpace($entry.personId)) {
    if (-not $entriesByPerson.ContainsKey($entry.personId)) {
      $entriesByPerson[$entry.personId] = [System.Collections.Generic.List[object]]::new()
    }
    $entriesByPerson[$entry.personId].Add($entry) | Out-Null
  }
}

$matchedPeople = [System.Collections.Generic.List[object]]::new()
foreach ($personId in @($entriesByPerson.Keys)) {
  $entries = @($entriesByPerson[$personId])
  $due = [decimal](@($entries | Measure-Object -Property buyIn -Sum).Sum)
  $paid = if ($paidByPerson.ContainsKey($personId)) { [decimal]$paidByPerson[$personId] } else { [decimal]0 }
  $matchedPeople.Add([pscustomobject]@{
    personId = $personId
    personName = $entries[0].personName
    entries = $entries
    due = $due
    paid = $paid
    balance = $due - $paid
  }) | Out-Null
}

$unmatchedSleeperEntries = @($sleeperEntries | Where-Object { [string]::IsNullOrWhiteSpace($_.personId) })
$unmatchedPayments = @($paymentRows | Where-Object { -not $_.matched })
$totalDueKnownPeople = Measure-DecimalSum -Items @($matchedPeople) -PropertyName "due"
$totalPaidMatched = Measure-DecimalSum -Items @($paymentRows | Where-Object { $_.matched }) -PropertyName "amount"
$totalPaidUnmatched = Measure-DecimalSum -Items @($unmatchedPayments) -PropertyName "amount"
$totalSleeperEntries = $sleeperEntries.Count

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# BBU Payment Reconciliation") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- BBU Sleeper entries found: $totalSleeperEntries") | Out-Null
$lines.Add("- Identity-matched people with BBU entries: $($matchedPeople.Count)") | Out-Null
$lines.Add("- Unmatched Sleeper entries: $($unmatchedSleeperEntries.Count)") | Out-Null
$lines.Add("- Matched LeagueSafe money: $(Format-Money $totalPaidMatched)") | Out-Null
$lines.Add("- Unmatched LeagueSafe money: $(Format-Money $totalPaidUnmatched)") | Out-Null
$lines.Add("- Known-person BBU amount due: $(Format-Money $totalDueKnownPeople)") | Out-Null
$lines.Add("") | Out-Null

if ($fetchErrors.Count -gt 0) {
  $lines.Add("## Sleeper Fetch Warnings") | Out-Null
  $lines.Add("") | Out-Null
  foreach ($errorRow in @($fetchErrors)) {
    $lines.Add("- $($errorRow.leagueId) $($errorRow.name): $($errorRow.error)") | Out-Null
  }
  $lines.Add("") | Out-Null
}

$lines.Add("## By BBU League") | Out-Null
$lines.Add("") | Out-Null
foreach ($league in $bbuLeagues) {
  $leagueEntries = @($sleeperEntries | Where-Object { $_.leagueId -eq (Get-StringValue $league.id) } | Sort-Object rosterId)
  $lines.Add("### $($league.id) - $($league.name)") | Out-Null
  $lines.Add("") | Out-Null
  if ($leagueEntries.Count -eq 0) {
    $lines.Add("- No Sleeper managers found yet.") | Out-Null
  } else {
    foreach ($entry in $leagueEntries) {
      $identity = if ([string]::IsNullOrWhiteSpace($entry.personName)) { "UNMATCHED" } else { "$($entry.personName) [$($entry.personId)]" }
      $lines.Add("- $($entry.teamName) / $($entry.username) / $($entry.displayName) / Sleeper $($entry.sleeperUserId) -> $identity") | Out-Null
    }
  }
  $lines.Add("") | Out-Null
}

$lines.Add("## Matched People") | Out-Null
$lines.Add("") | Out-Null
if ($matchedPeople.Count -eq 0) {
  $lines.Add("- No matched people yet. Add known identities to `$IdentityPath`.") | Out-Null
} else {
  foreach ($personSummary in @($matchedPeople | Sort-Object personName)) {
    $status = if ($personSummary.balance -gt 0) { "OWES $(Format-Money $personSummary.balance)" } elseif ($personSummary.balance -lt 0) { "EXTRA $(Format-Money ([Math]::Abs($personSummary.balance)))" } else { "PAID EVEN" }
    $leagueList = (@($personSummary.entries) | ForEach-Object { $_.leagueId }) -join ", "
    $lines.Add("- $($personSummary.personName) [$($personSummary.personId)] - $leagueList - due $(Format-Money $personSummary.due), matched paid $(Format-Money $personSummary.paid) - $status") | Out-Null
  }
}
$lines.Add("") | Out-Null

$lines.Add("## Unmatched Sleeper Entries") | Out-Null
$lines.Add("") | Out-Null
if ($unmatchedSleeperEntries.Count -eq 0) {
  $lines.Add("- None.") | Out-Null
} else {
  foreach ($entry in @($unmatchedSleeperEntries | Sort-Object leagueId, username)) {
    $lines.Add("- $($entry.leagueId): $($entry.teamName) / $($entry.username) / $($entry.displayName) / Sleeper $($entry.sleeperUserId)") | Out-Null
  }
}
$lines.Add("") | Out-Null

$lines.Add("## Unmatched LeagueSafe Payments") | Out-Null
$lines.Add("") | Out-Null
if ($unmatchedPayments.Count -eq 0) {
  $lines.Add("- None.") | Out-Null
} else {
  foreach ($payment in @($unmatchedPayments | Sort-Object date, payerName)) {
    $where = if ([string]::IsNullOrWhiteSpace($payment.leagueRecordId)) { $payment.leagueGroup } else { $payment.leagueRecordId }
    $lines.Add("- $($payment.date) - $($payment.payerName) <$($payment.payerEmail)> - $(Format-Money $payment.amount) - $where - $($payment.notes)") | Out-Null
  }
}
$lines.Add("") | Out-Null

$lines.Add("## Next Matching Steps") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("1. For each unmatched Sleeper entry, ask for the LeagueSafe payer name/email.") | Out-Null
$lines.Add("2. Add one person record to `$IdentityPath` with that Sleeper user and LeagueSafe identity.") | Out-Null
$lines.Add("3. For each unmatched payment, add `personId` in `$PaymentsCsvPath` if the payer name/email is not enough to match automatically.") | Out-Null
$lines.Add("4. Re-run this script. People in multiple BBU rooms will roll up under one person total.") | Out-Null

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
  New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if (-not (Test-Path -LiteralPath $CsvOutputDirectory)) {
  New-Item -ItemType Directory -Path $CsvOutputDirectory | Out-Null
}

$sleeperEntriesCsvPath = Join-Path $CsvOutputDirectory "sleeper-entries.csv"
$personSummaryCsvPath = Join-Path $CsvOutputDirectory "person-summary.csv"
$unmatchedPaymentsCsvPath = Join-Path $CsvOutputDirectory "unmatched-payments.csv"
$leagueSafeExportCsvPath = Join-Path $CsvOutputDirectory "leaguesafe-export.csv"
$actionTrackerCsvPath = Join-Path $CsvOutputDirectory "bbu-action-tracker.csv"
$commissionerTrackerCsvPath = Join-Path $CsvOutputDirectory "commissioner-tracker.csv"
$paidUnassignedCsvPath = Join-Path $CsvOutputDirectory "paid-not-assigned.csv"

@($sleeperEntries | Sort-Object leagueId, teamName | ForEach-Object {
  [pscustomobject]@{
    leagueId = $_.leagueId
    leagueName = $_.leagueName
    buyIn = $_.buyIn
    rosterId = $_.rosterId
    assignmentStatus = $_.assignmentStatus
    teamName = $_.teamName
    sleeperDisplayName = $_.displayName
    sleeperUsername = $_.username
    sleeperUserId = $_.sleeperUserId
    personId = $_.personId
    personName = $_.personName
    matchStatus = if ([string]::IsNullOrWhiteSpace($_.personId)) { "Needs identity match" } else { "Matched" }
  }
}) | Export-Csv -LiteralPath $sleeperEntriesCsvPath -NoTypeInformation -Encoding UTF8

@($paymentRows | Sort-Object payerName | ForEach-Object {
  [pscustomobject]@{
    owner = $_.payerName
    ownerEmail = $_.payerEmail
    paid = $_.amount
    status = $_.status
    leagueGroup = $_.leagueGroup
    leagueRecordId = $_.leagueRecordId
    paymentId = $_.paymentId
    personId = $_.personId
    matched = $_.matched
    notes = $_.notes
  }
}) | Export-Csv -LiteralPath $leagueSafeExportCsvPath -NoTypeInformation -Encoding UTF8

function Get-MatchKey {
  param(
    [AllowNull()]
    [object]$Value
  )

  return ((Get-StringValue $Value).ToLowerInvariant() -replace '[^a-z0-9]', '')
}

$paymentCandidates = @($paymentRows | ForEach-Object {
  [pscustomobject]@{
    row = $_
    matchKey = Get-MatchKey $_.payerName
  }
})

@($sleeperEntries | Sort-Object leagueId, assignmentStatus, teamName | ForEach-Object {
  $entry = $_
  $keys = @(
    Get-MatchKey $entry.teamName
    Get-MatchKey $entry.displayName
    Get-MatchKey $entry.username
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  $candidate = $null
  $confidence = ""
  if (-not [string]::IsNullOrWhiteSpace($entry.personId)) {
    foreach ($paymentCandidate in $paymentCandidates) {
      if ((Get-StringValue $paymentCandidate.row.personId) -eq (Get-StringValue $entry.personId)) {
        $candidate = $paymentCandidate.row
        $confidence = "Identity ledger match"
        break
      }
    }
  }

  if ($null -eq $candidate) {
    foreach ($paymentCandidate in $paymentCandidates) {
      if ($keys -contains $paymentCandidate.matchKey) {
        $candidate = $paymentCandidate.row
        $confidence = "Exact name/username match"
        break
      }
    }
  }

  if ($null -eq $candidate) {
    foreach ($paymentCandidate in $paymentCandidates) {
      foreach ($key in $keys) {
        if ($key.Length -ge 5 -and $paymentCandidate.matchKey.Length -ge 5 -and ($paymentCandidate.matchKey.Contains($key) -or $key.Contains($paymentCandidate.matchKey))) {
          $candidate = $paymentCandidate.row
          $confidence = "Possible partial match"
          break
        }
      }
      if ($null -ne $candidate) {
        break
      }
    }
  }

  $actionStatus = if ($entry.assignmentStatus -eq "Waiting assignment") {
    "Waiting assignment - unpaid"
  } elseif ($null -eq $candidate) {
    "Assigned - needs LeagueSafe match"
  } elseif ($candidate.amount -ge $entry.buyIn) {
    "Assigned - possible paid match"
  } elseif ($candidate.amount -gt 0) {
    "Assigned - partial/extra review"
  } else {
    "Assigned - matched name but not paid"
  }

  [pscustomobject]@{
    leagueId = $entry.leagueId
    leagueName = $entry.leagueName
    buyIn = $entry.buyIn
    assignmentStatus = $entry.assignmentStatus
    rosterId = $entry.rosterId
    sleeperTeamName = $entry.teamName
    sleeperDisplayName = $entry.displayName
    sleeperUsername = $entry.username
    sleeperUserId = $entry.sleeperUserId
    leagueSafeOwnerCandidate = if ($candidate) { $candidate.payerName } else { "" }
    leagueSafeEmailCandidate = if ($candidate) { $candidate.payerEmail } else { "" }
    leagueSafePaid = if ($candidate) { $candidate.amount } else { "" }
    leagueSafeStatus = if ($candidate) { $candidate.status } else { "" }
    leagueSafePaymentId = if ($candidate) { $candidate.paymentId } else { "" }
    matchConfidence = $confidence
    actionStatus = $actionStatus
    confirmedPersonId = $entry.personId
    commissionerNotes = ""
  }
}) | Export-Csv -LiteralPath $actionTrackerCsvPath -NoTypeInformation -Encoding UTF8

@($sleeperEntries | Sort-Object leagueId, assignmentStatus, teamName | ForEach-Object {
  $entry = $_
  $keys = @(
    Get-MatchKey $entry.teamName
    Get-MatchKey $entry.displayName
    Get-MatchKey $entry.username
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  $candidate = $null
  $confidence = ""
  if (-not [string]::IsNullOrWhiteSpace($entry.personId)) {
    foreach ($paymentCandidate in $paymentCandidates) {
      if ((Get-StringValue $paymentCandidate.row.personId) -eq (Get-StringValue $entry.personId)) {
        $candidate = $paymentCandidate.row
        $confidence = "Identity ledger"
        break
      }
    }
  }

  if ($null -eq $candidate) {
    foreach ($paymentCandidate in $paymentCandidates) {
      if ($keys -contains $paymentCandidate.matchKey) {
        $candidate = $paymentCandidate.row
        $confidence = "Exact"
        break
      }
    }
  }

  if ($null -eq $candidate) {
    foreach ($paymentCandidate in $paymentCandidates) {
      foreach ($key in $keys) {
        if ($key.Length -ge 5 -and $paymentCandidate.matchKey.Length -ge 5 -and ($paymentCandidate.matchKey.Contains($key) -or $key.Contains($paymentCandidate.matchKey))) {
          $candidate = $paymentCandidate.row
          $confidence = "Possible"
          break
        }
      }
      if ($null -ne $candidate) {
        break
      }
    }
  }

  $paidAmount = if ($candidate) { $candidate.amount } else { [decimal]0 }
  $status = if ($entry.assignmentStatus -eq "Waiting assignment") {
    "Waiting - not assigned/unpaid"
  } elseif ($candidate -and $paidAmount -ge $entry.buyIn) {
    "Assigned + paid candidate"
  } elseif ($candidate -and $paidAmount -gt 0) {
    "Assigned + payment review"
  } else {
    "Assigned - needs payment match"
  }

  [pscustomobject]@{
    BBU = $entry.leagueId
    "Sleeper Name" = if ([string]::IsNullOrWhiteSpace($entry.teamName)) { $entry.displayName } else { $entry.teamName }
    "Sleeper User ID" = $entry.sleeperUserId
    "Assignment" = $entry.assignmentStatus
    "Roster Slot" = $entry.rosterId
    "LeagueSafe Name" = if ($candidate) { $candidate.payerName } else { "" }
    "LeagueSafe Email" = if ($candidate) { $candidate.payerEmail } else { "" }
    "Paid" = if ($candidate) { $candidate.amount } else { "" }
    "Status" = $status
    "Match" = $confidence
    "Person" = $entry.personName
    "Person ID" = $entry.personId
    "Notes" = ""
  }
}) | Export-Csv -LiteralPath $commissionerTrackerCsvPath -NoTypeInformation -Encoding UTF8

$assignedPersonIds = @{}
$assignedSleeperKeys = @{}
foreach ($entry in @($sleeperEntries | Where-Object { $_.assignmentStatus -eq "Assigned team" })) {
  if (-not [string]::IsNullOrWhiteSpace($entry.personId)) {
    $assignedPersonIds[(Get-StringValue $entry.personId)] = $true
  }
  foreach ($key in @((Get-MatchKey $entry.teamName), (Get-MatchKey $entry.displayName), (Get-MatchKey $entry.username))) {
    if (-not [string]::IsNullOrWhiteSpace($key)) {
      $assignedSleeperKeys[$key] = $true
    }
  }
}

$waitingEntries = @($sleeperEntries | Where-Object { $_.assignmentStatus -eq "Waiting assignment" })

@($paymentRows | Where-Object {
  $paymentKey = Get-MatchKey $_.payerName
  $hasAssignedPerson = -not [string]::IsNullOrWhiteSpace($_.personId) -and $assignedPersonIds.ContainsKey((Get-StringValue $_.personId))
  $hasAssignedName = -not [string]::IsNullOrWhiteSpace($paymentKey) -and $assignedSleeperKeys.ContainsKey($paymentKey)
  -not $hasAssignedPerson -and -not $hasAssignedName
} | Sort-Object payerName | ForEach-Object {
  $payment = $_
  $paymentKey = Get-MatchKey $payment.payerName
  $candidate = $null
  $confidence = ""

  foreach ($waiting in $waitingEntries) {
    if (-not [string]::IsNullOrWhiteSpace($payment.personId) -and (Get-StringValue $payment.personId) -eq (Get-StringValue $waiting.personId)) {
      $candidate = $waiting
      $confidence = "Identity ledger waiting user"
      break
    }

    $waitingKeys = @((Get-MatchKey $waiting.teamName), (Get-MatchKey $waiting.displayName), (Get-MatchKey $waiting.username)) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($waitingKeys -contains $paymentKey) {
      $candidate = $waiting
      $confidence = "Exact waiting-user match"
      break
    }

    foreach ($waitingKey in $waitingKeys) {
      if ($waitingKey.Length -ge 5 -and $paymentKey.Length -ge 5 -and ($paymentKey.Contains($waitingKey) -or $waitingKey.Contains($paymentKey))) {
        $candidate = $waiting
        $confidence = "Possible waiting-user match"
        break
      }
    }

    if ($null -ne $candidate) {
      break
    }
  }

  [pscustomobject]@{
    "LeagueSafe Name" = $payment.payerName
    "LeagueSafe Email" = $payment.payerEmail
    "Paid" = $payment.amount
    "Payment ID" = $payment.paymentId
    "Matched Person" = $payment.personName
    "Possible Sleeper" = if ($candidate) { $candidate.teamName } else { "" }
    "Possible BBU" = if ($candidate) { $candidate.leagueId } else { "" }
    "Possible Assignment" = if ($candidate) { $candidate.assignmentStatus } else { "" }
    "Match" = $confidence
    "Status" = if ($candidate) { "Paid - possible waiting Sleeper" } else { "Paid - no assigned team found" }
    "Notes" = $payment.notes
  }
}) | Export-Csv -LiteralPath $paidUnassignedCsvPath -NoTypeInformation -Encoding UTF8

@($matchedPeople | Sort-Object personName | ForEach-Object {
  [pscustomobject]@{
    personId = $_.personId
    personName = $_.personName
    bbuEntries = (@($_.entries) | ForEach-Object { $_.leagueId }) -join "; "
    entryCount = @($_.entries).Count
    amountDue = $_.due
    matchedPaid = $_.paid
    balance = $_.balance
    paymentStatus = if ($_.balance -gt 0) { "Owes" } elseif ($_.balance -lt 0) { "Extra paid" } else { "Paid even" }
  }
}) | Export-Csv -LiteralPath $personSummaryCsvPath -NoTypeInformation -Encoding UTF8

@($unmatchedPayments | Sort-Object date, payerName | ForEach-Object {
  [pscustomobject]@{
    paymentId = $_.paymentId
    date = $_.date
    payerName = $_.payerName
    payerEmail = $_.payerEmail
    amount = $_.amount
    leagueGroup = $_.leagueGroup
    leagueRecordId = $_.leagueRecordId
    status = $_.status
    notes = $_.notes
    personId = $_.personId
    matchStatus = "Needs payment match"
  }
}) | Export-Csv -LiteralPath $unmatchedPaymentsCsvPath -NoTypeInformation -Encoding UTF8

$result = [pscustomobject]@{
  outputPath = $OutputPath
  csvOutputDirectory = $CsvOutputDirectory
  sleeperEntriesCsvPath = $sleeperEntriesCsvPath
  personSummaryCsvPath = $personSummaryCsvPath
  unmatchedPaymentsCsvPath = $unmatchedPaymentsCsvPath
  leagueSafeExportCsvPath = $leagueSafeExportCsvPath
  actionTrackerCsvPath = $actionTrackerCsvPath
  commissionerTrackerCsvPath = $commissionerTrackerCsvPath
  paidUnassignedCsvPath = $paidUnassignedCsvPath
  bbuLeagues = @($bbuLeagues | ForEach-Object { Get-StringValue $_.id })
  sleeperEntries = $totalSleeperEntries
  matchedPeople = $matchedPeople.Count
  unmatchedSleeperEntries = $unmatchedSleeperEntries.Count
  matchedPaymentTotal = $totalPaidMatched
  unmatchedPaymentTotal = $totalPaidUnmatched
  fetchErrors = @($fetchErrors)
}

if ($PassThru) {
  $result
} else {
  Write-Host "BBU payment reconciliation written to $OutputPath"
  Write-Host "Excel CSV exports written to $CsvOutputDirectory"
  Write-Host "Sleeper entries: $($result.sleeperEntries)"
  Write-Host "Matched people: $($result.matchedPeople)"
  Write-Host "Unmatched Sleeper entries: $($result.unmatchedSleeperEntries)"
  Write-Host "Unmatched LeagueSafe money: $(Format-Money $result.unmatchedPaymentTotal)"
}
