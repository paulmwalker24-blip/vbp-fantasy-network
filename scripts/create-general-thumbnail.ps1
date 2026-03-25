param(
  [string]$OutputPath = "assets/images/sleeper-thumbnail-general.png",
  [int]$Size = 1080
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$outputFullPath = Join-Path $repoRoot $OutputPath

$assets = @{
  banner = Join-Path $repoRoot "assets\\images\\banner.png"
}

foreach ($asset in $assets.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $asset.Value)) {
    throw "Missing image asset: $($asset.Value)"
  }
}

function New-RoundedRectPath {
  param(
    [float]$X,
    [float]$Y,
    [float]$Width,
    [float]$Height,
    [float]$Radius
  )

  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $diameter = $Radius * 2

  $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
  $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
  $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
  $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
  $path.CloseFigure()
  return $path
}

function Draw-ContainedImage {
  param(
    [System.Drawing.Graphics]$Graphics,
    [System.Drawing.Image]$Image,
    [float]$X,
    [float]$Y,
    [float]$Width,
    [float]$Height
  )

  $scale = [math]::Min($Width / $Image.Width, $Height / $Image.Height)
  $drawWidth = $Image.Width * $scale
  $drawHeight = $Image.Height * $scale
  $drawX = $X + (($Width - $drawWidth) / 2)
  $drawY = $Y + (($Height - $drawHeight) / 2)

  $Graphics.DrawImage($Image, [float]$drawX, [float]$drawY, [float]$drawWidth, [float]$drawHeight)
}

function Draw-CoverImage {
  param(
    [System.Drawing.Graphics]$Graphics,
    [System.Drawing.Image]$Image,
    [float]$X,
    [float]$Y,
    [float]$Width,
    [float]$Height
  )

  $scale = [math]::Max($Width / $Image.Width, $Height / $Image.Height)
  $drawWidth = $Image.Width * $scale
  $drawHeight = $Image.Height * $scale
  $drawX = $X + (($Width - $drawWidth) / 2)
  $drawY = $Y + (($Height - $drawHeight) / 2)

  $Graphics.DrawImage($Image, [float]$drawX, [float]$drawY, [float]$drawWidth, [float]$drawHeight)
}

$bitmap = New-Object System.Drawing.Bitmap $Size, $Size
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

$backgroundRect = New-Object System.Drawing.Rectangle 0, 0, $Size, $Size
$bannerImage = [System.Drawing.Image]::FromFile($assets.banner)
Draw-CoverImage -Graphics $graphics -Image $bannerImage -X 0 -Y 0 -Width $Size -Height $Size

$overlayBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  $backgroundRect,
  [System.Drawing.Color]::FromArgb(185, 15, 23, 42),
  [System.Drawing.Color]::FromArgb(220, 15, 23, 42),
  90
)
$graphics.FillRectangle($overlayBrush, $backgroundRect)

$navyBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(15, 23, 42))
$whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$softWhiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(222, 235, 245, 255))
$blueBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(37, 99, 235))
$cardBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(232, 248, 253, 255))
$borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 211, 225, 239), 2)

$bannerCardPath = New-RoundedRectPath -X 74 -Y 72 -Width ($Size - 148) -Height 310 -Radius 38
$graphics.FillPath($whiteBrush, $bannerCardPath)
$graphics.DrawPath($borderPen, $bannerCardPath)

Draw-ContainedImage -Graphics $graphics -Image $bannerImage -X 110 -Y 112 -Width ($Size - 220) -Height 220

$titleFont = New-Object System.Drawing.Font("Arial", 54, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$subtitleFont = New-Object System.Drawing.Font("Arial", 24, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$chipFont = New-Object System.Drawing.Font("Arial", 18, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$footerFont = New-Object System.Drawing.Font("Arial", 20, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

$graphics.DrawString("VBP Fantasy", $titleFont, $whiteBrush, 74, 462)
$graphics.DrawString("Network", $titleFont, $whiteBrush, 74, 522)
$graphics.DrawString("Competitive fantasy football with clear rules, real leagues, and a community that gives back.", $subtitleFont, $softWhiteBrush, 78, 612)

$chipPath = New-RoundedRectPath -X 74 -Y 704 -Width 312 -Height 52 -Radius 18
$graphics.FillPath($blueBrush, $chipPath)
$graphics.DrawString("VBP Fantasy Network", $chipFont, $whiteBrush, 98, 718)

$bottomCardPath = New-RoundedRectPath -X 74 -Y 812 -Width ($Size - 148) -Height 168 -Radius 32
$graphics.FillPath($cardBrush, $bottomCardPath)
$graphics.DrawPath($borderPen, $bottomCardPath)
$graphics.DrawString("Redraft  •  Dynasty  •  Best Ball", $footerFont, $navyBrush, 126, 860)
$graphics.DrawString("Bracket  •  Chopped", $footerFont, $navyBrush, 310, 908)

$bitmap.Save($outputFullPath, [System.Drawing.Imaging.ImageFormat]::Png)

$bannerImage.Dispose()
$graphics.Dispose()
$bitmap.Dispose()
$overlayBrush.Dispose()
$navyBrush.Dispose()
$whiteBrush.Dispose()
$softWhiteBrush.Dispose()
$blueBrush.Dispose()
$cardBrush.Dispose()
$borderPen.Dispose()
$titleFont.Dispose()
$subtitleFont.Dispose()
$chipFont.Dispose()
$footerFont.Dispose()

Write-Host ("Created thumbnail: {0}" -f $outputFullPath)
