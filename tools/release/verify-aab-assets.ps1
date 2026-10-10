param([Parameter(Mandatory = $true)][string]$BundlePath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $BundlePath))
try {
    $prefix = 'base/assets/flutter_assets/'
    $entry = $archive.GetEntry($prefix + 'FontManifest.json')
    if ($null -eq $entry -or $entry.Length -eq 0) { throw 'AAB FontManifest.json is missing or empty.' }
    $reader = [System.IO.StreamReader]::new($entry.Open())
    try { $fonts = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if (@($fonts | Where-Object { $_.family -eq 'MaterialIcons' }).Count -ne 1) {
        throw 'AAB must register the MaterialIcons font exactly once.'
    }
    foreach ($family in $fonts) {
        foreach ($font in $family.fonts) {
            $asset = $archive.GetEntry($prefix + $font.asset)
            if ($null -eq $asset -or $asset.Length -eq 0) { throw "AAB font asset is missing or empty: $($family.family)" }
        }
    }
    foreach ($name in @('AssetManifest.bin', 'NOTICES.Z')) {
        $asset = $archive.GetEntry($prefix + $name)
        if ($null -eq $asset -or $asset.Length -eq 0) { throw "AAB asset is missing or empty: $name" }
    }
    Write-Host 'AAB font registrations, font assets, asset manifest and license notices verified.'
} finally { $archive.Dispose() }
