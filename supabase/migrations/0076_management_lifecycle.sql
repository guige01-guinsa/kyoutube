-- Additive management controls. Historical trades are never deleted by a UI cleanup.
begin;

create table public.deleted_purchase_drafts (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 revision bigint not null, deleted_at timestamptz not null default now()
);
alter table public.deleted_purchase_drafts enable row level security;
revoke all on public.deleted_purchase_drafts from public,anon,authenticated;

create function public.reject_deleted_purchase_draft() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('supplier-request:'||new.id::text,0));
 if exists(select 1 from public.deleted_purchase_drafts where id=new.id) then raise exception 'MANAGEMENT_DELETED'; end if;
 return new;
end; $$;
revoke all on function public.reject_deleted_purchase_draft() from public,anon,authenticated;
create trigger reject_deleted_purchase_draft before insert on public.supplier_purchase_requests
 for each row execute function public.reject_deleted_purchase_draft();

-- Old clients must fail safely rather than deleting a sent or completed document.
revoke delete on public.supplier_purchase_requests from authenticated;
-- Directories use reversible archive too; historical suppliers keep their identity.
revoke delete on public.shopping_suppliers from authenticated;
create function public.delete_unused_purchase_draft(p_id uuid,p_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); r public.supplier_purchase_requests; tomb public.deleted_purchase_drafts;
begin
 if u is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'MANAGEMENT_DENIED'; end if;
 if p_id is null or p_revision is null then raise exception 'MANAGEMENT_INVALID'; end if;
 -- Same lock and order as save_supplier_purchase_request, before the row lock.
 perform pg_advisory_xact_lock(hashtextextended('supplier-request:'||p_id::text,0));
 select * into tomb from public.deleted_purchase_drafts where id=p_id;
 if tomb.id is not null then
  if tomb.owner_id=u and tomb.revision=p_revision then return null; end if;
  raise exception 'MANAGEMENT_STALE';
 end if;
 select * into r from public.supplier_purchase_requests where id=p_id and owner_id=u for update;
 if r.id is null or r.revision<>p_revision then raise exception 'MANAGEMENT_STALE'; end if;
 if r.status<>'draft' or exists(select 1 from public.supplier_request_events where request_id=p_id
   and (to_status<>'draft' or (from_status is not null and from_status<>'draft')))
   or exists(select 1 from public.supplier_buyer_reviews where request_id=p_id) then raise exception 'MANAGEMENT_USED'; end if;
 insert into public.deleted_purchase_drafts(id,owner_id,revision) values(r.id,u,r.revision);
 delete from public.supplier_purchase_requests where id=r.id;
 return to_jsonb(r);
end; $$;
revoke all on function public.delete_unused_purchase_draft(uuid,bigint) from public,anon;
grant execute on function public.delete_unused_purchase_draft(uuid,bigint) to authenticated;

alter table public.business_menu_templates add column archived boolean not null default false;
create table public.business_management_events (
 id bigint generated always as identity primary key,
 workspace_id uuid not null references public.business_workspaces(id) on delete cascade,
 kind text not null check(kind in ('supplier','product','template','stock')),
 record_id uuid not null, action text not null, revision bigint not null,
 actor_id uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
alter table public.business_management_events enable row level security;
revoke all on public.business_management_events from public,anon,authenticated;
grant select on public.business_management_events to authenticated;
create policy business_management_read on public.business_management_events for select to authenticated
 using(public.business_can(workspace_id,'purchasing.read'));

create function public.audit_business_catalog_management() returns trigger
language plpgsql security definer set search_path='' as $$
declare kind text; action text;
begin
 -- Cascading account/workspace erasure can null updated_by while its parent is gone.
 if not exists(select 1 from public.business_workspaces where id=new.workspace_id) then return new; end if;
 kind:=case tg_table_name when 'business_suppliers' then 'supplier' when 'business_supplier_products' then 'product' else 'template' end;
 action:=case when tg_op='INSERT' then 'created' else 'edited' end;
 if tg_op='UPDATE' then
  if kind='template' then
   if new.archived is distinct from old.archived then
    action:=case when new.archived then 'archived' else 'restored' end;
   end if;
  elsif kind in ('supplier','product') then
   if new.data->'active' is distinct from old.data->'active' then
    action:=case when new.data->>'active'='true' then 'reactivated' else 'deactivated' end;
   end if;
  end if;
 end if;
 insert into public.business_management_events(workspace_id,kind,record_id,action,revision,actor_id)
 values(new.workspace_id,kind,new.id,action,new.revision,(select id from auth.users where id=auth.uid()));
 return new;
end; $$;
revoke all on function public.audit_business_catalog_management() from public,anon,authenticated;
create trigger business_supplier_management_audit after insert or update on public.business_suppliers
 for each row execute function public.audit_business_catalog_management();
create trigger business_product_management_audit after insert or update on public.business_supplier_products
 for each row execute function public.audit_business_catalog_management();
create trigger business_template_management_audit after insert or update on public.business_menu_templates
 for each row execute function public.audit_business_catalog_management();

create function public.business_menu_template_manage(p_workspace uuid,p_id uuid,p_revision bigint,p_action text,p_name text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.business_menu_templates;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') or not public.business_can(p_workspace,'recipes.read') then raise exception 'BUSINESS_DENIED'; end if;
 select * into r from public.business_menu_templates where id=p_id and workspace_id=p_workspace for update;
 if r.id is null or p_revision is null or r.revision<>p_revision then raise exception 'BUSINESS_STALE'; end if;
 if p_action is null or p_action not in ('rename','archive','restore') then raise exception 'BUSINESS_INVALID'; end if;
 if p_action='rename' and (p_name is null or length(btrim(p_name)) not between 1 and 80 or p_name~'[[:cntrl:]]') then raise exception 'BUSINESS_INVALID'; end if;
 if (p_action='archive' and r.archived) or (p_action='restore' and not r.archived) then return to_jsonb(r); end if;
 -- Restoring a saved plan is not buying it; source revisions are rechecked when it is loaded/purchased.
 update public.business_menu_templates set name=case when p_action='rename' then btrim(p_name) else name end,
  archived=case when p_action='archive' then true when p_action='restore' then false else archived end,
  revision=revision+1,updated_at=now(),updated_by=auth.uid() where id=r.id returning * into r;
 return to_jsonb(r);
end; $$;
revoke all on function public.business_menu_template_manage(uuid,uuid,bigint,text,text) from public,anon;
grant execute on function public.business_menu_template_manage(uuid,uuid,bigint,text,text) to authenticated;

-- Metadata is independent of immutable stock identity and physical movements.
alter table public.business_stock_items add column management_note text not null default '' check(length(management_note)<=500);
alter table public.business_stock_items add column management_revision bigint not null default 1;
create function public.business_stock_note(p_workspace uuid,p_id uuid,p_revision bigint,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare r public.business_stock_items;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') then raise exception 'BUSINESS_DENIED'; end if;
 if p_note is null or length(p_note)>500 then raise exception 'BUSINESS_INVALID'; end if;
 select * into r from public.business_stock_items where id=p_id and workspace_id=p_workspace for update;
 if r.id is null or p_revision is null or r.management_revision<>p_revision then raise exception 'BUSINESS_STALE'; end if;
 if r.management_note=btrim(p_note) then return; end if;
 update public.business_stock_items set management_note=btrim(p_note),management_revision=management_revision+1 where id=r.id;
 insert into public.business_management_events(workspace_id,kind,record_id,action,revision,actor_id)
 values(p_workspace,'stock',r.id,'note',r.management_revision+1,auth.uid());
end; $$;
revoke all on function public.business_stock_note(uuid,uuid,bigint,text) from public,anon;
grant execute on function public.business_stock_note(uuid,uuid,bigint,text) to authenticated;
notify pgrst,'reload schema';
commit;
