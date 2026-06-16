param(
  [Parameter(Mandatory = $true)]
  [string]$FormatKey,
  [string]$JsonPath = "data/leagues.json",
  [string]$OverridesPath = "data/private/discord-status-overrides.json",
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "",
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
    return "Not listed"
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

function ConvertTo-TitleText {
  param(
    [AllowNull()]
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return "Unknown"
  }

  $text = $Value.Trim() -replace '[_-]+', ' '
  $culture = [System.Globalization.CultureInfo]::CurrentCulture
  return $culture.TextInfo.ToTitleCase($text.ToLowerInvariant())
}

function Get-LeagueStatusMarker {
  param(
    [string]$Status,
    [int]$OpenSpots,
    [bool]$IsFull
  )

  if ($IsFull -or $OpenSpots -le 0 -or $Status -eq "full" -or $Status -eq "closed") {
    return [char]::ConvertFromUtf32(0x1F534)
  }

  if ($Status -eq "open") {
    return [char]::ConvertFromUtf32(0x1F7E2)
  }

  return [char]::ConvertFromUtf32(0x1F7E1)
}

function Get-FormatConfig {
  param(
    [string]$Key
  )

  switch ($Key.Trim().ToLowerInvariant()) {
    "keeper" {
      return [pscustomobject]@{
        key = "keeper"
        dataFormats = @("keeper")
        label = "Keeper"
        title = "VBP Keeper Openings"
        description = "Keeper leagues with escalating keeper costs, future-pick payment rules, and long-term roster decisions."
        basics = @("Escalating keeper costs with multi-year roster planning.", "Future draft picks may be traded up to two years out.", "Keeper decisions and payment obligations are governed by the constitution.")
        image = "constitution-keeper.png"
        color = 0xF2C94C
        constitutionPage = "keeper-constitution.html"
        includeAllStatuses = $true
        emptyText = "No keeper league records are currently listed."
      }
    }
    "pickem" {
      return [pscustomobject]@{
        key = "pickem"
        dataFormats = @("pickem")
        label = "Pick'em"
        title = "VBP Pick'em Openings"
        description = "Spread-based NFL pick'em contest. This board uses Sleeper league users because Pick'em does not use normal fantasy rosters."
        basics = @("NFL pick'em contest using weekly picks instead of fantasy rosters.", "Live availability uses Sleeper league users.", "Best fit for managers who want a lighter weekly commitment.")
        image = "constitution-pickem.png"
        color = 0x56CCF2
        constitutionPage = "pickem-constitution.html"
        includeAllStatuses = $true
        emptyText = "No Pick'em league records are currently listed."
      }
    }
    "chopped" {
      return [pscustomobject]@{
        key = "chopped"
        dataFormats = @("chopped")
        label = "Chopped"
        title = "VBP Chopped Status"
        description = "18-team elimination redraft. One team is chopped each week until the final survivor path is settled."
        basics = @("18-team elimination redraft.", "One team is chopped each week during the elimination phase.", "Draft-pick trading and chop rules are handled by the Chopped constitution.")
        image = "constitution-chopped.png"
        color = 0xEB5757
        constitutionPage = "chopped-constitution.html"
        includeAllStatuses = $true
        emptyText = "No Chopped league records are currently listed."
      }
    }
    "sacrifice" {
      return [pscustomobject]@{
        key = "sacrifice"
        dataFormats = @("sacrifice")
        label = "Sacrifice Redraft"
        title = "VBP Sacrifice Redraft Status"
        description = "Sacrifice Redraft is a separate test format with its own rules page. No active public league record is listed yet."
        basics = @("Experimental redraft format with its own rules page.", "No active public league record is listed yet.", "Use this channel for format status once a public room opens.")
        image = "constitution-sacrifice.png"
        color = 0xBB6BD9
        constitutionPage = "sacrifice-redraft-constitution.html"
        includeAllStatuses = $true
        emptyText = "No active Sacrifice Redraft league record is listed yet."
      }
    }
    "dynasty" {
      return [pscustomobject]@{
        key = "dynasty"
        dataFormats = @("dynasty")
        label = "Dynasty"
        title = "VBP Dynasty Status"
        description = "Standalone dynasty leagues with long-term roster building, rookie drafts, and future-pick payment rules."
        basics = @("Long-term roster building with rookie drafts.", "Future-pick trades require payment coverage for the involved season.", "Full leagues may be listed for network context without join details.")
        image = "constitution-dynasty.png"
        color = 0x9B51E0
        constitutionPage = "dynasty-constitution.html"
        includeAllStatuses = $true
        emptyText = "No dynasty league records are currently listed."
      }
    }
    "bbg" {
      return [pscustomobject]@{
        key = "bbg"
        dataFormats = @("gauntlet")
        label = "Best Ball Gauntlet"
        title = "VBP Best Ball Gauntlet Status"
        description = '24-team micro best ball gauntlet. The full-room payout is $110 to the standings champion and $10 to the highest single-week scorer.'
        basics = @("24-team micro best ball gauntlet.", "Best ball scoring means no weekly lineup setting.", "Full-room payout: `$110 standings champion and `$10 highest single-week scorer.")
        image = "constitution-bestball-gauntlet.png"
        color = 0xF2994A
        constitutionPage = "bestball-gauntlet-constitution.html"
        includeAllStatuses = $true
        emptyText = "No Best Ball Gauntlet league records are currently listed."
      }
    }
    "gauntlet" {
      return Get-FormatConfig -Key "bbg"
    }
    "comanager" {
      return [pscustomobject]@{
        key = "comanager"
        dataFormats = @("comanager")
        label = "Co-Manager Redraft"
        title = "VBP Co-Manager Redraft Status"
        description = "Co-manager redraft where each team has 2-3 managers, with superflex scoring and a scheduled slow draft."
        basics = @("12-team co-manager redraft.", "Each team must have 2-3 co-managers.", "Lineup uses superflex scoring with TE premium and 6-point passing TDs.")
        image = "constitution-co-manager.png"
        color = 0x27AE60
        constitutionPage = "co-manager-constitution.html"
        includeAllStatuses = $true
        emptyText = "No co-manager league records are currently listed."
      }
    }
    "co-manager" {
      return Get-FormatConfig -Key "comanager"
    }
    "redraft32" {
      return [pscustomobject]@{
        key = "redraft32"
        dataFormats = @("redraft32")
        label = "32-Team Redraft"
        title = "VBP 32-Team Redraft Status"
        description = "32-team redraft with deep lineup decisions and a separate channel from standard seasonal redraft."
        basics = @("32-team seasonal redraft with scarce player supply.", "Lineup: 1 RB, 2 WR, 3 FLEX, 1 SUPER FLEX.", "Bench: 4. Waivers: `$200 FAAB. No kicker or defense.")
        image = "constitution-32-team-redraft.png"
        color = 0x2F80ED
        constitutionPage = "32-team-redraft-constitution.html"
        includeAllStatuses = $true
        emptyText = "No 32-team redraft league records are currently listed."
      }
    }
    "32team" {
      return Get-FormatConfig -Key "redraft32"
    }
    "32-team" {
      return Get-FormatConfig -Key "redraft32"
    }
    default {
      throw "Unsupported format key '$Key'."
    }
  }
}

function Get-SleeperAssignedSnapshot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LeagueId,
    [switch]$UseUsers
  )

  $league = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}" -f $LeagueId)
  $teams = To-Number $league.total_rosters
  $status = ([string]$league.status).Trim().ToLowerInvariant()

  if ($UseUsers) {
    $users = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/users" -f $LeagueId)
    $assigned = Normalize-FilledCount -Teams $teams -Filled @($users).Count

    return [pscustomobject]@{
      teams = $teams
      assigned = $assigned
      openSpots = [math]::Max($teams - $assigned, 0)
      status = $status
      draftStatus = ""
    }
  }

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
  $draftStatus = Get-ObjectPropertyValue -InputObject $latestDraft -Name "status"

  [pscustomobject]@{
    teams = $teams
    assigned = $assigned
    openSpots = [math]::Max($teams - $assigned, 0)
    status = $status
    draftStatus = ([string]$draftStatus).Trim().ToLowerInvariant()
  }
}

function Get-PaidOverride {
  param(
    [string]$Path,
    [string]$FormatKey,
    [string]$LeagueId
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  foreach ($sectionName in @($FormatKey, "redraft", "all")) {
    $section = Get-ObjectPropertyValue -InputObject $payload -Name $sectionName
    $league = Get-ObjectPropertyValue -InputObject $section -Name $LeagueId
    $paid = Get-ObjectPropertyValue -InputObject $league -Name "paid"

    if ($null -ne $paid) {
      return [int](To-Number $paid)
    }
  }

  return $null
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

  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path
}

function New-EmbedObject {
  param(
    [hashtable]$Values
  )

  return $Values
}

function Invoke-DiscordJsonRequest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Uri,
    [Parameter(Mandatory = $true)]
    [string]$Method,
    [Parameter(Mandatory = $true)]
    [string]$JsonBody
  )

  $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)
  return Invoke-RestMethod -Uri $Uri -Method $Method -ContentType "application/json; charset=utf-8" -Body $bodyBytes
}

function Get-PropertySum {
  param(
    [object[]]$Rows,
    [string]$PropertyName
  )

  if (-not $Rows -or $Rows.Count -eq 0) {
    return 0
  }

  $sum = ($Rows | Measure-Object -Property $PropertyName -Sum).Sum
  if ($null -eq $sum) {
    return 0
  }

  return [int]$sum
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find league data file at '$JsonPath'."
}

$config = Get-FormatConfig -Key $FormatKey
if ([string]::IsNullOrWhiteSpace($StateKey)) {
  $StateKey = ("{0}-status" -f $config.key)
}

$leaguePayload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $JsonPath).Path -Raw | ConvertFrom-Json
$leagueRows = foreach ($league in $leaguePayload.leagues) {
  $format = ([string]$league.format).Trim().ToLowerInvariant()
  $status = ([string]$league.status).Trim().ToLowerInvariant()
  $sleeperLeagueId = ([string]$league.sleeperLeagueId).Trim()

  if (-not ($config.dataFormats -contains $format)) {
    continue
  }

  if (-not $config.includeAllStatuses -and $status -ne "open") {
    continue
  }

  $teams = To-Number $league.teams
  $assigned = Normalize-FilledCount -Teams $teams -Filled (To-Number $league.filled)
  $openSpots = [math]::Max($teams - $assigned, 0)
  $sleeperStatus = ""
  $draftStatus = ""

  if (-not [string]::IsNullOrWhiteSpace($sleeperLeagueId)) {
    $snapshot = Get-SleeperAssignedSnapshot -LeagueId $sleeperLeagueId -UseUsers:($config.key -eq "pickem")
    $teams = $snapshot.teams
    $assigned = $snapshot.assigned
    $openSpots = $snapshot.openSpots
    $sleeperStatus = $snapshot.status
    $draftStatus = $snapshot.draftStatus
  }

  $leagueId = [string]$league.id
  $paid = Get-PaidOverride -Path $OverridesPath -FormatKey $config.key -LeagueId $leagueId
  $constitutionPage = ([string]$league.constitutionPage).Trim()
  if ([string]::IsNullOrWhiteSpace($constitutionPage)) {
    $constitutionPage = $config.constitutionPage
  }

  $isFull = ($teams -gt 0 -and ($assigned -ge $teams -or $status -eq "full"))
  $statusMarker = Get-LeagueStatusMarker -Status $status -OpenSpots $openSpots -IsFull $isFull

  [pscustomobject]@{
    id = $leagueId
    name = [string]$league.name
    status = $status
    statusMarker = $statusMarker
    statusLabel = ConvertTo-TitleText $status
    sleeperStatus = $sleeperStatus
    sleeperStatusLabel = if ($sleeperStatus) { ConvertTo-TitleText $sleeperStatus } else { "" }
    draftStatus = $draftStatus
    draftStatusLabel = if ($draftStatus) { ConvertTo-TitleText $draftStatus } else { "" }
    buyIn = Format-MoneyValue $league.buyIn
    assigned = $assigned
    teams = $teams
    openSpots = $openSpots
    isFull = $isFull
    paid = $paid
    inviteLink = ([string]$league.inviteLink).Trim()
    rulesLink = ("{0}/{1}" -f $AssetBaseUrl.TrimEnd('/'), $constitutionPage)
    imageUrl = ("{0}/assets/images/{1}" -f $AssetBaseUrl.TrimEnd('/'), $config.image)
    notes = ([string]$league.notes).Trim()
  }
}

$leagueRows = @($leagueRows | Sort-Object name)
$totalTeams = Get-PropertySum -Rows $leagueRows -PropertyName "teams"
$totalAssigned = Get-PropertySum -Rows $leagueRows -PropertyName "assigned"
$totalOpen = Get-PropertySum -Rows $leagueRows -PropertyName "openSpots"
$paidRows = @($leagueRows | Where-Object { $null -ne $_.paid })
$totalPaid = if ($paidRows.Count -gt 0) { Get-PropertySum -Rows $paidRows -PropertyName "paid" } else { $null }
$fullRows = @($leagueRows | Where-Object { $_.isFull })
$openRows = @($leagueRows | Where-Object { -not $_.isFull })

$updatedAt = Get-Date
$timestamp = $updatedAt.ToUniversalTime().ToString("o")
$imageUrl = ("{0}/assets/images/{1}" -f $AssetBaseUrl.TrimEnd('/'), $config.image)
$rulesUrl = ("{0}/{1}" -f $AssetBaseUrl.TrimEnd('/'), $config.constitutionPage)
$paidText = if ($null -ne $totalPaid -and $totalTeams -gt 0) {
  "$totalPaid/$totalTeams paid where supplied"
} else {
  "Paid counts not supplied yet"
}
$snapshotText = if ($totalTeams -gt 0) {
  "$totalAssigned/$totalTeams assigned | $totalOpen open"
} else {
  $config.emptyText
}
$fullSummaryLines = @($fullRows | ForEach-Object {
  "- $($_.name): full ($($_.assigned)/$($_.teams))"
})
$fullSummaryText = if ($fullSummaryLines.Count -gt 0) {
  $fullSummaryLines -join "`n"
} else {
  "No full $($config.label) league records yet."
}
$openSummaryText = if ($openRows.Count -gt 0) {
  "$($openRows.Count) league(s) with openings are listed below."
} elseif ($leagueRows.Count -gt 0) {
  "No current openings. Full leagues are listed above as network proof."
} else {
  $config.emptyText
}
$formatBasicLines = @($config.basics | ForEach-Object { "- $_" })
$formatBasicsText = if ($formatBasicLines.Count -gt 0) {
  $formatBasicLines -join "`n"
} else {
  $config.description
}

$overviewDescription = @(
  "**Current Snapshot**",
  "$($leagueRows.Count) league record(s)",
  $snapshotText,
  $paidText,
  "",
  "**Full / Established Rooms**",
  $fullSummaryText,
  "",
  "**Current Openings**",
  $openSummaryText,
  "",
  "**Format Basics**",
  $formatBasicsText,
  "",
  "**Rules:** $rulesUrl"
) -join "`n"

$overviewEmbed = New-EmbedObject @{
  title = $config.title
  url = $rulesUrl
  description = $overviewDescription
  color = $config.color
  thumbnail = @{
    url = $imageUrl
  }
  footer = @{
    text = ("Living {0} board" -f $config.label)
  }
  timestamp = $timestamp
}

$visibleRows = @($openRows | Select-Object -First 9)
$leagueEmbeds = foreach ($row in $visibleRows) {
  $rowPaidText = if ($null -ne $row.paid) { "$($row.paid)/$($row.teams)" } else { "Not supplied" }
  $joinText = if ($row.inviteLink) { $row.inviteLink } else { "No public invite listed" }
  $draftLine = if ($row.draftStatusLabel) { "**Draft status:** $($row.draftStatusLabel)" } else { $null }
  $sleeperLine = if ($row.sleeperStatusLabel) { "**Sleeper status:** $($row.sleeperStatusLabel)" } else { $null }
  $notesLine = if ($row.notes) { "**Notes:** $($row.notes)" } else { $null }
  $descriptionLines = @(
    "**Status:** $($row.statusMarker) $($row.statusLabel)",
    $sleeperLine,
    $draftLine,
    "**Buy-in:** $($row.buyIn)",
    "**Assigned teams:** $($row.assigned)/$($row.teams)",
    "**Paid teams:** $rowPaidText",
    "**Open spots:** $($row.openSpots)",
    "**Join:** $joinText",
    "**Rules:** $($row.rulesLink)",
    $notesLine
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

  $embed = @{
    title = $row.name
    description = ($descriptionLines -join "`n")
    color = $config.color
    thumbnail = @{
      url = $row.imageUrl
    }
    footer = @{
      text = ("{0} | {1}" -f $row.id, $config.label)
    }
    timestamp = $timestamp
  }

  if ($row.inviteLink) {
    $embed.url = $row.inviteLink
  }

  New-EmbedObject $embed
}

if ($openRows.Count -gt $visibleRows.Count) {
  $hiddenCount = $openRows.Count - $visibleRows.Count
  $leagueEmbeds += New-EmbedObject @{
    title = ("Additional {0} Records" -f $config.label)
    description = "$hiddenCount more open record(s) are tracked in local league data. Full leagues stay summarized at the top so openings remain easy to scan."
    color = $config.color
    footer = @{
      text = "Overflow summary"
    }
    timestamp = $timestamp
  }
}

$payloadObject = @{
  content = ""
  embeds = @($overviewEmbed) + @($leagueEmbeds)
}

$payload = $payloadObject | ConvertTo-Json -Depth 10

$result = [pscustomobject]@{
  formatKey = $config.key
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
      Invoke-DiscordJsonRequest -Uri ("{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $existingMessageId) -Method Patch -JsonBody $payload | Out-Null
      $result.messageId = $existingMessageId
      $result.action = "updated"
    } catch {
      Write-Warning ("Could not update stored Discord message {0}; posting a new {1} status message instead. {2}" -f $existingMessageId, $config.label, $_.Exception.Message)
    }
  }

  if ([string]::IsNullOrWhiteSpace([string]$result.messageId)) {
    $postResponse = Invoke-DiscordJsonRequest -Uri ("{0}?wait=true" -f $WebhookUrl) -Method Post -JsonBody $payload
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
    Write-Host ("Dry run only for {0}. Set DISCORD_WEBHOOK_URL or pass -WebhookUrl to post this into Discord." -f $config.label)
  } else {
    Write-Host ("Discord {0} message {1}: {2}" -f $config.label, $result.action, $result.messageId)
  }
}
