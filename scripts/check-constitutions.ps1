param(
  [string[]]$Pages,
  [switch]$PassThru,
  [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$issues = [System.Collections.Generic.List[object]]::new()
$regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline

function Add-Issue {
  param(
    [string]$Severity,
    [string]$Source,
    [string]$Message
  )

  $issues.Add([pscustomobject]@{
    severity = $Severity
    source = $Source
    message = $Message
  }) | Out-Null
}

if ($Pages -and $Pages.Count -gt 0) {
  $constitutionPages = $Pages
} else {
  $constitutionPages = Get-ChildItem -LiteralPath $repoRoot -Filter "*-constitution.html" |
    Sort-Object Name |
    Select-Object -ExpandProperty Name
}

if (-not $constitutionPages -or $constitutionPages.Count -eq 0) {
  throw "No constitution pages were found to check."
}

foreach ($page in $constitutionPages) {
  $pagePath = Join-Path $repoRoot $page
  if (-not (Test-Path -LiteralPath $pagePath)) {
    Add-Issue -Severity "error" -Source $page -Message "Constitution page file is missing."
    continue
  }

  $content = Get-Content -LiteralPath $pagePath -Raw

  if ($content -notmatch 'class="constitution-page"') {
    Add-Issue -Severity "warning" -Source $page -Message "Missing constitution-page body class."
  }

  if ($content -notmatch 'class="constitution-hero"') {
    Add-Issue -Severity "warning" -Source $page -Message "Missing constitution hero container."
  }

  if ($content -notmatch 'id="top"') {
    Add-Issue -Severity "error" -Source $page -Message "Missing top anchor target for back-to-top links."
  }

  $backLinkMatch = [regex]::Match(
    $content,
    '<a\b(?=[^>]*class="constitution-back-link")(?=[^>]*href="([^"]+)")[^>]*>(.*?)</a>',
    $regexOptions
  )

  if (-not $backLinkMatch.Success) {
    Add-Issue -Severity "error" -Source $page -Message "Missing Back to Hub link."
  } else {
    $backLinkHref = $backLinkMatch.Groups[1].Value.Trim()
    $backLinkText = [regex]::Replace($backLinkMatch.Groups[2].Value, '<[^>]+>', '').Trim()

    if ($backLinkHref -ne "index.html#constitutions") {
      Add-Issue -Severity "error" -Source $page -Message ("Back link points to '{0}' instead of 'index.html#constitutions'." -f $backLinkHref)
    }

    if ($backLinkText -ne "Back to Hub") {
      Add-Issue -Severity "warning" -Source $page -Message ("Back link text is '{0}' instead of 'Back to Hub'." -f $backLinkText)
    }
  }

  $bannerMatch = [regex]::Match(
    $content,
    '<img\b(?=[^>]*class="constitution-banner")(?=[^>]*src="([^"]+)")(?=[^>]*alt="([^"]+)")[^>]*>',
    $regexOptions
  )

  if (-not $bannerMatch.Success) {
    Add-Issue -Severity "error" -Source $page -Message "Missing constitution banner image."
  } else {
    $bannerSrc = $bannerMatch.Groups[1].Value.Trim()
    $bannerAlt = $bannerMatch.Groups[2].Value.Trim()
    $bannerPath = Join-Path $repoRoot $bannerSrc

    if (-not (Test-Path -LiteralPath $bannerPath)) {
      Add-Issue -Severity "error" -Source $page -Message ("Banner image file does not exist: {0}" -f $bannerSrc)
    }

    if ([string]::IsNullOrWhiteSpace($bannerAlt)) {
      Add-Issue -Severity "warning" -Source $page -Message "Banner image is missing alt text."
    }
  }

  if ($content -notmatch 'class="constitution-summary-card"') {
    Add-Issue -Severity "error" -Source $page -Message "Missing constitution summary card."
  }

  if ($content -notmatch 'class="constitution-toc"') {
    Add-Issue -Severity "error" -Source $page -Message "Missing constitution table of contents."
  }

  if ($content -notmatch '<h1>') {
    Add-Issue -Severity "warning" -Source $page -Message "Missing page h1."
  }

  $sectionMatches = [regex]::Matches(
    $content,
    '<section\b(?=[^>]*class="constitution-section-card")(?=[^>]*id="([^"]+)")[^>]*>',
    $regexOptions
  )

  if ($sectionMatches.Count -eq 0) {
    Add-Issue -Severity "error" -Source $page -Message "No constitution section cards with ids were found."
    continue
  }

  $sectionIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($match in $sectionMatches) {
    $sectionId = $match.Groups[1].Value.Trim()
    if (-not $sectionIds.Add($sectionId)) {
      Add-Issue -Severity "error" -Source $page -Message ("Duplicate constitution section id '{0}'." -f $sectionId)
    }
  }

  $tocLinkMatches = [regex]::Matches(
    $content,
    '<a\b(?=[^>]*class="constitution-toc-link")(?=[^>]*href="#([^"]+)")[^>]*>',
    $regexOptions
  )

  if ($tocLinkMatches.Count -eq 0) {
    Add-Issue -Severity "error" -Source $page -Message "No table-of-contents links were found."
  } else {
    foreach ($tocLink in $tocLinkMatches) {
      $targetId = $tocLink.Groups[1].Value.Trim()
      if (-not $sectionIds.Contains($targetId)) {
        Add-Issue -Severity "error" -Source $page -Message ("Table-of-contents link points to missing section id '{0}'." -f $targetId)
      }
    }
  }

  $jumpLinkMatches = [regex]::Matches(
    $content,
    '<a\b(?=[^>]*class="constitution-jump-link")(?=[^>]*href="#top")[^>]*>',
    $regexOptions
  )

  if ($jumpLinkMatches.Count -eq 0) {
    Add-Issue -Severity "error" -Source $page -Message "No Back to top jump links were found."
  } elseif ($jumpLinkMatches.Count -ne $sectionMatches.Count) {
    Add-Issue -Severity "warning" -Source $page -Message (
      "Found {0} Back to top links for {1} constitution sections." -f $jumpLinkMatches.Count, $sectionMatches.Count
    )
  }
}

$errorCount = @($issues | Where-Object { $_.severity -eq "error" }).Count
$warningCount = @($issues | Where-Object { $_.severity -eq "warning" }).Count
$report = [pscustomobject]@{
  checkedAt = (Get-Date).ToString("s")
  pageCount = @($constitutionPages).Count
  errorCount = $errorCount
  warningCount = $warningCount
  issues = @($issues)
}

if ($PassThru) {
  $report
} else {
  Write-Host ("Checked {0} constitution page(s): {1} error(s), {2} warning(s)" -f $report.pageCount, $errorCount, $warningCount)
  foreach ($issue in $issues) {
    Write-Host ("{0} [{1}] {2}" -f $issue.severity.ToUpperInvariant(), $issue.source, $issue.message)
  }
}

if ($Strict -and $errorCount -gt 0) {
  exit 1
}
