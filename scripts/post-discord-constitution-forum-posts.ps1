param(
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "constitution-forum-posts",
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK_URL,
  [switch]$DryRun,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ObjectPropertyValue {
  param([AllowNull()][object]$InputObject, [string]$Name)
  if ($null -eq $InputObject) { return $null }
  $property = $InputObject.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}

function Get-StateRoot {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  return [pscustomobject]@{}
}

function Get-PostState {
  param([object]$StateRoot, [string]$Key, [string]$Slug)
  $group = Get-ObjectPropertyValue -InputObject $StateRoot -Name $Key
  return Get-ObjectPropertyValue -InputObject $group -Name $Slug
}

function Save-PostState {
  param(
    [string]$Path,
    [string]$Key,
    [string]$Slug,
    [string]$MessageId,
    [string]$ThreadId
  )

  $state = Get-StateRoot -Path $Path
  $group = Get-ObjectPropertyValue -InputObject $state -Name $Key
  if ($null -eq $group) {
    $group = [pscustomobject]@{}
    if ($state.PSObject.Properties[$Key]) { $state.$Key = $group } else { $state | Add-Member -NotePropertyName $Key -NotePropertyValue $group }
  }

  $entry = [pscustomobject]@{
    messageId = $MessageId
    threadId = $ThreadId
    updatedAt = (Get-Date).ToString("s")
  }

  if ($group.PSObject.Properties[$Slug]) { $group.$Slug = $entry } else { $group | Add-Member -NotePropertyName $Slug -NotePropertyValue $entry }

  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
  }
  $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path
}

function New-ConstitutionPost {
  param(
    [string]$Slug,
    [string]$Title,
    [string]$Path,
    [string]$Category,
    [string]$Summary,
    [string[]]$Highlights,
    [int]$Color,
    [string]$Image,
    [string]$BaseUrl
  )

  [pscustomobject]@{
    slug = $Slug
    title = $Title
    threadName = $Title
    path = $Path
    category = $Category
    summary = $Summary
    highlights = $Highlights
    color = $Color
    imageUrl = if ($Image) { ("{0}/assets/images/{1}" -f $BaseUrl.TrimEnd('/'), $Image) } else { "" }
    url = ("{0}/{1}" -f $BaseUrl.TrimEnd('/'), $Path)
  }
}

function New-Payload {
  param([object]$Post)

  $highlightLines = @($Post.highlights | ForEach-Object { "- $_" })
  $description = @(
    $Post.summary,
    "",
    "**Official Constitution**",
    $Post.url,
    "",
    "**Key Areas Covered**",
    ($highlightLines -join "`n"),
    "",
    "**Source of Truth**",
    "This constitution controls the format unless the commissioner posts an official correction."
  ) -join "`n"

  $embed = @{
    title = $Post.title
    url = $Post.url
    description = $description
    color = $Post.color
    footer = @{ text = ("{0} constitution" -f $Post.category) }
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
  }
  if ($Post.imageUrl) { $embed.thumbnail = @{ url = $Post.imageUrl } }

  @{
    content = ("Official VBP constitution for **{0}**." -f $Post.title)
    thread_name = $Post.threadName
    embeds = @($embed)
  }
}

$siteUrl = $AssetBaseUrl.TrimEnd('/')
$posts = @(
  New-ConstitutionPost -Slug "redraft" -Title "Redraft Constitution" -Path "redraft-constitution.html" -Category "Seasonal Redraft" -Summary "Standard seasonal redraft rules for VBP leagues." -Highlights @("scoring and roster settings", "draft and playoff structure", "payout and payment expectations") -Color 0xC0392B -Image "constitution-redraft.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "redraft-bracket" -Title "Redraft Bracket Constitution" -Path "bracket-constitution.html" -Category "Redraft Bracket" -Summary "Five-division redraft tournament rules with one combined playoff bracket." -Highlights @("division setup", "combined playoff qualification", "payout and bracket rules") -Color 0xC0392B -Image "constitution-redraft-bracket.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "32-team-redraft" -Title "32-Team Redraft Constitution" -Path "32-team-redraft-constitution.html" -Category "32-Team Redraft" -Summary "Deep 32-team redraft rules with expanded player scarcity and lineup decisions." -Highlights @("32-team roster structure", "lineup requirements", "draft and scoring rules") -Color 0x2F80ED -Image "constitution-32-team-redraft.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "co-manager-redraft" -Title "Co-Manager Redraft Constitution" -Path "co-manager-constitution.html" -Category "Co-Manager Redraft" -Summary "Redraft format where each team is managed by a small group." -Highlights @("2-3 co-managers per team", "superflex settings", "draft timing and payment expectations") -Color 0x27AE60 -Image "constitution-co-manager.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "sacrifice-redraft" -Title "Sacrifice Redraft Constitution" -Path "sacrifice-redraft-constitution.html" -Category "Sacrifice Redraft" -Summary "Experimental sacrifice-format redraft rules." -Highlights @("sacrifice format structure", "lineup and scoring rules", "commissioner clarification path") -Color 0xBB6BD9 -Image "constitution-sacrifice.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "dynasty" -Title "Dynasty Constitution" -Path "dynasty-constitution.html" -Category "Dynasty" -Summary "Standalone dynasty rules for long-term roster building." -Highlights @("startup and rookie draft rules", "future-pick payment obligations", "trade and roster management policy") -Color 0x9B51E0 -Image "constitution-dynasty.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "dynasty-bracket" -Title "Dynasty Bracket Constitution" -Path "dynasty-bracket-constitution.html" -Category "Dynasty Bracket" -Summary "Multi-division dynasty tournament format with a combined playoff path." -Highlights @("division setup", "combined playoff rules", "dynasty payment and trade policy") -Color 0x8E44AD -Image "constitution-dynasty-bracket.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "keeper" -Title "Keeper Constitution" -Path "keeper-constitution.html" -Category "Keeper" -Summary "Keeper league rules with escalating keeper cost and year tracking." -Highlights @("keeper costs and eligibility", "keeper-year rules", "future-pick and trade policy") -Color 0xF2C94C -Image "constitution-keeper.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "best-ball-union" -Title "Best Ball Union Constitution" -Path "bestball-constitution.html" -Category "Best Ball Union" -Summary "10-team best ball rooms connected by a Union-wide high-score race." -Highlights @("room payouts", "Union-wide high-score prize", "best ball roster and scoring settings") -Color 0x2F80ED -Image "constitution-bestball-union.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "best-ball-gauntlet" -Title "Best Ball Gauntlet Constitution" -Path "bestball-gauntlet-constitution.html" -Category "Best Ball Gauntlet" -Summary "24-team micro best ball gauntlet rules." -Highlights @("24-team format", "standings champion prize", "highest single-week scorer prize") -Color 0xF2994A -Image "constitution-bestball-gauntlet.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "chopped" -Title "Chopped Constitution" -Path "chopped-constitution.html" -Category "Chopped" -Summary "Weekly elimination redraft format." -Highlights @("elimination schedule", "lineup and scoring rules", "tiebreakers and commissioner handling") -Color 0xEB5757 -Image "constitution-chopped.png" -BaseUrl $siteUrl
  New-ConstitutionPost -Slug "pickem" -Title "Pick'em Constitution" -Path "pickem-constitution.html" -Category "Pick'em" -Summary "Spread-based NFL Pick'em contest rules." -Highlights @("spread-based picks", "weekly and season scoring", "tiebreaker and payment rules") -Color 0x56CCF2 -Image "constitution-pickem.png" -BaseUrl $siteUrl
)

$stateRoot = Get-StateRoot -Path $StatePath
$results = foreach ($post in $posts) {
  $payloadObject = New-Payload -Post $post
  $payload = $payloadObject | ConvertTo-Json -Depth 8
  $postResult = [pscustomobject]@{
    slug = $post.slug
    title = $post.title
    messageId = $null
    threadId = $null
    action = if ($DryRun) { "dry-run" } else { "pending" }
  }

  if (-not $DryRun) {
    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { throw "Set DISCORD_WEBHOOK_URL or pass -WebhookUrl before posting to Discord." }

    $existing = Get-PostState -StateRoot $stateRoot -Key $StateKey -Slug $post.slug
    $existingMessageId = if ($existing) { [string]$existing.messageId } else { "" }
    $existingThreadId = if ($existing) { [string]$existing.threadId } else { "" }

    if (-not [string]::IsNullOrWhiteSpace($existingMessageId)) {
      try {
        $patchUrl = if ([string]::IsNullOrWhiteSpace($existingThreadId)) {
          ("{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $existingMessageId)
        } else {
          ("{0}/messages/{1}?thread_id={2}" -f $WebhookUrl.TrimEnd('/'), $existingMessageId, $existingThreadId)
        }
        Invoke-RestMethod -Uri $patchUrl -Method Patch -ContentType "application/json" -Body $payload | Out-Null
        $postResult.messageId = $existingMessageId
        $postResult.threadId = $existingThreadId
        $postResult.action = "updated"
      } catch {
        Write-Warning ("Could not update {0}; posting a new forum post instead. {1}" -f $post.title, $_.Exception.Message)
      }
    }

    if ([string]::IsNullOrWhiteSpace([string]$postResult.messageId)) {
      $postResponse = Invoke-RestMethod -Uri ("{0}?wait=true" -f $WebhookUrl) -Method Post -ContentType "application/json" -Body $payload
      $newMessageId = [string]$postResponse.id
      $newThreadId = [string]$postResponse.channel_id
      if ([string]::IsNullOrWhiteSpace($newMessageId)) { throw "Discord did not return a message ID for $($post.title)." }
      Save-PostState -Path $StatePath -Key $StateKey -Slug $post.slug -MessageId $newMessageId -ThreadId $newThreadId
      $stateRoot = Get-StateRoot -Path $StatePath
      $postResult.messageId = $newMessageId
      $postResult.threadId = $newThreadId
      $postResult.action = "created"
    } else {
      Save-PostState -Path $StatePath -Key $StateKey -Slug $post.slug -MessageId ([string]$postResult.messageId) -ThreadId ([string]$postResult.threadId)
      $stateRoot = Get-StateRoot -Path $StatePath
    }
  }

  $postResult
}

$result = [pscustomobject]@{
  postCount = @($posts).Count
  dryRun = [bool]$DryRun
  statePath = $StatePath
  stateKey = $StateKey
  posts = @($results)
}

if ($PassThru) {
  $result
} else {
  if ($DryRun) {
    Write-Host ("Dry run only. {0} constitution forum posts would be created or updated." -f @($posts).Count)
  } else {
    Write-Host ("Discord constitution forum posts complete: {0} posts processed." -f @($posts).Count)
  }
}
