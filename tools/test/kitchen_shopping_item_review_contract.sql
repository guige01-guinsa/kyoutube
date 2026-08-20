-- Part A contract suite. Run only against an explicitly migrated local database.
-- All dedicated auth/profile/list/item fixtures are transaction-local and rolled back.
begin;

create or replace function pg_temp.assert_true(p_condition boolean, p_name text)
returns void language plpgsql as $assert_true$
begin
  if p_condition is not true then
    raise exception 'FAIL:%', p_name;
  end if;
  raise notice 'PASS:%', p_name;
end;
$assert_true$;

create or replace function pg_temp.assert_expected_error(
  p_sqlstate text, p_message text, p_marker text, p_name text
) returns void language plpgsql as $assert_error$
begin
  perform pg_temp.assert_true(
    p_sqlstate = 'P0001' and position(p_marker in p_message) > 0, p_name
  );
end;
$assert_error$;

create or replace function pg_temp.assert_expected_sqlstate(
  p_sqlstate text, p_expected text, p_name text
) returns void language plpgsql as $assert_sqlstate$
begin
  perform pg_temp.assert_true(p_sqlstate = p_expected, p_name);
end;
$assert_sqlstate$;

do $part_a$
declare
  v_owner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_marker text := 'review-contract-' || replace(gen_random_uuid()::text, '-', '');
  v_baseline_count integer;
  v_list uuid;
  v_item uuid;
  v_duplicate_item uuid;
  v_revision bigint;
  v_result record;
  v_replayed record;
  v_error_state text;
  v_error_message text;
  v_index_predicate text;
  v_definition text;
  v_status text;
begin
  -- Baseline rows are captured before any dedicated fixture exists.  The local
  -- Phase 3.5 baseline is deliberately fixed at 16 rows.
  select count(*) into v_baseline_count from public.kitchen_shopping_items;
  perform pg_temp.assert_true(v_baseline_count = 16, 'backfill_baseline_item_count_16');
  perform pg_temp.assert_true((select count(*) = 16 from public.kitchen_shopping_items where review_status = 'required'), 'backfill_required_16');
  perform pg_temp.assert_true((select count(*) = 16 from public.kitchen_shopping_items where reviewed_at is null), 'backfill_reviewed_at_null_16');
  perform pg_temp.assert_true((select count(*) = 16 from public.kitchen_shopping_items where revision = 0), 'backfill_revision_zero_16');
  perform pg_temp.assert_true((select count(*) = 16 from public.kitchen_shopping_items where status = 'pending'), 'backfill_pending_16');
  perform pg_temp.assert_true((select count(*) = 16 from public.kitchen_shopping_items as item join public.kitchen_shopping_lists as list on list.id = item.list_id where item.owner_id = list.owner_id), 'backfill_owner_list_match_16');
  perform pg_temp.assert_true((select count(*) = 16 from public.kitchen_shopping_items where btrim(coalesce(name, '')) <> '' and btrim(coalesce(normalized_name, '')) <> '' and btrim(coalesce(ingredient_text, '')) <> ''), 'backfill_text_fields_nonblank_16');

  -- Schema: catalog metadata plus the review RPC behavior below establish both
  -- the declared contract and its enforcement path.
  perform pg_temp.assert_true(exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'kitchen_shopping_items' and column_name = 'review_status'), 'schema_review_status_exists');
  perform pg_temp.assert_true(exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'kitchen_shopping_items' and column_name = 'review_status' and data_type = 'text' and is_nullable = 'NO'), 'schema_review_status_text_not_null');
  perform pg_temp.assert_true(exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'kitchen_shopping_items' and column_name = 'review_status' and column_default = '''required''::text'), 'schema_review_status_default_required');
  perform pg_temp.assert_true(exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'kitchen_shopping_items' and column_name = 'reviewed_at' and data_type = 'timestamp with time zone' and is_nullable = 'YES'), 'schema_reviewed_at_nullable');
  perform pg_temp.assert_true(exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'kitchen_shopping_items' and column_name = 'revision' and data_type = 'bigint' and is_nullable = 'NO' and column_default = '0'), 'schema_revision_bigint_not_null_default_zero');
  perform pg_temp.assert_true(exists (select 1 from pg_constraint where conrelid = 'public.kitchen_shopping_items'::regclass and conname = 'kitchen_shopping_items_review_status_check' and contype = 'c'), 'schema_review_status_check');
  perform pg_temp.assert_true(exists (select 1 from pg_constraint where conrelid = 'public.kitchen_shopping_items'::regclass and conname = 'kitchen_shopping_items_review_timestamp_check' and contype = 'c'), 'schema_review_timestamp_check');
  perform pg_temp.assert_true(exists (select 1 from pg_constraint where conrelid = 'public.kitchen_shopping_items'::regclass and conname = 'kitchen_shopping_items_revision_check' and contype = 'c'), 'schema_revision_nonnegative_check');
  perform pg_temp.assert_true(exists (select 1 from pg_constraint where conrelid = 'public.kitchen_shopping_items'::regclass and conname = 'kitchen_shopping_items_purchased_review_check' and contype = 'c') and exists (select 1 from pg_constraint where conrelid = 'public.kitchen_shopping_items'::regclass and conname = 'kitchen_shopping_items_confirmed_quantity_unit_check' and contype = 'c'), 'schema_purchased_review_quantity_unit_checks');
  select coalesce(pg_get_expr(indexprs, indrelid), '') || ' ' || coalesce(pg_get_expr(indpred, indrelid), '') into v_index_predicate from pg_index where indexrelid = 'public.kitchen_shopping_items_owner_list_review_required_idx'::regclass;
  perform pg_temp.assert_true(v_index_predicate like '%review_status%' and v_index_predicate like '%required%', 'schema_required_review_partial_index');
  perform pg_temp.assert_true(exists (select 1 from pg_trigger where tgrelid = 'public.kitchen_shopping_items'::regclass and tgname = 'kitchen_shopping_items_legacy_check_sync' and not tgisinternal), 'schema_status_is_checked_compatibility_trigger');
  perform pg_temp.assert_true(exists (select 1 from pg_proc where oid = 'public.sync_kitchen_shopping_item_legacy_check()'::regprocedure) and exists (select 1 from pg_trigger where tgrelid = 'public.kitchen_shopping_items'::regclass and tgfoid = 'public.sync_kitchen_shopping_item_legacy_check()'::regprocedure), 'schema_revision_trigger_function_bound');

  -- Security catalog checks. Definitions are inspected but never emitted.
  perform pg_temp.assert_true('public.review_kitchen_shopping_item(uuid,text,numeric,text,bigint)'::regprocedure is not null and 'public.set_kitchen_shopping_item_status(uuid,text,bigint)'::regprocedure is not null, 'security_review_rpcs_exist');
  perform pg_temp.assert_true(pg_get_function_identity_arguments('public.review_kitchen_shopping_item(uuid,text,numeric,text,bigint)'::regprocedure) = 'p_item_id uuid, p_name text, p_quantity numeric, p_unit text, p_expected_revision bigint' and pg_get_function_identity_arguments('public.set_kitchen_shopping_item_status(uuid,text,bigint)'::regprocedure) = 'p_item_id uuid, p_status text, p_expected_revision bigint', 'security_review_rpc_signatures_exact');
  perform pg_temp.assert_true(not has_function_privilege('public', 'public.review_kitchen_shopping_item(uuid,text,numeric,text,bigint)'::regprocedure, 'execute') and not has_function_privilege('public', 'public.set_kitchen_shopping_item_status(uuid,text,bigint)'::regprocedure, 'execute'), 'security_review_rpcs_no_public_execute');
  perform pg_temp.assert_true(not has_function_privilege('anon', 'public.review_kitchen_shopping_item(uuid,text,numeric,text,bigint)'::regprocedure, 'execute') and not has_function_privilege('anon', 'public.set_kitchen_shopping_item_status(uuid,text,bigint)'::regprocedure, 'execute'), 'security_review_rpcs_no_anon_execute');
  perform pg_temp.assert_true(has_function_privilege('authenticated', 'public.review_kitchen_shopping_item(uuid,text,numeric,text,bigint)'::regprocedure, 'execute') and has_function_privilege('authenticated', 'public.set_kitchen_shopping_item_status(uuid,text,bigint)'::regprocedure, 'execute'), 'security_review_rpcs_authenticated_execute');
  perform pg_temp.assert_true((select prosecdef and coalesce(array_to_string(proconfig, ','), '') like '%search_path=pg_catalog, public, pg_temp%' from pg_proc where oid = 'public.review_kitchen_shopping_item(uuid,text,numeric,text,bigint)'::regprocedure) and (select prosecdef and coalesce(array_to_string(proconfig, ','), '') like '%search_path=pg_catalog, public, pg_temp%' from pg_proc where oid = 'public.set_kitchen_shopping_item_status(uuid,text,bigint)'::regprocedure), 'security_definer_fixed_search_path');
  select pg_get_functiondef('public.review_kitchen_shopping_item(uuid,text,numeric,text,bigint)'::regprocedure) || pg_get_functiondef('public.set_kitchen_shopping_item_status(uuid,text,bigint)'::regprocedure) into v_definition;
  perform pg_temp.assert_true(v_definition like '%public.kitchen_shopping_items%' and v_definition like '%public.kitchen_shopping_lists%' and v_definition !~ E'(?i)(from|update)[[:space:]]+kitchen_shopping_(items|lists)', 'security_relation_qualification_policy');
  perform pg_temp.assert_true((select relrowsecurity from pg_class where oid = 'public.kitchen_shopping_items'::regclass) and (select relrowsecurity from pg_class where oid = 'public.kitchen_shopping_lists'::regclass), 'security_rls_enabled');
  perform pg_temp.assert_true(not exists (select 1 from pg_proc where oid in ('public.review_kitchen_shopping_item(uuid,text,numeric,text,bigint)'::regprocedure, 'public.set_kitchen_shopping_item_status(uuid,text,bigint)'::regprocedure) and 'owner_id' = any(proargnames)), 'security_review_rpcs_no_owner_argument');

  insert into auth.users(id) values (v_owner), (v_other);
  insert into public.profiles(id) values (v_owner), (v_other);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  -- Structured create: all rows use this transaction's unique marker.
  select list_id into v_list from public.create_kitchen_shopping_list(
    'public:' || v_marker,
    jsonb_build_array(jsonb_build_object('name', '  Create L  ', 'ingredient_text', 'raw create original', 'quantity', 1, 'unit', 'L')),
    gen_random_uuid()
  );
  select id, revision into v_item, v_revision from public.kitchen_shopping_items where list_id = v_list and owner_id = v_owner;
  perform pg_temp.assert_true((select review_status = 'confirmed' and reviewed_at is not null and revision = 0 and normalized_name = 'create l' and ingredient_text = 'raw create original' and quantity = 1 and unit = 'l' from public.kitchen_shopping_items where id = v_item), 'create_structured_confirmed_canonical_preserved');
  perform pg_temp.assert_true((select count(*) = 1 from public.kitchen_shopping_items where list_id = v_list), 'create_structured_item_created');
  select * into v_replayed from public.create_kitchen_shopping_list('public:' || v_marker, jsonb_build_array(jsonb_build_object('name', 'ignored replay', 'ingredient_text', 'ignored replay')), (select create_idempotency_key from public.kitchen_shopping_lists where id = v_list));
  perform pg_temp.assert_true(v_replayed.replayed and v_replayed.list_id = v_list and (select count(*) = 1 from public.kitchen_shopping_lists where owner_id = v_owner and source_recipe_id = 'public:' || v_marker) and (select count(*) = 1 from public.kitchen_shopping_items where list_id = v_list), 'create_idempotency_replay_no_duplicate_list_or_item');

  select list_id into v_duplicate_item from public.create_kitchen_shopping_list('public:' || v_marker || '-nulls', jsonb_build_array(jsonb_build_object('name', 'Create Nulls', 'ingredient_text', 'raw nulls', 'quantity', null, 'unit', null)), gen_random_uuid());
  perform pg_temp.assert_true((select quantity is null and unit is null from public.kitchen_shopping_items where list_id = v_duplicate_item), 'create_quantity_unit_both_null_allowed');
  select list_id into v_duplicate_item from public.create_kitchen_shopping_list('public:' || v_marker || '-ea', jsonb_build_array(jsonb_build_object('name', 'Create Each', 'ingredient_text', 'raw each', 'quantity', 2, 'unit', '개')), gen_random_uuid());
  perform pg_temp.assert_true((select unit = 'ea' from public.kitchen_shopping_items where list_id = v_duplicate_item), 'create_korean_each_canonicalized');

  foreach v_status in array array['quantity_only','unit_only','zero_quantity','negative_quantity','noncanonical_unit','client_review_status','client_reviewed_at','client_revision','client_normalized_name','client_owner_id'] loop
    v_error_state := null; v_error_message := null;
    begin
      if v_status = 'quantity_only' then perform * from public.create_kitchen_shopping_list('public:' || v_marker, '[{"name":"bad","ingredient_text":"raw","quantity":1}]'::jsonb, gen_random_uuid());
      elsif v_status = 'unit_only' then perform * from public.create_kitchen_shopping_list('public:' || v_marker, '[{"name":"bad","ingredient_text":"raw","unit":"g"}]'::jsonb, gen_random_uuid());
      elsif v_status = 'zero_quantity' then perform * from public.create_kitchen_shopping_list('public:' || v_marker, '[{"name":"bad","ingredient_text":"raw","quantity":0,"unit":"g"}]'::jsonb, gen_random_uuid());
      elsif v_status = 'negative_quantity' then perform * from public.create_kitchen_shopping_list('public:' || v_marker, '[{"name":"bad","ingredient_text":"raw","quantity":-1,"unit":"g"}]'::jsonb, gen_random_uuid());
      elsif v_status = 'noncanonical_unit' then perform * from public.create_kitchen_shopping_list('public:' || v_marker, '[{"name":"bad","ingredient_text":"raw","quantity":1,"unit":"cup"}]'::jsonb, gen_random_uuid());
      elsif v_status = 'client_review_status' then perform * from public.create_kitchen_shopping_list('public:' || v_marker, '[{"name":"bad","ingredient_text":"raw","review_status":"required"}]'::jsonb, gen_random_uuid());
      elsif v_status = 'client_reviewed_at' then perform * from public.create_kitchen_shopping_list('public:' || v_marker, '[{"name":"bad","ingredient_text":"raw","reviewed_at":"2020-01-01T00:00:00Z"}]'::jsonb, gen_random_uuid());
      elsif v_status = 'client_revision' then perform * from public.create_kitchen_shopping_list('public:' || v_marker, '[{"name":"bad","ingredient_text":"raw","revision":0}]'::jsonb, gen_random_uuid());
      elsif v_status = 'client_normalized_name' then perform * from public.create_kitchen_shopping_list('public:' || v_marker, '[{"name":"bad","ingredient_text":"raw","normalized_name":"bad"}]'::jsonb, gen_random_uuid());
      else perform * from public.create_kitchen_shopping_list('public:' || v_marker, jsonb_build_array(jsonb_build_object('name','bad','ingredient_text','raw','owner_id',v_other)), gen_random_uuid());
      end if;
    exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
    end;
    perform pg_temp.assert_expected_error(v_error_state, v_error_message, case when v_status in ('quantity_only','unit_only','zero_quantity','negative_quantity','noncanonical_unit') then 'invalid kitchen shopping item quantity or unit' else 'invalid kitchen shopping item payload' end, 'create_rejects_' || v_status);
  end loop;

  -- Review behavior on a dedicated active list/item.
  select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-review', jsonb_build_array(jsonb_build_object('name','Review Original','ingredient_text','raw review original','quantity',null,'unit',null)), gen_random_uuid());
  select id, revision into v_item, v_revision from public.kitchen_shopping_items where list_id = v_list;
  select * into v_result from public.review_kitchen_shopping_item(v_item, '  Review Changed  ', null, null, v_revision);
  perform pg_temp.assert_true(v_result.review_status = 'confirmed' and v_result.revision = v_revision + 1 and (select reviewed_at is not null and name = 'Review Changed' and normalized_name = 'review changed' and ingredient_text = 'raw review original' and quantity is null and unit is null from public.kitchen_shopping_items where id = v_item), 'review_owner_confirmed_trim_revision');
  v_revision := v_result.revision;
  select * into v_result from public.review_kitchen_shopping_item(v_item, 'Review Changed', null, null, v_revision - 1);
  perform pg_temp.assert_true(v_result.revision = v_revision and (select revision = v_revision from public.kitchen_shopping_items where id = v_item), 'review_same_value_stale_idempotent');
  select * into v_result from public.review_kitchen_shopping_item(v_item, 'Review Changed', null, null, v_revision);
  perform pg_temp.assert_true(v_result.revision = v_revision and (select revision = v_revision from public.kitchen_shopping_items where id = v_item), 'review_same_value_no_extra_revision');

  foreach v_status in array array['other_user','null_auth','quantity_only','unit_only','noncanonical_unit','duplicate_normalized_name','stale_changed_value'] loop
    v_error_state := null; v_error_message := null;
    begin
      if v_status = 'other_user' then perform set_config('request.jwt.claim.sub', v_other::text, true); perform * from public.review_kitchen_shopping_item(v_item, 'Other', null, null, v_revision);
      elsif v_status = 'null_auth' then perform set_config('request.jwt.claim.sub', '', true); perform * from public.review_kitchen_shopping_item(v_item, 'No Auth', null, null, v_revision);
      elsif v_status = 'quantity_only' then perform set_config('request.jwt.claim.sub', v_owner::text, true); perform * from public.review_kitchen_shopping_item(v_item, 'Quantity Only', 1, null, v_revision);
      elsif v_status = 'unit_only' then perform * from public.review_kitchen_shopping_item(v_item, 'Unit Only', null, 'g', v_revision);
      elsif v_status = 'noncanonical_unit' then perform * from public.review_kitchen_shopping_item(v_item, 'Bad Unit', 1, 'cup', v_revision);
      elsif v_status = 'duplicate_normalized_name' then
        select id into v_duplicate_item from public.kitchen_shopping_items where list_id = v_list and id <> v_item limit 1;
        if v_duplicate_item is null then
          perform set_config('app.kitchen_create_rpc', '1', true);
          insert into public.kitchen_shopping_items(list_id, owner_id, name, normalized_name, ingredient_text, quantity, unit, review_status, reviewed_at) values (v_list, v_owner, 'Duplicate Name', 'duplicate name', 'raw duplicate', null, null, 'confirmed', transaction_timestamp()) returning id into v_duplicate_item;
        end if;
        perform * from public.review_kitchen_shopping_item(v_item, 'Duplicate Name', null, null, v_revision);
      else perform * from public.review_kitchen_shopping_item(v_item, 'Stale Changed', null, null, v_revision - 1);
      end if;
    exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
    end;
    perform pg_temp.assert_expected_error(v_error_state, v_error_message, case when v_status = 'other_user' then 'shopping item not found' when v_status = 'null_auth' then 'authentication required' when v_status = 'duplicate_normalized_name' then 'duplicate canonical shopping item name' when v_status = 'stale_changed_value' then 'shopping item revision conflict' else 'shopping item review values are invalid' end, 'review_rejects_' || v_status);
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
  end loop;

  -- The duplicate fixture has a confirmed review but is not used to change any
  -- baseline row.  Direct review-field writes must still be trigger-rejected.
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  v_error_state := null; v_error_message := null;
  begin update public.kitchen_shopping_items
    set name = 'Direct Review Mutation', normalized_name = 'direct review mutation',
        quantity = 2, unit = 'g', review_status = 'confirmed', reviewed_at = transaction_timestamp()
    where id = v_item;
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping item review fields can only change through the review RPC', 'schema_revision_trigger_rejects_direct_review_write');

  perform set_config('app.kitchen_create_rpc', '1', true);
  v_error_state := null;
  begin
    insert into public.kitchen_shopping_items(list_id, owner_id, name, normalized_name, ingredient_text, status, is_checked, review_status, reviewed_at)
    values (v_list, v_owner, 'Invalid Review Status', 'invalid review status', 'raw invalid status', 'pending', false, 'invalid', null);
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate;
  end;
  perform pg_temp.assert_expected_sqlstate(v_error_state, '23514', 'schema_review_status_check_enforced');
  v_error_state := null;
  begin
    insert into public.kitchen_shopping_items(list_id, owner_id, name, normalized_name, ingredient_text, status, is_checked, review_status, reviewed_at)
    values (v_list, v_owner, 'Invalid Review Time', 'invalid review time', 'raw invalid time', 'pending', false, 'required', transaction_timestamp());
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate;
  end;
  perform pg_temp.assert_expected_sqlstate(v_error_state, '23514', 'schema_review_timestamp_check_enforced');
  v_error_state := null;
  begin
    insert into public.kitchen_shopping_items(list_id, owner_id, name, normalized_name, ingredient_text, status, is_checked, revision)
    values (v_list, v_owner, 'Invalid Revision', 'invalid revision', 'raw invalid revision', 'pending', false, -1);
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate;
  end;
  perform pg_temp.assert_expected_sqlstate(v_error_state, '23514', 'schema_revision_nonnegative_check_enforced');

  v_error_state := null; v_error_message := null;
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  begin update public.kitchen_shopping_items set status = 'purchased' where id = v_item;
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping item status can only change through the status RPC', 'schema_direct_status_rejected_before_purchase_constraint');

  -- List status has no literal "inactive" value; every non-active state is
  -- exercised, and the active-list success above verifies the complement.
  foreach v_status in array array['completed','cancelled','archived'] loop
    update public.kitchen_shopping_lists set status = v_status where id = v_list and owner_id = v_owner;
    v_error_state := null; v_error_message := null;
    begin perform * from public.review_kitchen_shopping_item(v_item, 'List ' || v_status, null, null, v_revision);
    exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
    end;
    perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping list is not active', 'review_rejects_' || v_status || '_list');
    update public.kitchen_shopping_lists set status = 'active' where id = v_list and owner_id = v_owner;
  end loop;

  -- Status RPC follows the same auth contract; use its own behavior, not just existence.
  perform set_config('request.jwt.claim.sub', '', true);
  v_error_state := null; v_error_message := null;
  begin perform * from public.set_kitchen_shopping_item_status(v_item, 'pending', v_revision);
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'authentication required', 'security_status_rpc_null_auth_rejected');
  perform set_config('request.jwt.claim.sub', v_other::text, true);
  v_error_state := null; v_error_message := null;
  begin perform * from public.set_kitchen_shopping_item_status(v_item, 'pending', v_revision);
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping item not found', 'security_status_rpc_other_user_rejected');
end;
$part_a$;

-- Part B contract suite.  Its marker, users, lists, and items are independent
-- from Part A and from the fixed sixteen-row backfill fixture.
do $part_b$
declare
  v_owner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_marker text := 'review-contract-part-b-' || replace(gen_random_uuid()::text, '-', '');
  v_list uuid;
  v_status_list uuid;
  v_item uuid;
  v_item_two uuid;
  v_revision bigint;
  v_before_revision bigint;
  v_before_updated_at timestamptz;
  v_completed_at timestamptz;
  v_key uuid;
  v_result record;
  v_error_state text;
  v_error_message text;
  v_definition text;
  v_inventory_before numeric;
  v_required_inventory_before integer;
  v_ledger_before integer;
  v_status text;
begin
  insert into auth.users(id) values (v_owner), (v_other);
  insert into public.profiles(id) values (v_owner), (v_other);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  -- Status success, status/is_checked synchronization, and revision behavior.
  select list_id into v_list from public.create_kitchen_shopping_list(
    'public:' || v_marker || '-status',
    jsonb_build_array(jsonb_build_object('name', 'Part B Status Mass', 'ingredient_text', 'part b status raw', 'quantity', 2, 'unit', 'g')),
    gen_random_uuid()
  );
  select id, revision, updated_at into v_item, v_revision, v_before_updated_at from public.kitchen_shopping_items where list_id = v_list;
  v_status_list := v_list;
  select * into v_result from public.set_kitchen_shopping_item_status(v_item, 'skipped', v_revision);
  perform pg_temp.assert_true(v_result.status = 'skipped' and v_result.revision = v_revision + 1 and (select status = 'skipped' and not is_checked and updated_at >= v_before_updated_at from public.kitchen_shopping_items where id = v_item), 'part_b_status_pending_to_skipped_revision_checked_active');
  v_revision := v_result.revision;
  select * into v_result from public.set_kitchen_shopping_item_status(v_item, 'pending', v_revision);
  perform pg_temp.assert_true(v_result.status = 'pending' and v_result.revision = v_revision + 1 and (select not is_checked and status = 'pending' from public.kitchen_shopping_items where id = v_item), 'part_b_status_skipped_to_pending_sync');
  v_revision := v_result.revision;
  select * into v_result from public.set_kitchen_shopping_item_status(v_item, 'unavailable', v_revision);
  perform pg_temp.assert_true(v_result.status = 'unavailable' and v_result.revision = v_revision + 1 and (select not is_checked from public.kitchen_shopping_items where id = v_item), 'part_b_status_pending_to_unavailable_revision_checked');
  v_revision := v_result.revision;
  select * into v_result from public.set_kitchen_shopping_item_status(v_item, 'pending', v_revision);
  perform pg_temp.assert_true(v_result.status = 'pending' and v_result.revision = v_revision + 1 and (select not is_checked from public.kitchen_shopping_items where id = v_item), 'part_b_status_unavailable_to_pending_sync');
  v_revision := v_result.revision;
  select * into v_result from public.set_kitchen_shopping_item_status(v_item, 'purchased', v_revision);
  perform pg_temp.assert_true(v_result.status = 'purchased' and v_result.review_status = 'confirmed' and v_result.revision = v_revision + 1 and (select is_checked and status = 'purchased' and updated_at is not null from public.kitchen_shopping_items where id = v_item), 'part_b_status_confirmed_valid_to_purchased_sync_updated_at');
  v_revision := v_result.revision;
  select * into v_result from public.set_kitchen_shopping_item_status(v_item, 'pending', v_revision);
  perform pg_temp.assert_true(v_result.status = 'pending' and v_result.revision = v_revision + 1 and (select not is_checked and status = 'pending' and (select status from public.kitchen_shopping_lists where id = v_list) = 'active' from public.kitchen_shopping_items where id = v_item), 'part_b_status_purchased_to_pending_list_active');
  v_revision := v_result.revision;

  -- Same desired state is a network-safe no-op even when the supplied revision is stale.
  select * into v_result from public.set_kitchen_shopping_item_status(v_item, 'pending', v_revision);
  perform pg_temp.assert_true(v_result.revision = v_revision and (select revision = v_revision from public.kitchen_shopping_items where id = v_item), 'part_b_status_same_state_current_revision_idempotent');
  select * into v_result from public.set_kitchen_shopping_item_status(v_item, 'pending', v_revision - 1);
  perform pg_temp.assert_true(v_result.revision = v_revision and v_result.status = 'pending' and (select revision = v_revision from public.kitchen_shopping_items where id = v_item), 'part_b_status_same_state_stale_revision_idempotent');
  v_before_revision := v_revision;
  select * into v_result from public.set_kitchen_shopping_item_status(v_item, 'pending', v_revision - 5);
  perform pg_temp.assert_true(v_result.revision = v_before_revision and (select revision = v_before_revision and status = 'pending' from public.kitchen_shopping_items where id = v_item), 'part_b_status_network_retry_same_value_consistent');
  v_error_state := null; v_error_message := null;
  begin perform * from public.set_kitchen_shopping_item_status(v_item, 'skipped', v_revision - 1);
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping item revision conflict', 'part_b_status_changed_value_stale_conflict');
  perform pg_temp.assert_true((select status = 'pending' and revision = v_revision from public.kitchen_shopping_items where id = v_item), 'part_b_status_conflict_preserves_row');

  -- Input, ownership, authentication, and non-active-list failures are verified
  -- with error markers rather than catch-and-pass behavior.
  foreach v_status in array array['bad_status','null_status','blank_status','required_purchased','null_quantity_purchased','null_unit_purchased','zero_quantity_purchased','negative_quantity_purchased','noncanonical_unit_purchased','other_user','null_auth','missing_item'] loop
    v_error_state := null; v_error_message := null;
    begin
      if v_status = 'bad_status' then perform * from public.set_kitchen_shopping_item_status(v_item, 'done', v_revision);
      elsif v_status = 'null_status' then perform * from public.set_kitchen_shopping_item_status(v_item, null, v_revision);
      elsif v_status = 'blank_status' then perform * from public.set_kitchen_shopping_item_status(v_item, ' ', v_revision);
      elsif v_status = 'required_purchased' then
        select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-required', jsonb_build_array(jsonb_build_object('name','Part B Required','ingredient_text','part b required raw')), gen_random_uuid());
        select id, revision into v_item_two, v_before_revision from public.kitchen_shopping_items where list_id = v_list;
        perform * from public.set_kitchen_shopping_item_status(v_item_two, 'purchased', v_before_revision);
      elsif v_status in ('null_quantity_purchased','null_unit_purchased','zero_quantity_purchased','negative_quantity_purchased','noncanonical_unit_purchased') then
        -- The structured RPC rejects malformed confirmed values at the DB boundary.
        perform * from public.create_kitchen_shopping_list('public:' || v_marker || '-' || v_status,
          case v_status when 'null_quantity_purchased' then '[{"name":"Part B Bad Q","ingredient_text":"raw","unit":"g"}]'::jsonb
                        when 'null_unit_purchased' then '[{"name":"Part B Bad U","ingredient_text":"raw","quantity":1}]'::jsonb
                        when 'zero_quantity_purchased' then '[{"name":"Part B Zero","ingredient_text":"raw","quantity":0,"unit":"g"}]'::jsonb
                        when 'negative_quantity_purchased' then '[{"name":"Part B Negative","ingredient_text":"raw","quantity":-1,"unit":"g"}]'::jsonb
                        else '[{"name":"Part B Cup","ingredient_text":"raw","quantity":1,"unit":"cup"}]'::jsonb end, gen_random_uuid());
      elsif v_status = 'other_user' then perform set_config('request.jwt.claim.sub', v_other::text, true); perform * from public.set_kitchen_shopping_item_status(v_item, 'skipped', v_revision);
      elsif v_status = 'null_auth' then perform set_config('request.jwt.claim.sub', '', true); perform * from public.set_kitchen_shopping_item_status(v_item, 'skipped', v_revision);
      else perform * from public.set_kitchen_shopping_item_status(gen_random_uuid(), 'skipped', 0);
      end if;
    exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
    end;
    perform pg_temp.assert_expected_error(v_error_state, v_error_message,
      case when v_status in ('bad_status','null_status','blank_status') then 'invalid shopping item status request'
           when v_status = 'required_purchased' then 'purchased shopping item is not review-ready'
           when v_status in ('other_user','missing_item') then 'shopping item not found'
           when v_status = 'null_auth' then 'authentication required'
           else 'invalid kitchen shopping item quantity or unit' end,
      'part_b_status_rejects_' || v_status);
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
  end loop;
  foreach v_status in array array['completed','cancelled','archived'] loop
    update public.kitchen_shopping_lists set status = v_status where id = v_status_list and owner_id = v_owner;
    v_error_state := null; v_error_message := null;
    begin perform * from public.set_kitchen_shopping_item_status(v_item, 'skipped', v_revision);
    exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
    end;
    perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping list is not active', 'part_b_status_rejects_' || v_status || '_list');
    update public.kitchen_shopping_lists set status = 'active' where id = v_status_list and owner_id = v_owner;
  end loop;

  -- Required reviews use dedicated direct fixtures so create RPC's confirmed
  -- default cannot become the initial state of this policy test.
  insert into public.kitchen_shopping_lists(owner_id, status, title, source_recipe_id)
    values (v_owner, 'active', 'Part B Required Skip Fixture', 'public:' || v_marker || '-required-skip') returning id into v_list;
  insert into public.kitchen_shopping_items(list_id, owner_id, name, normalized_name, ingredient_text, status, is_checked, review_status, reviewed_at, revision)
    values (v_list, v_owner, 'Required Skip Fixture', 'required skip fixture', 'required skip raw', 'pending', false, 'required', null, 0)
    returning id, revision into v_item_two, v_before_revision;
  select count(*) into v_required_inventory_before from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'required skip fixture';
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  select * into v_result from public.set_kitchen_shopping_item_status(v_item_two, 'skipped', v_before_revision);
  perform pg_temp.assert_true(v_result.status = 'skipped', 'required_skipped_rpc_result_status');
  perform pg_temp.assert_true((select status = 'skipped' from public.kitchen_shopping_items where id = v_item_two), 'required_skipped_row_status');
  perform pg_temp.assert_true((select review_status = 'required' and reviewed_at is null from public.kitchen_shopping_items where id = v_item_two), 'required_skipped_review_status_preserved');
  perform pg_temp.assert_true((select not is_checked from public.kitchen_shopping_items where id = v_item_two), 'required_skipped_is_checked_false');
  perform pg_temp.assert_true((select revision = v_before_revision + 1 from public.kitchen_shopping_items where id = v_item_two), 'required_skipped_revision_incremented');
  perform pg_temp.assert_true((select count(*) = v_required_inventory_before from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'required skip fixture'), 'required_skipped_inventory_unchanged');
  select * into v_result from public.set_kitchen_shopping_item_status(v_item_two, 'pending', v_result.revision);
  perform pg_temp.assert_true(v_result.status = 'pending' and (select status = 'pending' and review_status = 'required' and reviewed_at is null and not is_checked from public.kitchen_shopping_items where id = v_item_two), 'part_b_required_pending_return_preserves_review');

  insert into public.kitchen_shopping_lists(owner_id, status, title, source_recipe_id)
    values (v_owner, 'active', 'Part B Required Unavailable Fixture', 'public:' || v_marker || '-required-unavailable') returning id into v_list;
  insert into public.kitchen_shopping_items(list_id, owner_id, name, normalized_name, ingredient_text, status, is_checked, review_status, reviewed_at, revision)
    values (v_list, v_owner, 'Required Unavailable Fixture', 'required unavailable fixture', 'required unavailable raw', 'pending', false, 'required', null, 0)
    returning id, revision into v_item_two, v_before_revision;
  select count(*) into v_required_inventory_before from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'required unavailable fixture';
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  select * into v_result from public.set_kitchen_shopping_item_status(v_item_two, 'unavailable', v_before_revision);
  perform pg_temp.assert_true(v_result.status = 'unavailable', 'required_unavailable_rpc_result_status');
  perform pg_temp.assert_true((select status = 'unavailable' from public.kitchen_shopping_items where id = v_item_two), 'required_unavailable_row_status');
  perform pg_temp.assert_true((select review_status = 'required' and reviewed_at is null and not is_checked from public.kitchen_shopping_items where id = v_item_two), 'required_unavailable_review_status_preserved');
  perform pg_temp.assert_true((select revision = v_before_revision + 1 from public.kitchen_shopping_items where id = v_item_two), 'required_unavailable_revision_incremented');
  perform pg_temp.assert_true((select count(*) = v_required_inventory_before from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'required unavailable fixture'), 'required_unavailable_inventory_unchanged');

  -- Legacy boolean compatibility exercises the actual trigger without disabling it.
  select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-legacy', jsonb_build_array(jsonb_build_object('name','Part B Legacy','ingredient_text','part b legacy raw','quantity',3,'unit','g')), gen_random_uuid());
  select id, revision into v_item, v_revision from public.kitchen_shopping_items where list_id = v_list;
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  update public.kitchen_shopping_items set is_checked = true where id = v_item;
  perform pg_temp.assert_true((select status = 'purchased' and is_checked and revision = v_revision + 1 and name = 'Part B Legacy' and ingredient_text = 'part b legacy raw' and quantity = 3 and unit = 'g' from public.kitchen_shopping_items where id = v_item), 'part_b_legacy_checked_true_purchases_once_preserves_fields');
  v_revision := v_revision + 1;
  v_error_state := null; v_error_message := null;
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  begin update public.kitchen_shopping_items set status = 'skipped' where id = v_item;
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping item status can only change through the status RPC', 'part_b_legacy_status_only_direct_rejected');
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  update public.kitchen_shopping_items set is_checked = false where id = v_item;
  perform pg_temp.assert_true((select status = 'pending' and not is_checked and revision = v_revision + 1 from public.kitchen_shopping_items where id = v_item), 'part_b_legacy_checked_false_pending_once');
  v_revision := v_revision + 1;
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  update public.kitchen_shopping_items set is_checked = false where id = v_item;
  perform pg_temp.assert_true((select revision = v_revision and status = 'pending' and not is_checked from public.kitchen_shopping_items where id = v_item), 'part_b_legacy_same_value_no_extra_revision_or_recursion');
  v_error_state := null; v_error_message := null;
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  begin update public.kitchen_shopping_items set status = 'skipped', is_checked = true where id = v_item;
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping item status can only change through the status RPC', 'part_b_legacy_status_and_checked_direct_rejected');
  select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-legacy-required', jsonb_build_array(jsonb_build_object('name','Part B Legacy Required','ingredient_text','part b legacy required raw')), gen_random_uuid());
  select id into v_item_two from public.kitchen_shopping_items where list_id = v_list;
  v_error_state := null; v_error_message := null;
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  begin update public.kitchen_shopping_items set is_checked = true where id = v_item_two;
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'purchased shopping items require confirmed review and a canonical quantity and unit', 'part_b_legacy_required_checked_true_cannot_bypass_purchase');
  foreach v_status in array array['completed','cancelled','archived'] loop
    update public.kitchen_shopping_lists set status = v_status where id = v_list and owner_id = v_owner;
    v_error_state := null; v_error_message := null;
    perform set_config('app.kitchen_review_rpc', '0', true);
    perform set_config('app.kitchen_status_rpc', '0', true);
    begin update public.kitchen_shopping_items set is_checked = true where id = v_item_two;
    exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
    end;
    perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping items can only change while their list is active', 'part_b_legacy_rejects_' || v_status || '_list');
  end loop;

  -- Completion normal behavior and idempotency use separate resolved fixtures.
  select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-complete', jsonb_build_array(
    jsonb_build_object('name','Part B Complete G','ingredient_text','not-a-key-g','quantity',2,'unit','g'),
    jsonb_build_object('name','Part B Complete Skip','ingredient_text','not-a-key-skip','quantity',1,'unit','g'),
    jsonb_build_object('name','Part B Complete Unavailable','ingredient_text','not-a-key-unavailable','quantity',1,'unit','g')), gen_random_uuid());
  select id, revision into v_item, v_revision from public.kitchen_shopping_items where list_id = v_list and normalized_name = 'part b complete g';
  perform * from public.set_kitchen_shopping_item_status(v_item, 'purchased', v_revision);
  select id, revision into v_item, v_revision from public.kitchen_shopping_items where list_id = v_list and normalized_name = 'part b complete skip';
  perform * from public.set_kitchen_shopping_item_status(v_item, 'skipped', v_revision);
  select id, revision into v_item, v_revision from public.kitchen_shopping_items where list_id = v_list and normalized_name = 'part b complete unavailable';
  perform * from public.set_kitchen_shopping_item_status(v_item, 'unavailable', v_revision);
  v_key := gen_random_uuid();
  select * into v_result from public.complete_kitchen_shopping_list(v_list, v_key);
  perform pg_temp.assert_true(v_result.status = 'completed' and v_result.purchased_count = 1 and v_result.skipped_count = 1 and v_result.unavailable_count = 1 and v_result.inventory_change_count = 1 and (select status = 'completed' and completed_at is not null from public.kitchen_shopping_lists where id = v_list), 'part_b_completion_confirmed_purchased_only_marks_completed');
  select completed_at into v_completed_at from public.kitchen_shopping_lists where id = v_list;
  perform pg_temp.assert_true((select quantity = 2 and unit = 'g' and name = 'Part B Complete G' from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'part b complete g') and not exists (select 1 from public.kitchen_ingredients where owner_id = v_owner and normalized_name in ('part b complete skip','part b complete unavailable')), 'part_b_completion_skipped_unavailable_not_inventory');
  perform pg_temp.assert_true((select count(*) = 3 from public.kitchen_shopping_items where list_id = v_list and ((status = 'purchased' and review_status = 'confirmed' and ingredient_text = 'not-a-key-g') or status in ('skipped','unavailable'))), 'part_b_completion_item_status_review_ingredient_preserved');
  select * into v_result from public.complete_kitchen_shopping_list(v_list, v_key);
  perform pg_temp.assert_true(v_result.replayed and v_result.inventory_change_count = 1 and (select completed_at = v_completed_at from public.kitchen_shopping_lists where id = v_list) and (select quantity = 2 from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'part b complete g'), 'part_b_completion_same_key_replay_unchanged');
  select * into v_result from public.complete_kitchen_shopping_list(v_list, gen_random_uuid());
  perform pg_temp.assert_true(not v_result.replayed and v_result.inventory_change_count = 1 and (select count(*) = 2 from public.kitchen_shopping_idempotency where owner_id = v_owner and operation = 'complete' and list_id = v_list), 'part_b_completion_different_key_ledger_consistent');

  foreach v_status in array array['skipped','unavailable'] loop
    select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-all-' || v_status, jsonb_build_array(jsonb_build_object('name','Part B All ' || v_status,'ingredient_text','part b all resolved raw')), gen_random_uuid());
    select id, revision into v_item, v_revision from public.kitchen_shopping_items where list_id = v_list;
    perform * from public.set_kitchen_shopping_item_status(v_item, v_status, v_revision);
    select * into v_result from public.complete_kitchen_shopping_list(v_list, gen_random_uuid());
    perform pg_temp.assert_true(v_result.status = 'completed' and v_result.inventory_change_count = 0 and (select status = 'completed' and completed_at is not null from public.kitchen_shopping_lists where id = v_list), 'part_b_completion_all_' || v_status || '_allowed_zero_inventory');
  end loop;

  -- Pending failures leave no successful completion ledger and can be retried.
  select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-pending', jsonb_build_array(jsonb_build_object('name','Part B Pending','ingredient_text','part b pending raw','quantity',1,'unit','ea')), gen_random_uuid());
  select id, revision into v_item, v_revision from public.kitchen_shopping_items where list_id = v_list;
  v_key := gen_random_uuid(); v_error_state := null; v_error_message := null;
  begin perform * from public.complete_kitchen_shopping_list(v_list, v_key);
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'pending shopping items must be resolved before completion', 'part_b_completion_pending_rejected');
  perform pg_temp.assert_true((select status = 'active' and completed_at is null from public.kitchen_shopping_lists where id = v_list) and not exists (select 1 from public.kitchen_shopping_idempotency where owner_id = v_owner and operation = 'complete' and idempotency_key = v_key), 'part_b_completion_pending_failure_no_ledger_or_list_change');
  perform * from public.set_kitchen_shopping_item_status(v_item, 'purchased', v_revision);
  select * into v_result from public.complete_kitchen_shopping_list(v_list, v_key);
  perform pg_temp.assert_true(v_result.status = 'completed' and v_result.inventory_change_count = 1, 'part_b_completion_pending_same_key_safe_after_resolution');

  -- Catalog proof complements DB-boundary tests for impossible malformed purchased rows.
  select pg_get_functiondef('public.complete_kitchen_shopping_list(uuid,uuid)'::regprocedure) into v_definition;
  perform pg_temp.assert_true(v_definition like '%item_review_status%<>%confirmed%' and v_definition like '%purchased shopping item lacks confirmed canonical review%' and exists (select 1 from pg_constraint where conrelid = 'public.kitchen_shopping_items'::regclass and conname = 'kitchen_shopping_items_purchased_review_check'), 'part_b_completion_review_guard_and_constraint_catalogued');
  perform pg_temp.assert_true(exists (select 1 from pg_constraint where conrelid = 'public.kitchen_shopping_items'::regclass and conname = 'kitchen_shopping_items_confirmed_quantity_unit_check'), 'part_b_completion_malformed_purchased_db_boundary_catalogued');
  perform set_config('request.jwt.claim.sub', v_other::text, true); v_error_state := null; v_error_message := null;
  begin perform * from public.complete_kitchen_shopping_list(v_list, gen_random_uuid());
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping list was not found for the authenticated user', 'part_b_completion_other_user_rejected');
  perform set_config('request.jwt.claim.sub', '', true); v_error_state := null; v_error_message := null;
  begin perform * from public.complete_kitchen_shopping_list(v_list, gen_random_uuid());
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'authentication required', 'part_b_completion_null_auth_rejected');
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  foreach v_status in array array['cancelled','archived'] loop
    select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-complete-' || v_status, jsonb_build_array(jsonb_build_object('name','Part B Closed ' || v_status,'ingredient_text','part b closed raw')), gen_random_uuid());
    update public.kitchen_shopping_lists set status = v_status where id = v_list and owner_id = v_owner;
    v_error_state := null; v_error_message := null;
    begin perform * from public.complete_kitchen_shopping_list(v_list, gen_random_uuid());
    exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
    end;
    perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'only active shopping lists can be completed', 'part_b_completion_rejects_' || v_status || '_list');
  end loop;
  v_error_state := null; v_error_message := null;
  begin perform * from public.complete_kitchen_shopping_list(gen_random_uuid(), gen_random_uuid());
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'shopping list was not found for the authenticated user', 'part_b_completion_missing_list_rejected');

  -- Canonical inventory matching, conversions, display-name preservation, and atomic rollback.
  insert into public.kitchen_ingredients(owner_id,name,normalized_name,quantity,unit) values (v_owner,'Existing Display G','part b merge g',10,'g'), (v_owner,'Existing Display ML','part b merge ml',500,'ml'), (v_owner,'Existing Display EA','part b merge ea',4,'ea'), (v_owner,'Existing Display Bad','part b merge bad',1,'ml');
  select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-merge', jsonb_build_array(
    jsonb_build_object('name','Part B Merge G','ingredient_text','different ingredient text g','quantity',1,'unit','kg'),
    jsonb_build_object('name','Part B Merge ML','ingredient_text','different ingredient text ml','quantity',1,'unit','l'),
    jsonb_build_object('name','Part B Merge EA','ingredient_text','different ingredient text ea','quantity',2,'unit','ea')), gen_random_uuid());
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  update public.kitchen_shopping_items set is_checked = true where list_id = v_list;
  select * into v_result from public.complete_kitchen_shopping_list(v_list, gen_random_uuid());
  perform pg_temp.assert_true(v_result.inventory_change_count = 3 and (select quantity = 1010 and name = 'Existing Display G' from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'part b merge g') and (select quantity = 1500 and name = 'Existing Display ML' from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'part b merge ml') and (select quantity = 6 and name = 'Existing Display EA' from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'part b merge ea'), 'part_b_inventory_normalized_match_converts_preserves_display');
  select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-new-display', jsonb_build_array(jsonb_build_object('name','Part B New Display','ingredient_text','part b unrelated raw text','quantity',5,'unit','g')), gen_random_uuid());
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  update public.kitchen_shopping_items set is_checked = true where list_id = v_list;
  perform * from public.complete_kitchen_shopping_list(v_list, gen_random_uuid());
  perform pg_temp.assert_true((select name = 'Part B New Display' and quantity = 5 from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'part b new display') and not exists (select 1 from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'part b unrelated raw text'), 'part_b_inventory_new_uses_item_name_not_ingredient_text');
  select list_id into v_list from public.create_kitchen_shopping_list('public:' || v_marker || '-rollback', jsonb_build_array(jsonb_build_object('name','Part B Merge Bad','ingredient_text','part b bad raw','quantity',1,'unit','g')), gen_random_uuid());
  perform set_config('app.kitchen_review_rpc', '0', true);
  perform set_config('app.kitchen_status_rpc', '0', true);
  update public.kitchen_shopping_items set is_checked = true where list_id = v_list;
  select quantity into v_inventory_before from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'part b merge bad';
  select count(*) into v_ledger_before from public.kitchen_shopping_idempotency where owner_id = v_owner and operation = 'complete' and list_id = v_list;
  v_key := gen_random_uuid(); v_error_state := null; v_error_message := null;
  begin perform * from public.complete_kitchen_shopping_list(v_list, v_key);
  exception when others then get stacked diagnostics v_error_state = returned_sqlstate, v_error_message = message_text;
  end;
  perform pg_temp.assert_expected_error(v_error_state, v_error_message, 'incompatible inventory units cannot be merged', 'part_b_inventory_dimension_mismatch_rejected');
  perform pg_temp.assert_true((select status = 'active' and completed_at is null from public.kitchen_shopping_lists where id = v_list) and (select quantity = v_inventory_before from public.kitchen_ingredients where owner_id = v_owner and normalized_name = 'part b merge bad') and (select status = 'purchased' from public.kitchen_shopping_items where list_id = v_list) and (select count(*) = v_ledger_before from public.kitchen_shopping_idempotency where owner_id = v_owner and operation = 'complete' and list_id = v_list), 'part_b_completion_incompatible_unit_rolls_back_everything');
end;
$part_b$;

rollback;
