-- Read-only diagnostic probe: every fixture write is rolled back.
begin;

do $probe$
declare
  v_owner uuid := gen_random_uuid();
  v_list_only uuid := gen_random_uuid();
  v_item_only uuid := gen_random_uuid();
  v_list_checked uuid := gen_random_uuid();
  v_item_checked uuid := gen_random_uuid();
  v_list_combined uuid := gen_random_uuid();
  v_item_combined uuid := gen_random_uuid();
  v_list_rpc uuid := gen_random_uuid();
  v_item_rpc uuid := gen_random_uuid();
  v_error_state text;
  v_result record;
  v_sync boolean;
  v_revision bigint;
  v_status_only text;
  v_status_only_state text := 'none';
  v_checked_only text;
  v_checked_only_state text := 'none';
  v_combined text;
  v_combined_state text := 'none';
  v_rpc text;
  v_rpc_state text := 'none';
begin
  -- Fixture setup is owner-privileged and uses four independent active lists/items.
  insert into auth.users(id) values (v_owner);
  insert into public.profiles(id) values (v_owner);
  insert into public.kitchen_shopping_lists(id, owner_id, status, title, source_recipe_id)
    values
      (v_list_only, v_owner, 'active', 'probe status only', 'user:direct-status-only'),
      (v_list_checked, v_owner, 'active', 'probe checked only', 'user:direct-checked-only'),
      (v_list_combined, v_owner, 'active', 'probe combined', 'user:direct-combined'),
      (v_list_rpc, v_owner, 'active', 'probe status rpc', 'user:status-rpc');
  perform set_config('app.kitchen_create_rpc', '1', true);
  insert into public.kitchen_shopping_items(
    id, list_id, owner_id, name, normalized_name, ingredient_text,
    quantity, unit, status, is_checked, review_status, reviewed_at, revision
  ) values
    (v_item_only, v_list_only, v_owner, 'Probe Status Only', 'probe status only', 'probe raw only', null, null, 'pending', false, 'required', null, 0),
    (v_item_checked, v_list_checked, v_owner, 'Probe Checked Only', 'probe checked only', 'probe raw checked', null, null, 'pending', false, 'required', null, 0),
    (v_item_combined, v_list_combined, v_owner, 'Probe Combined', 'probe combined', 'probe raw combined', null, null, 'pending', false, 'required', null, 0),
    (v_item_rpc, v_list_rpc, v_owner, 'Probe Status RPC', 'probe status rpc', 'probe raw rpc', null, null, 'pending', false, 'required', null, 0);

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  -- Every status fixture is first confirmed through the review RPC.
  select * into v_result from public.review_kitchen_shopping_item(v_item_only, 'Probe Status Only Confirmed', 1, 'g', 0);
  select * into v_result from public.review_kitchen_shopping_item(v_item_checked, 'Probe Checked Only Confirmed', 1, 'g', 0);
  select * into v_result from public.review_kitchen_shopping_item(v_item_combined, 'Probe Combined Confirmed', 1, 'g', 0);
  select * into v_result from public.review_kitchen_shopping_item(v_item_rpc, 'Probe Status RPC Confirmed', 1, 'g', 0);

  -- Status-only direct write: status changes, is_checked is omitted.
  v_error_state := null;
  begin
    update public.kitchen_shopping_items set status = 'purchased' where id = v_item_only;
    v_status_only := 'ALLOWED';
  exception when others then
    get stacked diagnostics v_error_state = returned_sqlstate;
    v_status_only := 'DENIED';
    v_status_only_state := coalesce(v_error_state, 'unknown');
  end;
  raise notice 'DIRECT_STATUS_ONLY=%', v_status_only;
  raise notice 'DIRECT_STATUS_ONLY_SQLSTATE=%', v_status_only_state;

  -- is_checked-only legacy write: status is omitted and compatibility may apply.
  select revision into v_revision from public.kitchen_shopping_items where id = v_item_checked;
  v_error_state := null;
  begin
    update public.kitchen_shopping_items set is_checked = true where id = v_item_checked;
    v_checked_only := 'ALLOWED';
  exception when others then
    get stacked diagnostics v_error_state = returned_sqlstate;
    v_checked_only := 'DENIED';
    v_checked_only_state := coalesce(v_error_state, 'unknown');
  end;
  select status = 'purchased' and is_checked and revision = v_revision + 1 into v_sync
    from public.kitchen_shopping_items where id = v_item_checked;
  raise notice 'DIRECT_IS_CHECKED_ONLY=%', v_checked_only;
  raise notice 'DIRECT_IS_CHECKED_ONLY_SQLSTATE=%', v_checked_only_state;
  raise notice 'DIRECT_IS_CHECKED_SYNC=%', case when v_sync then 'PASS' else 'FAIL' end;
  raise notice 'DIRECT_IS_CHECKED_REVISION=%', case when v_sync then 'PASS' else 'FAIL' end;

  -- Combined direct write: both columns are explicitly supplied; 0019 expects denial.
  v_error_state := null;
  begin
    update public.kitchen_shopping_items
      set status = 'purchased', is_checked = true
      where id = v_item_combined;
    v_combined := 'ALLOWED';
  exception when others then
    get stacked diagnostics v_error_state = returned_sqlstate;
    v_combined := 'DENIED';
    v_combined_state := coalesce(v_error_state, 'unknown');
  end;
  raise notice 'DIRECT_STATUS_AND_CHECKED=%', v_combined;
  raise notice 'DIRECT_STATUS_AND_CHECKED_SQLSTATE=%', v_combined_state;

  -- Status RPC is tested on its own confirmed fixture and expected to mutate once.
  select revision into v_revision from public.kitchen_shopping_items where id = v_item_rpc;
  v_error_state := null;
  begin
    select * into v_result from public.set_kitchen_shopping_item_status(v_item_rpc, 'purchased', v_revision);
    v_rpc := 'ALLOWED';
  exception when others then
    get stacked diagnostics v_error_state = returned_sqlstate;
    v_rpc := 'DENIED';
    v_rpc_state := coalesce(v_error_state, 'unknown');
  end;
  select status = 'purchased' and is_checked and revision = v_revision + 1 into v_sync
    from public.kitchen_shopping_items where id = v_item_rpc;
  raise notice 'STATUS_RPC=%', v_rpc;
  raise notice 'STATUS_RPC_SQLSTATE=%', v_rpc_state;
  raise notice 'STATUS_RPC_SYNC=%', case when v_sync then 'PASS' else 'FAIL' end;
  raise notice 'STATUS_RPC_REVISION=%', case when v_sync then 'PASS' else 'FAIL' end;
end;
$probe$;

rollback;
