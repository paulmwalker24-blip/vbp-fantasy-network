param(
  [string]$AssetBaseUrl = "https://vbp-fantasy-network.vercel.app",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string]$StateKey = "server-rules",
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
  param([string]$Path, [string]$Key, [string]$MessageId)
  $state = [pscustomobject]@{}
  if (Test-Path -LiteralPath $Path) {
    $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } else {
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
      New-Item -ItemType Directory -Path $directory | Out-Null
    }
  }
  $entry = [pscustomobject]@{ messageId = $MessageId; updatedAt = (Get-Date).ToString("s") }
  if ($state.PSObject.Properties[$Key]) { $state.$Key = $entry } else { $state | Add-Member -NotePropertyName $Key -NotePropertyValue $entry }
  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path
}

$siteUrl = $AssetBaseUrl.TrimEnd('/')
$timestamp = (Get-Date).ToUniversalTime().ToString("o")

$welcomeDescription = @(
  "Welcome to the VBP Fantasy Network Discord.",
  "",
  "This server is for league recruiting, league status updates, rules access, payment coordination, and commissioner announcements. Keep the server useful, professional, and easy for managers to trust.",
  "",
  "**Website:** $siteUrl/"
) -join "`n"

$communityDescription = @(
  "**1. Be Respectful**",
  "Trash talk is fine. Personal attacks, harassment, hate speech, threats, slurs, or targeted pile-ons are not.",
  "",
  "**2. Keep League Channels Useful**",
  "Use the league-type channels for questions and interest tied to that format. Avoid spamming the same message across multiple channels.",
  "",
  "**3. No Scams, Spam, or Unapproved Promotion**",
  "Do not advertise outside leagues, paid services, gambling links, referral links, or unrelated servers without commissioner approval.",
  "",
  "**4. Protect Private Information**",
  "Do not post another manager's legal name, email, phone number, payment details, address, or private DMs without permission."
) -join "`n"

$leagueDescription = @(
  "**5. League Constitutions Control League Rules**",
  "Each league is governed by its posted constitution. If a Discord message and a constitution conflict, the constitution controls unless the commissioner announces an official correction.",
  "",
  "**6. Payments Must Be Verified**",
  "LeagueSafe or commissioner-approved payment tracking determines paid status. A Sleeper join alone does not guarantee a reserved or paid spot.",
  "",
  "**7. Assigned Spots Matter**",
  "Openings are based on assigned teams, draft slots, or format-specific tracking. Managers should not assume a league is full or open from raw member count alone.",
  "",
  "**8. Drafts, Trades, and Special Rules Follow the Format**",
  "Draft timing, keeper costs, future-pick payment obligations, bracket qualification, best ball payouts, chopped eliminations, and Pick'em scoring follow the relevant league constitution."
) -join "`n"

$integrityDescription = @(
  "**9. Competitive Integrity Comes First**",
  "No collusion, roster dumping, payment dodging, deliberate competitive imbalance, or bad-faith trade behavior. Commissioner review may apply when league integrity is at risk.",
  "",
  "**10. Commissioner Decisions**",
  "The commissioner may clarify rules, correct administrative mistakes, enforce payment requirements, reverse clear platform errors, or remove managers who harm the league or server.",
  "",
  "**11. Disputes and Questions**",
  "Ask questions calmly and with context. For sensitive issues, message the commissioner instead of turning the server into a public argument.",
  "",
  "**12. Keep It Fun**",
  "The goal is competitive fantasy football with clean operations and good people. Help keep the room worth joining."
) -join "`n"

$payloadObject = @{
  content = ""
  embeds = @(
    @{
      title = "VBP Fantasy Network Rules"
      url = "$siteUrl/"
      description = $welcomeDescription
      color = 0x5865F2
      thumbnail = @{ url = "$siteUrl/assets/images/sleeper-thumbnail-general.png" }
      footer = @{ text = "Server rules and league standards" }
      timestamp = $timestamp
    },
    @{
      title = "Discord Conduct"
      description = $communityDescription
      color = 0x2F80ED
      footer = @{ text = "Applies server-wide" }
      timestamp = $timestamp
    },
    @{
      title = "League Operations"
      description = $leagueDescription
      color = 0x27AE60
      footer = @{ text = "Constitutions remain the source of truth" }
      timestamp = $timestamp
    },
    @{
      title = "Integrity and Enforcement"
      description = $integrityDescription
      color = 0xC0392B
      footer = @{ text = "Commissioner review may apply" }
      timestamp = $timestamp
    }
  )
}

$payload = $payloadObject | ConvertTo-Json -Depth 8
$result = [pscustomobject]@{
  embeds = @($payloadObject.embeds)
  dryRun = [bool]$DryRun
  statePath = $StatePath
  stateKey = $StateKey
  messageId = $null
  action = if ($DryRun) { "dry-run" } else { "pending" }
}

if (-not $DryRun) {
  if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { throw "Set DISCORD_WEBHOOK_URL or pass -WebhookUrl before posting to Discord." }
  $existingState = Get-DiscordMessageState -Path $StatePath -Key $StateKey
  $existingMessageId = if ($existingState) { [string]$existingState.messageId } else { "" }
  if (-not [string]::IsNullOrWhiteSpace($existingMessageId)) {
    try {
      Invoke-RestMethod -Uri ("{0}/messages/{1}" -f $WebhookUrl.TrimEnd('/'), $existingMessageId) -Method Patch -ContentType "application/json" -Body $payload | Out-Null
      $result.messageId = $existingMessageId
      $result.action = "updated"
    } catch {
      Write-Warning ("Could not update stored Discord rules message {0}; posting a new rules message instead. {1}" -f $existingMessageId, $_.Exception.Message)
    }
  }
  if ([string]::IsNullOrWhiteSpace([string]$result.messageId)) {
    $postResponse = Invoke-RestMethod -Uri ("{0}?wait=true" -f $WebhookUrl) -Method Post -ContentType "application/json" -Body $payload
    $newMessageId = [string]$postResponse.id
    if ([string]::IsNullOrWhiteSpace($newMessageId)) { throw "Discord did not return a message ID. Cannot save update state." }
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
  if ($DryRun) { Write-Host "Dry run only. Set DISCORD_WEBHOOK_URL or pass -WebhookUrl to post the server rules into Discord." }
  else { Write-Host ("Discord server rules message {0}: {1}" -f $result.action, $result.messageId) }
}
