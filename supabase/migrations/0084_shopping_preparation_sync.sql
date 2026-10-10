-- Personal preparation drafts only: never create purchases or alter inventory.
begin;
create table public.shopping_preparation_drafts (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  document jsonb not null check (jsonb_typeof(document) = 'object' and octet_length(document::text) <= 524288),
  updated_at timestamptz not null default now()
);
alter table public.shopping_preparation_drafts enable row level security;
revoke all on public.shopping_preparation_drafts from public, anon, authenticated;
grant select on public.shopping_preparation_drafts to authenticated;
create policy own_preparation on public.shopping_preparation_drafts for select to authenticated
  using (owner_id = auth.uid() and coalesce((auth.jwt()->>'is_anonymous')::boolean,false) = false);

create function public.save_shopping_preparation(p_revision bigint, p_document jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); saved public.shopping_preparation_drafts;
begin
  if uid is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
    raise exception 'PREPARATION_DENIED' using errcode = '42501';
  end if;
  if p_revision is null or p_revision < 0 or jsonb_typeof(p_document) is distinct from 'object'
    or octet_length(p_document::text) > 524288
    or jsonb_typeof(p_document->'fingerprint') is distinct from 'string'
    or jsonb_typeof(p_document->'selected') is distinct from 'array'
    or jsonb_typeof(p_document->'edits') is distinct from 'object'
    or jsonb_typeof(p_document->'confirmed') is distinct from 'boolean' then
    raise exception 'PREPARATION_INVALID' using errcode = '22023';
  end if;
  if p_revision = 0 then
    insert into public.shopping_preparation_drafts(owner_id,document)
      values(uid,p_document) on conflict do nothing returning * into saved;
  else
    update public.shopping_preparation_drafts set document=p_document,revision=revision+1,updated_at=now()
      where owner_id=uid and revision=p_revision returning * into saved;
  end if;
  if saved.owner_id is null then raise exception 'PREPARATION_CONFLICT' using errcode='40001'; end if;
  return jsonb_build_object('revision',saved.revision,'document',saved.document,'updated_at',saved.updated_at);
end;$$;
revoke all on function public.save_shopping_preparation(bigint,jsonb) from public,anon;
grant execute on function public.save_shopping_preparation(bigint,jsonb) to authenticated;
commit;
