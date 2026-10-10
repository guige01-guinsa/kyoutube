$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sources = Get-Content -LiteralPath (Join-Path $repo 'tools/data/ingredient-image-sources.json') -Raw | ConvertFrom-Json
$destination = Join-Path $repo 'assets/ingredients'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($entry in $sources) {
    $original = [System.Drawing.Image]::FromFile($entry.source)
    $thumbnail = [System.Drawing.Bitmap]::new(256, 256)
    $graphics = [System.Drawing.Graphics]::FromImage($thumbnail)
    try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($original, 0, 0, 256, 256)
        $thumbnail.Save((Join-Path $destination ($entry.id + '.jpg')), [System.Drawing.Imaging.ImageFormat]::Jpeg)
    } finally {
        $graphics.Dispose()
        $thumbnail.Dispose()
        $original.Dispose()
    }
}
Get-ChildItem -LiteralPath $destination -Filter '*.jpg' | Select-Object Name, Length
