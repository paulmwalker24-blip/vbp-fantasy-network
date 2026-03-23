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

function Get-PythonExecutable {
  $candidatePaths = [System.Collections.Generic.List[string]]::new()

  foreach ($pattern in @(
    (Join-Path $env:LOCALAPPDATA "Python\pythoncore-*\python.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Python\Python*\python.exe")
  )) {
    Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      ForEach-Object {
        if ($_.FullName -notlike "*\WindowsApps\*") {
          $candidatePaths.Add($_.FullName) | Out-Null
        }
      }
  }

  foreach ($commandName in @("python", "py")) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($command -and $command.Path -and $command.Path -notlike "*\WindowsApps\*") {
      $candidatePaths.Add($command.Path) | Out-Null
    }
  }

  $pythonPath = $candidatePaths |
    Select-Object -Unique |
    Select-Object -First 1

  if (-not $pythonPath) {
    throw "Could not find a usable local Python interpreter. Install Python or disable the Windows Store app alias for py/python."
  }

  return $pythonPath
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
  $pythonExecutable = Get-PythonExecutable
  Start-Process -FilePath $pythonExecutable -ArgumentList "-m", "http.server", "$Port" -WorkingDirectory $repoRoot | Out-Null
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
