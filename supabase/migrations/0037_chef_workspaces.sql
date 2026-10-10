-- Private professional recipe workspaces and immutable version snapshots.
create table public.chef_workspaces (
  recipe_id uuid primary key references public.recipes_creator(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  document jsonb not null,
  revision bigint not null default 0 check (revision >= 0),
  next_version integer not null default 1,
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(document) = 'object' and octet_length(document::text) <= 262144)
);
create table public.chef_recipe_versions (
  recipe_id uuid not null references public.chef_workspaces(recipe_id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  label text not null check (length(trim(label)) between 1 and 80),
  note text not null default '' check (length(note) <= 1000),
  document jsonb not null,
  created_at timestamptz not null default now(),
  primary key (recipe_id, version_number),
  check (jsonb_typeof(document) = 'object' and octet_length(document::text) <= 262144)
);
create index chef_workspaces_owner_idx on public.chef_workspaces(owner_id);
create index chef_versions_owner_idx on public.chef_recipe_versions(owner_id);
alter table public.chef_workspaces enable row level security;
alter table public.chef_recipe_versions enable row level security;
revoke all on public.chef_workspaces, public.chef_recipe_versions from anon, authenticated;
grant select on public.chef_workspaces, public.chef_recipe_versions to authenticated;
grant all on public.chef_workspaces, public.chef_recipe_versions to service_role;
create policy chef_workspaces_read_own on public.chef_workspaces for select to authenticated
  using (owner_id = auth.uid());
create policy chef_versions_read_own on public.chef_recipe_versions for select to authenticated
  using (owner_id = auth.uid());

create function public.chef_number_valid(v jsonb, lo numeric, hi numeric, optional boolean)
returns boolean language sql immutable set search_path = '' as $$
  select case when v is null or v = 'null'::jsonb then optional
    when jsonb_typeof(v) = 'number' then (v::text)::numeric between lo and hi
    else false end;
$$;
revoke all on function public.chef_number_valid(jsonb,numeric,numeric,boolean) from public;

create function public.chef_document_valid(d jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare item jsonb; ids text[] := '{}';
begin
  if d is null or jsonb_typeof(d) <> 'object' or octet_length(d::text) > 262144 then return false; end if;
  if (d->>'schema') is distinct from '1' or
     jsonb_typeof(d->'title') is distinct from 'string' or length(trim(d->>'title')) not between 1 and 120 or
     jsonb_typeof(d->'steps') is distinct from 'string' or length(d->>'steps') > 30000 or
     jsonb_typeof(d->'notes') is distinct from 'string' or length(d->>'notes') > 4000 or
     coalesce(d->>'currency','') not in ('KRW','USD') or
     jsonb_typeof(d->'ingredients') is distinct from 'array' then return false; end if;
  if jsonb_array_length(d->'ingredients') > 200 then return false; end if;
  if not public.chef_number_valid(d->'baseServings',0.001,100000,true) or
     not public.chef_number_valid(d->'targetServings',0.001,100000,true) or
     not public.chef_number_valid(d->'extraCost',0,1000000000000,false) or
     not public.chef_number_valid(d->'inputWeight',0.001,1000000000,true) or
     not public.chef_number_valid(d->'outputWeight',0.001,1000000000,true) then return false; end if;
  for item in select value from jsonb_array_elements(d->'ingredients') loop
    if jsonb_typeof(item) <> 'object' or
       jsonb_typeof(item->'id') is distinct from 'string' or length(item->>'id') not between 1 and 80 or
       (item->>'id') = any(ids) or
       jsonb_typeof(item->'name') is distinct from 'string' or length(trim(item->>'name')) not between 1 and 250 or
       coalesce(item->>'unit','') not in ('g','kg','ml','l','each') or
       coalesce(item->>'purchaseUnit','') not in ('g','kg','ml','l','each') or
       not public.chef_number_valid(item->'quantity',0.000001,1000000000,true) or
       not public.chef_number_valid(item->'purchaseQuantity',0.000001,1000000000,true) or
       not public.chef_number_valid(item->'purchasePrice',0,1000000000000,true) or
       not public.chef_number_valid(item->'yieldPercent',0.001,100,false) then return false; end if;
    ids := array_append(ids, item->>'id');
  end loop;
  return true;
end;
$$;
revoke all on function public.chef_document_valid(jsonb) from public;

create function public.save_chef_workspace(
  p_recipe_id uuid, p_document jsonb, p_expected_revision bigint,
  p_version_label text default null, p_version_note text default ''
) returns bigint language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); current_row public.chef_workspaces%rowtype;
begin
  if uid is null then raise exception 'CHEF_LOGIN_REQUIRED'; end if;
  -- Lock the source first: concurrent creation, saving and deletion serialize.
  perform 1 from public.recipes_creator where id = p_recipe_id and author_id = uid for update;
  if not found then raise exception 'CHEF_RECIPE_NOT_OWNED'; end if;
  if p_expected_revision is null or p_expected_revision < 0 or not public.chef_document_valid(p_document) then
    raise exception 'CHEF_INVALID_DOCUMENT';
  end if;
  if p_version_note is null or length(p_version_note) > 1000 or
     (p_version_label is not null and length(trim(p_version_label)) not between 1 and 80) then
    raise exception 'CHEF_INVALID_VERSION';
  end if;
  insert into public.chef_workspaces(recipe_id,owner_id,document)
    values(p_recipe_id,uid,p_document) on conflict (recipe_id) do nothing;
  select * into current_row from public.chef_workspaces where recipe_id = p_recipe_id for update;
  if current_row.owner_id <> uid then raise exception 'CHEF_RECIPE_NOT_OWNED'; end if;
  if current_row.revision <> p_expected_revision then raise exception 'CHEF_REVISION_CONFLICT'; end if;
  if p_version_label is not null then
    insert into public.chef_recipe_versions(recipe_id,owner_id,version_number,label,note,document)
      values(p_recipe_id,uid,current_row.next_version,trim(p_version_label),p_version_note,p_document);
  end if;
  update public.chef_workspaces set document = p_document, revision = revision + 1,
    next_version = next_version + case when p_version_label is not null then 1 else 0 end,
    updated_at = now() where recipe_id = p_recipe_id;
  return current_row.revision + 1;
end;
$$;
revoke all on function public.save_chef_workspace(uuid,jsonb,bigint,text,text) from public,anon;
grant execute on function public.save_chef_workspace(uuid,jsonb,bigint,text,text) to authenticated;
