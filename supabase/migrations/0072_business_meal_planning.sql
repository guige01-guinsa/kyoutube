-- Per-business calendars. All writes are serialized by the workspace lock.
begin;
create table public.business_meal_plans (
 id uuid primary key, workspace_id uuid not null references public.business_workspaces on delete cascade,
 meal_date date not null, slot text not null check(length(btrim(slot)) between 1 and 40),
 title text not null check(length(btrim(title)) between 1 and 120), notes text not null default '' check(length(notes)<=2000),
 sources jsonb not null, snapshot jsonb not null,
 status text not null default 'draft' check(status in ('draft','confirmed','cooked','cancelled')),
 revision bigint not null default 1, updated_by uuid references auth.users on delete set null,
 updated_at timestamptz not null default now(), created_at timestamptz not null default now(),
 unique(workspace_id,id)
);
create index business_meal_calendar on public.business_meal_plans(workspace_id,meal_date,id);
create unique index business_meal_slot on public.business_meal_plans(workspace_id,meal_date,lower(slot)) where status<>'cancelled';
create table public.business_meal_history (
 meal_id uuid not null references public.business_meal_plans on delete cascade,
 revision bigint not null, workspace_id uuid not null references public.business_workspaces on delete cascade,
 snapshot jsonb not null, actor_id uuid references auth.users on delete set null, created_at timestamptz not null default now(),
 primary key(meal_id,revision)
);
create table public.business_meal_purchase_links (
 workspace_id uuid not null, meal_id uuid primary key, batch_id uuid not null references public.business_menu_batches,
 foreign key(workspace_id,meal_id) references public.business_meal_plans(workspace_id,id) on delete cascade
);
create table public.business_meal_copies (
 id uuid primary key, workspace_id uuid not null references public.business_workspaces on delete cascade,
 actor_id uuid references auth.users on delete set null, fingerprint text not null, result jsonb not null
);
alter table public.business_meal_plans enable row level security;
alter table public.business_meal_history enable row level security;
alter table public.business_meal_purchase_links enable row level security;
alter table public.business_meal_copies enable row level security;
revoke all on public.business_meal_plans,public.business_meal_history,public.business_meal_purchase_links,public.business_meal_copies from public,anon,authenticated;
grant select on public.business_meal_plans,public.business_meal_history,public.business_meal_purchase_links to authenticated;
grant all on public.business_meal_plans,public.business_meal_history,public.business_meal_purchase_links,public.business_meal_copies to service_role;
create policy meal_read on public.business_meal_plans for select to authenticated using(public.business_can(workspace_id,'recipes.read'));
create policy meal_history_read on public.business_meal_history for select to authenticated using(public.business_can(workspace_id,'recipes.read'));
create policy meal_link_read on public.business_meal_purchase_links for select to authenticated using(public.business_can(workspace_id,'recipes.read') and public.business_can(workspace_id,'purchasing.read'));
-- Internal snapshot builder: never trusts recipe contents supplied by a client.
create function public.business_meal_snapshot(p_workspace uuid,p_sources jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s jsonb; r public.business_records; v public.business_record_versions; m public.business_menu_items; refs jsonb:='[]';
 item jsonb; hashkey text; amount numeric; merged jsonb:='{}'; reqs jsonb;
begin
 if jsonb_typeof(p_sources) is distinct from 'array' then raise exception 'BUSINESS_INVALID';end if;
 if jsonb_array_length(p_sources) not between 1 and 20 or octet_length(p_sources::text)>20000 then raise exception 'BUSINESS_INVALID';end if;
 if (select count(distinct (x->>'kind',x->>'id')) from jsonb_array_elements(p_sources) x)<>jsonb_array_length(p_sources) then raise exception 'BUSINESS_INVALID';end if;
 for s in select value from jsonb_array_elements(p_sources) loop
  if jsonb_typeof(s) is distinct from 'object' or exists(select 1 from jsonb_object_keys(s) k where k not in ('kind','id','revision','servings'))
   or not public.business_menu_number_valid(s->'servings',0.001,100000) or not public.chef_number_valid(s->'revision',1,1e12,false) then raise exception 'BUSINESS_INVALID';end if;
  r:=null;v:=null;m:=null;
  if s->>'kind'='recipe' then
   select * into r from public.business_records where id=(s->>'id')::uuid and workspace_id=p_workspace and kind='recipe' and status='draft';
   select * into v from public.business_record_versions where record_id=r.id and to_jsonb(revision)=s->'revision';
  elsif s->>'kind'='menu' then
   select * into m from public.business_menu_items where id=(s->>'id')::uuid and workspace_id=p_workspace and status='on_sale' and not is_candidate and to_jsonb(revision)=s->'revision';
   select * into r from public.business_records where id=m.recipe_id and workspace_id=p_workspace and status='draft';
   select * into v from public.business_record_versions where record_id=r.id and revision=m.recipe_revision;
  else raise exception 'MENU_SOURCE';end if;
  if v.record_id is null then raise exception 'BUSINESS_STALE';end if;
  if not coalesce(public.business_ingredient_lines_valid(v.data->'ingredient_lines'),false) or not public.business_menu_number_valid(v.data->'servings',0.001,100000) then raise exception 'MENU_STRUCTURED_REQUIRED';end if;
  refs:=refs||jsonb_build_array(s||jsonb_build_object('title',coalesce(m.name,v.title),'recipe_id',r.id,'recipe_revision',v.revision,'recipe',jsonb_build_object('title',v.title,'data',v.data)));
  for item in select value from jsonb_array_elements(v.data->'ingredient_lines') loop
   hashkey:=encode(extensions.digest(jsonb_build_array(lower(btrim(item->>'name')),lower(btrim(item->>'spec')),lower(btrim(item->>'unit')))::text,'sha256'),'hex');
   amount:=(item->>'quantity')::numeric*(s->>'servings')::numeric/(v.data->>'servings')::numeric+coalesce((merged->hashkey->>'required')::numeric,0);
   if amount>1e9 then raise exception 'BUSINESS_LIMIT';end if;
   merged:=jsonb_set(merged,array[hashkey],jsonb_build_object('key',hashkey,'name',btrim(item->>'name'),'spec',btrim(item->>'spec'),'unit',btrim(item->>'unit'),'required',amount));
  end loop;
 end loop;
 if (select count(*) from jsonb_object_keys(merged))>100 then raise exception 'BUSINESS_LIMIT';end if;
 select jsonb_agg(value||jsonb_build_object('required',ceil((value->>'required')::numeric*1000000)/1000000) order by value->>'name',key) into reqs from jsonb_each(merged);
 return jsonb_build_object('sources',refs,'requirements',reqs);
end;$$;
create function public.business_meal_save(p_workspace uuid,p_id uuid,p_revision bigint,p_date date,p_slot text,p_title text,p_notes text,p_sources jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old public.business_meal_plans; m public.business_meal_plans; snap jsonb;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'recipes.write') then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_revision is null or p_revision<0 or p_date is null or p_date not between date '2000-01-01' and date '2100-12-31' or p_slot is null or p_title is null or p_notes is null then raise exception 'BUSINESS_INVALID';end if;
 select * into old from public.business_meal_plans where id=p_id;
 if old.id is not null and old.workspace_id<>p_workspace then raise exception 'BUSINESS_DENIED';end if;
 -- Exact retry after a lost response returns the committed draft.
 if old.id is not null and old.revision=p_revision+1 and old.status='draft' and old.updated_by=auth.uid() and old.meal_date=p_date and old.slot=btrim(p_slot) and old.title=btrim(p_title) and old.notes=p_notes and old.sources=p_sources then return to_jsonb(old);end if;
 if coalesce(old.revision,0)<>p_revision then raise exception 'BUSINESS_STALE';end if;
 if old.id is not null and old.status<>'draft' then raise exception 'BUSINESS_FROZEN';end if;
 if exists(select 1 from public.business_meal_plans where workspace_id=p_workspace and meal_date=p_date and lower(slot)=lower(btrim(p_slot)) and status<>'cancelled' and id<>p_id) then raise exception 'MEAL_SLOT_EXISTS';end if;
 snap:=public.business_meal_snapshot(p_workspace,p_sources);
 insert into public.business_meal_plans(id,workspace_id,meal_date,slot,title,notes,sources,snapshot,updated_by)
 values(p_id,p_workspace,p_date,btrim(p_slot),btrim(p_title),p_notes,p_sources,snap,auth.uid())
 on conflict(id) do update set meal_date=excluded.meal_date,slot=excluded.slot,title=excluded.title,notes=excluded.notes,sources=excluded.sources,snapshot=excluded.snapshot,revision=business_meal_plans.revision+1,updated_by=auth.uid(),updated_at=now() returning * into m;
 insert into public.business_meal_history values(m.id,m.revision,p_workspace,to_jsonb(m),auth.uid(),now());return to_jsonb(m);
end;$$;
create function public.business_meal_transition(p_workspace uuid,p_id uuid,p_revision bigint,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.business_meal_plans;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'recipes.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_status='confirmed' or p_status='cancelled' then
  if not public.business_can(p_workspace,'menus.approve') and not(p_status='cancelled' and public.business_can(p_workspace,'recipes.write')) then raise exception 'BUSINESS_DENIED';end if;
 elsif p_status='cooked' then
  if not public.business_can(p_workspace,'recipes.write') then raise exception 'BUSINESS_DENIED';end if;
 else raise exception 'BUSINESS_INVALID';end if;
 select * into m from public.business_meal_plans where id=p_id and workspace_id=p_workspace;
 if m.id is null then raise exception 'BUSINESS_STALE';end if;
 if m.status=p_status and m.revision=p_revision+1 and m.updated_by=auth.uid() then return to_jsonb(m);end if;
 if m.revision is distinct from p_revision then raise exception 'BUSINESS_STALE';end if;
 if not ((m.status='draft' and p_status in ('confirmed','cancelled')) or (m.status='confirmed' and p_status in ('cooked','cancelled'))) then raise exception 'BUSINESS_FROZEN';end if;
 if m.status='confirmed' and p_status='cancelled' then
  if not public.business_can(p_workspace,'menus.approve') then raise exception 'BUSINESS_DENIED';end if;
  if exists(select 1 from public.business_meal_purchase_links where meal_id=p_id) then raise exception 'MEAL_PURCHASE_LINKED';end if;
 end if;
 -- Confirmation freezes the already reviewed recipe revisions, not current recipes.
 update public.business_meal_plans set status=p_status,revision=revision+1,updated_by=auth.uid(),updated_at=now() where id=p_id returning * into m;
 insert into public.business_meal_history values(m.id,m.revision,p_workspace,to_jsonb(m),auth.uid(),now());return to_jsonb(m);
end;$$;
create function public.business_meal_copy(p_workspace uuid,p_id uuid,p_from date,p_to date,p_target date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old public.business_meal_copies; m public.business_meal_plans; n public.business_meal_plans; result jsonb:='[]'; fingerprint text;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'recipes.write') then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_from is null or p_to is null or p_target is null or p_to-p_from not between 0 and 6 or p_target not between date '2000-01-01' and date '2100-12-25' or (p_target<=p_to and p_target+(p_to-p_from)>=p_from) then raise exception 'BUSINESS_INVALID';end if;
 fingerprint:=jsonb_build_array(p_from,p_to,p_target)::text;
 select * into old from public.business_meal_copies where id=p_id;
 if old.id is not null then
  if old.workspace_id<>p_workspace or old.actor_id is distinct from auth.uid() or old.fingerprint<>fingerprint then raise exception 'BUSINESS_STALE';end if;
  return old.result;
 end if;
 for m in select * from public.business_meal_plans where workspace_id=p_workspace and meal_date between p_from and p_to and status<>'cancelled' order by meal_date,slot loop
  if exists(select 1 from public.business_meal_plans where workspace_id=p_workspace and meal_date=p_target+(m.meal_date-p_from) and lower(slot)=lower(m.slot) and status<>'cancelled') then raise exception 'MEAL_SLOT_EXISTS';end if;
  insert into public.business_meal_plans(id,workspace_id,meal_date,slot,title,notes,sources,snapshot,updated_by)
  values(gen_random_uuid(),p_workspace,p_target+(m.meal_date-p_from),m.slot,m.title,m.notes,m.sources,m.snapshot,auth.uid()) returning * into n;
  insert into public.business_meal_history values(n.id,n.revision,p_workspace,to_jsonb(n),auth.uid(),now());result:=result||jsonb_build_array(n.id);
 end loop;
 if result='[]' then raise exception 'MEAL_EMPTY';end if;
 insert into public.business_meal_copies values(p_id,p_workspace,auth.uid(),fingerprint,result);return result;
end;$$;
-- Reuse purchasing calculations, explicit mappings, stock reservations and audit.
alter function public.business_menu_plan(uuid,text,jsonb) rename to business_menu_plan_before_meals;
revoke all on function public.business_menu_plan_before_meals(uuid,text,jsonb) from public,anon,authenticated;
create function public.business_menu_plan(p_workspace uuid,p_purpose text,p_sources jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s jsonb; m public.business_meal_plans; refs jsonb:='[]'; merged jsonb:='{}'; item jsonb; hashkey text; amount numeric; reqs jsonb;
begin
 if not public.business_can(p_workspace,'recipes.read') or not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 if jsonb_typeof(p_sources) is distinct from 'array' then raise exception 'BUSINESS_INVALID';end if;
 if not exists(select 1 from jsonb_array_elements(p_sources) x where x->>'kind'='meal') then return public.business_menu_plan_before_meals(p_workspace,p_purpose,p_sources);end if;
 if p_purpose is distinct from 'operations' or jsonb_array_length(p_sources) not between 1 and 20 or (select count(distinct x->>'id') from jsonb_array_elements(p_sources) x)<>jsonb_array_length(p_sources) then raise exception 'BUSINESS_INVALID';end if;
 for s in select value from jsonb_array_elements(p_sources) loop
  if s->>'kind' is distinct from 'meal' or s->'servings' is distinct from '1'::jsonb or exists(select 1 from jsonb_object_keys(s) x where x not in ('kind','id','revision','servings')) then raise exception 'BUSINESS_INVALID';end if;
  select * into m from public.business_meal_plans where workspace_id=p_workspace and id=(s->>'id')::uuid;
  if m.id is null or to_jsonb(m.revision) is distinct from s->'revision' then raise exception 'BUSINESS_STALE';end if;
  if m.status<>'confirmed' then raise exception 'MEAL_NOT_CONFIRMED';end if;
  refs:=refs||jsonb_build_array(s||jsonb_build_object('title',m.title,'recipe_revision',m.revision,'date',m.meal_date,'slot',m.slot,'snapshot',m.snapshot));
  for item in select value from jsonb_array_elements(m.snapshot->'requirements') loop
   hashkey:=item->>'key';amount:=(item->>'required')::numeric+coalesce((merged->hashkey->>'required')::numeric,0);
   if amount>1e9 then raise exception 'BUSINESS_LIMIT';end if;
   merged:=jsonb_set(merged,array[hashkey],item||jsonb_build_object('required',amount));
  end loop;
 end loop;
 if (select count(*) from jsonb_object_keys(merged))>100 then raise exception 'BUSINESS_LIMIT';end if;
 select jsonb_agg(value order by value->>'name',key) into reqs from jsonb_each(merged);
 return jsonb_build_object('purpose','operations','sources',refs,'requirements',reqs);
end;$$;
alter function public.business_menu_batch_create(uuid,uuid,jsonb,boolean,text,date,boolean) rename to business_menu_batch_before_meals;
revoke all on function public.business_menu_batch_before_meals(uuid,uuid,jsonb,boolean,text,date,boolean) from public,anon,authenticated;
create function public.business_menu_batch_create(p_workspace uuid,p_id uuid,p_sources jsonb,p_use_stock boolean,p_preview text,p_delivery date,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; s jsonb;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') or not public.business_can(p_workspace,'recipes.read') then raise exception 'BUSINESS_DENIED';end if;
 if exists(select 1 from public.business_menu_batches where id=p_id) then return public.business_menu_batch_before_meals(p_workspace,p_id,p_sources,p_use_stock,p_preview,p_delivery,p_confirmed);end if;
 if exists(select 1 from jsonb_array_elements(p_sources) x join public.business_meal_purchase_links l on l.meal_id=(x->>'id')::uuid where x->>'kind'='meal') then raise exception 'MEAL_PURCHASE_LINKED';end if;
 result:=public.business_menu_batch_before_meals(p_workspace,p_id,p_sources,p_use_stock,p_preview,p_delivery,p_confirmed);
 for s in select value from jsonb_array_elements(p_sources) where value->>'kind'='meal' loop
  insert into public.business_meal_purchase_links values(p_workspace,(s->>'id')::uuid,p_id);
 end loop;
 return result;
end;$$;
alter function public.business_menu_purchase(uuid,uuid,text,jsonb,jsonb,text) rename to business_menu_purchase_before_meals;
revoke all on function public.business_menu_purchase_before_meals(uuid,uuid,text,jsonb,jsonb,text) from public,anon,authenticated;
create function public.business_menu_purchase(p_workspace uuid,p_request uuid,p_purpose text,p_sources jsonb,p_adjustments jsonb,p_supplier text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from jsonb_array_elements(p_sources) s where s->>'kind'='meal') then raise exception 'MEAL_BATCH_REQUIRED';end if;
 return public.business_menu_purchase_before_meals(p_workspace,p_request,p_purpose,p_sources,p_adjustments,p_supplier);
end;$$;
revoke all on function public.business_menu_purchase(uuid,uuid,text,jsonb,jsonb,text) from public,anon;
grant execute on function public.business_menu_purchase(uuid,uuid,text,jsonb,jsonb,text) to authenticated;
do $migration$ declare definition text; begin
 select pg_get_functiondef('public.business_menu_batch_before_meals(uuid,uuid,jsonb,boolean,text,date,boolean)'::regprocedure) into definition;
 execute replace(definition,'public.business_menu_purchase(', 'public.business_menu_purchase_before_meals(');
end;$migration$;
do $migration$ declare definition text; begin
 select pg_get_functiondef('public.business_menu_purchase_before_meals(uuid,uuid,text,jsonb,jsonb,text)'::regprocedure) into definition;
 execute replace(definition,
  $old$(s->>'title')||' v'||(s->>'recipe_revision')||' / '||(s->>'servings')||' servings'$old$,
  $new$case when s->>'kind'='meal' then (s->>'date')||' / '||(s->>'slot')||' / '||(s->>'title')||' v'||(s->>'revision') else (s->>'title')||' v'||(s->>'recipe_revision')||' / '||(s->>'servings')||' servings' end$new$);
end;$migration$;
revoke all on function public.business_meal_snapshot(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.business_meal_save(uuid,uuid,bigint,date,text,text,text,jsonb),public.business_meal_transition(uuid,uuid,bigint,text),public.business_meal_copy(uuid,uuid,date,date,date),public.business_menu_plan(uuid,text,jsonb),public.business_menu_batch_create(uuid,uuid,jsonb,boolean,text,date,boolean) from public,anon;
grant execute on function public.business_meal_save(uuid,uuid,bigint,date,text,text,text,jsonb),public.business_meal_transition(uuid,uuid,bigint,text),public.business_meal_copy(uuid,uuid,date,date,date),public.business_menu_plan(uuid,text,jsonb),public.business_menu_batch_create(uuid,uuid,jsonb,boolean,text,date,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
