param(
  [string]$JsonPath = "data/leagues.json",
  [string]$LeagueRecordId,
  [string]$SleeperLeagueId,
  [string]$DisplayName,
  [string]$JoinUrl,
  [string]$ConstitutionPage,
  [string]$BuyIn,
  [string]$WinningsText,
  [Nullable[int]]$PaidCount,
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

function Normalize-FilledCount {
  param(
    [int]$Teams,
    [int]$Filled
  )

  $safeTeams = [math]::Max($Teams, 0)
  $safeFilled = [math]::Max($Filled, 0)
  return [math]::Min($safeFilled, $safeTeams)
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

function Get-LeagueRecord {
  param(
    [string]$Path,
    [string]$RecordId
  )

  if (-not $RecordId) {
    return $null
  }

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Could not find league data file at '$Path'."
  }

  $payload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $Path).Path -Raw | ConvertFrom-Json
  $match = $payload.leagues | Where-Object { [string]$_.id -eq $RecordId } | Select-Object -First 1
  return $match
}

function Get-SleeperAssignedSnapshot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LeagueId
  )

  $league = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}" -f $LeagueId)
  $teams = To-Number $league.total_rosters
  $isPickemLeague = ([string]$league.sport).Trim().ToLowerInvariant().StartsWith("pickem:")

  if ($isPickemLeague) {
    $users = Invoke-RestMethod -Uri ("https://api.sleeper.app/v1/league/{0}/users" -f $LeagueId)
    $assigned = Normalize-FilledCount -Teams $teams -Filled $users.Count
    $source = "Sleeper users"
  } else {
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
    $source = "assigned rosters/draft slots"
  }

  [pscustomobject]@{
    sleeperLeagueId = $LeagueId
    sleeperName = [string]$league.name
    sleeperStatus = ([string]$league.status).Trim().ToLowerInvariant()
    season = [string]$league.season
    teams = $teams
    assigned = $assigned
    openSpots = [math]::Max($teams - $assigned, 0)
    assignedSource = $source
  }
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

function Format-StatusLabel {
  param(
    [string]$Status
  )

  $cleaned = $Status -replace '[_-]+', ' '
  $words = @($cleaned.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
  if ($words.Count -eq 0) {
    return "Unknown"
  }

  return (($words | ForEach-Object {
    if ($_.Length -le 1) {
      $_.ToUpperInvariant()
    } else {
      $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1).ToLowerInvariant()
    }
  }) -join ' ')
}

function Convert-HtmlToPlainText {
  param(
    [string]$Html
  )

  $text = $Html -replace '(?is)<script.*?</script>', ' '
  $text = $text -replace '(?is)<style.*?</style>', ' '
  $text = $text -replace '(?is)</(p|li|tr|h[1-6])>', '. '
  $text = $text -replace '(?is)<br\s*/?>', ' '
  $text = $text -replace '(?is)<[^>]+>', ' '
  $text = [System.Net.WebUtility]::HtmlDecode($text)
  $text = $text -replace '\s+', ' '
  $text = $text -replace '\s+\.', '.'
  return $text.Trim()
}

function Get-TablePayoutSummaries {
  param(
    [string]$Html
  )

  $rows = [System.Collections.Generic.List[string]]::new()
  $rowMatches = [regex]::Matches($Html, '(?is)<tr[^>]*>(.*?)</tr>')
  foreach ($rowMatch in $rowMatches) {
    $cells = [System.Collections.Generic.List[string]]::new()
    foreach ($cellMatch in [regex]::Matches($rowMatch.Groups[1].Value, '(?is)<t[dh][^>]*>(.*?)</t[dh]>')) {
      $cellText = Convert-HtmlToPlainText $cellMatch.Groups[1].Value
      if (-not [string]::IsNullOrWhiteSpace($cellText)) {
        $cells.Add($cellText) | Out-Null
      }
    }

    if ($cells.Count -eq 2 -and $cells[0] -notmatch 'placement|payout|teams|leagues|prize|entries|pool|season payouts|^\d+$') {
      $rows.Add(("{0}: {1}" -f $cells[0], $cells[1])) | Out-Null
    } elseif ($cells.Count -ge 3 -and $cells[0] -notmatch 'placement|payout|teams|leagues|prize|entries|pool|season payouts|^\d+$') {
      $rows.Add(($cells -join " - ")) | Out-Null
    }
  }

  return @($rows)
}

function Get-ConstitutionWinningsText {
  param(
    [string]$PagePath,
    [AllowNull()]
    [object]$League
  )

  if ([string]::IsNullOrWhiteSpace($PagePath)) {
    return ""
  }

  $resolvedPagePath = Join-Path (Get-Location) $PagePath
  if (-not (Test-Path -LiteralPath $resolvedPagePath)) {
    return ""
  }

  $html = Get-Content -LiteralPath $resolvedPagePath -Raw

  $directPayoutMatch = [regex]::Match($html, '(?is)<(?:li|p)[^>]*>\s*<strong>\s*Payout:\s*</strong>\s*(.*?)</(?:li|p)>')
  if ($directPayoutMatch.Success) {
    return ("Payout: {0}" -f (Convert-HtmlToPlainText $directPayoutMatch.Groups[1].Value).TrimEnd('.'))
  }

  $sectionMatches = [regex]::Matches($html, '(?is)<section\b[^>]*>.*?</section>')
  $targetSections = [System.Collections.Generic.List[string]]::new()
  foreach ($sectionMatch in $sectionMatches) {
    $sectionHtml = $sectionMatch.Value
    if ($sectionHtml -match '(?is)<h2[^>]*>.*?(prize|payout|buy-in|high score).*?</h2>') {
      $targetSections.Add($sectionHtml) | Out-Null
    }
  }

  if ($targetSections.Count -eq 0) {
    return ""
  }

  $combinedHtml = ($targetSections -join "`n")
  $tables = Get-TablePayoutSummaries -Html $combinedHtml
  $listItems = [System.Collections.Generic.List[string]]::new()
  foreach ($listMatch in [regex]::Matches($combinedHtml, '(?is)<li[^>]*>(.*?)</li>')) {
    $item = Convert-HtmlToPlainText $listMatch.Groups[1].Value
    if ($item -match '(?i)champion|winner|runner-up|semifinal|quarterfinal|overall high score|weekly prize|full-season points') {
      $listItems.Add($item.TrimEnd('.')) | Out-Null
    }
  }

  $sentences = [System.Collections.Generic.List[string]]::new()
  foreach ($match in [regex]::Matches((Convert-HtmlToPlainText $combinedHtml), '[^.!?]+[.!?]')) {
    $sentence = $match.Value.Trim()
    $sentence = ($sentence -replace '(?i)^Back to top\s+', '').Trim()
    if ($sentence -match '(?i)^(buy-in|buy-in & prize pool|prize structure|prize distribution structure|weekly prize thresholds|regular season winner|champion and payout|payouts)\.?$') {
      continue
    }
    if ($sentence -match '(?i)payout|prize|champion|winner|overall high score|high-score|full-season points|division winner|runner-up|semifinal|quarterfinal|regular season winner|weekly prize') {
      if ($sentence -notmatch '(?i)approval|commissioner is responsible|rule changes|removed for inactivity|payment avoidance|accountability') {
        $sentences.Add($sentence.TrimEnd('.')) | Out-Null
      }
    }
  }

  $parts = [System.Collections.Generic.List[string]]::new()
  foreach ($table in $tables | Select-Object -First 6) {
    $parts.Add($table) | Out-Null
  }
  foreach ($item in $listItems | Select-Object -First 6) {
    if (-not ($parts -contains $item)) {
      $parts.Add($item) | Out-Null
    }
  }
  foreach ($sentence in $sentences | Select-Object -First 4) {
    if (-not ($parts -contains $sentence)) {
      $parts.Add($sentence) | Out-Null
    }
  }

  if ($parts.Count -eq 0) {
    return ""
  }

  return (($parts | Select-Object -First 6) -join "; ")
}

function Get-ConstitutionBuyIn {
  param(
    [string]$PagePath
  )

  if ([string]::IsNullOrWhiteSpace($PagePath)) {
    return ""
  }

  $resolvedPagePath = Join-Path (Get-Location) $PagePath
  if (-not (Test-Path -LiteralPath $resolvedPagePath)) {
    return ""
  }

  $text = Convert-HtmlToPlainText (Get-Content -LiteralPath $resolvedPagePath -Raw)
  $match = [regex]::Match($text, '(?i)Buy-In:\s*(\$[0-9,]+(?:\.[0-9]{2})?)')
  if ($match.Success) {
    return $match.Groups[1].Value
  }

  return ""
}

$record = Get-LeagueRecord -Path $JsonPath -RecordId $LeagueRecordId

if ($record) {
  if (-not $SleeperLeagueId) {
    $SleeperLeagueId = ([string]$record.sleeperLeagueId).Trim()
  }
  if (-not $DisplayName) {
    $DisplayName = [string]$record.name
  }
  if (-not $JoinUrl) {
    $JoinUrl = ([string]$record.inviteLink).Trim()
  }
  if (-not $ConstitutionPage) {
    $ConstitutionPage = ([string]$record.constitutionPage).Trim()
  }
  if (-not $BuyIn) {
    $BuyIn = Format-MoneyValue $record.buyIn
  }
  if (-not $WinningsText) {
    $WinningsText = Get-ConstitutionWinningsText -PagePath $ConstitutionPage -League $record
  }
  if (-not $WinningsText) {
    foreach ($propertyName in @("winnings", "payouts", "prizeText")) {
      $value = Get-ObjectPropertyValue -InputObject $record -Name $propertyName
      if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
        $WinningsText = ([string]$value).Trim()
        break
      }
    }
  }
}

if (-not $SleeperLeagueId) {
  throw "Provide -SleeperLeagueId or a -LeagueRecordId with a sleeperLeagueId in $JsonPath."
}

if (-not $JoinUrl) {
  $JoinUrl = "https://sleeper.com/leagues/$SleeperLeagueId/predraft"
}

$snapshot = Get-SleeperAssignedSnapshot -LeagueId $SleeperLeagueId
if (-not $DisplayName) {
  $DisplayName = $snapshot.sleeperName
}

if (-not $BuyIn) {
  $BuyIn = Get-ConstitutionBuyIn -PagePath $ConstitutionPage
}

if (-not $BuyIn) {
  $BuyIn = "Not supplied"
}

if (-not $WinningsText) {
  $WinningsText = Get-ConstitutionWinningsText -PagePath $ConstitutionPage -League $record
}

if (-not $WinningsText) {
  $WinningsText = "Not supplied"
}

$hasPaidCount = $PSBoundParameters.ContainsKey("PaidCount") -and $null -ne $PaidCount

$paidText = if ($hasPaidCount) {
  "Paid: $PaidCount/$($snapshot.teams)"
} else {
  "Paid: not supplied"
}

$contentLines = @(
  "**VBP League Status**",
  "",
  "**$DisplayName**",
  "Buy-in: $BuyIn",
  "Winnings: $WinningsText",
  "Assigned: $($snapshot.assigned)/$($snapshot.teams)",
  $paidText,
  "Open spots: $($snapshot.openSpots)",
  "Join: $JoinUrl",
  "Sleeper status: $(Format-StatusLabel $snapshot.sleeperStatus)",
  "Updated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))"
)

$message = ($contentLines -join "`n")
$payload = @{
  content = $message
} | ConvertTo-Json -Depth 4

$result = [pscustomobject]@{
  displayName = $DisplayName
  sleeperLeagueId = $SleeperLeagueId
  assigned = $snapshot.assigned
  teams = $snapshot.teams
  openSpots = $snapshot.openSpots
  paid = if ($hasPaidCount) { $PaidCount } else { $null }
  joinUrl = $JoinUrl
  constitutionPage = $ConstitutionPage
  buyIn = $BuyIn
  winnings = $WinningsText
  dryRun = [bool]$DryRun
  message = $message
}

if (-not $DryRun) {
  if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
    throw "Set DISCORD_WEBHOOK_URL or pass -WebhookUrl before posting to Discord."
  }

  Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType "application/json" -Body $payload | Out-Null
}

if ($PassThru) {
  $result
} else {
  Write-Host $message
  if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run only. Set DISCORD_WEBHOOK_URL to post this into Discord."
  } else {
    Write-Host ""
    Write-Host "Posted league status to Discord."
  }
}
