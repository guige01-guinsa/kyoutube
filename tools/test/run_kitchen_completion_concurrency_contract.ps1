[CmdletBinding()]
param(
  [switch]$Run
)

$ErrorActionPreference = 'Stop'

if (-not $Run) {
  Write-Output 'NOT_RUN: Invoke with -Run only against approved local Supabase.'
  exit 0
}

function Invoke-LocalPsql([string]$DatabaseContainer, [string]$Sql) {
  $Sql | docker exec -i $DatabaseContainer psql -qAt -U postgres -d postgres -v ON_ERROR_STOP=1
  if ($LASTEXITCODE -ne 0) { throw 'CONCURRENCY_CONTRACT_SQL_FAILED' }
}

$db = docker ps --filter 'name=^/supabase_db_k-youtube$' --format '{{.Names}}'
if (-not $db) { throw 'LOCAL_TEST_DB_NOT_RUNNING' }

$ownerId = [guid]::NewGuid().ToString()
$sameKeyListId = $null
$differentKeyListId = $null

try {
  $setupSql = @"
insert into auth.users (id) values ('$ownerId'::uuid);
insert into public.profiles (id) values ('$ownerId'::uuid);
set request.jwt.claim.sub = '$ownerId';
select list_id from public.create_kitchen_shopping_list(
  'public:concurrency-same', '[{"name":"contract concurrent same","ingredient_text":"contract concurrent same","quantity":1,"unit":"g"}]'::jsonb,
  '00000000-0000-0000-0000-000000000301'::uuid);
"@
  $sameKeyListId = (Invoke-LocalPsql $db $setupSql | Select-Object -Last 1).Trim()
  Invoke-LocalPsql $db @"
set request.jwt.claim.sub = '$ownerId';
update public.kitchen_shopping_items set status = 'purchased' where list_id = '$sameKeyListId'::uuid;
select list_id from public.create_kitchen_shopping_list(
  'public:concurrency-different', '[{"name":"contract concurrent different","ingredient_text":"contract concurrent different","quantity":1,"unit":"g"}]'::jsonb,
  '00000000-0000-0000-0000-000000000302'::uuid);
"@ | Out-Null
  $differentKeyListId = (Invoke-LocalPsql $db @"
select id from public.kitchen_shopping_lists
where owner_id = '$ownerId'::uuid and source_recipe_id = 'public:concurrency-different';
"@ | Select-Object -Last 1).Trim()
  Invoke-LocalPsql $db @"
set request.jwt.claim.sub = '$ownerId';
update public.kitchen_shopping_items set status = 'purchased' where list_id = '$differentKeyListId'::uuid;
"@ | Out-Null

  function Start-CompletionWorker([string]$ListId, [string]$Key) {
    $workerSql = "set request.jwt.claim.sub = '$ownerId'; select count(*) from public.complete_kitchen_shopping_list('$ListId'::uuid, '$Key'::uuid);"
    Start-Job -ScriptBlock {
      param($Container, $Sql)
      $Sql | docker exec -i $Container psql -qAt -U postgres -d postgres -v ON_ERROR_STOP=1
      if ($LASTEXITCODE -ne 0) { exit 1 }
    } -ArgumentList $db, $workerSql
  }

  $sameOne = Start-CompletionWorker $sameKeyListId '00000000-0000-0000-0000-000000000401'
  $sameTwo = Start-CompletionWorker $sameKeyListId '00000000-0000-0000-0000-000000000401'
  Wait-Job $sameOne, $sameTwo | Out-Null
  if ($sameOne.State -ne 'Completed' -or $sameTwo.State -ne 'Completed') { throw 'SAME_KEY_CONCURRENCY_WORKER_FAILED' }
  Receive-Job $sameOne, $sameTwo | Out-Null
  Remove-Job $sameOne, $sameTwo -Force

  $differentOne = Start-CompletionWorker $differentKeyListId '00000000-0000-0000-0000-000000000402'
  $differentTwo = Start-CompletionWorker $differentKeyListId '00000000-0000-0000-0000-000000000403'
  Wait-Job $differentOne, $differentTwo | Out-Null
  if ($differentOne.State -ne 'Completed' -or $differentTwo.State -ne 'Completed') { throw 'DIFFERENT_KEY_CONCURRENCY_WORKER_FAILED' }
  Receive-Job $differentOne, $differentTwo | Out-Null
  Remove-Job $differentOne, $differentTwo -Force

  $verification = Invoke-LocalPsql $db @"
select case when
  (select count(*) from public.kitchen_shopping_lists where owner_id = '$ownerId'::uuid and status = 'completed') = 2
  and (select count(*) from public.kitchen_ingredients where owner_id = '$ownerId'::uuid) = 2
  and (select count(*) from public.kitchen_shopping_idempotency where owner_id = '$ownerId'::uuid and operation = 'complete') = 3
then 'PASS' else 'FAIL' end;
"@
  if (($verification | Select-Object -Last 1).Trim() -ne 'PASS') { throw 'CONCURRENCY_CONTRACT_ASSERTION_FAILED' }
  Write-Output 'KITCHEN_COMPLETION_CONCURRENCY_CONTRACT_PASS'
}
finally {
  if ($ownerId) {
    "delete from auth.users where id = '$ownerId'::uuid;" | docker exec -i $db psql -q -U postgres -d postgres -v ON_ERROR_STOP=1 | Out-Null
  }
}
