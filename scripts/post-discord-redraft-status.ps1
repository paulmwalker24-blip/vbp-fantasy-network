param(
  [string]$JsonPath = "data/leagues.json",
  [string]$OverridesPath = "data/private/discord-status-overrides.json",
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "redraft-status",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_URL,
  [switch]$DryRun,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function To-Number {
  param(
    [AllowNull()]
    [object]$Value
  )

  $cleaned = [string]$Value
  $cleaned = $cleaned -replace '[$,%\s]', ''
  $cleaned = $cleaned -replace ',', ''

  $parsed = 0
  if ([double]::TryParse($cleaned, [ref]$parsed)) {
    return [int][math]::Floor($parsed)
  }

  return 0
}

function Format-MoneyValue {
  param(
    [AllowNull()]
    [object]$Value
  )

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return ""
  }

  $text = ([string]$Value).Trim()
  if ($text.StartsWith('$')) {
    return $text
  }

  $number = 0
  if ([double]::TryParse(($text -replace ',', ''), [ref]$number)) {
    return ('$' + ('{0:N0}' -f $number))
  }

  return $text
}

function Normalize-FilledCount {
  param(
    [int]$Teams,
    [int]$Filled
  )

  return [math]::Min([math]::Max($Filled, 0), [math]::Max($Teams, 0))
}

function Get-ObjectPropertyValue {
  param(
    [AllowNull()]
    [object]$InputObject,
    [string]$Name
  )

  if ($null -eq $InputObject) {
    return $null
  }

  $property = $InputObject.PSObject.Properties[$Name]
  if ($property) {
    return $property.Value
  }

  return $null
}

function Get-SleeperAssignedSnapshot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LeagueId
  )

  $league = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}" -f $LeagueId)
  $teams = To-Number $league.total_rosters
  $rosters = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/rosters" -f $LeagueId)
  $drafts = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/drafts" -f $LeagueId)
  $rosterAssignedCount = @($rosters | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.owner_id) }).Count
  $latestDraft = @($drafts | Sort-Object { [double]$_.created } -Descending | Select-Object -First 1)
  $latestDraftOrder = Get-ObjectPropertyValue -InputObject $latestDraft -Name "draft_order"
  $draftAssignedCount = if ($latestDraftOrder) {
    @($latestDraftOrder.PSObject.Properties | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Name) }).Count
  } else {
    0
  }
  $assigned = Normalize-FilledCount -Teams $teams -Filled ([math]::Max($rosterAssignedCount, $draftAssignedCount))

  [pscustomobject]@{
    teams = $teams
    assigned = $assigned
    openSpots = [math]::Max($teams - $assigned, 0)
    status = ([string]$league.status).Trim().ToLowerInvariant()
  }
}

function Get-FormatLabel {
  param(
    [string]$Format
  )

  switch ($Format.Trim().ToLowerInvariant()) {
    "redraft" { return "Seasonal Redraft" }
    "redraft32" { return "32-Team Redraft" }
    "comanager" { return "Co-Manager Redraft" }
    default { return "Redraft" }
  }
}

function Get-FormatRank {
  param(
    [string]$Format
  )

  switch ($Format.Trim().ToLowerInvariant()) {
    "redraft" { return 1 }
    "redraft32" { return 2 }
    "comanager" { return 3 }
    default { return 99 }
  }
}

function Get-FormatImageUrl {
  param(
    [string]$Format,
    [string]$BaseUrl
  )

  $fileName = switch ($Format.Trim().ToLowerInvariant()) {
    "redraft" { "constitution-redraft.png" }
    "redraft32" { "constitution-32-team-redraft.png" }
    "comanager" { "constitution-co-manager.png" }
    default { "constitution-redraft.png" }
  }

  return ("{0}/assets/images/{1}" -f $BaseUrl.TrimEnd('/'), $fileName)
}

function Get-FormatColor {
  param(
    [string]$Format
  )

  switch ($Format.Trim().ToLowerInvariant()) {
    "redraft" { return 0xC0392B }
    "redraft32" { return 0x2F80ED }
    "comanager" { return 0x27AE60 }
    default { return 0x5865F2 }
  }
}

function Get-PaidOverride {
  param(
    [string]$Path,
    [string]$LeagueId
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  $redraft = Get-ObjectPropertyValue -InputObject $payload -Name "redraft"
  $league = Get-ObjectPropertyValue -InputObject $redraft -Name $LeagueId
  $paid = Get-ObjectPropertyValue -InputObject $league -Name "paid"

  if ($null -eq $paid) {
    return $null
  }

  return [int](To-Number $paid)
}

function Get-DiscordMessageState {
  param(
    [string]$Path,
    [string]$Key
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  return Get-ObjectPropertyValue -InputObject $state -Name $Key
}

function Save-DiscordMessageState {
  param(
    [string]$Path,
    [string]$Key,
    [string]$MessageId
  )

  $state = [pscustomobject]@{}
  if (Test-Path -LiteralPath $Path) {
    $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } else {
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
      New-Item -ItemType Directory -Path $directory | Out-Null
    }
  }

  $entry = [pscustomobject]@{
    messageId = $MessageId
    updatedAt = (Get-Date).ToString("s")
  }

  if ($state.PSObject.Properties[$Key]) {
    $state.$Key = $entry
  } else {
    $state | Add-Member -NotePropertyName $Key -NotePropertyValue $entry
  }

  $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find league data file at '$JsonPath'."
}

$leaguePayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $JsonPath).Path -Raw | ConvertFrom-Json
$redraftFormats = @("redraft")

$leagueRows = foreach ($league in $leaguePayload.leagues) {
  $format = ([string]$league.format).Trim().ToLowerInvariant()
  $status = ([string]$league.status).Trim().ToLowerInvariant()
  $sleeperLeagueId = ([string]$league.sleeperLeagueId).Trim()

  if (-not ($redraftFormats -contains $format) -or $status -ne "open" -or -not $sleeperLeagueId) {
    continue
  }

  $snapshot = Get-SleeperAssignedSnapshot -LeagueId $sleeperLeagueId
  $leagueId = [string]$league.id
  $paid = Get-PaidOverride -Path $OverridesPath -LeagueId $leagueId

  [pscustomobject]@{
    id = $leagueId
    name = [string]$league.name
    format = $format
    formatLabel = Get-FormatLabel -Format $format
    formatRank = Get-FormatRank -Format $format
    buyIn = Format-MoneyValue $league.buyIn
    assigned = $snapshot.assigned
    teams = $snapshot.teams
    openSpots = $snapshot.openSpots
    isFull = ($snapshot.teams -gt 0 -and ($snapshot.assigned -ge $snapshot.teams -or $status -eq "full"))
    paid = $paid
    inviteLink = [string]$league.inviteLink
    rulesLink = ("{0}/{1}" -f $AssetBaseUrl.TrimEnd('/'), ([string]$league.constitutionPage).Trim())
    imageUrl = Get-FormatImageUrl -Format $format -BaseUrl $AssetBaseUrl
  }
}

$leagueRows = @($leagueRows | Sort-Object formatRank, name)
$totalTeams = [int](@($leagueRows | Measure-Object -Property teams -Sum).Sum)
$totalAssigned = [int](@($leagueRows | Measure-Object -Property assigned -Sum).Sum)
$totalOpen = [int](@($leagueRows | Measure-Object -Property openSpots -Sum).Sum)
$paidRows = @($leagueRows | Where-Object { $null -ne $_.paid })
$totalPaid = if ($paidRows.Count -gt 0) { [int](@($paidRows | Measure-Object -Property paid -Sum).Sum) } else { $null }
$fullRows = @($leagueRows | Where-Object { $_.isFull })
$openRows = @($leagueRows | Where-Object { -not $_.isFull })

$updatedAt = Get-Date
$timestamp = $updatedAt.ToUniversalTime().ToString("o")
$overviewPaidText = if ($null -ne $totalPaid) {
  "$totalPaid/$totalTeams paid across leagues with supplied paid counts."
} else {
  "Paid counts not supplied yet."
}
$fullSummaryLines = @($fullRows | ForEach-Object {
  "- $($_.name): full ($($_.assigned)/$($_.teams))"
})
$fullSummaryText = if ($fullSummaryLines.Count -gt 0) {
  $fullSummaryLines -join "`n"
} else {
  "No full standard redraft rooms yet."
}
$openSummaryText = if ($openRows.Count -gt 0) {
  "$($openRows.Count) standard redraft league(s) with openings are listed below."
} elseif ($leagueRows.Count -gt 0) {
  "No current standard redraft openings. Full rooms are listed above as network proof."
} else {
  "No standard redraft records are currently listed."
}

$overviewDescription = @(
  "**Current Snapshot**",
  "$($leagueRows.Count) standard redraft record(s)",
  "$totalAssigned/$totalTeams assigned | $totalOpen open",
  $overviewPaidText,
  "",
  "**Full / Established Rooms**",
  $fullSummaryText,
  "",
  "**Current Openings**",
  $openSummaryText,
  "",
  "**Board Notes**",
  "Assigned teams update from Sleeper rosters/draft slots.",
  "Paid teams come from the local Discord status override file.",
  "This channel only includes standard seasonal redraft leagues."
) -join "`n"

$overviewEmbed = @{
  title = "VBP Redraft Openings"
  url = "https://vbp-fantasy-network.vercel.app/"
  description = $overviewDescription
  color = 0xC0392B
  footer = @{
    text = "Living redraft openings board"
  }
  timestamp = $timestamp
}

$leagueEmbeds = foreach ($row in $openRows) {
  $paidText = if ($null -ne $row.paid) { "$($row.paid)/$($row.teams)" } else { "Not supplied" }
  $description = @(
    "**Type:** $($row.formatLabel)",
    "**Buy-in:** $($row.buyIn)",
    "**Assigned teams:** $($row.assigned)/$($row.teams)",
    "**Paid teams:** $paidText",
    "**Open spots:** $($row.openSpots)",
    "**Join:** $($row.inviteLink)",
    "**Rules:** $($row.rulesLink)"
  ) -join "`n"

  $embed = @{
    title = $row.name
    url = $row.inviteLink
    description = $description
    color = Get-FormatColor -Format $row.format
    footer = @{
      text = ("{0} | {1}" -f $row.id, $row.formatLabel)
    }
    timestamp = $timestamp
  }

  if ($row.imageUrl) {
    $embed.thumbnail = @{
      url = $row.imageUrl
    }
  }

  $embed
}

$payloadObject = @{
  content = ""
  embeds = @($overviewEmbed) + @($leagueEmbeds)
}

$payload = $payloadObject | ConvertTo-Json -Depth 8

$result = [pscustomobject]@{
  totalTeams = $totalTeams
  totalAssigned = $totalAssigned
  totalOpen = $totalOpen
  totalPaid = $totalPaid
  leagues = @($leagueRows)
  embeds = @($payloadObject.embeds)
  dryRun = [bool]$DryRun
  statePath = $StatePath
  stateKey = $StateKey
  messageId = $null
  action = if ($DryRun) { "dry-run" } else { "pending" }
}

if (-not $DryRun) {
  if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
    throw "Set DISCORD_WEBHOOK_URL or pass -WebhookUrl before posting to Discord."
  }

  $existingState = Get-DiscordMessageState -Path $StatePath -Key $StateKey
  $existingMessageId = if ($existingState) { [string]$existingState.messageId } else { "" }

  if (-not [string]::IsNullOrWhiteSpace($existingMessageId)) {
    try {
      Invoke-RestMethod -Uri ("{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $existingMessageId) -Method Patch -ContentType "application/json" -Body $payload | Out-Null
      $result.messageId = $existingMessageId
      $result.action = "updated"
    } catch {
      Write-Warning ("Could not update stored Discord message {0}; posting a new redraft status message instead. {1}" -f $existingMessageId, $_.Exception.Message)
    }
  }

  if ([string]::IsNullOrWhiteSpace([string]$result.messageId)) {
    $postResponse = Invoke-RestMethod -Uri ("{0}?wait=true" -f $WebhookUrl) -Method Post -ContentType "application/json" -Body $payload
    $newMessageId = [string]$postResponse.id
    if ([string]::IsNullOrWhiteSpace($newMessageId)) {
      throw "Discord did not return a message ID. Cannot save update state."
    }

    Save-DiscordMessageState -Path $StatePath -Key $StateKey -MessageId $newMessageId
    $result.messageId = $newMessageId
    $result.action = "created"
  } else {
    Save-DiscordMessageState -Path $StatePath -Key $StateKey -MessageId ([string]$result.messageId)
  }
}

if ($PassThru) {
  $result
} else {
  if ($DryRun) {
    Write-Host "Dry run only. Set DISCORD_WEBHOOK_URL or pass -WebhookUrl to post this into Discord."
  } else {
    Write-Host ("Discord message {0}: {1}" -f $result.action, $result.messageId)
  }
}
