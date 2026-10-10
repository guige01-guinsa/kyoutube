-- Reversible presentation-only archives. Never changes source status, stock, money or receipt history.
create table public.shopping_record_archives (
  scope_id uuid not null,
  workspace_id uuid references public.business_workspaces(id) on delete cascade,
  owner_id uuid references auth.users(id) on delete cascade,
  kind text not null check (kind in ('request','record','favorite','supplier','business_purchase')),
  record_id uuid not null,
  source_token text not null,
  archived boolean not null,
  revision bigint not null default 1,
  changed_at timestamptz not null default now(),
  changed_by uuid references auth.users(id) on delete set null,
  primary key(scope_id,kind,record_id),
  check ((workspace_id is null and owner_id=scope_id and kind <> 'business_purchase') or
         (owner_id is null and workspace_id=scope_id and kind='business_purchase'))
);
create table public.shopping_cleanup_events (
  id bigint generated always as identity primary key,
  scope_id uuid not null,
  workspace_id uuid references public.business_workspaces(id) on delete cascade,
  owner_id uuid references auth.users(id) on delete cascade,
  kind text not null,
  record_id uuid not null,
  action text not null check(action in ('archive','restore')),
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.shopping_record_archives enable row level security;
alter table public.shopping_cleanup_events enable row level security;
revoke all on public.shopping_record_archives,public.shopping_cleanup_events from public,anon,authenticated;
grant select on public.shopping_record_archives,public.shopping_cleanup_events to authenticated;
create policy cleanup_archive_read on public.shopping_record_archives for select to authenticated using (
 (workspace_id is null and owner_id=auth.uid()) or
 (workspace_id is not null and public.business_can(workspace_id,'purchasing.read')));
create policy cleanup_event_read on public.shopping_cleanup_events for select to authenticated using (
 (workspace_id is null and owner_id=auth.uid()) or
 (workspace_id is not null and public.business_can(workspace_id,'purchasing.read')));

-- Private helper: only the public RPCs below may choose an owner or read a snapshot.
create function public.shopping_cleanup_source(p_owner uuid,p_workspace uuid,p_kind text,p_ids uuid[] default null)
returns table(id uuid,title text,detail text,status text,record_date timestamptz,source_token text)
language plpgsql security definer set search_path='' as $$
begin
 if p_workspace is not null then
  if p_kind <> 'business_purchase' then raise exception 'CLEANUP_INVALID'; end if;
  return query select r.id,r.title,coalesce(r.data->>'supplier',''),r.status,r.updated_at,
    md5(to_jsonb(r)::text) from public.business_records r
    where r.workspace_id=p_workspace and r.kind='purchase' and (p_ids is null or r.id=any(p_ids));
 elsif p_kind='request' then
  return query select r.id,coalesce(r.data->'supplier'->>'name',''),
    coalesce((select string_agg(x->>'name',', ') from jsonb_array_elements(r.data->'lines') x),''),
    r.status,r.updated_at,md5(to_jsonb(r)::text) from public.supplier_purchase_requests r
    where r.owner_id=p_owner and (p_ids is null or r.id=any(p_ids));
 elsif p_kind='record' then
  return query select r.id,r.ingredient_name,r.product_name,'received'::text,r.created_at,
    md5(to_jsonb(r)::text) from public.shopping_purchase_records r
    where r.owner_id=p_owner and (p_ids is null or r.id=any(p_ids));
 elsif p_kind='favorite' then
  return query select r.id,r.product_name,r.ingredient_name,'saved'::text,null::timestamptz,
    md5(to_jsonb(r)::text) from public.shopping_product_favorites r
    where r.owner_id=p_owner and (p_ids is null or r.id=any(p_ids));
 elsif p_kind='supplier' then
  return query select r.id,r.name,r.products,'saved'::text,r.created_at,
    md5(to_jsonb(r)::text) from public.shopping_suppliers r
    where r.owner_id=p_owner and (p_ids is null or r.id=any(p_ids));
 else raise exception 'CLEANUP_INVALID'; end if;
end; $$;
revoke all on function public.shopping_cleanup_source(uuid,uuid,text,uuid[]) from public,anon,authenticated;

create function public.shopping_cleanup_list(p_workspace uuid default null,p_kind text default 'request',
 p_archived boolean default false,p_before timestamptz default null,p_query text default '',p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=auth.uid(); v_scope uuid:=coalesce(p_workspace,auth.uid()); v_result jsonb;
begin
 if v_owner is null then raise exception 'CLEANUP_AUTH'; end if;
 if p_workspace is not null and not public.business_can(p_workspace,'purchasing.read') then raise exception 'CLEANUP_DENIED'; end if;
 if p_archived is null or p_offset is null or p_offset<0 or p_offset>100000 or p_query is null or char_length(p_query)>200 then raise exception 'CLEANUP_INVALID'; end if;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into v_result from (
  select s.id,s.title,s.detail,s.status,s.record_date,
   s.source_token||':'||coalesce(a.revision,0)::text as token,
   s.status in ('draft','received','cancelled','saved') as eligible,
   coalesce(a.archived and a.source_token=s.source_token and s.status in ('draft','received','cancelled','saved'),false) as archived,
   a.changed_at as archived_at,a.changed_by as actor_id
  from public.shopping_cleanup_source(v_owner,p_workspace,p_kind) s
  left join public.shopping_record_archives a on a.scope_id=v_scope and a.kind=p_kind and a.record_id=s.id
  where coalesce(a.archived and a.source_token=s.source_token and s.status in ('draft','received','cancelled','saved'),false)=p_archived
    and (p_before is null or s.record_date<p_before)
    and (p_query='' or strpos(lower(s.title||' '||s.detail||' '||s.id::text),lower(p_query))>0)
  order by s.record_date desc nulls last,s.id limit 51 offset p_offset
 ) t;
 return v_result;
end; $$;

create function public.shopping_cleanup_index(p_workspace uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=auth.uid(); v_scope uuid:=coalesce(p_workspace,auth.uid()); v_kind text; v_ids uuid[]; v_part jsonb; v_result jsonb:='[]';
begin
 if v_owner is null then raise exception 'CLEANUP_AUTH'; end if;
 if p_workspace is not null and not public.business_can(p_workspace,'purchasing.read') then raise exception 'CLEANUP_DENIED'; end if;
 for v_kind,v_ids in select a.kind,array_agg(a.record_id) from public.shopping_record_archives a
   where a.scope_id=v_scope and a.workspace_id is not distinct from p_workspace and a.archived group by a.kind loop
  select coalesce(jsonb_agg(jsonb_build_object('kind',v_kind,'id',s.id)),'[]') into v_part
   from public.shopping_cleanup_source(v_owner,p_workspace,v_kind,v_ids) s
   join public.shopping_record_archives a on a.scope_id=v_scope and a.kind=v_kind and a.record_id=s.id
   where a.archived and a.source_token=s.source_token and s.status in ('draft','received','cancelled','saved');
  v_result:=v_result||v_part;
 end loop;
 return v_result;
end; $$;

create function public.shopping_cleanup_apply(p_workspace uuid,p_kind text,p_targets jsonb,p_archive boolean)
returns integer language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=auth.uid(); v_scope uuid:=coalesce(p_workspace,auth.uid()); v_item jsonb; v_id uuid;
 v_source record; v_old public.shopping_record_archives; v_count integer:=0; v_effective boolean;
begin
 if v_owner is null then raise exception 'CLEANUP_AUTH'; end if;
 if p_archive is null or p_kind is null or p_targets is null or jsonb_typeof(p_targets)<>'array' then raise exception 'CLEANUP_INVALID'; end if;
 if jsonb_array_length(p_targets) not between 1 and 50 or octet_length(p_targets::text)>16384 then raise exception 'CLEANUP_INVALID'; end if;
 if (select count(distinct x->>'id') from jsonb_array_elements(p_targets) x)<>jsonb_array_length(p_targets) then raise exception 'CLEANUP_INVALID'; end if;
 if p_workspace is not null then
  -- Same lock order as the existing business mutations protects membership/record changes.
  perform 1 from public.business_workspaces where id=p_workspace for update;
  if p_kind<>'business_purchase' or not public.business_can(p_workspace,'purchasing.write') then raise exception 'CLEANUP_DENIED'; end if;
 elsif p_kind not in ('request','record','favorite','supplier') then raise exception 'CLEANUP_INVALID'; end if;
 perform pg_advisory_xact_lock(hashtextextended('record-cleanup:'||v_scope::text,0));
 for v_item in select value from jsonb_array_elements(p_targets) order by value->>'id' loop
  v_id:=(v_item->>'id')::uuid;
  if v_id is null or v_item->>'token' is null then raise exception 'CLEANUP_INVALID'; end if;
  case p_kind
   when 'business_purchase' then perform 1 from public.business_records where id=v_id and workspace_id=p_workspace and kind='purchase' for update;
   when 'request' then perform 1 from public.supplier_purchase_requests where id=v_id and owner_id=v_owner for update;
   when 'record' then perform 1 from public.shopping_purchase_records where id=v_id and owner_id=v_owner for update;
   when 'favorite' then perform 1 from public.shopping_product_favorites where id=v_id and owner_id=v_owner for update;
   when 'supplier' then perform 1 from public.shopping_suppliers where id=v_id and owner_id=v_owner for update;
  end case;
  select * into v_source from public.shopping_cleanup_source(v_owner,p_workspace,p_kind,array[v_id]);
  if v_source.id is null then raise exception 'CLEANUP_STALE'; end if;
  select * into v_old from public.shopping_record_archives where scope_id=v_scope and kind=p_kind and record_id=v_id for update;
  if v_item->>'token' is distinct from (v_source.source_token||':'||coalesce(v_old.revision,0)::text) then raise exception 'CLEANUP_STALE'; end if;
  if v_source.status not in ('draft','received','cancelled','saved') then raise exception 'CLEANUP_ACTIVE'; end if;
  v_effective:=coalesce(v_old.archived and v_old.source_token=v_source.source_token,false);
  if v_effective=p_archive then raise exception 'CLEANUP_STALE'; end if;
  insert into public.shopping_record_archives(scope_id,workspace_id,owner_id,kind,record_id,source_token,archived,changed_by)
   values(v_scope,p_workspace,case when p_workspace is null then v_owner end,p_kind,v_id,v_source.source_token,p_archive,v_owner)
   on conflict(scope_id,kind,record_id) do update set source_token=excluded.source_token,archived=excluded.archived,
    revision=shopping_record_archives.revision+1,changed_at=now(),changed_by=v_owner;
  insert into public.shopping_cleanup_events(scope_id,workspace_id,owner_id,kind,record_id,action,actor_id)
   values(v_scope,p_workspace,case when p_workspace is null then v_owner end,p_kind,v_id,case when p_archive then 'archive' else 'restore' end,v_owner);
  v_count:=v_count+1;
 end loop;
 return v_count;
end; $$;
revoke all on function public.shopping_cleanup_list(uuid,text,boolean,timestamptz,text,integer),public.shopping_cleanup_index(uuid),public.shopping_cleanup_apply(uuid,text,jsonb,boolean) from public,anon;
grant execute on function public.shopping_cleanup_list(uuid,text,boolean,timestamptz,text,integer),public.shopping_cleanup_index(uuid),public.shopping_cleanup_apply(uuid,text,jsonb,boolean) to authenticated;
