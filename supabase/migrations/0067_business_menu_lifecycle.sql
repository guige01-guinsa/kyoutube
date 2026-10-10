-- Menu releases pin immutable recipe revisions. All writes serialize per workspace.
-- Existing personal recipes, purchases and the business approval workflow are retained.
create table public.business_recipe_reviews (
 id bigint generated always as identity primary key,
 workspace_id uuid not null references public.business_workspaces on delete cascade,
 recipe_id uuid not null,
 recipe_revision bigint not null,
 stage text not null check(stage in ('development','testing','approved')),
 note text not null check(length(btrim(note)) between 1 and 2000),
 actor_id uuid references auth.users on delete set null,
 created_at timestamptz not null default now(),
 foreign key(recipe_id,recipe_revision) references public.business_record_versions(record_id,revision) on delete cascade
);
create index business_recipe_reviews_lookup on public.business_recipe_reviews(workspace_id,recipe_id,recipe_revision,id desc);
create table public.business_menu_items (
 id uuid primary key,
 workspace_id uuid not null references public.business_workspaces on delete cascade,
 name text not null check(length(btrim(name)) between 1 and 120),
 category text not null check(length(category)<=80),
 description text not null check(length(description)<=1000),
 price numeric not null check(price>=0 and price<=1e12),
 currency text not null check(currency in ('KRW','USD')),
 recipe_id uuid not null,
 recipe_revision bigint not null,
 recipe_snapshot jsonb not null,
 status text not null check(status in ('preparing','on_sale','stopped')),
 revision bigint not null default 1,
 updated_at timestamptz not null default now(),
 foreign key(recipe_id,recipe_revision) references public.business_record_versions(record_id,revision) on delete cascade
);
create index business_menu_workspace on public.business_menu_items(workspace_id,category,name,id);
create table public.business_menu_history (
 menu_id uuid not null references public.business_menu_items on delete cascade,
 revision bigint not null,
 workspace_id uuid not null references public.business_workspaces on delete cascade,
 snapshot jsonb not null,
 actor_id uuid references auth.users on delete set null,
 created_at timestamptz not null default now(),
 primary key(menu_id,revision)
);
create table public.business_purchase_bases (
 request_id uuid primary key references public.business_records on delete cascade,
 workspace_id uuid not null references public.business_workspaces on delete cascade,
 purpose text not null check(purpose in ('development','launch','operations')),
 sources jsonb not null,
 requirements jsonb not null,
 adjustments jsonb not null,
 input_hash text not null,
 actor_id uuid references auth.users on delete set null,
 created_at timestamptz not null default now()
);
alter table public.business_recipe_reviews enable row level security;
alter table public.business_menu_items enable row level security;
alter table public.business_menu_history enable row level security;
alter table public.business_purchase_bases enable row level security;
revoke all on public.business_recipe_reviews,public.business_menu_items,public.business_menu_history,public.business_purchase_bases from public,anon,authenticated;
grant select on public.business_recipe_reviews,public.business_menu_items,public.business_menu_history,public.business_purchase_bases to authenticated;
grant all on public.business_recipe_reviews,public.business_menu_items,public.business_menu_history,public.business_purchase_bases to service_role;
create policy business_recipe_review_read on public.business_recipe_reviews for select to authenticated using(public.business_can(workspace_id,'recipes.read'));
create policy business_menu_read on public.business_menu_items for select to authenticated using(public.business_can(workspace_id,'recipes.read'));
create policy business_menu_history_read on public.business_menu_history for select to authenticated using(public.business_can(workspace_id,'recipes.read'));
create policy business_purchase_basis_read on public.business_purchase_bases for select to authenticated using(public.business_can(workspace_id,'purchasing.read'));

-- Preserve the installed validators, including any prior hardening, as private helpers.
do $migration$
declare n text; definition text;
begin
 foreach n in array array['business_data_valid','business_save_record','business_archive_record'] loop
  select pg_get_functiondef(p.oid) into strict definition from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public' and p.proname=n;
  execute replace(definition,'FUNCTION public.'||n||'(', 'FUNCTION public.'||n||'_before_menu(');
 end loop;
end;$migration$;
revoke all on function public.business_data_valid_before_menu(text,jsonb),public.business_save_record_before_menu(uuid,uuid,text,text,jsonb,bigint),public.business_archive_record_before_menu(uuid,uuid,bigint) from public,anon,authenticated;

create function public.business_menu_number_valid(v jsonb,lo numeric,hi numeric) returns boolean language plpgsql immutable set search_path='' as $$
begin
 if not public.chef_number_valid(v,lo,hi,false) then return false;end if;
 return (v::text)::numeric=round((v::text)::numeric,6);
exception when others then return false;
end;$$;
revoke all on function public.business_menu_number_valid(jsonb,numeric,numeric) from public,anon,authenticated;
create function public.business_ingredient_lines_valid(lines jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare item jsonb; k text;
begin
 if jsonb_typeof(lines) is distinct from 'array' then return false;end if;
 if jsonb_array_length(lines) not between 1 and 100 then return false;end if;
 for item in select value from jsonb_array_elements(lines) loop
  if jsonb_typeof(item) is distinct from 'object' or exists(select 1 from jsonb_object_keys(item) a where a not in ('name','spec','quantity','unit')) then return false;end if;
  foreach k in array array['name','spec','unit'] loop
   if jsonb_typeof(item->k) is distinct from 'string' then return false;end if;
  end loop;
  if length(btrim(item->>'name')) not between 1 and 150 or length(item->>'spec')>150 or length(btrim(item->>'unit')) not between 1 and 30
   or not public.business_menu_number_valid(item->'quantity',0.000001,1e9) then return false;end if;
 end loop;
 return true;
end;$$;
create or replace function public.business_data_valid(p_kind text,d jsonb) returns boolean language plpgsql immutable set search_path='' as $$
begin
 if p_kind='recipe' and d ? 'ingredient_lines' then
  return public.business_ingredient_lines_valid(d->'ingredient_lines') and coalesce(public.business_data_valid_before_menu(p_kind,d-'ingredient_lines'),false);
 end if;
 return public.business_data_valid_before_menu(p_kind,d);
end;$$;
create or replace function public.business_save_record(p_workspace uuid,p_id uuid,p_kind text,p_title text,p_data jsonb,p_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old public.business_records; d jsonb:=p_data;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,public.business_record_permission(p_kind,true)) then raise exception 'BUSINESS_DENIED';end if;
 select * into old from public.business_records where id=p_id and workspace_id=p_workspace;
 if p_kind='recipe' then
  if old.data ? 'ingredient_lines' and not d ? 'ingredient_lines' then
   if d->>'ingredients' is distinct from old.data->>'ingredients' then raise exception 'MENU_STRUCTURED_REQUIRED';end if;
   d:=d||jsonb_build_object('ingredient_lines',old.data->'ingredient_lines');
  end if;
  if d ? 'ingredient_lines' then
   if not public.business_ingredient_lines_valid(d->'ingredient_lines') then raise exception 'BUSINESS_INVALID';end if;
   -- The human-readable list is always derived from the same purchase basis.
   d:=d||jsonb_build_object('ingredients',(select string_agg((x->>'name')||' '||(x->>'quantity')||' '||(x->>'unit')||case when x->>'spec'<>'' then ' ('||(x->>'spec')||')' else '' end,E'\n' order by ord) from jsonb_array_elements(d->'ingredient_lines') with ordinality a(x,ord)));
  end if;
 end if;
 return public.business_save_record_before_menu(p_workspace,p_id,p_kind,p_title,d,p_revision);
end;$$;

create function public.business_recipe_review(p_workspace uuid,p_recipe uuid,p_revision bigint,p_expected bigint,p_stage text,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.business_records; prior public.business_recipe_reviews; result public.business_recipe_reviews;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'recipes.read') or not (public.business_can(p_workspace,'recipes.write') or public.business_can(p_workspace,'finance.write')) then raise exception 'BUSINESS_DENIED';end if;
 select * into r from public.business_records where id=p_recipe and workspace_id=p_workspace and kind='recipe' and status='draft';
 if r.id is null or r.revision is distinct from p_revision then raise exception 'BUSINESS_STALE';end if;
 select * into prior from public.business_recipe_reviews where recipe_id=p_recipe and recipe_revision=p_revision order by id desc limit 1;
 if coalesce(prior.id,0) is distinct from p_expected then raise exception 'BUSINESS_STALE';end if;
 if p_stage is null or p_stage not in ('development','testing','approved') or p_note is null or length(btrim(p_note)) not between 1 and 2000 then raise exception 'BUSINESS_INVALID';end if;
 if coalesce(prior.stage,'development')='approved' then raise exception 'MENU_APPROVED_FROZEN';end if;
 if p_stage='approved' then
  if not public.business_can(p_workspace,'finance.write') then raise exception 'BUSINESS_DENIED';end if;
  if prior.stage is distinct from 'testing' then raise exception 'MENU_STAGE';end if;
 elsif not public.business_can(p_workspace,'recipes.write') then raise exception 'BUSINESS_DENIED';
 elsif (p_stage='testing' and coalesce(prior.stage,'development')<>'development') or (p_stage='development' and prior.stage is distinct from 'testing') then raise exception 'MENU_STAGE';end if;
 if not coalesce(public.business_ingredient_lines_valid(r.data->'ingredient_lines'),false) then raise exception 'MENU_STRUCTURED_REQUIRED';end if;
 insert into public.business_recipe_reviews(workspace_id,recipe_id,recipe_revision,stage,note,actor_id) values(p_workspace,p_recipe,p_revision,p_stage,btrim(p_note),auth.uid()) returning * into result;
 return to_jsonb(result);
end;$$;

create function public.business_menu_save(p_workspace uuid,p_id uuid,p_revision bigint,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old public.business_menu_items; m public.business_menu_items; r public.business_records; v public.business_record_versions;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'recipes.read') or not public.business_can(p_workspace,'finance.write') then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_revision is null or p_revision<0 or jsonb_typeof(p_data) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(p_data) k where k not in ('name','category','description','price','currency','recipe_id','recipe_revision','status')) then raise exception 'BUSINESS_INVALID';end if;
 select * into old from public.business_menu_items where id=p_id;
 if old.id is not null and old.workspace_id<>p_workspace then raise exception 'BUSINESS_DENIED';end if;
 if coalesce(old.revision,0)<>p_revision then raise exception 'BUSINESS_STALE';end if;
 if old.id is null and (select count(*) from public.business_menu_items where workspace_id=p_workspace)>=300 then raise exception 'BUSINESS_LIMIT';end if;
 if not public.chef_number_valid(p_data->'price',0,1e12,false) or not public.chef_number_valid(p_data->'recipe_revision',1,1e12,false) or (p_data->>'recipe_revision')::numeric<>trunc((p_data->>'recipe_revision')::numeric) or exists(select 1 from unnest(array['name','category','description','currency','recipe_id','status']) k where jsonb_typeof(p_data->k) is distinct from 'string') then raise exception 'BUSINESS_INVALID';end if;
 if p_data->>'status' is null or p_data->>'status' not in ('preparing','on_sale','stopped') then raise exception 'BUSINESS_INVALID';end if;
 select * into r from public.business_records where id=(p_data->>'recipe_id')::uuid and workspace_id=p_workspace and kind='recipe';
 select * into v from public.business_record_versions where record_id=r.id and revision=(p_data->>'recipe_revision')::bigint;
 if v.record_id is null or not exists(select 1 from public.business_recipe_reviews where recipe_id=v.record_id and recipe_revision=v.revision and stage='approved') then raise exception 'MENU_APPROVAL_REQUIRED';end if;
 if r.status<>'draft' and p_data->>'status'<>'stopped' then raise exception 'MENU_ARCHIVED_RECIPE';end if;
 insert into public.business_menu_items(id,workspace_id,name,category,description,price,currency,recipe_id,recipe_revision,recipe_snapshot,status)
 values(p_id,p_workspace,btrim(p_data->>'name'),btrim(p_data->>'category'),btrim(p_data->>'description'),(p_data->>'price')::numeric,p_data->>'currency',r.id,v.revision,jsonb_build_object('title',v.title,'data',v.data),p_data->>'status')
 on conflict(id) do update set name=excluded.name,category=excluded.category,description=excluded.description,price=excluded.price,currency=excluded.currency,recipe_id=excluded.recipe_id,recipe_revision=excluded.recipe_revision,recipe_snapshot=excluded.recipe_snapshot,status=excluded.status,revision=business_menu_items.revision+1,updated_at=now() returning * into m;
 insert into public.business_menu_history(menu_id,revision,workspace_id,snapshot,actor_id) values(m.id,m.revision,p_workspace,to_jsonb(m),auth.uid());
 return to_jsonb(m);
end;$$;
create or replace function public.business_archive_record(p_workspace uuid,p_id uuid,p_revision bigint) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'recipes.write') and not public.business_can(p_workspace,'finance.write') then raise exception 'BUSINESS_DENIED';end if;
 if exists(select 1 from public.business_menu_items where workspace_id=p_workspace and recipe_id=p_id and status='on_sale') then raise exception 'MENU_ON_SALE';end if;
 perform public.business_archive_record_before_menu(p_workspace,p_id,p_revision);
end;$$;

create function public.business_menu_plan(p_workspace uuid,p_purpose text,p_sources jsonb)
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

create function public.business_menu_purchase(p_workspace uuid,p_request uuid,p_purpose text,p_sources jsonb,p_adjustments jsonb,p_supplier text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare plan jsonb; req jsonb; a jsonb; net numeric; packs numeric; lines jsonb:='[]'; adjustments jsonb:='[]'; result jsonb; prior public.business_purchase_bases; fingerprint text;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') or not public.business_can(p_workspace,'recipes.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_request is null or p_supplier is null or length(btrim(p_supplier)) not between 1 and 120 then raise exception 'BUSINESS_INVALID';end if;
 fingerprint:=encode(extensions.digest(jsonb_build_array(p_purpose,p_sources,p_adjustments,btrim(p_supplier))::text,'sha256'),'hex');
 select * into prior from public.business_purchase_bases where request_id=p_request;
 if prior.request_id is not null then
  if prior.workspace_id<>p_workspace or prior.actor_id is distinct from auth.uid() or prior.input_hash<>fingerprint then raise exception 'BUSINESS_STALE';end if;
  return (select to_jsonb(r) from public.business_records r where id=p_request);
 end if;
 if exists(select 1 from public.business_records where id=p_request) then raise exception 'BUSINESS_STALE';end if;
 plan:=public.business_menu_plan(p_workspace,p_purpose,p_sources);
 if jsonb_typeof(p_adjustments) is distinct from 'array' then raise exception 'BUSINESS_INVALID';end if;
 if jsonb_array_length(p_adjustments)<>jsonb_array_length(plan->'requirements') or (select count(distinct x->>'key') from jsonb_array_elements(p_adjustments) x)<>jsonb_array_length(p_adjustments) then raise exception 'BUSINESS_INVALID';end if;
 for req in select value from jsonb_array_elements(plan->'requirements') loop
  select value into a from jsonb_array_elements(p_adjustments) where value->>'key'=req->>'key';
  if a is null or jsonb_typeof(a) is distinct from 'object' or exists(select 1 from jsonb_object_keys(a) k where k not in ('key','stock','incoming','pack_size','pack_unit','confirmed','include'))
   or jsonb_typeof(a->'include') is distinct from 'boolean' then raise exception 'MENU_STOCK_CONFIRM';end if;
  if a->'include'='false'::jsonb then adjustments:=adjustments||jsonb_build_array(jsonb_build_object('key',a->>'key','include',false));continue;end if;
  if a->'confirmed' is distinct from 'true'::jsonb or not public.business_menu_number_valid(a->'stock',0,1e9) or not public.business_menu_number_valid(a->'incoming',0,1e9)
   or not public.business_menu_number_valid(a->'pack_size',0.000001,1e9) or jsonb_typeof(a->'pack_unit') is distinct from 'string' or length(btrim(a->>'pack_unit')) not between 1 and 30 then raise exception 'MENU_STOCK_CONFIRM';end if;
  net:=greatest(0,(req->>'required')::numeric-(a->>'stock')::numeric-(a->>'incoming')::numeric);
  packs:=ceil(net/(a->>'pack_size')::numeric);
  if packs>1e9 then raise exception 'BUSINESS_LIMIT';end if;
  adjustments:=adjustments||jsonb_build_array(a||jsonb_build_object('net',net,'purchase_quantity',packs,'overage',packs*(a->>'pack_size')::numeric-net));
  if packs>0 then
   lines:=lines||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'name',req->>'name','spec',left((req->>'spec')||' / '||(a->>'pack_size')||' '||(req->>'unit')||' / '||(a->>'pack_unit'),300),'quantity',packs,'unit',btrim(a->>'pack_unit'),'price',null));
  end if;
 end loop;
 if jsonb_array_length(lines)=0 then raise exception 'MENU_NOTHING_TO_BUY';end if;
 result:=public.business_save_record(p_workspace,p_request,'purchase','Menu / Recipe purchase',jsonb_build_object('supplier',btrim(p_supplier),'buyer',(select name from public.business_workspaces where id=p_workspace),'phone','','address','','delivery_date','','notes','Menu/Recipe / 메뉴·레시피: '||p_purpose||E'\n'||(select string_agg((s->>'title')||' v'||(s->>'recipe_revision')||' / '||(s->>'servings')||' servings',E'\n' order by ord) from jsonb_array_elements(plan->'sources') with ordinality a(s,ord)),'currency','KRW','lines',lines),0);
 insert into public.business_purchase_bases(request_id,workspace_id,purpose,sources,requirements,adjustments,input_hash,actor_id) values(p_request,p_workspace,p_purpose,plan->'sources',plan->'requirements',adjustments,fingerprint,auth.uid());
 return result;
end;$$;

revoke all on function public.business_ingredient_lines_valid(jsonb) from public,anon,authenticated;
revoke all on function public.business_recipe_review(uuid,uuid,bigint,bigint,text,text),public.business_menu_save(uuid,uuid,bigint,jsonb),public.business_menu_plan(uuid,text,jsonb),public.business_menu_purchase(uuid,uuid,text,jsonb,jsonb,text) from public,anon;
grant execute on function public.business_recipe_review(uuid,uuid,bigint,bigint,text,text),public.business_menu_save(uuid,uuid,bigint,jsonb),public.business_menu_plan(uuid,text,jsonb),public.business_menu_purchase(uuid,uuid,text,jsonb,jsonb,text) to authenticated;
