-- Additive manual lists: recipe lists, purchase records and stock are untouched.
alter table public.kitchen_shopping_items add column purchase_specification text not null default ''
  check (length(purchase_specification) <= 120);
create function public.guard_shopping_specification() returns trigger
language plpgsql set search_path = pg_catalog, public, pg_temp as $$
begin
  if new.purchase_specification is distinct from old.purchase_specification then
    raise exception 'MANUAL_SPECIFICATION_IMMUTABLE';
  end if;
  return new;
end;
$$;
create trigger kitchen_shopping_specification_guard before update on public.kitchen_shopping_items
  for each row execute function public.guard_shopping_specification();
revoke all on function public.guard_shopping_specification() from public, anon, authenticated;
create table public.manual_shopping_submissions (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  request_key uuid not null,
  payload jsonb not null,
  list_id uuid references public.kitchen_shopping_lists(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(owner_id, request_key)
);
alter table public.manual_shopping_submissions enable row level security;
revoke all on public.manual_shopping_submissions from public, anon, authenticated;
grant select on public.manual_shopping_submissions to authenticated;
create policy manual_shopping_submissions_read_own
  on public.manual_shopping_submissions for select to authenticated
  using (owner_id = auth.uid());

create function public.create_manual_shopping_list(p_items jsonb, p_request_key uuid)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_owner uuid := auth.uid(); v_list uuid; v_previous public.manual_shopping_submissions;
  v_item jsonb; v_quantity numeric; v_flag text;
  v_units constant text[] := array['g','kg','oz','lb','ml','l','fl_oz','pint','quart','gallon',
    'ea','piece','slice','clove','stalk','head','dozen','pack','bag','bottle','jar','can',
    'carton','box','case','bundle','bunch','net','container','sachet','pouch','tube','tray','roll'];
begin
  if v_owner is null or coalesce(auth.jwt()->>'is_anonymous','false') = 'true' then
    raise exception 'MANUAL_AUTH_REQUIRED';
  end if;
  if p_request_key is null or p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'MANUAL_INVALID';
  end if;
  if jsonb_array_length(p_items) not between 1 and 100 or octet_length(p_items::text) > 65536 then
    raise exception 'MANUAL_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object' then raise exception 'MANUAL_INVALID'; end if;
    if (v_item - array['name','quantity','unit','specification']) <> '{}'::jsonb
       or jsonb_typeof(v_item->'name') is distinct from 'string'
       or length(btrim(v_item->>'name')) not between 1 and 200
       or jsonb_typeof(v_item->'quantity') is distinct from 'number'
       or jsonb_typeof(v_item->'unit') is distinct from 'string'
       or not ((v_item->>'unit') = any(v_units))
       or jsonb_typeof(v_item->'specification') is distinct from 'string'
       or length(v_item->>'specification') > 120 then raise exception 'MANUAL_INVALID'; end if;
    v_quantity := (v_item->>'quantity')::numeric;
    if v_quantity <= 0 or v_quantity > 1e9 or v_quantity <> round(v_quantity,6) then
      raise exception 'MANUAL_INVALID';
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended('manual-shopping:'||v_owner::text||':'||p_request_key::text,0));
  select * into v_previous from public.manual_shopping_submissions
    where owner_id=v_owner and request_key=p_request_key;
  if found then
    if v_previous.payload <> p_items then raise exception 'MANUAL_KEY_CONFLICT'; end if;
    if v_previous.list_id is null then raise exception 'MANUAL_LIST_REMOVED'; end if;
    return v_previous.list_id;
  end if;
  insert into public.kitchen_shopping_lists(owner_id,title,source_recipe_id,status)
    values(v_owner,'직접 추가한 재료 · '||to_char(now() at time zone 'Asia/Seoul','MM/DD HH24:MI'),null,'active')
    returning id into v_list;
  v_flag := coalesce(current_setting('app.kitchen_create_rpc',true),'');
  perform set_config('app.kitchen_create_rpc','1',true);
  insert into public.kitchen_shopping_items(list_id,owner_id,name,normalized_name,ingredient_text,
      quantity,unit,status,review_status,reviewed_at,revision,purchase_specification)
    select v_list,v_owner,btrim(e->>'name'),lower(btrim(e->>'name')),
      concat_ws(' ',btrim(e->>'name'),e->>'quantity',e->>'unit',nullif(btrim(e->>'specification'),'')),
      (e->>'quantity')::numeric,e->>'unit','pending','confirmed',now(),0,btrim(e->>'specification')
    from jsonb_array_elements(p_items) e;
  perform set_config('app.kitchen_create_rpc',v_flag,true);
  insert into public.manual_shopping_submissions(owner_id,request_key,payload,list_id)
    values(v_owner,p_request_key,p_items,v_list);
  return v_list;
end;
$$;
revoke all on function public.create_manual_shopping_list(jsonb,uuid) from public, anon;
grant execute on function public.create_manual_shopping_list(jsonb,uuid) to authenticated;
