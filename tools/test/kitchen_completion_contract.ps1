[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Invoke-LocalSchemaQuery([string]$Sql) {
  $db = docker ps --filter 'name=^/supabase_db_k-youtube$' --format '{{.Names}}'
  if (-not $db) { throw 'LOCAL_TEST_DB_NOT_RUNNING' }
  return docker exec $db psql -U postgres -d postgres -At -v ON_ERROR_STOP=1 -c $Sql
}

# Phase 1 contract: Phase 2 must add these RPCs.  The runner deliberately
# fails before creating any fixture rows when the current implementation does
# not provide them.
$requiredProcedures = @(
  'public.create_kitchen_shopping_list(text,jsonb,uuid)',
  'public.complete_kitchen_shopping_list(uuid,uuid)'
)

foreach ($procedure in $requiredProcedures) {
  $exists = Invoke-LocalSchemaQuery "select to_regprocedure('$procedure') is not null;"
  if ($exists.Trim() -ne 't') {
    throw "KITCHEN_COMPLETION_CONTRACT_MISSING_RPC:$procedure"
  }
}

# The transaction-scoped behavior suite is in
# kitchen_completion_behavior_contract.sql. It covers pending rejection,
# purchased-only inventory, skipped/unavailable no-op, retries, rollback,
# owner/list ownership, and creation-key deduplication without retaining rows.
Write-Output 'KITCHEN_COMPLETION_RPC_CONTRACT_PRESENT'
