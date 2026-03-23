param(
  [string]$JsonPath = "data/donations.json",
  [switch]$CheckLinks,
  [switch]$PassThru,
  [switch]$Strict
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
    return [double]$parsed
  }

  return $null
}

function Test-HttpUrl {
  param(
    [AllowNull()]
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }

  $uri = $null
  return [System.Uri]::TryCreate($Value.Trim(), [System.UriKind]::Absolute, [ref]$uri) -and (
    $uri.Scheme -eq "http" -or $uri.Scheme -eq "https"
  )
}

function Add-Issue {
  param(
    [System.Collections.Generic.List[object]]$Issues,
    [string]$Severity,
    [string]$ProjectLabel,
    [string]$Message
  )

  $Issues.Add([pscustomobject]@{
    severity = $Severity
    project = $ProjectLabel
    message = $Message
  }) | Out-Null
}

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Could not find donation data file at '$JsonPath'."
}

$jsonFullPath = (Resolve-Path -LiteralPath $JsonPath).Path
$payload = Get-Content -LiteralPath $jsonFullPath -Raw | ConvertFrom-Json

if (-not $payload.projects) {
  throw "The JSON file at '$JsonPath' does not contain a 'projects' array."
}

$issues = [System.Collections.Generic.List[object]]::new()
$projects = @($payload.projects)
$seenSlotLabels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$seenLinks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if ($projects.Count -eq 0) {
  Add-Issue -Issues $issues -Severity "warning" -ProjectLabel "<all-projects>" -Message "No projects are currently listed."
}

for ($i = 0; $i -lt $projects.Count; $i += 1) {
  $project = $projects[$i]
  $projectLabel = [string]$project.name
  if ([string]::IsNullOrWhiteSpace($projectLabel)) {
    $projectLabel = "Project #{0}" -f ($i + 1)
  }

  $slot = ([string]$project.slot).Trim()
  $slotLabelRaw = [string]$project.slotLabel
  $name = ([string]$project.name).Trim()
  $state = ([string]$project.state).Trim()
  $link = ([string]$project.link).Trim()
  $goal = To-Number $project.goal
  $donated = To-Number $project.donated
  $remaining = if ($project.PSObject.Properties.Match('remaining').Count -gt 0) { To-Number $project.remaining } else { $null }

  if ([string]::IsNullOrWhiteSpace($slot)) {
    Add-Issue -Issues $issues -Severity "warning" -ProjectLabel $projectLabel -Message "Missing slot label."
  }

  $slotLabelNumber = 0
  if (-not [int]::TryParse($slotLabelRaw, [ref]$slotLabelNumber) -or $slotLabelNumber -le 0) {
    Add-Issue -Issues $issues -Severity "warning" -ProjectLabel $projectLabel -Message "slotLabel should be a positive integer."
  } elseif (-not $seenSlotLabels.Add([string]$slotLabelNumber)) {
    Add-Issue -Issues $issues -Severity "error" -ProjectLabel $projectLabel -Message ("Duplicate slotLabel '{0}'." -f $slotLabelNumber)
  }

  if ([string]::IsNullOrWhiteSpace($name)) {
    Add-Issue -Issues $issues -Severity "error" -ProjectLabel $projectLabel -Message "Missing project name."
  }

  if ([string]::IsNullOrWhiteSpace($state)) {
    Add-Issue -Issues $issues -Severity "error" -ProjectLabel $projectLabel -Message "Missing project state."
  }

  if ($null -eq $goal -or $goal -le 0) {
    Add-Issue -Issues $issues -Severity "error" -ProjectLabel $projectLabel -Message "goal must be a number greater than 0."
  }

  if ($null -eq $donated) {
    Add-Issue -Issues $issues -Severity "error" -ProjectLabel $projectLabel -Message "donated must be numeric."
  } elseif ($donated -lt 0) {
    Add-Issue -Issues $issues -Severity "error" -ProjectLabel $projectLabel -Message "donated cannot be negative."
  }

  if ($null -eq $remaining) {
    Add-Issue -Issues $issues -Severity "warning" -ProjectLabel $projectLabel -Message "remaining is missing or not numeric."
  } elseif ($remaining -lt 0) {
    Add-Issue -Issues $issues -Severity "error" -ProjectLabel $projectLabel -Message "remaining cannot be negative."
  }

  if ($goal -is [double] -and $remaining -is [double] -and $remaining -gt $goal) {
    Add-Issue -Issues $issues -Severity "warning" -ProjectLabel $projectLabel -Message "remaining is greater than goal."
  }

  if ($goal -is [double] -and $donated -is [double] -and $donated -gt $goal) {
    Add-Issue -Issues $issues -Severity "warning" -ProjectLabel $projectLabel -Message "donated is greater than goal."
  }

  if ([string]::IsNullOrWhiteSpace($link)) {
    Add-Issue -Issues $issues -Severity "error" -ProjectLabel $projectLabel -Message "Missing DonorsChoose link."
  } elseif (-not (Test-HttpUrl $link)) {
    Add-Issue -Issues $issues -Severity "error" -ProjectLabel $projectLabel -Message "link is not a valid http/https URL."
  } else {
    if (-not $seenLinks.Add($link)) {
      Add-Issue -Issues $issues -Severity "warning" -ProjectLabel $projectLabel -Message "Duplicate project link."
    }

    if ($link -notmatch 'donorschoose\.org') {
      Add-Issue -Issues $issues -Severity "warning" -ProjectLabel $projectLabel -Message "Project link is not on donorschoose.org."
    }

    if ($CheckLinks) {
      try {
        try {
          $response = Invoke-WebRequest -UseBasicParsing -Uri $link -Method Head -MaximumRedirection 5 -TimeoutSec 15
        } catch {
          $response = Invoke-WebRequest -UseBasicParsing -Uri $link -Method Get -MaximumRedirection 5 -TimeoutSec 15
        }

        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 400) {
          Add-Issue -Issues $issues -Severity "warning" -ProjectLabel $projectLabel -Message ("Link health check returned status {0}." -f $response.StatusCode)
        }
      } catch {
        Add-Issue -Issues $issues -Severity "warning" -ProjectLabel $projectLabel -Message ("Link health check failed: {0}" -f $_.Exception.Message)
      }
    }
  }
}

$errorCount = @($issues | Where-Object { $_.severity -eq "error" }).Count
$warningCount = @($issues | Where-Object { $_.severity -eq "warning" }).Count
$report = [pscustomobject]@{
  jsonPath = $JsonPath
  checkedAt = (Get-Date).ToString("s")
  projectCount = $projects.Count
  linkChecksEnabled = [bool]$CheckLinks
  errorCount = $errorCount
  warningCount = $warningCount
  issues = @($issues)
}

if ($PassThru) {
  $report
} else {
  Write-Host ("Checked {0} donation project(s): {1} error(s), {2} warning(s)" -f $report.projectCount, $errorCount, $warningCount)
  foreach ($issue in $issues) {
    Write-Host ("{0} {1}: {2}" -f $issue.severity.ToUpperInvariant(), $issue.project, $issue.message)
  }
}

if ($Strict -and $errorCount -gt 0) {
  exit 1
}
