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
  [System.Drawing.Color]::FromArgb(190, 15, 23, 42),
  [System.Drawing.Color]::FromArgb(232, 15, 23, 42),
  90
)
$graphics.FillRectangle($overlayBrush, $backgroundRect)

$navyBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(15, 23, 42))
$whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$softWhiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(222, 235, 245, 255))
$cardBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(228, 248, 253, 255))
$darkCardBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 10, 18, 34))
$borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 211, 225, 239), 2)
$dividerPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(150, 96, 165, 250), 3)

$bannerCardPath = New-RoundedRectPath -X 74 -Y 72 -Width ($Size - 148) -Height 312 -Radius 38
$graphics.FillPath($cardBrush, $bannerCardPath)
$graphics.DrawPath($borderPen, $bannerCardPath)
Draw-ContainedImage -Graphics $graphics -Image $bannerImage -X 102 -Y 112 -Width ($Size - 204) -Height 224

$titleFont = New-Object System.Drawing.Font("Arial", 58, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$subtitleFont = New-Object System.Drawing.Font("Arial", 25, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$labelFont = New-Object System.Drawing.Font("Arial", 20, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$footerFont = New-Object System.Drawing.Font("Arial", 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

$centerFormat = New-Object System.Drawing.StringFormat
$centerFormat.Alignment = [System.Drawing.StringAlignment]::Center
$centerFormat.LineAlignment = [System.Drawing.StringAlignment]::Near

$graphics.DrawString(
  "VBP Fantasy Network",
  $titleFont,
  $whiteBrush,
  (New-Object System.Drawing.RectangleF(74, 428, ($Size - 148), 76)),
  $centerFormat
)

$graphics.DrawString(
  "Competitive fantasy football with clear rules, live leagues, and public format centers.",
  $subtitleFont,
  $softWhiteBrush,
  (New-Object System.Drawing.RectangleF(118, 538, ($Size - 236), 86)),
  $centerFormat
)

$graphics.DrawLine($dividerPen, 206, 648, ($Size - 206), 648)

$bottomCardPath = New-RoundedRectPath -X 88 -Y 704 -Width ($Size - 176) -Height 196 -Radius 30
$graphics.FillPath($darkCardBrush, $bottomCardPath)
$graphics.DrawPath($borderPen, $bottomCardPath)

$graphics.DrawString(
  "Formats",
  $labelFont,
  $whiteBrush,
  (New-Object System.Drawing.RectangleF(120, 734, ($Size - 240), 36)),
  $centerFormat
)

$graphics.DrawString(
  "Redraft | Dynasty | Best Ball",
  $footerFont,
  $whiteBrush,
  (New-Object System.Drawing.RectangleF(120, 786, ($Size - 240), 34)),
  $centerFormat
)

$graphics.DrawString(
  "Bracket | Keeper | Chopped",
  $footerFont,
  $whiteBrush,
  (New-Object System.Drawing.RectangleF(120, 830, ($Size - 240), 34)),
  $centerFormat
)

$graphics.DrawString(
  "League Constitutions and Public Centers",
  $labelFont,
  $softWhiteBrush,
  (New-Object System.Drawing.RectangleF(120, 864, ($Size - 240), 32)),
  $centerFormat
)

$bitmap.Save($outputFullPath, [System.Drawing.Imaging.ImageFormat]::Png)

$bannerImage.Dispose()
$graphics.Dispose()
$bitmap.Dispose()
$overlayBrush.Dispose()
$navyBrush.Dispose()
$whiteBrush.Dispose()
$softWhiteBrush.Dispose()
$cardBrush.Dispose()
$darkCardBrush.Dispose()
$borderPen.Dispose()
$dividerPen.Dispose()
$titleFont.Dispose()
$subtitleFont.Dispose()
$labelFont.Dispose()
$footerFont.Dispose()
$centerFormat.Dispose()

Write-Host ("Created thumbnail: {0}" -f $outputFullPath)
