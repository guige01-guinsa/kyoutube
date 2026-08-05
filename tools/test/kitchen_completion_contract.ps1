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

# The behavior suite is intentionally transaction-scoped. Phase 2 will add
# the implementation and enable these scenarios without touching developer
# data: pending rejection; purchased-only inventory; skipped/unavailable
# no-op; same-key retry/concurrency; completed no-op; rollback; owner/list
# ownership; and create-key deduplication.
throw 'KITCHEN_COMPLETION_BEHAVIOR_SUITE_PENDING_PHASE_2_IMPLEMENTATION'
