param(
  [Parameter(Mandatory = $true)]
  [string]$Format,

  [string]$JsonPath = "data/leagues.json",

  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$prefixByFormat = @{
  redraft = "RD"
  dynasty = "DYN"
  bestball = "BBU"
  bracket = "RDB"
  keeper = "KP"
  chopped = "CH"
}

function Normalize-Format {
  param(
    [string]$Value
  )

  $normalized = ($Value -replace '\s+', '').Trim().ToLowerInvariant()

  switch ($normalized) {
    "redraft" { return "redraft" }
    "dynasty" { return "dynasty" }
    "bestball" { return "bestball" }
    "bestballunion" { return "bestball" }
    "bracket" { return "bracket" }
    "bracketredraft" { return "bracket" }
    "keeper" { return "keeper" }
    "chopped" { return "chopped" }
    default { throw "Unsupported format '$Value'." }
  }
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find league data file at '$JsonPath'."
}

$normalizedFormat = Normalize-Format -Value $Format
$prefix = $prefixByFormat[$normalizedFormat]
$payload = Get-Content -LiteralPath (Resolve-Path -LiteralPath $JsonPath).Path -Raw | ConvertFrom-Json

if (-not $payload.leagues) {
  throw "The JSON file at '$JsonPath' does not contain a 'leagues' array."
}

$maxSuffix = 0
foreach ($league in $payload.leagues) {
  $id = [string]$league.id
  if ($id -match ("^{0}(\d+)$" -f [regex]::Escape($prefix))) {
    $suffix = [int]$matches[1]
    if ($suffix -gt $maxSuffix) {
      $maxSuffix = $suffix
    }
  }
}

$nextNumber = $maxSuffix + 1
$suggestedId = "{0}{1}" -f $prefix, $nextNumber

$result = [pscustomobject]@{
  format = $normalizedFormat
  prefix = $prefix
  nextNumber = $nextNumber
  suggestedId = $suggestedId
  jsonPath = $JsonPath
}

if ($PassThru) {
  $result
} else {
  Write-Host ("Next {0} league ID: {1}" -f $normalizedFormat, $suggestedId)
}
