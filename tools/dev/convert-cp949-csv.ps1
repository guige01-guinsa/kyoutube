param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (([IO.Path]::GetFullPath($InputPath)) -eq ([IO.Path]::GetFullPath($OutputPath))) {
    throw 'Input and output paths must be different.'
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "Output already exists: $OutputPath"
}

$cp949 = [Text.Encoding]::GetEncoding(949)
$utf8Bom = [Text.UTF8Encoding]::new($true)
$source = [IO.File]::ReadAllText($InputPath, $cp949)
$header = ($source -split "`r?`n")[0]
if (($header -split ',').Count -lt 2) {
    throw 'The input does not appear to be a comma-separated CSV file.'
}
[IO.File]::WriteAllText($OutputPath, $source, $utf8Bom)
Write-Output "Created UTF-8 CSV: $OutputPath"
