[CmdletBinding()]
param(
  [switch]$Run
)

$ErrorActionPreference = 'Stop'
$suite = Join-Path $PSScriptRoot 'kitchen_completion_behavior_contract.sql'

if (-not $Run) {
  Write-Output 'NOT_RUN: Apply 0014 only after approval, then invoke this script with -Run.'
  exit 0
}

$db = docker ps --filter 'name=^/supabase_db_k-youtube$' --format '{{.Names}}'
if (-not $db) { throw 'LOCAL_TEST_DB_NOT_RUNNING' }

$hasRpc = docker exec $db psql -U postgres -d postgres -At -v ON_ERROR_STOP=1 -c "select to_regprocedure('public.create_kitchen_shopping_list(text,jsonb,uuid)') is not null and to_regprocedure('public.complete_kitchen_shopping_list(uuid,uuid)') is not null;"
if ($hasRpc.Trim() -ne 't') { throw 'KITCHEN_COMPLETION_CONTRACT_MISSING_RPC' }

Get-Content -Raw $suite | docker exec -i $db psql -U postgres -d postgres -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
