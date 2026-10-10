$ErrorActionPreference='Stop'
$db='supabase_db_k-youtube'
$state=& docker inspect --type container --format '{{.Name}}|{{.State.Running}}' $db
if($LASTEXITCODE -ne 0 -or $state.Trim() -ne '/supabase_db_k-youtube|true'){throw 'Expected local DB unavailable'}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sql="BEGIN; SET LOCAL ROLE postgres;"+[Environment]::NewLine
foreach($version in @('0036','0037','0038','0039','0040','0041','0042','0043','0044','0045','0046','0047','0048')){
 $path=Get-ChildItem (Join-Path $root 'supabase/migrations') -Filter "$version`_*.sql"
 $sql+=(Get-Content -LiteralPath $path.FullName -Raw -Encoding UTF8)+[Environment]::NewLine
}
$sql+=(Get-Content (Join-Path $PSScriptRoot 'security_rollout_contract.sql') -Raw -Encoding UTF8)+[Environment]::NewLine+'ROLLBACK;'
$sql | & docker exec -i $db psql -X -q -v ON_ERROR_STOP=1 -U supabase_admin -d postgres
if($LASTEXITCODE -ne 0){throw 'Rollout contract failed; transaction rolls back'}
