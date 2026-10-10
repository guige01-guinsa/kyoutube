$ErrorActionPreference='Stop'
$db='supabase_db_k-youtube'
$state=& docker inspect --type container --format '{{.Name}}|{{.State.Running}}' $db
if($LASTEXITCODE -ne 0 -or $state.Trim() -ne '/supabase_db_k-youtube|true'){throw 'Expected local test database unavailable'}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sql='BEGIN;'+[Environment]::NewLine
foreach($path in @('supabase/migrations/0042_private_recipe_default.sql','supabase/migrations/0043_authenticated_rpc_grants.sql','supabase/migrations/0044_private_promoted_recipes.sql','tools/test/security_hardening_contract.sql')){
 $sql+=(Get-Content -LiteralPath (Join-Path $root $path) -Raw)+[Environment]::NewLine
}
$sql+='ROLLBACK;'
$sql | & docker exec -i $db psql -X -q -v ON_ERROR_STOP=1 -U supabase_admin -d postgres
if($LASTEXITCODE -ne 0){throw 'Security contract failed; connection closure rolls back'}
