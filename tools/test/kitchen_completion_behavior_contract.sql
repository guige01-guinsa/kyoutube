-- Post-0014 local behaviour contract. Run only after explicit migration approval.
-- Every fixture below lives in this transaction and is rolled back at the end.
begin;

create or replace function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if not coalesce(p_condition, false) then
    raise exception 'CONTRACT_ASSERTION_FAILED:%', p_message;
  end if;
end;
$$;

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_other_owner uuid := gen_random_uuid();
  v_list uuid;
  v_all_skipped_list uuid;
  v_pending_list uuid;
  v_first_result record;
  v_retry_result record;
  v_completed_result record;
  v_inventory_count integer;
  v_rejected boolean;
begin
  -- Auth/profile rows are test-only and disappear with the transaction.
  insert into auth.users (id) values (v_owner), (v_other_owner);
  insert into public.profiles (id) values (v_owner), (v_other_owner);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  select * into v_first_result
  from public.create_kitchen_shopping_list(
    'public:contract-recipe',
    '[
      {"name":"contract potato","ingredient_text":"raw: contract potato 2kg","quantity":2,"unit":"kg"},
      {"name":"contract unavailable","ingredient_text":"raw: contract unavailable","quantity":1,"unit":"ea"}
    ]'::jsonb,
    '00000000-0000-0000-0000-000000000101'::uuid
  );
  v_list := v_first_result.list_id;
  perform pg_temp.assert_true(v_first_result.created and not v_first_result.replayed,
    'first create must create one active list');

  select * into v_retry_result
  from public.create_kitchen_shopping_list(
    'public:contract-recipe',
    '[
      {"name":"contract potato","ingredient_text":"raw: contract potato 2kg","quantity":2,"unit":"kg"},
      {"name":"contract unavailable","ingredient_text":"raw: contract unavailable","quantity":1,"unit":"ea"}
    ]'::jsonb,
    '00000000-0000-0000-0000-000000000101'::uuid
  );
  perform pg_temp.assert_true(v_retry_result.list_id = v_list and v_retry_result.replayed,
    'same create key must replay the original list');
  perform pg_temp.assert_true((select count(*) from public.kitchen_shopping_lists
    where owner_id = v_owner and create_idempotency_key = '00000000-0000-0000-0000-000000000101'::uuid) = 1,
    'same create key must not duplicate the list');

  -- New status updates own the derived legacy flag; legacy-only changes map back
  -- to purchased/pending while the list is active.
  update public.kitchen_shopping_items set status = 'skipped'
  where list_id = v_list and name = 'contract unavailable';
  perform pg_temp.assert_true((select not is_checked from public.kitchen_shopping_items
    where list_id = v_list and name = 'contract unavailable'),
    'skipped status must derive legacy is_checked=false');
  update public.kitchen_shopping_items set is_checked = true
  where list_id = v_list and name = 'contract unavailable';
  perform pg_temp.assert_true((select status = 'purchased' from public.kitchen_shopping_items
    where list_id = v_list and name = 'contract unavailable'),
    'legacy is_checked=true must map to purchased while active');
  update public.kitchen_shopping_items set is_checked = false
  where list_id = v_list and name = 'contract unavailable';
  perform pg_temp.assert_true((select status = 'pending' from public.kitchen_shopping_items
    where list_id = v_list and name = 'contract unavailable'),
    'legacy is_checked=false must map to pending while active');

  update public.kitchen_shopping_items
  set status = case when name = 'contract potato' then 'purchased' else 'unavailable' end,
      is_checked = (name = 'contract potato')
  where list_id = v_list;
  select * into v_completed_result
  from public.complete_kitchen_shopping_list(v_list, '00000000-0000-0000-0000-000000000201'::uuid);
  perform pg_temp.assert_true(v_completed_result.status = 'completed'
    and v_completed_result.purchased_count = 1
    and v_completed_result.unavailable_count = 1,
    'only purchased items may affect completed inventory');
  perform pg_temp.assert_true((select count(*) from public.kitchen_ingredients
    where owner_id = v_owner and normalized_name = 'contract potato') = 1,
    'purchased item must produce one inventory row');
  perform pg_temp.assert_true((select count(*) from public.kitchen_ingredients
    where owner_id = v_owner and normalized_name = 'contract unavailable') = 0,
    'unavailable item must not produce inventory');

  select count(*) into v_inventory_count from public.kitchen_ingredients where owner_id = v_owner;
  select * into v_retry_result
  from public.complete_kitchen_shopping_list(v_list, '00000000-0000-0000-0000-000000000201'::uuid);
  perform pg_temp.assert_true(v_retry_result.replayed and
    (select count(*) from public.kitchen_ingredients where owner_id = v_owner) = v_inventory_count,
    'same completion key must be a no-op');
  select * into v_retry_result
  from public.complete_kitchen_shopping_list(v_list, '00000000-0000-0000-0000-000000000202'::uuid);
  perform pg_temp.assert_true(not v_retry_result.replayed and
    (select count(*) from public.kitchen_ingredients where owner_id = v_owner) = v_inventory_count,
    'completed list with another key must also be a no-op');
  v_rejected := false;
  begin
    update public.kitchen_shopping_items set is_checked = false
    where list_id = v_list and name = 'contract potato';
  exception when others then v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected,
    'legacy update must not reopen an item in a completed list');

  select list_id into v_pending_list from public.create_kitchen_shopping_list(
    'public:pending-recipe', '[{"name":"contract pending","ingredient_text":"contract pending"}]'::jsonb,
    '00000000-0000-0000-0000-000000000102'::uuid);
  v_rejected := false;
  begin
    perform * from public.complete_kitchen_shopping_list(v_pending_list,
      '00000000-0000-0000-0000-000000000203'::uuid);
  exception when others then v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected and (select status = 'active' from public.kitchen_shopping_lists where id = v_pending_list),
    'pending item must reject completion without changing list state');

  select list_id into v_all_skipped_list from public.create_kitchen_shopping_list(
    'public:skipped-recipe', '[{"name":"contract skipped","ingredient_text":"contract skipped"}]'::jsonb,
    '00000000-0000-0000-0000-000000000103'::uuid);
  update public.kitchen_shopping_items set status = 'skipped' where list_id = v_all_skipped_list;
  select count(*) into v_inventory_count from public.kitchen_ingredients where owner_id = v_owner;
  select * into v_completed_result from public.complete_kitchen_shopping_list(v_all_skipped_list,
    '00000000-0000-0000-0000-000000000204'::uuid);
  perform pg_temp.assert_true(v_completed_result.status = 'completed'
    and v_completed_result.inventory_change_count = 0
    and (select count(*) from public.kitchen_ingredients where owner_id = v_owner) = v_inventory_count,
    'all-skipped list must complete without inventory changes');

  v_rejected := false;
  begin
    perform * from public.create_kitchen_shopping_list('public:invalid', '[]'::jsonb,
      '00000000-0000-0000-0000-000000000104'::uuid);
  exception when others then v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected, 'empty payload must be rejected');

  -- An authenticated different owner cannot complete this list through the RPC.
  perform set_config('request.jwt.claim.sub', v_other_owner::text, true);
  v_rejected := false;
  begin
    perform * from public.complete_kitchen_shopping_list(v_list,
      '00000000-0000-0000-0000-000000000206'::uuid);
  exception when others then v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected, 'other user must not complete another owner list');
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  v_rejected := false;
  begin
    insert into public.kitchen_shopping_items (list_id, owner_id, name, normalized_name, ingredient_text, status)
    values (v_list, v_other_owner, 'cross-owner', 'cross-owner', 'cross-owner', 'pending');
  exception when foreign_key_violation then v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected, 'item owner must match list owner');

  -- Quantity/unit safety: incompatible units reject and roll back the list completion.
  insert into public.kitchen_ingredients (owner_id, name, normalized_name, quantity, unit)
  values (v_owner, 'contract unit conflict', 'contract unit conflict', 1, 'g');
  select list_id into v_pending_list from public.create_kitchen_shopping_list(
    'public:unit-recipe', '[{"name":"contract unit conflict","ingredient_text":"contract unit conflict","quantity":1,"unit":"ml"}]'::jsonb,
    '00000000-0000-0000-0000-000000000105'::uuid);
  update public.kitchen_shopping_items set status = 'purchased' where list_id = v_pending_list;
  v_rejected := false;
  begin
    perform * from public.complete_kitchen_shopping_list(v_pending_list,
      '00000000-0000-0000-0000-000000000205'::uuid);
  exception when others then v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected and (select status = 'active' from public.kitchen_shopping_lists where id = v_pending_list),
    'incompatible unit must not partially complete the list');

  insert into public.kitchen_ingredients (owner_id, name, normalized_name, quantity, unit)
  values (v_owner, 'contract conversion', 'contract conversion', 500, 'g');
  select list_id into v_pending_list from public.create_kitchen_shopping_list(
    'public:conversion-recipe', '[{"name":"contract conversion","ingredient_text":"contract conversion","quantity":2,"unit":"kg"}]'::jsonb,
    '00000000-0000-0000-0000-000000000106'::uuid);
  update public.kitchen_shopping_items set status = 'purchased' where list_id = v_pending_list;
  perform * from public.complete_kitchen_shopping_list(v_pending_list,
    '00000000-0000-0000-0000-000000000207'::uuid);
  perform pg_temp.assert_true((select quantity = 2500 and unit = 'g'
    from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'contract conversion'),
    'kg must merge into existing g inventory without changing its unit');

  insert into public.kitchen_ingredients (owner_id, name, normalized_name, quantity, unit)
  values (v_owner, 'contract liquid', 'contract liquid', 500, 'ml');
  select list_id into v_pending_list from public.create_kitchen_shopping_list(
    'public:liquid-recipe', '[{"name":"contract liquid","ingredient_text":"contract liquid","quantity":2,"unit":"l"}]'::jsonb,
    '00000000-0000-0000-0000-000000000107'::uuid);
  update public.kitchen_shopping_items set status = 'purchased' where list_id = v_pending_list;
  perform * from public.complete_kitchen_shopping_list(v_pending_list,
    '00000000-0000-0000-0000-000000000208'::uuid);
  perform pg_temp.assert_true((select quantity = 2500 and unit = 'ml'
    from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'contract liquid'),
    'L must merge into existing ml inventory without changing its unit');

  insert into public.kitchen_ingredients (owner_id, name, normalized_name, quantity, unit)
  values (v_owner, 'contract grams', 'contract grams', 1, 'g');
  select list_id into v_pending_list from public.create_kitchen_shopping_list(
    'public:grams-recipe', '[{"name":"contract grams","ingredient_text":"contract grams","quantity":2,"unit":"g"}]'::jsonb,
    '00000000-0000-0000-0000-000000000109'::uuid);
  update public.kitchen_shopping_items set status = 'purchased' where list_id = v_pending_list;
  perform * from public.complete_kitchen_shopping_list(v_pending_list,
    '00000000-0000-0000-0000-000000000210'::uuid);
  perform pg_temp.assert_true((select quantity = 3 and unit = 'g'
    from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'contract grams'),
    'same unit g quantities must merge');

  select list_id into v_pending_list from public.create_kitchen_shopping_list(
    'public:null-quantity-recipe', '[{"name":"contract null quantity","ingredient_text":"contract null quantity"}]'::jsonb,
    '00000000-0000-0000-0000-000000000108'::uuid);
  update public.kitchen_shopping_items set status = 'purchased' where list_id = v_pending_list;
  v_rejected := false;
  begin
    perform * from public.complete_kitchen_shopping_list(v_pending_list,
      '00000000-0000-0000-0000-000000000209'::uuid);
  exception when others then v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected and (select status = 'active' from public.kitchen_shopping_lists where id = v_pending_list)
    and (select count(*) from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'contract null quantity') = 0,
    'null purchased quantity must roll back without an arbitrary conversion');
end;
$$;

rollback;
