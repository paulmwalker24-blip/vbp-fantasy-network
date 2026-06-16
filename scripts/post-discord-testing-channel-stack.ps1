param(
  [string]$WebhookConfigPath = "data/private/discord-webhooks.json",
  [string]$StatePath = "data/private/discord-message-state.json",
  [string[]]$Channels = @(),
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

function Invoke-PostScript {
  param(
    [string]$ScriptPath,
    [string]$WebhookUrl,
    [hashtable]$Arguments
  )

  $command = @("-ExecutionPolicy", "Bypass", "-File", $ScriptPath)
  foreach ($key in $Arguments.Keys) {
    $command += "-$key"
    $command += [string]$Arguments[$key]
  }
  $command += "-WebhookUrl"
  $command += $WebhookUrl
  if ($DryRun) { $command += "-DryRun" }

  & powershell @command
}

if (-not (Test-Path -LiteralPath $WebhookConfigPath)) {
  throw "Missing webhook config at '$WebhookConfigPath'. Copy data/private/discord-webhooks.example.json to that path and fill in the channel webhook URLs."
}

$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $WebhookConfigPath).Path -Raw | ConvertFrom-Json
$channelWebhooks = Get-ObjectPropertyValue -InputObject $config -Name "channels"
if ($null -eq $channelWebhooks) {
  throw "Webhook config must include a 'channels' object."
}

$stack = @(
  [pscustomobject]@{ channel = "32-team-redraft-testing"; guideKey = "redraft32"; statusScript = "scripts/post-discord-format-status.ps1"; statusArgs = @{ FormatKey = "redraft32" } },
  [pscustomobject]@{ channel = "best-ball-gauntlet-testing"; guideKey = "bbg"; statusScript = "scripts/post-discord-format-status.ps1"; statusArgs = @{ FormatKey = "bbg" } },
  [pscustomobject]@{ channel = "best-ball-union-testing"; guideKey = "bestball"; statusScript = "scripts/post-discord-bbu-status.ps1"; statusArgs = @{} },
  [pscustomobject]@{ channel = "chopped-testing"; guideKey = "chopped"; statusScript = "scripts/post-discord-format-status.ps1"; statusArgs = @{ FormatKey = "chopped" } },
  [pscustomobject]@{ channel = "co-manager-testing"; guideKey = "comanager"; statusScript = "scripts/post-discord-format-status.ps1"; statusArgs = @{ FormatKey = "comanager" } },
  [pscustomobject]@{ channel = "dynasty-bracket-testing"; guideKey = "dynastybracket"; statusScript = "scripts/post-discord-dynasty-bracket-status.ps1"; statusArgs = @{} },
  [pscustomobject]@{ channel = "dynasty-testing"; guideKey = "dynasty"; statusScript = "scripts/post-discord-format-status.ps1"; statusArgs = @{ FormatKey = "dynasty" } },
  [pscustomobject]@{ channel = "keeper-testing"; guideKey = "keeper"; statusScript = "scripts/post-discord-format-status.ps1"; statusArgs = @{ FormatKey = "keeper" } },
  [pscustomobject]@{ channel = "pickem-testing"; guideKey = "pickem"; statusScript = "scripts/post-discord-format-status.ps1"; statusArgs = @{ FormatKey = "pickem" } },
  [pscustomobject]@{ channel = "redraft-bracket-testing"; guideKey = "bracket"; statusScript = "scripts/post-discord-redraft-bracket-status.ps1"; statusArgs = @{} },
  [pscustomobject]@{ channel = "redraft-testing"; guideKey = "redraft"; statusScript = "scripts/post-discord-redraft-status.ps1"; statusArgs = @{} },
  [pscustomobject]@{ channel = "sacrifice-testing"; guideKey = "sacrifice"; statusScript = "scripts/post-discord-format-status.ps1"; statusArgs = @{ FormatKey = "sacrifice" } }
)

if ($Channels.Count -gt 0) {
  $wanted = @{}
  foreach ($channel in $Channels) { $wanted[$channel] = $true }
  $stack = @($stack | Where-Object { $wanted.ContainsKey($_.channel) })
}

$results = foreach ($item in $stack) {
  $webhookUrl = [string](Get-ObjectPropertyValue -InputObject $channelWebhooks -Name $item.channel)
  if ([string]::IsNullOrWhiteSpace($webhookUrl)) {
    [pscustomobject]@{
      channel = $item.channel
      guideKey = $item.guideKey
      status = "skipped"
      reason = "Missing webhook URL"
    }
    continue
  }

  Write-Host ("Posting guide for {0}..." -f $item.channel)
  Invoke-PostScript -ScriptPath "scripts/post-discord-format-guide.ps1" -WebhookUrl $webhookUrl -Arguments @{ FormatKey = $item.guideKey; StatePath = $StatePath }

  Write-Host ("Posting status board for {0}..." -f $item.channel)
  $statusArgs = @{} + $item.statusArgs
  $statusArgs.StatePath = $StatePath
  Invoke-PostScript -ScriptPath $item.statusScript -WebhookUrl $webhookUrl -Arguments $statusArgs

  [pscustomobject]@{
    channel = $item.channel
    guideKey = $item.guideKey
    status = if ($DryRun) { "dry-run" } else { "posted" }
    reason = ""
  }
}

if ($PassThru) {
  $results
} else {
  $posted = @($results | Where-Object { $_.status -ne "skipped" }).Count
  $skipped = @($results | Where-Object { $_.status -eq "skipped" }).Count
  Write-Host ("Testing channel stack complete. Processed: {0}; skipped: {1}." -f $posted, $skipped)
}
