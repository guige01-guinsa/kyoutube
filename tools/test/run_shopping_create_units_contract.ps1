param([switch]$BeforeFix)
$ErrorActionPreference = 'Stop'
$db = 'supabase_db_k-youtube'
$state = & docker inspect --type container --format '{{.Name}}|{{.State.Running}}' $db
if ($LASTEXITCODE -ne 0 -or $state.Trim() -ne '/supabase_db_k-youtube|true') { throw 'Expected local DB unavailable' }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sql = "BEGIN; SET LOCAL ROLE postgres;" + [Environment]::NewLine
if (-not $BeforeFix) {
  $purchaseTable = & docker exec $db psql -X -qAt -U supabase_admin -d postgres -c "select to_regclass('public.shopping_purchase_records') is not null"
  if ($LASTEXITCODE -ne 0) { throw 'Local purchase schema check failed' }
  if ($purchaseTable.Trim() -ne 't') {
    $sql += (Get-Content (Join-Path $root 'supabase/migrations/0051_shopping_assistant.sql') -Raw -Encoding UTF8) + [Environment]::NewLine
  }
  $sql += (Get-Content (Join-Path $root 'supabase/migrations/0058_fix_shopping_create_units.sql') -Raw -Encoding UTF8) + [Environment]::NewLine
}
$sql += (Get-Content (Join-Path $PSScriptRoot 'shopping_create_units_contract.sql') -Raw -Encoding UTF8) + [Environment]::NewLine + 'ROLLBACK;'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$sql | & docker exec -i $db psql -X -q -v ON_ERROR_STOP=1 -U supabase_admin -d postgres
if ($LASTEXITCODE -ne 0) { throw 'Shopping creation contract failed; test transaction rolls back' }
