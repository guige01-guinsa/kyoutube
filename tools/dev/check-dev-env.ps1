param([switch]$SkipPubGet)

$scriptPath = Join-Path $PSScriptRoot "bootstrap.ps1"
& $scriptPath -SkipPubGet:$SkipPubGet
