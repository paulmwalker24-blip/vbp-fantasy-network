param(
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "constitution-index",
  [string]$ThreadName = "League Constitutions",
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

function Get-DiscordMessageState {
  param([string]$Path, [string]$Key)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  return Get-ObjectPropertyValue -InputObject $state -Name $Key
}

function Save-DiscordMessageState {
  param(
    [string]$Path,
    [string]$Key,
    [string]$MessageId,
    [string]$ThreadId
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
    threadId = $ThreadId
    updatedAt = (Get-Date).ToString("s")
  }

  if ($state.PSObject.Properties[$Key]) { $state.$Key = $entry } else { $state | Add-Member -NotePropertyName $Key -NotePropertyValue $entry }
  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path
}

function New-LinkLine {
  param(
    [string]$Label,
    [string]$Path,
    [string]$Description,
    [string]$BaseUrl
  )

  return ("- **[{0}]({1}/{2})** - {3}" -f $Label, $BaseUrl.TrimEnd('/'), $Path, $Description)
}

$siteUrl = $AssetBaseUrl.TrimEnd('/')
$timestamp = (Get-Date).ToUniversalTime().ToString("o")

$overviewDescription = @(
  "This thread is the constitution index for VBP Fantasy Network leagues.",
  "",
  "Each league is governed by its posted constitution. If recruiting copy, Discord discussion, or a status board conflicts with a constitution, the constitution controls unless the commissioner posts an official correction.",
  "",
  "**Website:** $siteUrl/"
) -join "`n"

$seasonalDescription = @(
  (New-LinkLine -Label "Redraft" -Path "redraft-constitution.html" -Description "standard seasonal redraft rules" -BaseUrl $siteUrl),
  (New-LinkLine -Label "Redraft Bracket" -Path "bracket-constitution.html" -Description "five-division bracket tournament rules" -BaseUrl $siteUrl),
  (New-LinkLine -Label "32-Team Redraft" -Path "32-team-redraft-constitution.html" -Description "deep 32-team redraft format" -BaseUrl $siteUrl),
  (New-LinkLine -Label "Co-Manager Redraft" -Path "co-manager-constitution.html" -Description "2-3 managers per team with superflex settings" -BaseUrl $siteUrl),
  (New-LinkLine -Label "Sacrifice Redraft" -Path "sacrifice-redraft-constitution.html" -Description "experimental sacrifice-format rules" -BaseUrl $siteUrl)
) -join "`n"

$dynastyDescription = @(
  (New-LinkLine -Label "Dynasty" -Path "dynasty-constitution.html" -Description "standalone dynasty rules and future-pick policy" -BaseUrl $siteUrl),
  (New-LinkLine -Label "Dynasty Bracket" -Path "dynasty-bracket-constitution.html" -Description "multi-division dynasty bracket rules" -BaseUrl $siteUrl),
  (New-LinkLine -Label "Keeper" -Path "keeper-constitution.html" -Description "keeper costs, keeper years, and trade rules" -BaseUrl $siteUrl)
) -join "`n"

$specialDescription = @(
  (New-LinkLine -Label "Best Ball Union" -Path "bestball-constitution.html" -Description "10-team rooms plus Union-wide high-score race" -BaseUrl $siteUrl),
  (New-LinkLine -Label "Best Ball Gauntlet" -Path "bestball-gauntlet-constitution.html" -Description "24-team micro best ball gauntlet" -BaseUrl $siteUrl),
  (New-LinkLine -Label "Chopped" -Path "chopped-constitution.html" -Description "weekly elimination redraft format" -BaseUrl $siteUrl),
  (New-LinkLine -Label "Pick'em" -Path "pickem-constitution.html" -Description "spread-based NFL Pick'em contest" -BaseUrl $siteUrl)
) -join "`n"

$usageDescription = @(
  "**Before Joining**",
  "Read the constitution for the exact format you are joining, including scoring, payouts, draft timing, playoff structure, and payment expectations.",
  "",
  "**After Joining**",
  "Use the matching league status channel for openings, paid counts, assigned spots, and current recruiting details.",
  "",
  "**Questions**",
  "Ask in the relevant league channel or message the commissioner if the question involves payment, disputes, or private manager details."
) -join "`n"

$payloadObject = @{
  content = "Start here for every VBP league constitution. Each link below opens the official rules page for that format."
  thread_name = $ThreadName
  embeds = @(
    @{
      title = "VBP League Constitutions"
      url = "$siteUrl/"
      description = $overviewDescription
      color = 0x5865F2
      thumbnail = @{ url = "$siteUrl/assets/images/sleeper-thumbnail-general.png" }
      footer = @{ text = "Constitution index" }
      timestamp = $timestamp
    },
    @{
      title = "Seasonal and Redraft Formats"
      description = $seasonalDescription
      color = 0xC0392B
      footer = @{ text = "Redraft, bracket, co-manager, 32-team, and sacrifice formats" }
      timestamp = $timestamp
    },
    @{
      title = "Dynasty and Keeper Formats"
      description = $dynastyDescription
      color = 0x9B51E0
      footer = @{ text = "Long-term roster formats" }
      timestamp = $timestamp
    },
    @{
      title = "Best Ball, Chopped, and Pick'em"
      description = $specialDescription
      color = 0xF2994A
      footer = @{ text = "Specialty formats" }
      timestamp = $timestamp
    },
    @{
      title = "How To Use These Rules"
      description = $usageDescription
      color = 0x27AE60
      footer = @{ text = "Constitutions are the source of truth" }
      timestamp = $timestamp
    }
  )
}

$payload = $payloadObject | ConvertTo-Json -Depth 8
$result = [pscustomobject]@{
  threadName = $ThreadName
  embeds = @($payloadObject.embeds)
  dryRun = [bool]$DryRun
  statePath = $StatePath
  stateKey = $StateKey
  messageId = $null
  threadId = $null
  action = if ($DryRun) { "dry-run" } else { "pending" }
}

if (-not $DryRun) {
  if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { throw "Set DISCORD_WEBHOOK_URL or pass -WebhookUrl before posting to Discord." }

  $existingState = Get-DiscordMessageState -Path $StatePath -Key $StateKey
  $existingMessageId = if ($existingState) { [string]$existingState.messageId } else { "" }
  $existingThreadId = if ($existingState) { [string]$existingState.threadId } else { "" }

  if (-not [string]::IsNullOrWhiteSpace($existingMessageId)) {
    try {
      $patchUrl = if ([string]::IsNullOrWhiteSpace($existingThreadId)) {
        ("{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $existingMessageId)
      } else {
        ("{0}/messages/{1}?thread_id={2}" -f $WebhookUrl.TrimEnd('/'), $existingMessageId, $existingThreadId)
      }

      Invoke-RestMethod -Uri $patchUrl -Method Patch -ContentType "application/json" -Body $payload | Out-Null
      $result.messageId = $existingMessageId
      $result.threadId = $existingThreadId
      $result.action = "updated"
    } catch {
      Write-Warning ("Could not update stored Discord constitution message {0}; posting a new constitution thread/message instead. {1}" -f $existingMessageId, $_.Exception.Message)
    }
  }

  if ([string]::IsNullOrWhiteSpace([string]$result.messageId)) {
    $postResponse = Invoke-RestMethod -Uri ("{0}?wait=true" -f $WebhookUrl) -Method Post -ContentType "application/json" -Body $payload
    $newMessageId = [string]$postResponse.id
    $newThreadId = [string]$postResponse.channel_id
    if ([string]::IsNullOrWhiteSpace($newMessageId)) { throw "Discord did not return a message ID. Cannot save update state." }

    Save-DiscordMessageState -Path $StatePath -Key $StateKey -MessageId $newMessageId -ThreadId $newThreadId
    $result.messageId = $newMessageId
    $result.threadId = $newThreadId
    $result.action = "created"
  } else {
    Save-DiscordMessageState -Path $StatePath -Key $StateKey -MessageId ([string]$result.messageId) -ThreadId ([string]$result.threadId)
  }
}

if ($PassThru) {
  $result
} else {
  if ($DryRun) { Write-Host "Dry run only. Set DISCORD_WEBHOOK_URL or pass -WebhookUrl to post the constitution index into Discord." }
  else { Write-Host ("Discord constitution index {0}: message {1}, thread {2}" -f $result.action, $result.messageId, $result.threadId) }
}
