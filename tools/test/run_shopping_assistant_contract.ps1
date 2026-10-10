$ErrorActionPreference = 'Stop'
$db = 'supabase_db_k-youtube'
$state = & docker inspect --type container --format '{{.Name}}|{{.State.Running}}' $db
if ($LASTEXITCODE -ne 0 -or $state.Trim() -ne '/supabase_db_k-youtube|true') { throw 'Expected local DB unavailable' }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sql = "BEGIN; SET LOCAL ROLE postgres;" + [Environment]::NewLine
foreach ($version in 36..51) {
  $pattern = '{0:D4}_*.sql' -f $version
  $path = Get-ChildItem (Join-Path $root 'supabase/migrations') -Filter $pattern
  if (@($path).Count -ne 1) { throw "Expected exactly one migration: $pattern" }
  $sql += (Get-Content -LiteralPath $path.FullName -Raw -Encoding UTF8) + [Environment]::NewLine
}
$sql += (Get-Content (Join-Path $PSScriptRoot 'shopping_assistant_contract.sql') -Raw -Encoding UTF8) + [Environment]::NewLine + 'ROLLBACK;'
$sql | & docker exec -i $db psql -X -q -v ON_ERROR_STOP=1 -U supabase_admin -d postgres
if ($LASTEXITCODE -ne 0) { throw 'Shopping contract failed; test transaction rolls back' }
