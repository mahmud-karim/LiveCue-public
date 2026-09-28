param([Parameter(Mandatory=$true)][string]$Source)
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$image = [Drawing.Image]::FromFile($Source)
$bitmap = New-Object Drawing.Bitmap 1024,1024
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.DrawImage($image, 0, 0, 1024, 1024)
    $bitmap.Save((Join-Path $root 'Sources/LiveCue/Assets.xcassets/AppIcon.appiconset/AppIcon.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $graphics.Dispose(); $bitmap.Dispose(); $image.Dispose() }
