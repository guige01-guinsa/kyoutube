param(
    [string]$Source = "assets/branding/recipe-scout-icon-v5-peek.png"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $projectRoot
Add-Type -AssemblyName System.Drawing

# Resize the approved artwork without redrawing the mascot. Keep the original
# concept and earlier variants; only the canonical platform exports are replaced.
$sourceImage = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Source).Path)
$background = $sourceImage.GetPixel(0, 0)
$exportCount = 0

function Export-Icon {
    param([string]$Path, [int]$Size, [double]$ContentScale = 1)

    $destination = Join-Path $projectRoot $Path
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    # Google Play requires RGBA PNG; alpha stays fully opaque. iOS app icons
    # must have no alpha channel, so all native exports remain RGB.
    $pixelFormat = if ($Path -eq "store-assets/recipe-scout-play-icon-512.png") {
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    } else {
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    }
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, $pixelFormat)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear($background)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $contentSize = [int][Math]::Round($Size * $ContentScale)
        $offset = [int][Math]::Round(($Size - $contentSize) / 2)
        $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
        try {
            $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
            $rectangle = [System.Drawing.Rectangle]::new($offset, $offset, $contentSize, $contentSize)
            $graphics.DrawImage($sourceImage, $rectangle, 0, 0, $sourceImage.Width, $sourceImage.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        }
        finally { $attributes.Dispose() }
        $bitmap.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png)
        $script:exportCount++
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    if ($sourceImage.Width -ne $sourceImage.Height) { throw "The approved icon must be square." }
    Export-Icon "assets/branding/recipe-scout-icon.png" 1024
    Export-Icon "store-assets/recipe-scout-play-icon-512.png" 512

    $densities = @(
        @{ Name = "mdpi"; Scale = 1 },
        @{ Name = "hdpi"; Scale = 1.5 },
        @{ Name = "xhdpi"; Scale = 2 },
        @{ Name = "xxhdpi"; Scale = 3 },
        @{ Name = "xxxhdpi"; Scale = 4 }
    )
    foreach ($density in $densities) {
        $res = "android/app/src/main/res"
        Export-Icon "$res/mipmap-$($density.Name)/ic_launcher.png" ([int](48 * $density.Scale))
        # 108 dp adaptive layer with the original square occupying the central
        # 72 dp viewport. The mascot stays within Android's 66 dp safe circle.
        Export-Icon "$res/mipmap-$($density.Name)/ic_launcher_foreground.png" ([int](108 * $density.Scale)) (72.0 / 108)
        Export-Icon "$res/drawable-$($density.Name)/launch_image.png" ([int](160 * $density.Scale))
    }

    $appIconRoot = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    $catalog = Get-Content "$appIconRoot/Contents.json" -Raw | ConvertFrom-Json
    foreach ($entry in ($catalog.images | Sort-Object filename -Unique)) {
        $points = [double]::Parse(($entry.size -split "x")[0], [Globalization.CultureInfo]::InvariantCulture)
        $scale = [int]($entry.scale -replace "x", "")
        Export-Icon "$appIconRoot/$($entry.filename)" ([int][Math]::Round($points * $scale))
    }
    $launchRoot = "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    $launchCatalog = Get-Content "$launchRoot/Contents.json" -Raw | ConvertFrom-Json
    foreach ($entry in $launchCatalog.images) {
        $scale = [int]($entry.scale -replace "x", "")
        Export-Icon "$launchRoot/$($entry.filename)" (160 * $scale)
    }
    Write-Output "Exported $exportCount platform and brand images from the approved peeking chef."
    Write-Output ("Native background: #{0:X2}{1:X2}{2:X2}" -f $background.R, $background.G, $background.B)
}
finally { $sourceImage.Dispose() }
