param(
  [string]$LeaguesJsonPath = "data/leagues.json",
  [string]$IdentityPath = "data/private/manager-identities.json",
  [string]$PaymentsCsvPath = "data/private/leaguesafe-bracket-payments.csv",
  [string]$CsvOutputDirectory = "reports/private/redraft-bracket-payment-reconciliation",
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-StringValue { param([AllowNull()][object]$Value) return ([string]$Value).Trim() }
function Get-PropertyValue {
  param([AllowNull()][object]$Object, [string]$PropertyName)
  if ($null -eq $Object) { return $null }
  if ($Object.PSObject.Properties.Match($PropertyName).Count -gt 0) { return $Object.PSObject.Properties[$PropertyName].Value }
  return $null
}
function Get-MatchKey { param([AllowNull()][object]$Value) return ((Get-StringValue $Value).ToLowerInvariant() -replace '[^a-z0-9]', '') }
function Convert-ToDecimal {
  param([AllowNull()][object]$Value)
  $raw = (Get-StringValue $Value) -replace '[$,]', ''
  if ([string]::IsNullOrWhiteSpace($raw)) { return [decimal]0 }
  $parsed = [decimal]0
  if ([decimal]::TryParse($raw, [ref]$parsed)) { return $parsed }
  return [decimal]0
}
function Convert-ToObjectArray {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return @($Value) }
  $wrapped = Get-PropertyValue $Value "value"
  if ($null -ne $wrapped) { return @(Convert-ToObjectArray -Value $wrapped) }
  return @($Value)
}
function Add-PersonIndex {
  param([hashtable]$Index, [string]$Key, [object]$Person)
  $normalized = Get-MatchKey $Key
  if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $Index.ContainsKey($normalized)) { $Index[$normalized] = $Person }
}

$leaguesDocument = Get-Content -LiteralPath $LeaguesJsonPath -Raw | ConvertFrom-Json
$identityDocument = if (Test-Path -LiteralPath $IdentityPath) { Get-Content -LiteralPath $IdentityPath -Raw | ConvertFrom-Json } else { '{ "people": [] }' | ConvertFrom-Json }
$leagues = @($leaguesDocument.leagues | Where-Object { (Get-StringValue $_.format) -eq "bracket" })
$people = @($identityDocument.people)

$peopleBySleeperUserId = @{}
$peopleBySleeperName = @{}
$peopleByLeagueSafeEmail = @{}
$peopleByLeagueSafeName = @{}
foreach ($person in $people) {
  foreach ($sleeperUser in @((Get-PropertyValue $person "sleeperUsers"))) {
    Add-PersonIndex -Index $peopleBySleeperUserId -Key (Get-PropertyValue $sleeperUser "userId") -Person $person
    Add-PersonIndex -Index $peopleBySleeperName -Key (Get-PropertyValue $sleeperUser "username") -Person $person
    Add-PersonIndex -Index $peopleBySleeperName -Key (Get-PropertyValue $sleeperUser "displayName") -Person $person
  }
  foreach ($leagueSafeIdentity in @((Get-PropertyValue $person "leagueSafeIdentities"))) {
    Add-PersonIndex -Index $peopleByLeagueSafeName -Key (Get-PropertyValue $leagueSafeIdentity "payerName") -Person $person
    Add-PersonIndex -Index $peopleByLeagueSafeEmail -Key (Get-PropertyValue $leagueSafeIdentity "payerEmail") -Person $person
  }
}

$payments = @()
if (Test-Path -LiteralPath $PaymentsCsvPath) {
  $payments = @(Import-Csv -LiteralPath $PaymentsCsvPath | Where-Object { (Get-StringValue $_.status) -notmatch "refund|void|cancel" })
}

$paymentRows = @($payments | ForEach-Object {
  $person = $null
  $emailKey = Get-MatchKey $_.payerEmail
  $nameKey = Get-MatchKey $_.payerName
  if ($peopleByLeagueSafeEmail.ContainsKey($emailKey)) { $person = $peopleByLeagueSafeEmail[$emailKey] }
  elseif ($peopleByLeagueSafeName.ContainsKey($nameKey)) { $person = $peopleByLeagueSafeName[$nameKey] }
  [pscustomobject]@{
    paymentId = Get-StringValue $_.paymentId
    payerName = Get-StringValue $_.payerName
    payerEmail = Get-StringValue $_.payerEmail
    amount = Convert-ToDecimal $_.amount
    status = Get-StringValue $_.status
    notes = Get-StringValue $_.notes
    personId = if ($person) { Get-StringValue (Get-PropertyValue $person "personId") } else { "" }
    personName = if ($person) { Get-StringValue (Get-PropertyValue $person "name") } else { "" }
    matchKey = $nameKey
  }
})

$entries = [System.Collections.Generic.List[object]]::new()
foreach ($league in $leagues) {
  $leagueId = Get-StringValue $league.sleeperLeagueId
  if ([string]::IsNullOrWhiteSpace($leagueId)) { continue }
  $users = @(Convert-ToObjectArray -Value (Invoke-RestMethod -Uri "https://api.sleeper.app/v1/league/$leagueId/users" -Method Get))
  $rosters = @(Convert-ToObjectArray -Value (Invoke-RestMethod -Uri "https://api.sleeper.app/v1/league/$leagueId/rosters" -Method Get))
  $usersById = @{}
  foreach ($user in $users) {
    $userId = Get-StringValue (Get-PropertyValue $user "user_id")
    if ($userId) { $usersById[$userId] = $user }
  }
  $assigned = @{}
  foreach ($roster in $rosters) {
    $ownerId = Get-StringValue (Get-PropertyValue $roster "owner_id")
    if (-not $ownerId) { continue }
    $assigned[$ownerId] = $true
    $user = if ($usersById.ContainsKey($ownerId)) { $usersById[$ownerId] } else { $null }
    $display = Get-StringValue (Get-PropertyValue $user "display_name")
    $username = Get-StringValue (Get-PropertyValue $user "username")
    $person = $null
    $ownerKey = Get-MatchKey $ownerId
    if ($peopleBySleeperUserId.ContainsKey($ownerKey)) { $person = $peopleBySleeperUserId[$ownerKey] }
    elseif ($peopleBySleeperName.ContainsKey((Get-MatchKey $display))) { $person = $peopleBySleeperName[(Get-MatchKey $display)] }
    elseif ($peopleBySleeperName.ContainsKey((Get-MatchKey $username))) { $person = $peopleBySleeperName[(Get-MatchKey $username)] }
    $entries.Add([pscustomobject]@{
      leagueId = Get-StringValue $league.id
      leagueName = Get-StringValue $league.name
      draftType = Get-StringValue $league.division
      buyIn = Convert-ToDecimal $league.buyIn
      assignmentStatus = "Assigned team"
      rosterId = Get-StringValue (Get-PropertyValue $roster "roster_id")
      sleeperName = if ($display) { $display } else { $username }
      sleeperUserId = $ownerId
      personId = if ($person) { Get-StringValue (Get-PropertyValue $person "personId") } else { "" }
      personName = if ($person) { Get-StringValue (Get-PropertyValue $person "name") } else { "" }
    }) | Out-Null
  }
  foreach ($user in $users) {
    $userId = Get-StringValue (Get-PropertyValue $user "user_id")
    if (-not $userId -or $assigned.ContainsKey($userId)) { continue }
    $display = Get-StringValue (Get-PropertyValue $user "display_name")
    $username = Get-StringValue (Get-PropertyValue $user "username")
    $entries.Add([pscustomobject]@{
      leagueId = Get-StringValue $league.id
      leagueName = Get-StringValue $league.name
      draftType = Get-StringValue $league.division
      buyIn = Convert-ToDecimal $league.buyIn
      assignmentStatus = "Waiting assignment"
      rosterId = ""
      sleeperName = if ($display) { $display } else { $username }
      sleeperUserId = $userId
      personId = ""
      personName = ""
    }) | Out-Null
  }
}

if (-not (Test-Path -LiteralPath $CsvOutputDirectory)) { New-Item -ItemType Directory -Path $CsvOutputDirectory | Out-Null }

$paymentCandidates = @($paymentRows | ForEach-Object { [pscustomobject]@{ row = $_; matchKey = $_.matchKey } })
$trackerPath = Join-Path $CsvOutputDirectory "redraft-bracket-master.csv"
$paidNotAssignedPath = Join-Path $CsvOutputDirectory "redraft-bracket-paid-not-assigned.csv"
$universalTrackerAliasPath = Join-Path $CsvOutputDirectory "commissioner-tracker.csv"
$universalPaidNotAssignedAliasPath = Join-Path $CsvOutputDirectory "paid-not-assigned.csv"

@($entries | Sort-Object leagueId, assignmentStatus, sleeperName | ForEach-Object {
  $entry = $_
  $entryKey = Get-MatchKey $entry.sleeperName
  $candidate = $null
  $match = ""
  if ($entry.personId) {
    foreach ($pc in $paymentCandidates) {
      if ((Get-StringValue $pc.row.personId) -eq (Get-StringValue $entry.personId)) { $candidate = $pc.row; $match = "Identity ledger"; break }
    }
  }
  if (-not $candidate) {
    foreach ($pc in $paymentCandidates) {
      if ($pc.matchKey -eq $entryKey) { $candidate = $pc.row; $match = "Exact"; break }
    }
  }
  $status = if ($entry.assignmentStatus -eq "Waiting assignment") { "Waiting - not assigned/unpaid" }
    elseif ($candidate -and $candidate.amount -ge $entry.buyIn) { "Assigned + paid candidate" }
    else { "Assigned - needs payment match" }
  [pscustomobject]@{
    Bracket = $entry.leagueId
    Division = $entry.leagueName
    Draft = $entry.draftType
    "Sleeper Name" = $entry.sleeperName
    "Sleeper User ID" = $entry.sleeperUserId
    Assignment = $entry.assignmentStatus
    "Roster Slot" = $entry.rosterId
    "LeagueSafe Name" = if ($candidate) { $candidate.payerName } else { "" }
    "LeagueSafe Email" = if ($candidate) { $candidate.payerEmail } else { "" }
    Paid = if ($candidate) { $candidate.amount } else { "" }
    Status = $status
    Match = $match
    Person = $entry.personName
    Notes = ""
  }
}) | Export-Csv -LiteralPath $trackerPath -NoTypeInformation -Encoding UTF8
Copy-Item -LiteralPath $trackerPath -Destination $universalTrackerAliasPath -Force

$assignedKeys = @{}
$assignedPeople = @{}
foreach ($entry in @($entries | Where-Object { $_.assignmentStatus -eq "Assigned team" })) {
  $assignedKeys[(Get-MatchKey $entry.sleeperName)] = $true
  if ($entry.personId) { $assignedPeople[$entry.personId] = $true }
}
@($paymentRows | Where-Object {
  -not $assignedKeys.ContainsKey($_.matchKey) -and ([string]::IsNullOrWhiteSpace($_.personId) -or -not $assignedPeople.ContainsKey($_.personId))
} | Sort-Object payerName | ForEach-Object {
  [pscustomobject]@{
    "LeagueSafe Name" = $_.payerName
    "LeagueSafe Email" = $_.payerEmail
    Paid = $_.amount
    "Payment ID" = $_.paymentId
    Status = "Paid - no assigned team found"
    Notes = $_.notes
  }
}) | Export-Csv -LiteralPath $paidNotAssignedPath -NoTypeInformation -Encoding UTF8
Copy-Item -LiteralPath $paidNotAssignedPath -Destination $universalPaidNotAssignedAliasPath -Force

$result = [pscustomobject]@{
  csvOutputDirectory = $CsvOutputDirectory
  redraftBracketMasterPath = $trackerPath
  redraftBracketPaidNotAssignedPath = $paidNotAssignedPath
  universalTrackerAliasPath = $universalTrackerAliasPath
  universalPaidNotAssignedAliasPath = $universalPaidNotAssignedAliasPath
  sleeperEntries = $entries.Count
  paidRows = $paymentRows.Count
  assignedNeedsMatch = @((Import-Csv -LiteralPath $trackerPath) | Where-Object { $_.Status -eq "Assigned - needs payment match" }).Count
}

if ($PassThru) { $result } else {
  Write-Host "Redraft Bracket reconciliation CSVs written to $CsvOutputDirectory"
  Write-Host "Sleeper entries: $($result.sleeperEntries)"
  Write-Host "Paid rows: $($result.paidRows)"
  Write-Host "Assigned needing match: $($result.assignedNeedsMatch)"
}
