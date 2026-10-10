$ErrorActionPreference = 'Stop'
$db = 'supabase_db_k-youtube'
$state = & docker inspect --type container --format '{{.Name}}|{{.State.Running}}' $db
if ($LASTEXITCODE -ne 0 -or $state.Trim() -ne '/supabase_db_k-youtube|true') { throw 'Expected local DB is not running.' }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sql = 'BEGIN; SET LOCAL ROLE postgres;' + [Environment]::NewLine
foreach ($path in @('supabase/migrations/0036_operations_observability.sql','supabase/migrations/0040_operations_alerts.sql','supabase/migrations/0041_operations_safeupdate.sql','tools/test/ops_alert_contract.sql')) {
    $sql += (Get-Content -LiteralPath (Join-Path $root $path) -Raw) + [Environment]::NewLine
}
$sql += 'ROLLBACK;'
$sql | & docker exec -i $db psql -X -q -v ON_ERROR_STOP=1 -U supabase_admin -d postgres
if ($LASTEXITCODE -ne 0) { throw 'Ops alerts contract failed; connection closure rolls back.' }
