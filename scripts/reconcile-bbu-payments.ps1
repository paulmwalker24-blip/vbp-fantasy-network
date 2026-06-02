param(
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$IdentityPath = "data/private/manager-identities.json",
  [string]$PaymentsCsvPath = "data/private/leaguesafe-payments.csv",
  [string]$OutputPath = "reports/private/bbu-payment-reconciliation/bbu-master-readable.txt",
  [string]$CsvOutputDirectory = "reports/private/bbu-payment-reconciliation",
  [string[]]$LeagueRecordIds,
  [switch]$AllowPartialSleeperData,
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

if ($fetchErrors.Count -gt 0 -and -not $AllowPartialSleeperData) {
  $failedLeagues = (@($fetchErrors | ForEach-Object { $_.leagueId }) -join ", ")
  throw "Sleeper refresh failed for $failedLeagues. Existing BBU reconciliation outputs were left unchanged. Rerun when Sleeper is reachable, or explicitly use -AllowPartialSleeperData for a partial report."
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

if (-not (Test-Path -LiteralPath $CsvOutputDirectory)) {
  New-Item -ItemType Directory -Path $CsvOutputDirectory | Out-Null
}

function Get-MatchKey {
  param(
    [AllowNull()]
    [object]$Value
  )

  return ((Get-StringValue $Value).ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Format-TableLine {
  param([object[]]$Values, [int[]]$Widths)
  $parts = @()
  for ($i = 0; $i -lt $Widths.Count; $i++) {
    $value = Get-StringValue $Values[$i]
    if ($value.Length -gt $Widths[$i]) {
      $value = $value.Substring(0, [Math]::Max(0, $Widths[$i] - 1)) + "."
    }
    $parts += $value.PadRight($Widths[$i])
  }
  return ($parts -join "  ").TrimEnd()
}

$paymentCandidates = @($paymentRows | ForEach-Object {
  [pscustomobject]@{
    row = $_
    matchKey = Get-MatchKey $_.payerName
  }
})

function Get-BbuPaymentCandidate {
  param($Entry)
  $keys = @(
    Get-MatchKey $Entry.teamName
    Get-MatchKey $Entry.displayName
    Get-MatchKey $Entry.username
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  if (-not [string]::IsNullOrWhiteSpace($Entry.personId)) {
    foreach ($paymentCandidate in $paymentCandidates) {
      if ((Get-StringValue $paymentCandidate.row.personId) -eq (Get-StringValue $Entry.personId)) {
        return [pscustomobject]@{ row = $paymentCandidate.row; confidence = "Identity" }
      }
    }
  }

  foreach ($paymentCandidate in $paymentCandidates) {
    if ($keys -contains $paymentCandidate.matchKey) {
      return [pscustomobject]@{ row = $paymentCandidate.row; confidence = "Exact" }
    }
  }

  foreach ($paymentCandidate in $paymentCandidates) {
    foreach ($key in $keys) {
      if ($key.Length -ge 5 -and $paymentCandidate.matchKey.Length -ge 5 -and ($paymentCandidate.matchKey.Contains($key) -or $key.Contains($paymentCandidate.matchKey))) {
        return [pscustomobject]@{ row = $paymentCandidate.row; confidence = "Possible" }
      }
    }
  }

  return $null
}

$trackerRows = @($sleeperEntries | Sort-Object leagueId, assignmentStatus, teamName | ForEach-Object {
  $entry = $_
  $match = Get-BbuPaymentCandidate -Entry $entry
  $candidate = if ($match) { $match.row } else { $null }
  $confidence = if ($match) { $match.confidence } else { "" }

  $paidAmount = if ($candidate) { $candidate.amount } else { [decimal]0 }
  $isIdentityMatch = $confidence -eq "Identity"
  $isFullyCoveredIdentity = $false
  $identityShortfall = [decimal]0
  if ($isIdentityMatch -and $entriesByPerson.ContainsKey($entry.personId) -and $paidByPerson.ContainsKey($entry.personId)) {
    $personDue = [decimal](@($entriesByPerson[$entry.personId]).Count * $entry.buyIn)
    $isFullyCoveredIdentity = [decimal]$paidByPerson[$entry.personId] -ge $personDue
    if (-not $isFullyCoveredIdentity) {
      $identityShortfall = $personDue - [decimal]$paidByPerson[$entry.personId]
    }
  }
  $status = if ($entry.assignmentStatus -eq "Waiting assignment" -and $candidate -and $paidAmount -gt 0) {
    "Paid / waiting assignment"
  } elseif ($entry.assignmentStatus -eq "Waiting assignment") {
    "Waiting / unpaid"
  } elseif ($isFullyCoveredIdentity) {
    "Paid"
  } elseif ($isIdentityMatch -and $paidAmount -gt 0) {
    "Shortfall review"
  } elseif ($candidate -and $paidAmount -ge $entry.buyIn) {
    "Paid candidate"
  } elseif ($candidate -and $paidAmount -gt 0) {
    "Payment review"
  } else {
    "Needs match"
  }

  [pscustomobject]@{
    BBU = $entry.leagueId
    leagueName = $entry.leagueName
    sleeperName = if ([string]::IsNullOrWhiteSpace($entry.teamName)) { if ([string]::IsNullOrWhiteSpace($entry.displayName)) { $entry.username } else { $entry.displayName } } else { $entry.teamName }
    sleeperUserId = $entry.sleeperUserId
    assignment = if ($entry.assignmentStatus -eq "Assigned team") { "Assigned" } else { "Waiting" }
    rosterSlot = $entry.rosterId
    leagueSafeName = if ($candidate) { $candidate.payerName } else { "" }
    paymentId = if ($candidate) { $candidate.paymentId } else { "" }
    paid = if ($isFullyCoveredIdentity) { $entry.buyIn } elseif ($isIdentityMatch) { "" } elseif ($candidate) { $candidate.amount } else { "" }
    status = $status
    match = $confidence
    person = $entry.personName
    notes = if ($isIdentityMatch -and -not $isFullyCoveredIdentity) { "Known person owes $('${0:N2}' -f $identityShortfall) across all BBU entries." } else { "" }
  }
})

$candidatePaymentIds = @{}
foreach ($row in @($trackerRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.paymentId) })) {
  $candidatePaymentIds[(Get-StringValue $row.paymentId)] = $true
}

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

$paidNotAssignedRows = @($paymentRows | Where-Object {
  $paymentKey = Get-MatchKey $_.payerName
  $paymentId = Get-StringValue $_.paymentId
  $hasAssignedPerson = -not [string]::IsNullOrWhiteSpace($_.personId) -and $assignedPersonIds.ContainsKey((Get-StringValue $_.personId))
  $hasAssignedName = -not [string]::IsNullOrWhiteSpace($paymentKey) -and $assignedSleeperKeys.ContainsKey($paymentKey)
  $isCandidateForSleeper = -not [string]::IsNullOrWhiteSpace($paymentId) -and $candidatePaymentIds.ContainsKey($paymentId)
  -not $hasAssignedPerson -and -not $hasAssignedName -and -not $isCandidateForSleeper
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
})

$needsAttentionRows = @($trackerRows | Where-Object { $_.status -notin @("Paid", "Waiting / unpaid") })
$shortfallRows = @($matchedPeople | Where-Object { $_.balance -gt 0 } | Sort-Object personName)
$attentionOutputPath = Join-Path $CsvOutputDirectory "bbu-needs-attention-readable.txt"

$masterLines = [System.Collections.Generic.List[string]]::new()
$masterLines.Add("BBU PAYMENT MASTER") | Out-Null
$masterLines.Add(("Generated: {0}" -f (Get-Date).ToString("M/d/yyyy h:mm tt"))) | Out-Null
$masterLines.Add("") | Out-Null
$masterLines.Add(("Sleeper entries: {0}" -f $totalSleeperEntries)) | Out-Null
$masterLines.Add(("Matched people: {0}" -f $matchedPeople.Count)) | Out-Null
$masterLines.Add(("Known-person amount due: {0}" -f (Format-Money $totalDueKnownPeople))) | Out-Null
$masterLines.Add(("Matched LeagueSafe money: {0}" -f (Format-Money $totalPaidMatched))) | Out-Null
$masterLines.Add(("Unmatched LeagueSafe money: {0}" -f (Format-Money $totalPaidUnmatched))) | Out-Null
$masterLines.Add(("Rows needing attention: {0}" -f $needsAttentionRows.Count)) | Out-Null
$masterLines.Add("") | Out-Null

if ($fetchErrors.Count -gt 0) {
  $masterLines.Add("SLEEPER FETCH WARNINGS") | Out-Null
  foreach ($errorRow in @($fetchErrors)) {
    $masterLines.Add(("- {0} {1}: {2}" -f $errorRow.leagueId, $errorRow.name, $errorRow.error)) | Out-Null
  }
  $masterLines.Add("") | Out-Null
}

foreach ($leagueGroup in @($trackerRows | Sort-Object @{ Expression = { [int](($_.BBU -replace '\D', '')) } }, assignment, sleeperName | Group-Object BBU)) {
  $rows = @($leagueGroup.Group)
  $first = $rows[0]
  $masterLines.Add(("{0} - {1}" -f $first.BBU, $first.leagueName).ToUpperInvariant()) | Out-Null
  $masterLines.Add(("Paid: {0} | Paid candidate: {1} | Needs match: {2} | Waiting unpaid: {3}" -f
      @($rows | Where-Object { $_.status -eq "Paid" }).Count,
      @($rows | Where-Object { $_.status -eq "Paid candidate" }).Count,
      @($rows | Where-Object { $_.status -eq "Needs match" }).Count,
      @($rows | Where-Object { $_.status -eq "Waiting / unpaid" }).Count)) | Out-Null
  $masterLines.Add((Format-TableLine -Values @("Sleeper", "Assign", "Slot", "Paid", "LeagueSafe", "Status") -Widths @(24, 9, 4, 8, 22, 22))) | Out-Null
  $masterLines.Add((Format-TableLine -Values @("-------", "------", "----", "----", "----------", "------") -Widths @(24, 9, 4, 8, 22, 22))) | Out-Null
  foreach ($row in $rows) {
    $paid = if ([string]::IsNullOrWhiteSpace((Get-StringValue $row.paid))) { "" } else { "$" + ("{0:N0}" -f (Convert-ToDecimal $row.paid)) }
    $masterLines.Add((Format-TableLine -Values @($row.sleeperName, $row.assignment, $row.rosterSlot, $paid, $row.leagueSafeName, $row.status) -Widths @(24, 9, 4, 8, 22, 22))) | Out-Null
  }
  $masterLines.Add("") | Out-Null
}

$attentionLines = [System.Collections.Generic.List[string]]::new()
$attentionLines.Add("BBU PAYMENT ITEMS NEEDING ATTENTION") | Out-Null
$attentionLines.Add(("Generated: {0}" -f (Get-Date).ToString("M/d/yyyy h:mm tt"))) | Out-Null
$attentionLines.Add("") | Out-Null

if ($needsAttentionRows.Count -eq 0 -and $shortfallRows.Count -eq 0 -and $paidNotAssignedRows.Count -eq 0) {
  $attentionLines.Add("No BBU payment items currently need attention.") | Out-Null
} else {
  if ($needsAttentionRows.Count -gt 0) {
    $attentionLines.Add("SLEEPER ROWS TO REVIEW") | Out-Null
    $attentionLines.Add((Format-TableLine -Values @("BBU", "Sleeper", "Paid", "LeagueSafe", "Status", "Match") -Widths @(6, 24, 8, 22, 22, 10))) | Out-Null
    $attentionLines.Add((Format-TableLine -Values @("---", "-------", "----", "----------", "------", "-----") -Widths @(6, 24, 8, 22, 22, 10))) | Out-Null
    foreach ($row in $needsAttentionRows) {
      $paid = if ([string]::IsNullOrWhiteSpace((Get-StringValue $row.paid))) { "" } else { "$" + ("{0:N0}" -f (Convert-ToDecimal $row.paid)) }
      $attentionLines.Add((Format-TableLine -Values @($row.BBU, $row.sleeperName, $paid, $row.leagueSafeName, $row.status, $row.match) -Widths @(6, 24, 8, 22, 22, 10))) | Out-Null
    }
    $attentionLines.Add("") | Out-Null
  }

  if ($shortfallRows.Count -gt 0) {
    $attentionLines.Add("KNOWN PEOPLE WITH BALANCE DUE") | Out-Null
    foreach ($personSummary in $shortfallRows) {
      $leagueList = (@($personSummary.entries) | ForEach-Object { $_.leagueId }) -join ", "
      $attentionLines.Add(("- {0}: {1}; due {2}, paid {3}, owes {4}" -f $personSummary.personName, $leagueList, (Format-Money $personSummary.due), (Format-Money $personSummary.paid), (Format-Money $personSummary.balance))) | Out-Null
    }
    $attentionLines.Add("") | Out-Null
  }

  if ($paidNotAssignedRows.Count -gt 0) {
    $attentionLines.Add("PAID LEAGUESAFE ROWS NOT TIED TO AN ASSIGNED ROSTER") | Out-Null
    $attentionLines.Add((Format-TableLine -Values @("LeagueSafe", "Paid", "Possible Sleeper", "Possible BBU", "Status") -Widths @(26, 8, 24, 12, 32))) | Out-Null
    $attentionLines.Add((Format-TableLine -Values @("----------", "----", "----------------", "------------", "------") -Widths @(26, 8, 24, 12, 32))) | Out-Null
    foreach ($payment in $paidNotAssignedRows) {
      $paid = "$" + ("{0:N0}" -f (Convert-ToDecimal $payment.Paid))
      $attentionLines.Add((Format-TableLine -Values @($payment."LeagueSafe Name", $paid, $payment."Possible Sleeper", $payment."Possible BBU", $payment.Status) -Widths @(26, 8, 24, 12, 32))) | Out-Null
    }
  }
}

$legacyFiles = @(
  "bbu-action-tracker.csv",
  "commissioner-tracker.csv",
  "leaguesafe-export.csv",
  "paid-not-assigned.csv",
  "person-summary.csv",
  "sleeper-entries.csv",
  "unmatched-payments.csv",
  "bbu-payment-reconciliation.md"
)
foreach ($legacyFile in $legacyFiles) {
  $legacyPath = if ($legacyFile -eq "bbu-payment-reconciliation.md") { Join-Path (Split-Path -Parent $CsvOutputDirectory) $legacyFile } else { Join-Path $CsvOutputDirectory $legacyFile }
  if (Test-Path -LiteralPath $legacyPath) {
    Remove-Item -LiteralPath $legacyPath -Force
  }
}

Get-ChildItem -LiteralPath $CsvOutputDirectory -Filter "*.xlsx" -ErrorAction SilentlyContinue | Remove-Item -Force
$masterLines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$attentionLines | Set-Content -LiteralPath $attentionOutputPath -Encoding UTF8

$result = [pscustomobject]@{
  masterReadablePath = $OutputPath
  needsAttentionReadablePath = $attentionOutputPath
  reportDirectory = $CsvOutputDirectory
  bbuLeagues = @($bbuLeagues | ForEach-Object { Get-StringValue $_.id })
  sleeperEntries = $totalSleeperEntries
  matchedPeople = $matchedPeople.Count
  unmatchedSleeperEntries = $unmatchedSleeperEntries.Count
  matchedPaymentTotal = $totalPaidMatched
  unmatchedPaymentTotal = $totalPaidUnmatched
  needsAttentionRows = $needsAttentionRows.Count
  fetchErrors = @($fetchErrors)
}

if ($PassThru) {
  $result
} else {
  Write-Host "BBU readable payment master written to $OutputPath"
  Write-Host "BBU needs-attention report written to $attentionOutputPath"
  Write-Host "Sleeper entries: $($result.sleeperEntries)"
  Write-Host "Matched people: $($result.matchedPeople)"
  Write-Host "Unmatched Sleeper entries: $($result.unmatchedSleeperEntries)"
  Write-Host "Unmatched LeagueSafe money: $(Format-Money $result.unmatchedPaymentTotal)"
}
