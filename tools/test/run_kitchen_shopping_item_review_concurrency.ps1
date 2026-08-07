[CmdletBinding()]
param([switch]$Run)

$ErrorActionPreference = 'Stop'
$script:Container = 'supabase_db_k-youtube'
$script:Jobs = @()
$script:ScenarioCount = 0
$script:WorkerCount = 0
$script:Owner = $null
$script:Marker = $null
$script:Baseline = $null
$script:PrimaryFailure = $null
$script:CleanupFailure = $null

function Assert-LocalContainer {
  $inspect = docker inspect --type container --format '{{.Name}}|{{.State.Running}}' $script:Container 2>$null
  if ($LASTEXITCODE -ne 0 -or $inspect.Trim() -ne '/supabase_db_k-youtube|true') { throw 'LOCAL_TEST_DB_CONTAINER_INVALID' }
}

function Invoke-LocalPsql([string]$Sql) {
  $result = $Sql | docker exec -i $script:Container psql -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 2>$null
  if ($LASTEXITCODE -ne 0) { throw 'KITCHEN_ITEM_REVIEW_CONCURRENCY_SQL_FAILED' }
  return @($result | Where-Object { $_ -ne $null -and $_.ToString().Trim() -ne '' })
}

function Assert-True([bool]$Condition, [string]$Marker) {
  if (-not $Condition) { throw $Marker }
}

function Get-Baseline {
  $line = (Invoke-LocalPsql @'
select concat_ws('|',
  (select count(*) from public.kitchen_shopping_items),
  (select count(*) from public.kitchen_shopping_items where status = 'pending'),
  (select count(*) from public.kitchen_shopping_items where review_status = 'required'),
  (select count(*) from public.kitchen_shopping_items item join public.kitchen_shopping_lists list on list.id = item.list_id where item.owner_id <> list.owner_id));
'@ | Select-Object -Last 1).Trim()
  $parts = $line.Split('|')
  Assert-True ($parts.Count -eq 4) 'BASELINE_READ_INVALID'
  Assert-True ($parts[0] -eq '16' -and $parts[1] -eq '16' -and $parts[2] -eq '16' -and $parts[3] -eq '0') 'BASELINE_PRECONDITION_INVALID'
  return $line
}

function New-Fixture([string]$Scenario, [string]$Name, [string]$IngredientText, [decimal]$Quantity = 1, [string]$Unit = 'g') {
  $key = [guid]::NewGuid().ToString()
  $json = "[{`"name`":`"$Name`",`"ingredient_text`":`"$IngredientText`",`"quantity`":$Quantity,`"unit`":`"$Unit`"}]"
  $sql = @"
set request.jwt.claim.sub = '$script:Owner';
select list_id from public.create_kitchen_shopping_list('user:$script:Marker-$Scenario', '$json'::jsonb, '$key'::uuid);
"@
  $listId = (Invoke-LocalPsql $sql | Select-Object -Last 1).Trim()
  $item = (Invoke-LocalPsql "select concat_ws('|', id, revision) from public.kitchen_shopping_items where list_id = '$listId'::uuid and owner_id = '$script:Owner'::uuid;" | Select-Object -Last 1).Trim().Split('|')
  Assert-True ($item.Count -eq 2) 'FIXTURE_ITEM_INVALID'
  return [pscustomobject]@{ ListId = $listId; ItemId = $item[0]; Revision = [int64]$item[1]; IngredientText = $IngredientText }
}

function Start-Worker([string]$Kind, [string]$ItemId, [string]$ListId, [int64]$ExpectedRevision, [string]$Payload, [string]$Target) {
  $job = Start-Job -ScriptBlock {
    param($Container, $Owner, $Kind, $ItemId, $ListId, $ExpectedRevision, $Payload, $Target)
    $workerSql = @"
set client_min_messages = warning;
set lock_timeout = '5s';
set statement_timeout = '15s';
set request.jwt.claim.sub = '$Owner';
create temporary table worker_result(outcome text, error_marker text, duration_bucket text, changed boolean) on commit preserve rows;
do `$`$
declare v_ready boolean; v_started timestamptz; v_result record; v_changed boolean := false; v_error text := 'none'; v_outcome text := 'success';
begin
  select clock_timestamp() <= '$Target'::timestamptz into v_ready;
  if not v_ready then
    insert into worker_result values ('error','worker_not_ready','not_started',false);
    return;
  end if;
  perform pg_sleep(greatest(0, extract(epoch from '$Target'::timestamptz - clock_timestamp())));
  v_started := clock_timestamp();
  begin
    if '$Kind' = 'review' then
      select * into v_result from public.review_kitchen_shopping_item('$ItemId'::uuid, split_part('$Payload','|',1), split_part('$Payload','|',2)::numeric, split_part('$Payload','|',3), $ExpectedRevision);
      v_changed := v_result.updated_at = transaction_timestamp();
    elsif '$Kind' = 'status' then
      select * into v_result from public.set_kitchen_shopping_item_status('$ItemId'::uuid, '$Payload', $ExpectedRevision);
      v_changed := v_result.updated_at = transaction_timestamp();
    else
      select * into v_result from public.complete_kitchen_shopping_list('$ListId'::uuid, '$Payload'::uuid);
      v_changed := v_result.status = 'completed' and v_result.inventory_change_count > 0;
    end if;
  exception when others then
    if SQLERRM = 'shopping item revision conflict' then v_outcome := 'conflict'; v_error := 'shopping_item_conflict';
    elsif SQLERRM = 'pending shopping items must be resolved before completion' then v_outcome := 'error'; v_error := 'pending_items';
    else v_outcome := 'error'; v_error := 'safe_database_error'; end if;
  end;
  insert into worker_result values (v_outcome, v_error, case when clock_timestamp() - v_started < interval '15 seconds' then 'within_limit' else 'over_limit' end, v_changed);
end
`$`$;
select concat_ws('|','WORKER',outcome,error_marker,duration_bucket,changed) from worker_result;
"@
    $output = @($workerSql | docker exec -i $Container psql -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1)
    $exitCode = $LASTEXITCODE
    $line = @($output | Where-Object { $_.ToString() -like 'WORKER|*' } | Select-Object -Last 1)
    if ($exitCode -ne 0) {
      $text = ($output | Out-String)
      $marker = if ($text -match 'deadlock') { 'deadlock' } elseif ($text -match 'timeout|canceling statement|55P03') { 'timeout' } else { 'worker_process_error' }
      [pscustomobject]@{ Outcome = $marker; ErrorMarker = $marker; Duration = 'unknown'; Changed = $false; ExitCode = $exitCode }
    } elseif ($line.Count -ne 1) {
      [pscustomobject]@{ Outcome = 'error'; ErrorMarker = 'worker_no_safe_result'; Duration = 'unknown'; Changed = $false; ExitCode = $exitCode }
    } else {
      $parts = $line[0].ToString().Split('|')
      [pscustomobject]@{ Outcome = $parts[1]; ErrorMarker = $parts[2]; Duration = $parts[3]; Changed = ($parts[4] -eq 't'); ExitCode = $exitCode }
    }
  } -ArgumentList $script:Container, $script:Owner, $Kind, $ItemId, $ListId, $ExpectedRevision, $Payload, $Target
  $script:Jobs += $job
  return $job
}

function Invoke-WorkerPair([object]$Left, [object]$Right) {
  $target = [DateTime]::UtcNow.AddSeconds(7).ToString('o')
  $one = Start-Worker @Left -Target $target
  $two = Start-Worker @Right -Target $target
  Wait-Job -Job $one, $two -Timeout 30 | Out-Null
  $running = @($one, $two | Where-Object { $_.State -eq 'Running' })
  if ($running.Count -gt 0) { $running | Stop-Job -ErrorAction SilentlyContinue; throw 'WORKER_TIMEOUT' }
  if ($one.State -ne 'Completed' -or $two.State -ne 'Completed') { throw 'WORKER_JOB_FAILED' }
  $results = @($one, $two | ForEach-Object { Receive-Job -Job $_ -ErrorAction SilentlyContinue })
  if ($results.Count -ne 2) { throw 'WORKER_OUTPUT_MISSING' }
  foreach ($result in $results) {
    if ($result.ExitCode -ne 0 -or $result.Outcome -in @('timeout','deadlock') -or $result.Duration -ne 'within_limit') { throw 'WORKER_TIMEOUT_OR_DEADLOCK' }
    if ($result.ErrorMarker -eq 'worker_not_ready') { throw 'WORKER_NOT_READY' }
  }
  $script:WorkerCount += 2
  return $results
}

function Assert-Post([string]$Sql, [string]$FailureMarker) {
  Assert-True (((Invoke-LocalPsql $Sql | Select-Object -Last 1).Trim()) -eq 't') $FailureMarker
}

if (-not $Run) { Write-Output 'NOT_RUN'; exit 0 }
Assert-LocalContainer

try {
  $script:Baseline = Get-Baseline
  $script:Owner = [guid]::NewGuid().ToString()
  $script:Marker = "review-concurrency-$([guid]::NewGuid().ToString('N'))"
  Invoke-LocalPsql "insert into auth.users(id) values ('$script:Owner'::uuid); insert into public.profiles(id) values ('$script:Owner'::uuid);" | Out-Null

  # A: divergent reviews yield one mutation and one optimistic conflict.
  $a = New-Fixture 'a' 'Fixture A Base' 'fixture-a-raw'
  $r = Invoke-WorkerPair @{ Kind='review'; ItemId=$a.ItemId; ListId=$a.ListId; ExpectedRevision=$a.Revision; Payload='Fixture A One|1|g' } @{ Kind='review'; ItemId=$a.ItemId; ListId=$a.ListId; ExpectedRevision=$a.Revision; Payload='Fixture A Two|2|g' }
  Assert-True ((@($r | Where-Object Outcome -eq 'success').Count -eq 1) -and (@($r | Where-Object Outcome -eq 'conflict').Count -eq 1) -and (@($r | Where-Object Changed).Count -eq 1)) 'SCENARIO_A_RESULT_INVALID'
  Assert-Post "select revision = $($a.Revision + 1) and ingredient_text = '$($a.IngredientText)' and name in ('Fixture A One','Fixture A Two') from public.kitchen_shopping_items where id = '$($a.ItemId)'::uuid;" 'SCENARIO_A_POST_INVALID'
  $script:ScenarioCount++; Write-Output 'SCENARIO_A=PASS'

  # B: same review is idempotent even after the competing revision becomes stale.
  $b = New-Fixture 'b' 'Fixture B Base' 'fixture-b-raw'
  $r = Invoke-WorkerPair @{ Kind='review'; ItemId=$b.ItemId; ListId=$b.ListId; ExpectedRevision=$b.Revision; Payload='Fixture B Same|3|g' } @{ Kind='review'; ItemId=$b.ItemId; ListId=$b.ListId; ExpectedRevision=$b.Revision; Payload='Fixture B Same|3|g' }
  Assert-True ((@($r | Where-Object Outcome -eq 'success').Count -eq 2) -and (@($r | Where-Object Changed).Count -eq 1)) 'SCENARIO_B_RESULT_INVALID'
  Assert-Post "select revision = $($b.Revision + 1) and reviewed_at is not null from public.kitchen_shopping_items where id = '$($b.ItemId)'::uuid;" 'SCENARIO_B_POST_INVALID'
  $script:ScenarioCount++; Write-Output 'SCENARIO_B=PASS'

  # C: divergent valid statuses on a confirmed item conflict exactly once.
  $c = New-Fixture 'c' 'Fixture C Base' 'fixture-c-raw'
  $r = Invoke-WorkerPair @{ Kind='status'; ItemId=$c.ItemId; ListId=$c.ListId; ExpectedRevision=$c.Revision; Payload='skipped' } @{ Kind='status'; ItemId=$c.ItemId; ListId=$c.ListId; ExpectedRevision=$c.Revision; Payload='unavailable' }
  Assert-True ((@($r | Where-Object Outcome -eq 'success').Count -eq 1) -and (@($r | Where-Object Outcome -eq 'conflict').Count -eq 1) -and (@($r | Where-Object Changed).Count -eq 1)) 'SCENARIO_C_RESULT_INVALID'
  Assert-Post "select revision = $($c.Revision + 1) and ((status = 'purchased') = is_checked) from public.kitchen_shopping_items where id = '$($c.ItemId)'::uuid;" 'SCENARIO_C_POST_INVALID'
  $script:ScenarioCount++; Write-Output 'SCENARIO_C=PASS'

  # D: equal status calls both succeed but mutate once.
  $d = New-Fixture 'd' 'Fixture D Base' 'fixture-d-raw'
  $r = Invoke-WorkerPair @{ Kind='status'; ItemId=$d.ItemId; ListId=$d.ListId; ExpectedRevision=$d.Revision; Payload='skipped' } @{ Kind='status'; ItemId=$d.ItemId; ListId=$d.ListId; ExpectedRevision=$d.Revision; Payload='skipped' }
  Assert-True ((@($r | Where-Object Outcome -eq 'success').Count -eq 2) -and (@($r | Where-Object Changed).Count -eq 1)) 'SCENARIO_D_RESULT_INVALID'
  Assert-Post "select revision = $($d.Revision + 1) and ((status = 'purchased') = is_checked) from public.kitchen_shopping_items where id = '$($d.ItemId)'::uuid;" 'SCENARIO_D_POST_INVALID'
  $script:ScenarioCount++; Write-Output 'SCENARIO_D=PASS'

  # E: the list lock makes completion/status serializable; no failed completion may be treated as success.
  $e = New-Fixture 'e' 'Fixture E Base' 'fixture-e-raw'
  $r = Invoke-WorkerPair @{ Kind='status'; ItemId=$e.ItemId; ListId=$e.ListId; ExpectedRevision=$e.Revision; Payload='purchased' } @{ Kind='complete'; ItemId=''; ListId=$e.ListId; ExpectedRevision=0; Payload=([guid]::NewGuid().ToString()) }
  $statusWorker = $r[0]
  $completeWorker = $r[1]
  Assert-True ($statusWorker.Outcome -eq 'success' -and (($completeWorker.Outcome -eq 'success') -or ($completeWorker.Outcome -eq 'error' -and $completeWorker.ErrorMarker -eq 'pending_items'))) 'SCENARIO_E_RESULT_INVALID'
  Assert-Post "select (((status = 'active' and (select status from public.kitchen_shopping_items where id = '$($e.ItemId)'::uuid) = 'purchased' and (select count(*) from public.kitchen_ingredients where owner_id = '$script:Owner'::uuid) = 0 and (select count(*) from public.kitchen_shopping_idempotency where owner_id = '$script:Owner'::uuid and operation = 'complete' and list_id = '$($e.ListId)'::uuid) = 0) or (status = 'completed' and (select status from public.kitchen_shopping_items where id = '$($e.ItemId)'::uuid) = 'purchased' and (select count(*) from public.kitchen_ingredients where owner_id = '$script:Owner'::uuid) = 1 and (select count(*) from public.kitchen_shopping_idempotency where owner_id = '$script:Owner'::uuid and operation = 'complete' and list_id = '$($e.ListId)'::uuid) <= 1)) and (select review_status = 'confirmed' and quantity > 0 and unit in ('g','kg','ml','l','ea') and ((status = 'purchased') = is_checked) from public.kitchen_shopping_items where id = '$($e.ItemId)'::uuid)) from public.kitchen_shopping_lists where id = '$($e.ListId)'::uuid;" 'SCENARIO_E_POST_INVALID'
  $script:ScenarioCount++; Write-Output 'SCENARIO_E=PASS'

  # F: explicitly proves all prior lock-order races completed with no timeout/deadlock, then reports the aggregate.
  Assert-True ($script:ScenarioCount -eq 5 -and $script:WorkerCount -eq 10) 'SCENARIO_F_LOCK_ORDER_INVALID'
  $script:ScenarioCount++; Write-Output 'SCENARIO_F=PASS'
  Write-Output "KITCHEN_ITEM_REVIEW_CONCURRENCY=PASS scenarios=$script:ScenarioCount"
} catch {
  $script:PrimaryFailure = $_
} finally {
  foreach ($job in @($script:Jobs)) { if ($job.State -eq 'Running') { Stop-Job -Job $job -ErrorAction SilentlyContinue }; Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
  if ($script:Owner) {
    $cleanupStatements = @(
      "delete from public.kitchen_shopping_idempotency where owner_id = '$script:Owner'::uuid;",
      "delete from public.kitchen_ingredients where owner_id = '$script:Owner'::uuid;",
      "delete from public.kitchen_shopping_items where owner_id = '$script:Owner'::uuid;",
      "delete from public.kitchen_shopping_lists where owner_id = '$script:Owner'::uuid;",
      "delete from public.profiles where id = '$script:Owner'::uuid;",
      "delete from auth.users where id = '$script:Owner'::uuid;"
    )
    foreach ($statement in $cleanupStatements) {
      try { Invoke-LocalPsql $statement | Out-Null } catch { if (-not $script:CleanupFailure) { $script:CleanupFailure = $_ } }
    }
  }
  if ($script:Baseline) {
    try { Assert-True ((Get-Baseline) -eq $script:Baseline) 'CLEANUP_BASELINE_INVALID' } catch { if (-not $script:CleanupFailure) { $script:CleanupFailure = $_ } }
  }
  if ($script:Owner) {
    try {
      Assert-Post "select not exists (select 1 from public.kitchen_shopping_lists where owner_id = '$script:Owner'::uuid) and not exists (select 1 from public.kitchen_shopping_items where owner_id = '$script:Owner'::uuid) and not exists (select 1 from public.kitchen_ingredients where owner_id = '$script:Owner'::uuid) and not exists (select 1 from public.kitchen_shopping_idempotency where owner_id = '$script:Owner'::uuid) and not exists (select 1 from public.profiles where id = '$script:Owner'::uuid) and not exists (select 1 from auth.users where id = '$script:Owner'::uuid);" 'FIXTURE_CLEANUP_INVALID'
    } catch { if (-not $script:CleanupFailure) { $script:CleanupFailure = $_ } }
  }
}
if ($script:PrimaryFailure) { throw $script:PrimaryFailure }
if ($script:CleanupFailure) { throw $script:CleanupFailure }
