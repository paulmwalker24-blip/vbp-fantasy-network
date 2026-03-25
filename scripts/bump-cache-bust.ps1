[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$IndexPath = "index.html",
  [string]$Version = (Get-Date).ToString("yyyyMMddHHmmss"),
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $IndexPath)) {
  throw "Could not find index file at '$IndexPath'."
}

$resolvedPath = (Resolve-Path -LiteralPath $IndexPath).Path
$content = Get-Content -LiteralPath $resolvedPath -Raw

$stylesMatch = [regex]::Match($content, 'assets/css/styles\.css\?v=([^"]+)')
if (-not $stylesMatch.Success) {
  throw "Could not find an assets/css/styles.css cache-busting query string in '$IndexPath'."
}

$appMatch = [regex]::Match($content, 'assets/js/app\.js\?v=([^"]+)')
if (-not $appMatch.Success) {
  throw "Could not find an assets/js/app.js cache-busting query string in '$IndexPath'."
}

$updatedContent = $content
$updatedContent = [regex]::Replace($updatedContent, 'assets/css/styles\.css\?v=[^"]+', "assets/css/styles.css?v=$Version", 1)
$updatedContent = [regex]::Replace($updatedContent, 'assets/js/app\.js\?v=[^"]+', "assets/js/app.js?v=$Version", 1)

$changed = $updatedContent -ne $content
$updated = $false

if ($changed -and $PSCmdlet.ShouldProcess($resolvedPath, ("Set cache-busting version to '{0}'" -f $Version))) {
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($resolvedPath, $updatedContent, $utf8NoBom)
  $updated = $true
}

$result = [pscustomobject]@{
  indexPath = $IndexPath
  version = $Version
  previousStylesVersion = $stylesMatch.Groups[1].Value
  previousAppVersion = $appMatch.Groups[1].Value
  changed = $changed
  updated = $updated
}

if ($PassThru) {
  $result
} elseif (-not $changed) {
  Write-Host ("Cache-busting already uses version {0} in {1}" -f $Version, $IndexPath)
} elseif ($updated) {
  Write-Host ("Updated cache-busting version to {0} in {1}" -f $Version, $IndexPath)
} else {
  Write-Host ("Previewed cache-busting update to {0} in {1}" -f $Version, $IndexPath)
}
