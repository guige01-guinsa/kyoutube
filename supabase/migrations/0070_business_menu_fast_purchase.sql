-- Menu candidates, delegated approval and deterministic multi-supplier preparation.
begin;
-- Keep legacy non-null prices and status vocabulary for installed older clients.
alter table public.business_menu_items add column is_candidate boolean not null default false,
 add column price_confirmed boolean not null default true;
alter table public.business_menu_items add constraint business_menu_candidate_state check(not is_candidate or status='preparing');
alter table public.business_menu_items add constraint business_menu_price_ready check(is_candidate or price_confirmed);
create or replace function public.business_permissions_valid(p text[]) returns boolean language sql immutable set search_path='' as $$
 select p is not null and cardinality(p) between 1 and 8
 and p <@ array['recipes.read','recipes.write','purchasing.read','purchasing.write','finance.read','finance.write','purchases.approve','menus.approve']::text[]
 and (not 'menus.approve'=any(p) or 'recipes.read'=any(p))
 and array_position(p,null) is null
 and (not 'recipes.write'=any(p) or 'recipes.read'=any(p))
 and (not 'purchasing.write'=any(p) or 'purchasing.read'=any(p))
 and (not 'finance.write'=any(p) or 'finance.read'=any(p))
 and (not 'purchases.approve'=any(p) or 'purchasing.read'=any(p));
$$;
-- Retain installed test-workspace access guards and existing manager authority.
do $migration$ declare definition text; begin
 select pg_get_functiondef('public.business_can(uuid,text)'::regprocedure) into definition;
 execute replace(definition,'''purchases.approve''','''purchases.approve'',''menus.approve''');
end; $migration$;
with changed as (
 update public.business_members set permissions=array_append(permissions,'menus.approve')
 where 'finance.write'=any(permissions) and 'recipes.read'=any(permissions) and not 'menus.approve'=any(permissions)
 returning workspace_id,user_id,permissions
) insert into public.business_access_events(workspace_id,actor_id,action,permissions)
select workspace_id,user_id,'menu_approval_permission_migrated',permissions from changed;
update public.business_invites set permissions=array_append(permissions,'menus.approve')
where 'finance.write'=any(permissions) and 'recipes.read'=any(permissions) and not 'menus.approve'=any(permissions);
create or replace function public.business_recipe_review(p_workspace uuid,p_recipe uuid,p_revision bigint,p_expected bigint,p_stage text,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.business_records; prior public.business_recipe_reviews; result public.business_recipe_reviews;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'recipes.read') or not (public.business_can(p_workspace,'recipes.write') or public.business_can(p_workspace,'menus.approve')) then raise exception 'BUSINESS_DENIED';end if;
 select * into r from public.business_records where id=p_recipe and workspace_id=p_workspace and kind='recipe' and status='draft';
 if r.id is null or r.revision is distinct from p_revision then raise exception 'BUSINESS_STALE';end if;
 select * into prior from public.business_recipe_reviews where recipe_id=p_recipe and recipe_revision=p_revision order by id desc limit 1;
 if coalesce(prior.id,0) is distinct from p_expected then raise exception 'BUSINESS_STALE';end if;
 if p_stage is null or p_stage not in ('development','testing','approved') or p_note is null or length(btrim(p_note)) not between 1 and 2000 then raise exception 'BUSINESS_INVALID';end if;
 if coalesce(prior.stage,'development')='approved' then raise exception 'MENU_APPROVED_FROZEN';end if;
 if p_stage='approved' then
  if not public.business_can(p_workspace,'menus.approve') then raise exception 'BUSINESS_DENIED';end if;
  if prior.stage is distinct from 'testing' then raise exception 'MENU_STAGE';end if;
 elsif not public.business_can(p_workspace,'recipes.write') then raise exception 'BUSINESS_DENIED';
 elsif (p_stage='testing' and coalesce(prior.stage,'development')<>'development') or (p_stage='development' and prior.stage is distinct from 'testing') then raise exception 'MENU_STAGE';end if;
 if not coalesce(public.business_ingredient_lines_valid(r.data->'ingredient_lines'),false) then raise exception 'MENU_STRUCTURED_REQUIRED';end if;
 insert into public.business_recipe_reviews(workspace_id,recipe_id,recipe_revision,stage,note,actor_id) values(p_workspace,p_recipe,p_revision,p_stage,btrim(p_note),auth.uid()) returning * into result;
 return to_jsonb(result);
end;$$;
create or replace function public.business_menu_save(p_workspace uuid,p_id uuid,p_revision bigint,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old public.business_menu_items; m public.business_menu_items; r public.business_records; v public.business_record_versions;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'recipes.read') or not (public.business_can(p_workspace,'menus.approve') or public.business_can(p_workspace,'recipes.write')) then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_revision is null or p_revision<0 or jsonb_typeof(p_data) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(p_data) k where k not in ('name','category','description','price','currency','recipe_id','recipe_revision','status')) then raise exception 'BUSINESS_INVALID';end if;
 select * into old from public.business_menu_items where id=p_id;
 if old.id is not null and old.workspace_id<>p_workspace then raise exception 'BUSINESS_DENIED';end if;
 if not public.business_can(p_workspace,'menus.approve') and (p_data->>'status' is distinct from 'candidate' or (old.id is not null and not old.is_candidate)) then raise exception 'BUSINESS_DENIED';end if;
 if coalesce(old.revision,0)<>p_revision then raise exception 'BUSINESS_STALE';end if;
 if old.id is null and (select count(*) from public.business_menu_items where workspace_id=p_workspace)>=300 then raise exception 'BUSINESS_LIMIT';end if;
 if not ((p_data->>'status'='candidate' and (p_data->'price' is null or p_data->'price'='null'::jsonb)) or public.chef_number_valid(p_data->'price',0,1e12,false)) or not public.chef_number_valid(p_data->'recipe_revision',1,1e12,false) or (p_data->>'recipe_revision')::numeric<>trunc((p_data->>'recipe_revision')::numeric) or exists(select 1 from unnest(array['name','category','description','currency','recipe_id','status']) k where jsonb_typeof(p_data->k) is distinct from 'string') then raise exception 'BUSINESS_INVALID';end if;
 if p_data->>'status' is null or p_data->>'status' not in ('candidate','preparing','on_sale','stopped') then raise exception 'BUSINESS_INVALID';end if;
 select * into r from public.business_records where id=(p_data->>'recipe_id')::uuid and workspace_id=p_workspace and kind='recipe';
 select * into v from public.business_record_versions where record_id=r.id and revision=(p_data->>'recipe_revision')::bigint;
 if v.record_id is null then raise exception 'MENU_SOURCE';end if;
 if p_data->>'status'<>'candidate' and not exists(select 1 from public.business_recipe_reviews where recipe_id=v.record_id and recipe_revision=v.revision and stage='approved') then raise exception 'MENU_APPROVAL_REQUIRED';end if;
 if r.status<>'draft' and p_data->>'status'<>'stopped' then raise exception 'MENU_ARCHIVED_RECIPE';end if;
 insert into public.business_menu_items(id,workspace_id,name,category,description,price,currency,recipe_id,recipe_revision,recipe_snapshot,status,is_candidate,price_confirmed,revision)
 values(p_id,p_workspace,btrim(p_data->>'name'),btrim(p_data->>'category'),btrim(p_data->>'description'),coalesce((p_data->>'price')::numeric,0),p_data->>'currency',r.id,v.revision,jsonb_build_object('title',v.title,'data',v.data),case when p_data->>'status'='candidate' then 'preparing' else p_data->>'status' end,p_data->>'status'='candidate',p_data->>'price' is not null,1)
 on conflict(id) do update set name=excluded.name,category=excluded.category,description=excluded.description,price=excluded.price,currency=excluded.currency,recipe_id=excluded.recipe_id,recipe_revision=excluded.recipe_revision,recipe_snapshot=excluded.recipe_snapshot,status=excluded.status,is_candidate=excluded.is_candidate,price_confirmed=excluded.price_confirmed,revision=business_menu_items.revision+1,updated_at=now() returning * into m;
 insert into public.business_menu_history(menu_id,revision,workspace_id,snapshot,actor_id) values(m.id,m.revision,p_workspace,to_jsonb(m),auth.uid());
 return to_jsonb(m)||jsonb_build_object('status',p_data->>'status','price',p_data->'price');
end;$$;
create or replace function public.business_menu_plan(p_workspace uuid,p_purpose text,p_sources jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s jsonb; v public.business_record_versions; r public.business_records; m public.business_menu_items; quantity numeric; item jsonb; key text; merged jsonb:='{}'; refs jsonb:='[]'; reqs jsonb;
begin
 if not public.business_can(p_workspace,'recipes.read') or not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_purpose is null or p_purpose not in ('development','launch','operations') or jsonb_typeof(p_sources) is distinct from 'array' then raise exception 'BUSINESS_INVALID';end if;
 if jsonb_array_length(p_sources) not between 1 and 20 then raise exception 'BUSINESS_INVALID';end if;
 if (select count(distinct (x->>'kind',x->>'id')) from jsonb_array_elements(p_sources) x)<>jsonb_array_length(p_sources) then raise exception 'BUSINESS_INVALID';end if;
 for s in select value from jsonb_array_elements(p_sources) loop
  if jsonb_typeof(s) is distinct from 'object' or exists(select 1 from jsonb_object_keys(s) k where k not in ('kind','id','revision','servings'))
   or not public.business_menu_number_valid(s->'servings',0.001,100000) or not public.chef_number_valid(s->'revision',1,1e12,false) or (s->>'revision')::numeric<>trunc((s->>'revision')::numeric) then raise exception 'BUSINESS_INVALID';end if;
  m:=null;
  if s->>'kind'='menu' and p_purpose in ('launch','operations') then
   select * into m from public.business_menu_items where id=(s->>'id')::uuid and workspace_id=p_workspace;
   if m.id is null or m.revision is distinct from (s->>'revision')::bigint then raise exception 'BUSINESS_STALE';end if;
   if m.is_candidate then raise exception 'MENU_APPROVAL_REQUIRED';end if;
   if (p_purpose='operations' and m.status<>'on_sale') or (p_purpose='launch' and m.status<>'preparing') then raise exception 'MENU_STAGE';end if;
   select * into r from public.business_records where id=m.recipe_id and workspace_id=p_workspace and kind='recipe' and status='draft';
   select * into v from public.business_record_versions where record_id=r.id and revision=m.recipe_revision;
  elsif s->>'kind'='recipe' and p_purpose in ('development','launch') then
   select * into r from public.business_records where id=(s->>'id')::uuid and workspace_id=p_workspace and kind='recipe' and status='draft';
   select * into v from public.business_record_versions where record_id=r.id and revision=(s->>'revision')::bigint;
   if p_purpose='launch' and not exists(select 1 from public.business_recipe_reviews where recipe_id=r.id and recipe_revision=v.revision and stage='approved') then raise exception 'MENU_APPROVAL_REQUIRED';end if;
  else raise exception 'MENU_SOURCE';end if;
  if v.record_id is null then raise exception 'MENU_SOURCE';end if;
  if not coalesce(public.business_ingredient_lines_valid(v.data->'ingredient_lines'),false) then raise exception 'MENU_STRUCTURED_REQUIRED';end if;
  refs:=refs||jsonb_build_array(jsonb_build_object('kind',s->>'kind','id',s->>'id','revision',s->'revision','menu_name',m.name,'recipe_id',r.id,'recipe_revision',v.revision,'title',v.title,'servings',s->'servings','base_servings',v.data->'servings','ingredient_lines',v.data->'ingredient_lines'));
  for item in select value from jsonb_array_elements(v.data->'ingredient_lines') loop
   -- Only identical names, specifications and units are combined. No inferred conversions.
   key:=encode(extensions.digest(jsonb_build_array(lower(btrim(item->>'name')),lower(btrim(item->>'spec')),lower(btrim(item->>'unit')))::text,'sha256'),'hex');
   quantity:=(item->>'quantity')::numeric*(s->>'servings')::numeric/(v.data->>'servings')::numeric+coalesce((merged->key->>'required')::numeric,0);
   if quantity>1e9 then raise exception 'BUSINESS_LIMIT';end if;
   merged:=jsonb_set(merged,array[key],jsonb_build_object('key',key,'name',btrim(item->>'name'),'spec',btrim(item->>'spec'),'unit',btrim(item->>'unit'),'required',quantity));
  end loop;
 end loop;
 if (select count(*) from jsonb_object_keys(merged))>100 then raise exception 'BUSINESS_LIMIT';end if;
 select jsonb_agg(e.value||jsonb_build_object('required',ceil((e.value->>'required')::numeric*1000000)/1000000) order by e.value->>'name',e.key) into reqs from jsonb_each(merged) e;
 return jsonb_build_object('purpose',p_purpose,'sources',refs,'requirements',reqs);
end;$$;

create table public.business_ingredient_defaults (
 workspace_id uuid not null references public.business_workspaces on delete cascade,
 ingredient_key text not null, ingredient jsonb not null,
 supplier_id uuid not null, product_id uuid not null, supplier_revision bigint not null, product_revision bigint not null,
 factor numeric not null check(factor>0), stock_id uuid,
 revision bigint not null default 1, updated_by uuid references auth.users on delete set null,
 updated_at timestamptz not null default now(), primary key(workspace_id,ingredient_key),
 foreign key(workspace_id,supplier_id) references public.business_suppliers(workspace_id,id) on delete cascade,
 foreign key(product_id) references public.business_supplier_products on delete cascade,
 foreign key(workspace_id,stock_id) references public.business_stock_items(workspace_id,id)
);
create table public.business_menu_batches (
 id uuid primary key, workspace_id uuid not null references public.business_workspaces on delete cascade,
 actor_id uuid references auth.users on delete set null, fingerprint text not null,
 sources jsonb not null, preview jsonb not null, result jsonb not null,
 delivery_date date not null, created_at timestamptz not null default now()
);
create index business_menu_batches_recent on public.business_menu_batches(workspace_id,created_at desc);
create table public.business_menu_templates (
 id uuid primary key, workspace_id uuid not null references public.business_workspaces on delete cascade,
 name text not null check(length(btrim(name)) between 1 and 80), sources jsonb not null,
 revision bigint not null default 1, updated_at timestamptz not null default now(),
 updated_by uuid references auth.users on delete set null
);
alter table public.business_ingredient_defaults enable row level security;
alter table public.business_menu_batches enable row level security;
alter table public.business_menu_templates enable row level security;
revoke all on public.business_ingredient_defaults,public.business_menu_batches,public.business_menu_templates from public,anon,authenticated;
grant select on public.business_ingredient_defaults,public.business_menu_batches,public.business_menu_templates to authenticated;
grant all on public.business_ingredient_defaults,public.business_menu_batches,public.business_menu_templates to service_role;
create policy business_ingredient_defaults_read on public.business_ingredient_defaults for select to authenticated using(public.business_can(workspace_id,'purchasing.read'));
create policy business_menu_batches_read on public.business_menu_batches for select to authenticated using(public.business_can(workspace_id,'purchasing.read') and public.business_can(workspace_id,'recipes.read'));
create policy business_menu_templates_read on public.business_menu_templates for select to authenticated using(public.business_can(workspace_id,'purchasing.read') and public.business_can(workspace_id,'recipes.read'));

create function public.business_ingredient_default_save(p_workspace uuid,p_revision bigint,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare k text; ing jsonb; s public.business_suppliers; p public.business_supplier_products; old public.business_ingredient_defaults;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') or not public.business_can(p_workspace,'recipes.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_revision is null or p_revision<0 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>4096
 or exists(select 1 from jsonb_object_keys(p_data) x where x not in ('ingredient','supplier','supplier_revision','product','product_revision','factor','stock','confirmed'))
 or p_data->'confirmed' is distinct from 'true' or not public.business_menu_number_valid(p_data->'factor',0.000001,1e9) then raise exception 'BUSINESS_INVALID';end if;
 ing:=p_data->'ingredient';
 if jsonb_typeof(ing) is distinct from 'object' or exists(select 1 from jsonb_object_keys(ing) x where x not in ('name','spec','unit'))
 or not public.business_ingredient_lines_valid(jsonb_build_array(ing||jsonb_build_object('quantity',1))) then raise exception 'BUSINESS_INVALID';end if;
 k:=encode(extensions.digest(jsonb_build_array(lower(btrim(ing->>'name')),lower(btrim(ing->>'spec')),lower(btrim(ing->>'unit')))::text,'sha256'),'hex');
 select * into s from public.business_suppliers where id=(p_data->>'supplier')::uuid and workspace_id=p_workspace and data->'active'='true';
 select * into p from public.business_supplier_products where id=(p_data->>'product')::uuid and workspace_id=p_workspace and supplier_id=s.id and data->'active'='true';
 if s.id is null or p.id is null then raise exception 'SUPPLIER_UNAVAILABLE';end if;
 if to_jsonb(s.revision) is distinct from p_data->'supplier_revision' or to_jsonb(p.revision) is distinct from p_data->'product_revision' then raise exception 'BUSINESS_STALE';end if;
 if (p_data->>'factor')::numeric*(p.data->>'content_quantity')::numeric>1e9
 or round((p_data->>'factor')::numeric*(p.data->>'content_quantity')::numeric,6)<>(p_data->>'factor')::numeric*(p.data->>'content_quantity')::numeric then raise exception 'SUPPLIER_PACK';end if;
 if lower(btrim(ing->>'unit'))=lower(btrim(p.data->>'content_unit')) and (p_data->>'factor')::numeric<>1 then raise exception 'SUPPLIER_UNIT';end if;
 if p_data->>'stock' is not null and not exists(select 1 from public.business_stock_items i where i.workspace_id=p_workspace and i.id=(p_data->>'stock')::uuid and lower(btrim(i.unit))=lower(btrim(ing->>'unit'))) then raise exception 'SUPPLIER_UNIT';end if;
 select * into old from public.business_ingredient_defaults where workspace_id=p_workspace and ingredient_key=k;
 if coalesce(old.revision,0)<>p_revision then raise exception 'BUSINESS_STALE';end if;
 if old.ingredient_key is null and (select count(*) from public.business_ingredient_defaults where workspace_id=p_workspace)>=1000 then raise exception 'BUSINESS_LIMIT';end if;
 insert into public.business_ingredient_defaults(workspace_id,ingredient_key,ingredient,supplier_id,product_id,supplier_revision,product_revision,factor,stock_id,updated_by)
 values(p_workspace,k,ing,s.id,p.id,s.revision,p.revision,(p_data->>'factor')::numeric,(p_data->>'stock')::uuid,auth.uid())
 on conflict(workspace_id,ingredient_key) do update set ingredient=excluded.ingredient,supplier_id=excluded.supplier_id,product_id=excluded.product_id,supplier_revision=excluded.supplier_revision,product_revision=excluded.product_revision,factor=excluded.factor,stock_id=excluded.stock_id,revision=business_ingredient_defaults.revision+1,updated_at=now(),updated_by=auth.uid() returning * into old;
 return to_jsonb(old);
end;$$;

create function public.business_menu_fast_preview(p_workspace uuid,p_sources jsonb,p_use_stock boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare plan jsonb; req jsonb; d public.business_ingredient_defaults; s public.business_suppliers; p public.business_supplier_products;
 rows jsonb:='[]'; available numeric; taken numeric; packs numeric; size numeric; ready boolean; balance jsonb; used jsonb:='{}'; duplicate_count integer; result jsonb;
begin
 if p_use_stock is null then raise exception 'BUSINESS_INVALID';end if;
 plan:=public.business_menu_plan(p_workspace,'operations',p_sources);
 for req in select value from jsonb_array_elements(plan->'requirements') loop
  select * into d from public.business_ingredient_defaults where workspace_id=p_workspace and ingredient_key=req->>'key';
  select * into s from public.business_suppliers where id=d.supplier_id and workspace_id=p_workspace;
  select * into p from public.business_supplier_products where id=d.product_id and workspace_id=p_workspace and supplier_id=s.id;
  ready:=coalesce(d.ingredient_key is not null and s.data->'active'='true' and p.data->'active'='true' and s.revision=d.supplier_revision and p.revision=d.product_revision,false);
  available:=0;taken:=0;size:=null;packs:=null;
  if d.stock_id is not null then
   balance:=public.business_stock_balance(p_workspace,d.stock_id);
   available:=greatest(0,(balance->>'available')::numeric-coalesce((used->>d.stock_id::text)::numeric,0));
   if p_use_stock then taken:=least(available,(req->>'required')::numeric);end if;
   used:=jsonb_set(used,array[d.stock_id::text],to_jsonb(taken+coalesce((used->>d.stock_id::text)::numeric,0)));
  end if;
  if ready then size:=d.factor*(p.data->>'content_quantity')::numeric;packs:=ceil(greatest(0,(req->>'required')::numeric-taken)/size);end if;
  select count(*)::int into duplicate_count from public.business_purchase_bases b join public.business_records r on r.id=b.request_id
  where b.workspace_id=p_workspace and r.status in ('draft','review','approved','sent')
  and exists(select 1 from jsonb_array_elements(b.adjustments) a where a->>'key'=req->>'key' and a->'include'='true');
  rows:=rows||jsonb_build_array(req||jsonb_build_object('default',case when d.ingredient_key is null then null else to_jsonb(d) end,'supplier',case when s.id is null then null else to_jsonb(s) end,'product',case when p.id is null then null else to_jsonb(p) end,'ready',ready,'available',available,'stock',taken,'pack_size',size,'packs',packs,'open_requests',duplicate_count));
 end loop;
 result:=jsonb_build_object('sources',plan->'sources','rows',rows,'use_stock',p_use_stock);
 return result||jsonb_build_object('fingerprint',encode(extensions.digest(result::text,'sha256'),'hex'));
end;$$;

create function public.business_menu_template_save(p_workspace uuid,p_id uuid,p_revision bigint,p_name text,p_sources jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old public.business_menu_templates;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_revision is null or p_revision<0 or p_name is null then raise exception 'BUSINESS_INVALID';end if;
 perform public.business_menu_plan(p_workspace,'operations',p_sources);
 select * into old from public.business_menu_templates where id=p_id;
 if old.id is not null and old.workspace_id<>p_workspace then raise exception 'BUSINESS_DENIED';end if;
 if coalesce(old.revision,0)<>p_revision then raise exception 'BUSINESS_STALE';end if;
 if old.id is null and (select count(*) from public.business_menu_templates where workspace_id=p_workspace)>=100 then raise exception 'BUSINESS_LIMIT';end if;
 insert into public.business_menu_templates(id,workspace_id,name,sources,updated_by) values(p_id,p_workspace,btrim(p_name),p_sources,auth.uid())
 on conflict(id) do update set name=excluded.name,sources=excluded.sources,revision=business_menu_templates.revision+1,updated_at=now(),updated_by=auth.uid() returning * into old;
 return to_jsonb(old);
end;$$;

create function public.business_menu_batch_create(p_workspace uuid,p_id uuid,p_sources jsonb,p_use_stock boolean,p_preview text,p_delivery date,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare prior public.business_menu_batches; fingerprint text; view jsonb; row jsonb; supplier_id uuid; adjustments jsonb; adj jsonb; result jsonb;
 r jsonb; req_id uuid; reservations jsonb:='[]'; requests jsonb:='[]'; snap jsonb; lines jsonb; line jsonb; idx integer; products jsonb;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') or not public.business_can(p_workspace,'recipes.read') or not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_confirmed is distinct from true or p_delivery is null or p_delivery<current_date or p_delivery>current_date+365 then raise exception 'BUSINESS_INVALID';end if;
 fingerprint:=encode(extensions.digest(jsonb_build_array(p_sources,p_use_stock,p_preview,p_delivery)::text,'sha256'),'hex');
 select * into prior from public.business_menu_batches where id=p_id;
 if prior.id is not null then
  if prior.workspace_id<>p_workspace or prior.actor_id is distinct from auth.uid() or prior.fingerprint<>fingerprint then raise exception 'BUSINESS_STALE';end if;
  return prior.result;
 end if;
 if (select count(*) from public.business_menu_batches where workspace_id=p_workspace and created_at>now()-interval '1 hour')>=100 then raise exception 'BUSINESS_LIMIT';end if;
 view:=public.business_menu_fast_preview(p_workspace,p_sources,p_use_stock);
 if view->>'fingerprint' is distinct from p_preview then raise exception 'FAST_CHANGED';end if;
 if exists(select 1 from jsonb_array_elements(view->'rows') a where a->'ready' is distinct from 'true') then raise exception 'FAST_MAPPING_REQUIRED';end if;
 for row in select value from jsonb_array_elements(view->'rows') loop
  if (row->>'stock')::numeric>0 then
   snap:=public.business_stock_action(p_workspace,gen_random_uuid(),'reserve',jsonb_build_object('item',row->'default'->>'stock_id','quantity',row->'stock','reason','메뉴 구매 준비 / Menu preparation '||p_delivery::text||' / '||p_id::text));
   reservations:=reservations||jsonb_build_array(jsonb_build_object('id',snap->'id','item',snap->'item_id','quantity',snap->'quantity'));
  end if;
 end loop;
 for supplier_id in select distinct (a->'supplier'->>'id')::uuid from jsonb_array_elements(view->'rows') a where (a->>'packs')::numeric>0 order by 1 loop
  adjustments:='[]';products:='[]';lines:='[]';idx:=0;
  for row in select value from jsonb_array_elements(view->'rows') loop
   adj:=jsonb_build_object('key',row->>'key','include',row->'supplier'->>'id'=supplier_id::text);
   if row->'supplier'->>'id'=supplier_id::text then
    adj:=adj||jsonb_build_object('stock',row->'stock','incoming',0,'pack_size',row->'pack_size','pack_unit',row->'product'->'data'->>'pack_unit','confirmed',true);
    products:=products||jsonb_build_array(jsonb_build_object('key',row->>'key','id',row->'product'->'id','revision',row->'product'->'revision','data',row->'product'->'data','factor',row->'default'->'factor'));
   end if;
   adjustments:=adjustments||jsonb_build_array(adj);
  end loop;
  req_id:=gen_random_uuid();
  select a->'supplier' into snap from jsonb_array_elements(view->'rows') a where a->'supplier'->>'id'=supplier_id::text limit 1;
  r:=public.business_menu_purchase(p_workspace,req_id,'operations',p_sources,adjustments,snap->'data'->>'name');
  for row in select value from jsonb_array_elements(view->'rows') loop
   if row->'supplier'->>'id'=supplier_id::text and (row->>'packs')::numeric>0 then
    line:=r->'data'->'lines'->idx;idx:=idx+1;
    lines:=lines||jsonb_build_array(line||jsonb_build_object('name',row->'product'->'data'->>'name','spec',left(concat_ws(' / ',row->>'name',row->>'spec',row->'product'->'data'->>'spec',(row->>'pack_size')||' '||(row->>'unit')),300)));
   end if;
  end loop;
  r:=public.business_save_record(p_workspace,req_id,'purchase','메뉴 구매 / Menu purchase '||p_delivery::text,r->'data'||jsonb_build_object('delivery_date',p_delivery::text,'lines',lines),(r->>'revision')::bigint);
  insert into public.business_purchase_supplier_snapshots(request_id,workspace_id,supplier,products,input_hash,actor_id) values(req_id,p_workspace,snap,products,fingerprint,auth.uid());
  requests:=requests||jsonb_build_array(jsonb_build_object('id',req_id,'supplier',snap->'data'->>'name','revision',r->'revision'));
 end loop;
 result:=jsonb_build_object('id',p_id,'requests',requests,'reservations',reservations);
 insert into public.business_menu_batches(id,workspace_id,actor_id,fingerprint,sources,preview,result,delivery_date) values(p_id,p_workspace,auth.uid(),fingerprint,p_sources,view,result,p_delivery);
 return result;
end;$$;
revoke all on function public.business_ingredient_default_save(uuid,bigint,jsonb),public.business_menu_fast_preview(uuid,jsonb,boolean),public.business_menu_template_save(uuid,uuid,bigint,text,jsonb),public.business_menu_batch_create(uuid,uuid,jsonb,boolean,text,date,boolean) from public,anon;
grant execute on function public.business_ingredient_default_save(uuid,bigint,jsonb),public.business_menu_fast_preview(uuid,jsonb,boolean),public.business_menu_template_save(uuid,uuid,bigint,text,jsonb),public.business_menu_batch_create(uuid,uuid,jsonb,boolean,text,date,boolean) to authenticated;
create function public.business_menu_revisions(p_workspace uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.business_can(p_workspace,'recipes.read') then raise exception 'BUSINESS_DENIED';end if;
 return coalesce((select jsonb_object_agg(m.id::text,r.revision) from public.business_menu_items m join public.business_records r on r.id=m.recipe_id and r.workspace_id=m.workspace_id where m.workspace_id=p_workspace),'{}');
end;$$;
revoke all on function public.business_menu_revisions(uuid) from public,anon;
grant execute on function public.business_menu_revisions(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
