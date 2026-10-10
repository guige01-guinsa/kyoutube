param([Parameter(Mandatory = $true)][string]$BundlePath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $BundlePath))
try {
    $metadata = $archive.GetEntry('BUNDLE-METADATA/com.android.tools/r8.json')
    if ($null -eq $metadata -or $metadata.Length -eq 0) {
        throw 'AAB R8 metadata is missing or empty; release optimization must be enabled.'
    }
    $reader = [System.IO.StreamReader]::new($metadata.Open())
    try { $r8 = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if ($null -eq $r8 -or $r8 -isnot [pscustomobject] -or @($r8.PSObject.Properties).Count -eq 0) {
        throw 'AAB R8 metadata must be a nonempty JSON object.'
    }
    foreach ($flag in @('isObfuscationEnabled', 'isOptimizationsEnabled', 'isShrinkingEnabled')) {
        if ($r8.options.$flag -ne $true) { throw "AAB R8 option must be enabled: $flag" }
    }
    if ($r8.options.isDebugModeEnabled -ne $false) { throw 'AAB R8 must use release mode.' }
    $mapping = $archive.GetEntry('BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map')
    if ($null -eq $mapping -or $mapping.Length -eq 0) {
        throw 'AAB R8 mapping is missing or empty; preserve crash deobfuscation data.'
    }
    $dex = @($archive.Entries | Where-Object { $_.FullName -match '\.dex$' })
    if ($dex.Count -eq 0 -or @($dex | Where-Object { $_.Length -eq 0 }).Count -gt 0) {
        throw 'AAB DEX code is missing or empty.'
    }
    $bytes = ($dex | Measure-Object -Property Length -Sum).Sum
    Write-Host "AAB R8 metadata and mapping verified; uncompressed DEX bytes: $bytes. Play Console scores require separate confirmation."
} finally { $archive.Dispose() }
