$ErrorActionPreference = 'Stop'
$db = 'supabase_db_k-youtube'
$state = & docker inspect --type container --format '{{.Name}}|{{.State.Running}}' $db
if ($LASTEXITCODE -ne 0 -or $state.Trim() -ne '/supabase_db_k-youtube|true') { throw 'Expected local DB unavailable' }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sql = "BEGIN; SET LOCAL ROLE postgres;" + [Environment]::NewLine
foreach ($version in 36..53) {
  $pattern = '{0:D4}_*.sql' -f $version
  $path = Get-ChildItem (Join-Path $root 'supabase/migrations') -Filter $pattern
  if (@($path).Count -ne 1) { throw "Expected exactly one migration: $pattern" }
  $sql += (Get-Content -LiteralPath $path.FullName -Raw -Encoding UTF8) + [Environment]::NewLine
}
foreach ($contract in @('shopping_assistant_contract.sql', 'shopping_store_directory_contract.sql', 'supplier_request_contract.sql')) {
  $sql += (Get-Content (Join-Path $PSScriptRoot $contract) -Raw -Encoding UTF8) + [Environment]::NewLine
}
$sql += 'ROLLBACK;'
$sql | & docker exec -i $db psql -X -q -v ON_ERROR_STOP=1 -U supabase_admin -d postgres
if ($LASTEXITCODE -ne 0) { throw 'Supplier request contract failed; test transaction rolls back' }
