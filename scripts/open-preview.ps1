param(
  [string]$Target = "index.html",
  [int]$Port = 8000,
  [switch]$NoOpen,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetPath = Join-Path $repoRoot $Target

if (-not (Test-Path -LiteralPath $targetPath)) {
  throw "Could not find preview target '$Target'."
}

function Test-LocalServer {
  param(
    [int]$Port
  )

  try {
    $response = Invoke-WebRequest -UseBasicParsing ("http://localhost:{0}/" -f $Port) -TimeoutSec 2
    return $response.StatusCode -ge 200
  } catch {
    return $false
  }
}

if (-not (Test-LocalServer -Port $Port)) {
  Start-Process py -ArgumentList "-m", "http.server", "$Port" -WorkingDirectory $repoRoot | Out-Null
  Start-Sleep -Seconds 2
}

$cacheBust = (Get-Date).ToString("yyyyMMddHHmmss")
$targetUrl = "http://localhost:{0}/{1}?v={2}" -f $Port, $Target, $cacheBust

if (-not $NoOpen) {
  Start-Process chrome $targetUrl | Out-Null
}

if ($PassThru) {
  [pscustomobject]@{
    target = $Target
    port = $Port
    url = $targetUrl
  }
} else {
  Write-Host ("Opened preview: {0}" -f $targetUrl)
}
