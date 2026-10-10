$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$db = 'supabase_db_k-youtube'
$state = & docker inspect --type container --format '{{.Name}}|{{.State.Running}}' $db
if ($LASTEXITCODE -ne 0 -or $state.Trim() -ne '/supabase_db_k-youtube|true') { throw 'Expected local DB unavailable' }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sql = "BEGIN; SET LOCAL ROLE postgres;" + [Environment]::NewLine
foreach ($relative in @('supabase/migrations/0059_supplier_catalog_procurement.sql','supabase/migrations/0060_public_supplier_listings.sql','.artifacts/public-supplier-seed.sql','tools/test/public_supplier_contract.sql')) {
 $sql += [Environment]::NewLine + (Get-Content -LiteralPath (Join-Path $root $relative) -Raw -Encoding UTF8)
}
$sql += [Environment]::NewLine + 'ROLLBACK;'
$sql | & docker exec -i $db psql -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -U supabase_admin -d postgres
if ($LASTEXITCODE -ne 0) { throw 'Public supplier contract failed; transaction rolls back' }
