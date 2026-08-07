[CmdletBinding()]
param([switch]$Preflight, [switch]$Run, [switch]$Concurrency)

$ErrorActionPreference = 'Stop'
$suite = Join-Path $PSScriptRoot 'kitchen_shopping_item_review_contract.sql'
$preflightSuite = Join-Path $PSScriptRoot 'kitchen_shopping_item_review_preflight.sql'
$concurrencyRunner = Join-Path $PSScriptRoot 'run_kitchen_shopping_item_review_concurrency.ps1'

function Get-LocalDatabaseContainer {
  $inspect = docker inspect --type container --format '{{.Name}}|{{.State.Running}}' supabase_db_k-youtube 2>$null
  if ($LASTEXITCODE -ne 0 -or $inspect.Trim() -ne '/supabase_db_k-youtube|true') {
    throw 'LOCAL_TEST_DB_CONTAINER_INVALID'
  }
  return 'supabase_db_k-youtube'
}

function Invoke-SqlFile([string]$Source, [string]$Db) {
  $expected = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ([IO.Path]::GetFileName($Source))))
  $actual = [IO.Path]::GetFullPath($Source)
  if ($actual -ne $expected -or -not (Test-Path -LiteralPath $actual -PathType Leaf)) { throw 'LOCAL_SQL_SOURCE_INVALID' }

  $temp = "/tmp/kitchen-review-contract-$([guid]::NewGuid().ToString('N')).sql"
  $cleanupRequired = $true
  $primaryFailure = $null
  $cleanupFailure = $null
  try {
    & docker cp $actual "$Db`:$temp" 2>$null | Out-Null
    $copyExit = $LASTEXITCODE
    if ($copyExit -ne 0) { throw 'CONTRACT_SQL_COPY_FAILED' }
    & docker exec $Db psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres -f $temp
    $psqlExit = $LASTEXITCODE
    if ($psqlExit -ne 0) { throw "CONTRACT_SQL_PSQL_FAILED_EXIT_$psqlExit" }
  } catch {
    $primaryFailure = $_
  } finally {
    if ($cleanupRequired) {
      & docker exec $Db rm -f $temp 2>$null | Out-Null
      $cleanupExit = $LASTEXITCODE
      if ($cleanupExit -ne 0) { $cleanupFailure = [System.Management.Automation.ErrorRecord]::new((New-Object System.Exception('CONTRACT_SQL_TEMP_CLEANUP_FAILED')), 'CONTRACT_SQL_TEMP_CLEANUP_FAILED', 'NotSpecified', $null) }
    }
  }
  if ($primaryFailure) { throw $primaryFailure }
  if ($cleanupFailure) { throw $cleanupFailure }
}

if ((@($Preflight, $Run, $Concurrency | Where-Object { $_ }).Count) -gt 1) { throw 'KITCHEN_ITEM_REVIEW_MODE_CONFLICT' }
if (-not $Preflight -and -not $Run -and -not $Concurrency) {
  Write-Output 'Usage: .\tools\test\run_kitchen_shopping_item_review_contract.ps1 -Preflight'
  Write-Output 'Usage: .\tools\test\run_kitchen_shopping_item_review_contract.ps1 -Run'
  Write-Output 'Usage: .\tools\test\run_kitchen_shopping_item_review_contract.ps1 -Concurrency'
  Write-Output 'NOT_RUN'
  exit 0
}

$db = Get-LocalDatabaseContainer

if ($Concurrency) {
  & $concurrencyRunner -Run
  exit $LASTEXITCODE
}

if ($Preflight) {
  $requiredColumns = docker exec $db psql -X -U postgres -d postgres -qAt -v ON_ERROR_STOP=1 -c "select count(*) = 11 from information_schema.columns where table_schema = 'public' and table_name = 'kitchen_shopping_items' and column_name in ('id','list_id','owner_id','name','normalized_name','ingredient_text','quantity','unit','status','is_checked','updated_at');"
  if ($LASTEXITCODE -ne 0 -or $requiredColumns.Trim() -ne 't') { throw 'KITCHEN_ITEM_REVIEW_PREFLIGHT_SCHEMA_MISMATCH' }
  Invoke-SqlFile $preflightSuite $db
  exit 0
}

$requiredProcedures = @(
  'public.review_kitchen_shopping_item(uuid,text,numeric,text,bigint)',
  'public.set_kitchen_shopping_item_status(uuid,text,bigint)'
)
foreach ($procedure in $requiredProcedures) {
  $present = docker exec $db psql -U postgres -d postgres -qAt -v ON_ERROR_STOP=1 -c "select to_regprocedure('$procedure') is not null;"
  if ($present.Trim() -ne 't') { throw 'KITCHEN_ITEM_REVIEW_CONTRACT_MISSING_RPC' }
}
Invoke-SqlFile $suite $db
Write-Output 'KITCHEN_ITEM_REVIEW_CONTRACT=PASS'
