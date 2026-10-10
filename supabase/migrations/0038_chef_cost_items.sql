-- Keep v55 documents readable while adding named additional costs.
alter function public.chef_document_valid(jsonb) rename to chef_document_v1_valid;

create function public.chef_document_valid(d jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare item jsonb; ids text[] := '{}'; total numeric;
begin
  if d->>'schema' = '1' then
    return not (d ? 'costItems') and not (d ? 'legacyExtraCost')
      and public.chef_document_v1_valid(d);
  end if;
  if (d->>'schema') is distinct from '2' or
     not public.chef_document_v1_valid(jsonb_set(d,'{schema}','1')) or
     jsonb_typeof(d->'costItems') is distinct from 'array' or
     not public.chef_number_valid(d->'legacyExtraCost',0,1000000000000,false) or
     not public.chef_number_valid(d->'markupPercent',0,100,true) then
    return false;
  end if;
  if jsonb_array_length(d->'costItems') > 100 then return false; end if;
  total := (d->>'legacyExtraCost')::numeric;
  for item in select value from jsonb_array_elements(d->'costItems') loop
    if jsonb_typeof(item) <> 'object' or
       jsonb_typeof(item->'id') is distinct from 'string' or
       length(item->>'id') not between 1 and 80 or (item->>'id') = any(ids) or
       jsonb_typeof(item->'name') is distinct from 'string' or
       length(trim(item->>'name')) not between 1 and 80 or
       not public.chef_number_valid(item->'amount',0,1000000000000,false) then
      return false;
    end if;
    ids := array_append(ids,item->>'id');
    total := total + (item->>'amount')::numeric;
  end loop;
  -- Permit serialization noise only; cap relative tolerance at 1e-12.
  return total <= 1000000000000 and
    abs(total - (d->>'extraCost')::numeric) <= greatest(0.000001,abs(total)*0.000000000001);
end;
$$;
revoke all on function public.chef_document_valid(jsonb) from public;
create or replace function public.save_chef_workspace(
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
  if current_row.document->>'schema' = '2' and p_document->>'schema' <> '2' then
    raise exception 'CHEF_UPGRADE_REQUIRED';
  end if;
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

