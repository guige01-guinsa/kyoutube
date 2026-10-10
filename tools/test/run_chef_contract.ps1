$ErrorActionPreference = 'Stop'
$db = 'supabase_db_k-youtube'
$state = & docker inspect --type container --format '{{.Name}}|{{.State.Running}}' $db
if ($LASTEXITCODE -ne 0 -or $state.Trim() -ne '/supabase_db_k-youtube|true') {
    throw 'Expected local Supabase container is not running.'
}
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$migration = Get-Content -LiteralPath (Join-Path $root 'supabase/migrations/0037_chef_workspaces.sql') -Raw
$migration += [Environment]::NewLine + (Get-Content -LiteralPath (Join-Path $root 'supabase/migrations/0038_chef_cost_items.sql') -Raw)
$migration += [Environment]::NewLine + (Get-Content -LiteralPath (Join-Path $root 'supabase/migrations/0039_chef_sales.sql') -Raw)
$contract = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'chef_contract.sql') -Raw
$sql = 'BEGIN;' + [Environment]::NewLine + $migration + [Environment]::NewLine + $contract + [Environment]::NewLine + 'ROLLBACK;'
$sql | & docker exec -i $db psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres
if ($LASTEXITCODE -ne 0) { throw 'Local chef contract failed; connection closure rolls back the transaction.' }
