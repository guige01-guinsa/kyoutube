-- Business collaboration is opt-in. Personal records and policies are unchanged.
-- Membership, invitations and record mutations are server-authorized; UI duties grant nothing.
create table public.business_workspaces (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(btrim(name)) between 1 and 120),
 require_purchase_approval boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.business_members (
 workspace_id uuid not null references public.business_workspaces(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 display_name text not null check(length(btrim(display_name)) between 1 and 120),
 permissions text[] not null default '{}',
 active boolean not null default true,
 updated_at timestamptz not null default now(),
 primary key(workspace_id,user_id)
);
create table public.business_invites (
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references public.business_workspaces(id) on delete cascade,
 email text not null check(length(email) between 3 and 254),
 token_hash text not null unique,
 permissions text[] not null,
 expires_at timestamptz not null,
 used_at timestamptz,
 revoked boolean not null default false,
 created_at timestamptz not null default now()
);
create table public.business_records (
 id uuid primary key,
 workspace_id uuid not null references public.business_workspaces(id) on delete cascade,
 kind text not null check(kind in ('recipe','meal','purchase','cost','sale')),
 title text not null check(length(btrim(title)) between 1 and 120),
 data jsonb not null check(jsonb_typeof(data)='object' and octet_length(data::text)<=131072),
 status text not null default 'draft' check(status in ('draft','review','approved','sent','received','cancelled')),
 revision bigint not null default 1,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index business_records_recent on public.business_records(workspace_id,kind,updated_at desc,id);
create index business_members_user on public.business_members(user_id,workspace_id) where active;
create index business_invites_owner on public.business_invites(workspace_id,created_at desc);
create table public.business_record_versions (
 record_id uuid not null references public.business_records(id) on delete cascade,
 revision bigint not null, title text not null, data jsonb not null, status text not null,
 actor_id uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 primary key(record_id,revision)
);
create table public.business_access_events (
 id bigint generated always as identity primary key,
 workspace_id uuid not null references public.business_workspaces(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null,
 subject_id uuid references auth.users(id) on delete set null,
 action text not null, permissions text[] not null default '{}', created_at timestamptz not null default now()
);

create function public.business_permissions_valid(p text[]) returns boolean language sql immutable set search_path='' as $$
 select p is not null and cardinality(p) between 1 and 7
 and p <@ array['recipes.read','recipes.write','purchasing.read','purchasing.write','finance.read','finance.write','purchases.approve']::text[]
 and array_position(p,null) is null
 and (not 'recipes.write'=any(p) or 'recipes.read'=any(p))
 and (not 'purchasing.write'=any(p) or 'purchasing.read'=any(p))
 and (not 'finance.write'=any(p) or 'finance.read'=any(p))
 and (not 'purchases.approve'=any(p) or 'purchasing.read'=any(p));
$$;
alter table public.business_members add constraint business_member_permissions check(public.business_permissions_valid(permissions));
alter table public.business_invites add constraint business_invite_permissions check(public.business_permissions_valid(permissions));

create function public.business_owner(p_workspace uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 and exists(select 1 from public.business_workspaces where id=p_workspace and owner_id=auth.uid());
$$;
create function public.business_paid(p_workspace uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((public.member_feature_snapshot(owner_id)->>'can_manage_costs')::boolean,false)
 from public.business_workspaces where id=p_workspace;
$$;
create function public.business_can(p_workspace uuid,p_permission text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 and exists(select 1 from public.business_workspaces w join public.business_members m on m.workspace_id=w.id
 where w.id=p_workspace and m.user_id=auth.uid() and m.active
 and (w.owner_id=auth.uid() or p_permission=any(m.permissions))
 and (p_permission not in ('finance.read','finance.write','recipes.write','purchasing.write','purchases.approve') or public.business_paid(w.id)));
$$;
create function public.business_record_permission(p_kind text,p_write boolean default false) returns text language sql immutable set search_path='' as $$
 select case when p_kind in ('recipe','meal') then 'recipes.' when p_kind='purchase' then 'purchasing.' when p_kind in ('cost','sale') then 'finance.' else 'invalid.' end || case when p_write then 'write' else 'read' end;
$$;

alter table public.business_workspaces enable row level security;
alter table public.business_members enable row level security;
alter table public.business_invites enable row level security;
alter table public.business_records enable row level security;
alter table public.business_record_versions enable row level security;
alter table public.business_access_events enable row level security;
revoke all on public.business_workspaces,public.business_members,public.business_invites,public.business_records,public.business_record_versions,public.business_access_events from public,anon,authenticated;
grant select on public.business_workspaces,public.business_members,public.business_records,public.business_record_versions,public.business_access_events to authenticated;
grant select(id,workspace_id,email,permissions,expires_at,used_at,revoked,created_at) on public.business_invites to authenticated;
grant all on public.business_workspaces,public.business_members,public.business_invites,public.business_records,public.business_record_versions,public.business_access_events to service_role;
create policy business_workspace_read on public.business_workspaces for select to authenticated using(public.business_can(id,'recipes.read') or public.business_can(id,'purchasing.read') or public.business_can(id,'finance.read') or public.business_owner(id));
create policy business_member_read on public.business_members for select to authenticated using(public.business_owner(workspace_id) or (user_id=auth.uid() and active));
create policy business_invite_read on public.business_invites for select to authenticated using(public.business_owner(workspace_id));
create policy business_record_read on public.business_records for select to authenticated using(public.business_can(workspace_id,public.business_record_permission(kind)));
create policy business_version_read on public.business_record_versions for select to authenticated using(exists(select 1 from public.business_records r where r.id=record_id and public.business_can(r.workspace_id,public.business_record_permission(r.kind))));
create policy business_access_read on public.business_access_events for select to authenticated using(public.business_owner(workspace_id));

create function public.business_create(p_name text,p_display_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); w uuid; p text[]:=array['recipes.read','recipes.write','purchasing.read','purchasing.write','finance.read','finance.write','purchases.approve'];begin
 if u is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'BUSINESS_AUTH';end if;
 if not coalesce((public.member_feature_snapshot(u)->>'can_manage_costs')::boolean,false) then raise exception 'BUSINESS_PLAN';end if;
 perform pg_advisory_xact_lock(hashtextextended('business-create:'||u::text,0));
 if (select count(*) from public.business_workspaces where owner_id=u)>=3 then raise exception 'BUSINESS_LIMIT';end if;
 insert into public.business_workspaces(owner_id,name) values(u,btrim(p_name)) returning id into w;
 insert into public.business_members(workspace_id,user_id,display_name,permissions) values(w,u,btrim(p_display_name),p);
 return w;
end;$$;
create function public.business_settings(p_workspace uuid,p_name text,p_require_approval boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.business_owner(p_workspace) then raise exception 'BUSINESS_DENIED';end if;
 perform 1 from public.business_workspaces where id=p_workspace for update;
 update public.business_workspaces set name=btrim(p_name),require_purchase_approval=p_require_approval where id=p_workspace;
 insert into public.business_access_events(workspace_id,actor_id,action) values(p_workspace,auth.uid(),'settings');
end;$$;
create function public.business_invite(p_workspace uuid,p_email text,p_permissions text[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare token text; i uuid;begin
 if not public.business_owner(p_workspace) then raise exception 'BUSINESS_DENIED';end if;
 if not coalesce(public.business_paid(p_workspace),false) then raise exception 'BUSINESS_PLAN';end if;
 if p_email is null or length(btrim(p_email)) not between 3 and 254 or btrim(p_email) !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or not public.business_permissions_valid(p_permissions) then raise exception 'BUSINESS_INVALID';end if;
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if (select count(*) from public.business_invites where workspace_id=p_workspace and created_at>now()-interval '1 hour')>=30 then raise exception 'BUSINESS_LIMIT';end if;
 update public.business_invites set revoked=true where workspace_id=p_workspace and email=lower(btrim(p_email)) and used_at is null;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.business_invites(workspace_id,email,token_hash,permissions,expires_at)
 values(p_workspace,lower(btrim(p_email)),encode(extensions.digest(token,'sha256'),'hex'),p_permissions,now()+interval '24 hours') returning id into i;
 insert into public.business_access_events(workspace_id,actor_id,action,permissions) values(p_workspace,auth.uid(),'invited',p_permissions);
 return jsonb_build_object('id',i,'token',token,'expires_at',now()+interval '24 hours');
end;$$;
create function public.business_accept(p_token text,p_display_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); i public.business_invites; email text; w uuid;begin
 if u is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'BUSINESS_AUTH';end if;
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'BUSINESS_INVITE_INVALID';end if;
 select lower(a.email) into email from auth.users a where a.id=u and a.email_confirmed_at is not null;
 select workspace_id into w from public.business_invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 if w is null then raise exception 'BUSINESS_INVITE_INVALID';end if;
 perform 1 from public.business_workspaces where id=w for update;
 select * into i from public.business_invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if i.id is null or email is distinct from i.email or i.used_at is not null or i.revoked or i.expires_at<=now() then raise exception 'BUSINESS_INVITE_INVALID';end if;
 if public.business_owner(w) then raise exception 'BUSINESS_INVITE_INVALID';end if;
 if not coalesce(public.business_paid(w),false) then raise exception 'BUSINESS_PLAN';end if;
 if not exists(select 1 from public.business_members where workspace_id=w and user_id=u and active)
 and (select count(*) from public.business_members where workspace_id=w and active)>=30 then raise exception 'BUSINESS_LIMIT';end if;
 insert into public.business_members(workspace_id,user_id,display_name,permissions,active)
 values(w,u,btrim(p_display_name),i.permissions,true) on conflict(workspace_id,user_id) do update set display_name=excluded.display_name,permissions=excluded.permissions,active=true,updated_at=now();
 update public.business_invites set used_at=now() where id=i.id;
 insert into public.business_access_events(workspace_id,actor_id,subject_id,action,permissions) values(w,u,u,'joined',i.permissions);
 return w;
end;$$;
create function public.business_member_update(p_workspace uuid,p_user uuid,p_permissions text[],p_active boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.business_owner(p_workspace) then raise exception 'BUSINESS_DENIED';end if;
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if p_user=(select owner_id from public.business_workspaces where id=p_workspace) then raise exception 'BUSINESS_OWNER_FIXED';end if;
 if p_active is null or not public.business_permissions_valid(p_permissions) then raise exception 'BUSINESS_INVALID';end if;
 if p_active and not coalesce((select active from public.business_members where workspace_id=p_workspace and user_id=p_user),false) and (select count(*) from public.business_members where workspace_id=p_workspace and active)>=30 then raise exception 'BUSINESS_LIMIT';end if;
 update public.business_members set permissions=p_permissions,active=p_active,updated_at=now() where workspace_id=p_workspace and user_id=p_user;
 if not found then raise exception 'BUSINESS_NOT_FOUND';end if;
 -- A pending invitation must not restore permissions after revocation/change.
 update public.business_invites set revoked=true where workspace_id=p_workspace and used_at is null and email=(select lower(email) from auth.users where id=p_user);
 insert into public.business_access_events(workspace_id,actor_id,subject_id,action,permissions) values(p_workspace,auth.uid(),p_user,case when p_active then 'permissions' else 'revoked' end,p_permissions);
end;$$;
create function public.business_invite_revoke(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare w uuid;begin
 select workspace_id into w from public.business_invites where id=p_id;
 if not coalesce(public.business_owner(w),false) then raise exception 'BUSINESS_DENIED';end if;
 perform 1 from public.business_workspaces where id=w for update;
 update public.business_invites set revoked=true where id=p_id;
end;$$;

create function public.business_data_valid(p_kind text,d jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare keys text[]; item jsonb; k text;begin
 if d is null or jsonb_typeof(d)<>'object' or octet_length(d::text)>131072 then return false;end if;
 keys:=case p_kind when 'recipe' then array['ingredients','steps','notes','servings']
 when 'meal' then array['date','servings','recipe_ids','notes']
 when 'purchase' then array['supplier','buyer','phone','address','delivery_date','notes','currency','lines']
 when 'cost' then array['recipe_id','unit_cost','unit_price','currency','notes']
 when 'sale' then array['cost_id','date','quantity','unit_cost','unit_price','currency'] else '{}'::text[] end;
 if cardinality(keys)=0 or exists(select 1 from jsonb_object_keys(d) a where not a=any(keys)) then return false;end if;
 if p_kind in ('recipe','meal','purchase','cost') and (jsonb_typeof(d->'notes') is distinct from 'string' or length(d->>'notes')>4000) then return false;end if;
 if p_kind in ('recipe','meal') and not public.chef_number_valid(d->'servings',0.001,100000,false) then return false;end if;
 if p_kind='recipe' then
  return jsonb_typeof(d->'ingredients')='string' and length(d->>'ingredients') between 1 and 30000
   and jsonb_typeof(d->'steps')='string' and length(d->>'steps') between 1 and 30000;
 elsif p_kind='meal' then
  if jsonb_typeof(d->'recipe_ids') is distinct from 'array' then return false;end if;
  if jsonb_array_length(d->'recipe_ids') not between 1 and 20 then return false;end if;
  for k in select jsonb_array_elements_text(d->'recipe_ids') loop perform k::uuid;end loop;
 elsif p_kind='purchase' then
  foreach k in array array['supplier','buyer','phone','address','delivery_date','currency'] loop
    if jsonb_typeof(d->k) is distinct from 'string' or length(d->>k)>500 then return false;end if;
  end loop;
  if d->>'currency' not in ('KRW','USD') or jsonb_typeof(d->'lines') is distinct from 'array' then return false;end if;
  if jsonb_array_length(d->'lines') not between 1 and 100 then return false;end if;
  if (select count(distinct x->>'id') from jsonb_array_elements(d->'lines') x)<>jsonb_array_length(d->'lines') then return false;end if;
  for item in select value from jsonb_array_elements(d->'lines') loop
    if jsonb_typeof(item)<>'object' or exists(select 1 from jsonb_object_keys(item) a where a not in ('id','name','quantity','unit','spec','price')) then return false;end if;
    foreach k in array array['id','name','unit','spec'] loop
      if jsonb_typeof(item->k) is distinct from 'string' then return false;end if;
    end loop;
    perform (item->>'id')::uuid;
    if length(btrim(item->>'name')) not between 1 and 250 or length(item->>'unit')>30 or length(item->>'spec')>300
    or not public.chef_number_valid(item->'quantity',0.000001,1e9,true) or not public.chef_number_valid(item->'price',0,1e12,true) then return false;end if;
  end loop;
 elsif p_kind in ('cost','sale') then
  if d->>'currency' is null or d->>'currency' not in ('KRW','USD') or not public.chef_number_valid(d->'unit_cost',0,1e12,false)
   or not public.chef_number_valid(d->'unit_price',0,1e12,false) then return false;end if;
  if p_kind='cost' and d->>'recipe_id' is not null then perform (d->>'recipe_id')::uuid;end if;
  if p_kind='sale' then
   perform (d->>'cost_id')::uuid;
   if not public.chef_number_valid(d->'quantity',1,100000,false) or trunc((d->>'quantity')::numeric)<>(d->>'quantity')::numeric then return false;end if;
  end if;
 end if;
 if p_kind in ('sale','meal') then
  if jsonb_typeof(d->'date') is distinct from 'string' or d->>'date' !~ '^\d{4}-\d{2}-\d{2}$' or to_char((d->>'date')::date,'YYYY-MM-DD')<>d->>'date' then return false;end if;
 end if;
 if p_kind='purchase' and d->>'delivery_date'<>'' then
  if d->>'delivery_date' !~ '^\d{4}-\d{2}-\d{2}$' or to_char((d->>'delivery_date')::date,'YYYY-MM-DD')<>d->>'delivery_date' then return false;end if;
 end if;
 return true;
exception when others then return false;
end;$$;
create function public.business_purchase_ready(d jsonb) returns boolean language sql immutable set search_path='' as $$
 select btrim(coalesce(d->>'supplier',''))<>'' and btrim(coalesce(d->>'buyer',''))<>''
 and jsonb_array_length(d->'lines')>0 and not exists(select 1 from jsonb_array_elements(d->'lines') l
 where l->>'quantity' is null or btrim(coalesce(l->>'unit',''))='');
$$;
create function public.business_save_record(p_workspace uuid,p_id uuid,p_kind text,p_title text,p_data jsonb,p_revision bigint)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.business_records; cost public.business_records; d jsonb:=p_data; k text;begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,public.business_record_permission(p_kind,true)) then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_revision is null or p_revision<0 then raise exception 'BUSINESS_INVALID';end if;
 select * into r from public.business_records where id=p_id for update;
 if r.id is not null and (r.workspace_id<>p_workspace or r.kind<>p_kind) then raise exception 'BUSINESS_NOT_FOUND';end if;
 if (r.id is null and p_revision<>0) or (r.id is not null and r.revision<>p_revision) then raise exception 'BUSINESS_STALE';end if;
 if r.id is not null and r.status<>'draft' then raise exception 'BUSINESS_FROZEN';end if;
 if r.id is null and (select count(*) from public.business_records where workspace_id=p_workspace)>=3000 then raise exception 'BUSINESS_LIMIT';end if;
 if p_kind='sale' then
  select * into cost from public.business_records where id=(d->>'cost_id')::uuid and workspace_id=p_workspace and kind='cost' and (status='draft' or r.id is not null);
  if cost.id is null then raise exception 'BUSINESS_SOURCE';end if;
  if r.id is not null and d->>'cost_id' is distinct from r.data->>'cost_id' then raise exception 'BUSINESS_SOURCE';end if;
  d:=d||jsonb_build_object('unit_cost',coalesce(r.data,cost.data)->'unit_cost','unit_price',coalesce(r.data,cost.data)->'unit_price','currency',coalesce(r.data,cost.data)->'currency');
 elsif p_kind='meal' then
  for k in select jsonb_array_elements_text(d->'recipe_ids') loop
   if not exists(select 1 from public.business_records where id=k::uuid and workspace_id=p_workspace and kind='recipe') then raise exception 'BUSINESS_SOURCE';end if;
  end loop;
 elsif p_kind='cost' and d->>'recipe_id' is not null then
  if not exists(select 1 from public.business_records where id=(d->>'recipe_id')::uuid and workspace_id=p_workspace and kind='recipe') then raise exception 'BUSINESS_SOURCE';end if;
 end if;
 if not coalesce(public.business_data_valid(p_kind,d),false) then raise exception 'BUSINESS_INVALID';end if;
 if r.id is not null and r.title=btrim(p_title) and r.data=d then return to_jsonb(r);end if;
 insert into public.business_records(id,workspace_id,kind,title,data,updated_by)
 values(p_id,p_workspace,p_kind,btrim(p_title),d,auth.uid())
 on conflict(id) do update set title=excluded.title,data=excluded.data,revision=business_records.revision+1,updated_by=auth.uid(),updated_at=now() returning * into r;
 insert into public.business_record_versions(record_id,revision,title,data,status,actor_id)
 values(r.id,r.revision,r.title,r.data,r.status,auth.uid());
 return to_jsonb(r);
end;$$;
create function public.business_purchase_transition(p_workspace uuid,p_id uuid,p_revision bigint,p_status text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.business_records; approval boolean; allowed boolean:=false;begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 select * into r from public.business_records where id=p_id and workspace_id=p_workspace and kind='purchase' for update;
 if r.id is null or not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 if r.revision is distinct from p_revision then raise exception 'BUSINESS_STALE';end if;
 select require_purchase_approval into approval from public.business_workspaces where id=p_workspace;
 if p_status='approved' then
  allowed:=(r.status='review' and public.business_can(p_workspace,'purchases.approve')) or (r.status='draft' and not approval and public.business_can(p_workspace,'purchasing.write'));
 elsif p_status='review' then allowed:=r.status='draft' and approval and public.business_can(p_workspace,'purchasing.write');
 elsif p_status='draft' then allowed:=r.status in ('review','approved') and (public.business_can(p_workspace,'purchasing.write') or public.business_can(p_workspace,'purchases.approve'));
 elsif p_status='sent' then allowed:=r.status='approved' and public.business_can(p_workspace,'purchasing.write');
 elsif p_status='received' then allowed:=r.status='sent' and public.business_can(p_workspace,'purchasing.write');
 elsif p_status='cancelled' then allowed:=r.status in ('draft','review','approved','sent') and (public.business_can(p_workspace,'purchasing.write') or public.business_can(p_workspace,'purchases.approve'));
 end if;
 if not coalesce(allowed,false) then raise exception 'BUSINESS_TRANSITION';end if;
 if p_status in ('review','approved','sent') and not public.business_purchase_ready(r.data) then raise exception 'BUSINESS_PURCHASE_INCOMPLETE';end if;
 update public.business_records set status=p_status,revision=revision+1,updated_by=auth.uid(),updated_at=now() where id=r.id returning * into r;
 insert into public.business_record_versions(record_id,revision,title,data,status,actor_id) values(r.id,r.revision,r.title,r.data,r.status,auth.uid());
 return to_jsonb(r);
end;$$;
create function public.business_import_recipe(p_workspace uuid,p_recipe uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.recipes_creator; d jsonb;begin
 if not public.business_can(p_workspace,'recipes.write') then raise exception 'BUSINESS_DENIED';end if;
 select * into r from public.recipes_creator where id=p_recipe and author_id=auth.uid();
 if r.id is null then raise exception 'BUSINESS_SOURCE';end if;
 d:=jsonb_build_object('ingredients',(select string_agg(v,E'\n') from jsonb_array_elements_text(r.ingredients) v),'steps',(select string_agg(v,E'\n') from jsonb_array_elements_text(r.steps) v),'notes',coalesce(r.tips,''),'servings',1);
 return public.business_save_record(p_workspace,gen_random_uuid(),'recipe',r.title,d,0);
end;$$;
create function public.business_request_ingredients(p_workspace uuid,p_recipe uuid,p_revision bigint,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare source public.business_records; r public.business_records; lines jsonb;begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'recipes.write') or not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 select * into source from public.business_records where id=p_recipe and workspace_id=p_workspace and kind='recipe' and status='draft';
 if source.id is null then raise exception 'BUSINESS_SOURCE';end if;
 if source.revision is distinct from p_revision then raise exception 'BUSINESS_STALE';end if;
 if p_request is null then raise exception 'BUSINESS_INVALID';end if;
 select * into r from public.business_records where id=p_request;
 if r.id is not null then
  if r.workspace_id<>p_workspace or r.kind<>'purchase' or r.updated_by<>auth.uid() then raise exception 'BUSINESS_STALE';end if;
  return to_jsonb(r);
 end if;
 select jsonb_agg(jsonb_build_object('id',gen_random_uuid(),'name',left(btrim(a),250),'quantity',null,'unit','','price',null,'spec','')) into lines
 from regexp_split_to_table(source.data->>'ingredients',E'\n') a where btrim(a)<>'';
 if (select count(*) from public.business_records where workspace_id=p_workspace)>=3000 then raise exception 'BUSINESS_LIMIT';end if;
 if jsonb_array_length(lines) not between 1 and 100 then raise exception 'BUSINESS_INVALID';end if;
 insert into public.business_records(id,workspace_id,kind,title,data,updated_by)
 values(p_request,p_workspace,'purchase',source.title,jsonb_build_object('supplier','','buyer',(select name from public.business_workspaces where id=p_workspace),'phone','','address','','delivery_date','','notes','Recipe: '||source.title||' / revision '||source.revision||'. Confirm purchase quantities separately.','currency','KRW','lines',lines),auth.uid()) returning * into r;
 insert into public.business_record_versions(record_id,revision,title,data,status,actor_id) values(r.id,r.revision,r.title,r.data,r.status,auth.uid());
 return to_jsonb(r);
end;$$;

-- Explicit allowlist; helper/validation functions are never public RPC write paths.
revoke all on function public.business_permissions_valid(text[]),public.business_owner(uuid),public.business_paid(uuid),public.business_can(uuid,text),public.business_record_permission(text,boolean),public.business_data_valid(text,jsonb),public.business_purchase_ready(jsonb) from public,anon,authenticated;
grant execute on function public.business_owner(uuid),public.business_can(uuid,text),public.business_record_permission(text,boolean) to authenticated;
revoke all on function public.business_create(text,text),public.business_settings(uuid,text,boolean),public.business_invite(uuid,text,text[]),public.business_accept(text,text),public.business_member_update(uuid,uuid,text[],boolean),public.business_invite_revoke(uuid),public.business_save_record(uuid,uuid,text,text,jsonb,bigint),public.business_purchase_transition(uuid,uuid,bigint,text),public.business_import_recipe(uuid,uuid),public.business_request_ingredients(uuid,uuid,bigint,uuid) from public,anon;
grant execute on function public.business_create(text,text),public.business_settings(uuid,text,boolean),public.business_invite(uuid,text,text[]),public.business_accept(text,text),public.business_member_update(uuid,uuid,text[],boolean),public.business_invite_revoke(uuid),public.business_save_record(uuid,uuid,text,text,jsonb,bigint),public.business_purchase_transition(uuid,uuid,bigint,text),public.business_import_recipe(uuid,uuid),public.business_request_ingredients(uuid,uuid,bigint,uuid) to authenticated;

create function public.business_context(p_workspace uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare w public.business_workspaces; m public.business_members;begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'BUSINESS_AUTH';end if;
 select * into w from public.business_workspaces where id=p_workspace;
 select * into m from public.business_members where workspace_id=p_workspace and user_id=auth.uid() and active;
 if w.id is null or m.user_id is null then raise exception 'BUSINESS_DENIED';end if;
 return jsonb_build_object('id',w.id,'name',w.name,'owner',w.owner_id=auth.uid(),'paid',coalesce(public.business_paid(w.id),false),'require_approval',w.require_purchase_approval,'permissions',to_jsonb(m.permissions),'display_name',m.display_name);
end;$$;
create function public.business_document(p_workspace uuid,p_id uuid,p_revision bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.business_records;begin
 if not public.business_can(p_workspace,'purchasing.read') or not coalesce(public.business_paid(p_workspace),false) then raise exception 'BUSINESS_DENIED';end if;
 select * into r from public.business_records where id=p_id and workspace_id=p_workspace and kind='purchase' and status<>'cancelled';
 if r.id is null then raise exception 'BUSINESS_NOT_FOUND';end if;
 if r.revision is distinct from p_revision then raise exception 'BUSINESS_STALE';end if;
 if not public.business_purchase_ready(r.data) then raise exception 'BUSINESS_PURCHASE_INCOMPLETE';end if;
 return to_jsonb(r);
end;$$;
create function public.business_sales_totals(p_workspace uuid,p_from date,p_until date,p_currency text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.business_can(p_workspace,'finance.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_currency is null or p_currency not in ('KRW','USD') or p_from is null or p_until is null or p_until<=p_from then raise exception 'BUSINESS_INVALID';end if;
 return (select jsonb_build_object('quantity',coalesce(sum((data->>'quantity')::numeric),0),'revenue',coalesce(sum((data->>'quantity')::numeric*(data->>'unit_price')::numeric),0),'cost',coalesce(sum((data->>'quantity')::numeric*(data->>'unit_cost')::numeric),0))
 from public.business_records where workspace_id=p_workspace and kind='sale' and status='draft' and data->>'currency'=p_currency and (data->>'date')::date>=p_from and (data->>'date')::date<p_until);
end;$$;
revoke all on function public.business_context(uuid),public.business_document(uuid,uuid,bigint),public.business_sales_totals(uuid,date,date,text) from public,anon;
grant execute on function public.business_context(uuid),public.business_document(uuid,uuid,bigint),public.business_sales_totals(uuid,date,date,text) to authenticated;

create function public.business_archive_record(p_workspace uuid,p_id uuid,p_revision bigint) returns void language plpgsql security definer set search_path='' as $$
declare r public.business_records;begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 select * into r from public.business_records where id=p_id and workspace_id=p_workspace for update;
 if r.id is null or r.kind='purchase' or not public.business_can(p_workspace,public.business_record_permission(r.kind,true)) then raise exception 'BUSINESS_DENIED';end if;
 if r.revision is distinct from p_revision then raise exception 'BUSINESS_STALE';end if;
 update public.business_records set status='cancelled',revision=revision+1,updated_by=auth.uid(),updated_at=now() where id=r.id returning * into r;
 insert into public.business_record_versions(record_id,revision,title,data,status,actor_id) values(r.id,r.revision,r.title,r.data,r.status,auth.uid());
end;$$;
create function public.business_versions(p_workspace uuid,p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.business_records;begin
 select * into r from public.business_records where id=p_id and workspace_id=p_workspace;
 if r.id is null or not public.business_can(p_workspace,public.business_record_permission(r.kind)) then raise exception 'BUSINESS_DENIED';end if;
 return (select coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) from(select h.*,coalesce(m.display_name,'Former member') as actor_name from public.business_record_versions h left join public.business_members m on m.workspace_id=p_workspace and m.user_id=h.actor_id where h.record_id=p_id order by h.revision desc limit 30)v);
end;$$;
revoke all on function public.business_archive_record(uuid,uuid,bigint),public.business_versions(uuid,uuid) from public,anon;
grant execute on function public.business_archive_record(uuid,uuid,bigint),public.business_versions(uuid,uuid) to authenticated;
