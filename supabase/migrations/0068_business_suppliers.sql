-- Workspace-owned trading partners and pack specifications. No external orders.
begin;
create table public.business_suppliers (
 id uuid primary key, workspace_id uuid not null references public.business_workspaces on delete cascade,
 data jsonb not null, revision bigint not null default 1, updated_at timestamptz not null default now(),
 updated_by uuid references auth.users on delete set null, unique(workspace_id,id)
);
create table public.business_supplier_products (
 id uuid primary key, workspace_id uuid not null, supplier_id uuid not null,
 data jsonb not null, revision bigint not null default 1, updated_at timestamptz not null default now(),
 updated_by uuid references auth.users on delete set null,
 foreign key(workspace_id,supplier_id) references public.business_suppliers(workspace_id,id) on delete cascade
);
create index business_supplier_workspace on public.business_suppliers(workspace_id);
create index business_supplier_product_workspace on public.business_supplier_products(workspace_id,supplier_id);
create table public.business_purchase_supplier_snapshots (
 request_id uuid primary key references public.business_records on delete cascade,
 workspace_id uuid not null references public.business_workspaces on delete cascade,
 supplier jsonb not null, products jsonb not null, input_hash text not null,
 actor_id uuid references auth.users on delete set null, created_at timestamptz not null default now()
);
alter table public.business_suppliers enable row level security;
alter table public.business_supplier_products enable row level security;
alter table public.business_purchase_supplier_snapshots enable row level security;
revoke all on public.business_suppliers,public.business_supplier_products,public.business_purchase_supplier_snapshots from public,anon,authenticated;
grant select on public.business_suppliers,public.business_supplier_products,public.business_purchase_supplier_snapshots to authenticated;
grant all on public.business_suppliers,public.business_supplier_products,public.business_purchase_supplier_snapshots to service_role;
create policy business_supplier_read on public.business_suppliers for select to authenticated using(public.business_can(workspace_id,'purchasing.read'));
create policy business_supplier_product_read on public.business_supplier_products for select to authenticated using(public.business_can(workspace_id,'purchasing.read'));
create policy business_purchase_supplier_read on public.business_purchase_supplier_snapshots for select to authenticated using(public.business_can(workspace_id,'purchasing.read'));

create function public.business_supplier_data_valid(d jsonb,product boolean) returns boolean language plpgsql immutable set search_path='' as $$
declare k text; lim integer;
begin
 if jsonb_typeof(d) is distinct from 'object' or jsonb_typeof(d->'active') is distinct from 'boolean' then return false;end if;
 if product then
  if exists(select 1 from jsonb_object_keys(d) x where x not in ('name','spec','content_quantity','content_unit','pack_unit','active'))
   or not public.business_menu_number_valid(d->'content_quantity',0.000001,1e9) then return false;end if;
 else
  if exists(select 1 from jsonb_object_keys(d) x where x not in ('name','contact','phone','address','website','active')) then return false;end if;
 end if;
 foreach k in array case when product then array['name','spec','content_unit','pack_unit'] else array['name','contact','phone','address','website'] end loop
  lim:=case k when 'name' then 120 when 'spec' then 120 when 'contact' then 120 when 'phone' then 80 when 'address' then 300 when 'website' then 500 else 30 end;
  if jsonb_typeof(d->k) is distinct from 'string' or length(d->>k)>lim or (d->>k)~'[[:cntrl:]]' then return false;end if;
  if k in ('name','content_unit','pack_unit') and length(btrim(d->>k))=0 then return false;end if;
 end loop;
 if not product and d->>'website'<>'' and d->>'website' !~ '^https?://[^[:space:]]+$' then return false;end if;
 return true;
end;$$;
revoke all on function public.business_supplier_data_valid(jsonb,boolean) from public,anon,authenticated;

create function public.business_supplier_save(p_workspace uuid,p_id uuid,p_revision bigint,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.business_suppliers;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_revision is null or not public.business_supplier_data_valid(p_data,false) then raise exception 'BUSINESS_INVALID';end if;
 select * into r from public.business_suppliers where id=p_id;
 if r.id is null then
  if p_revision<>0 then raise exception 'BUSINESS_STALE';end if;
  if (select count(*) from public.business_suppliers where workspace_id=p_workspace)>=300 then raise exception 'BUSINESS_LIMIT';end if;
  insert into public.business_suppliers(id,workspace_id,data,updated_by) values(p_id,p_workspace,p_data,auth.uid()) returning * into r;
 else
  if r.workspace_id<>p_workspace or r.revision<>p_revision then raise exception 'BUSINESS_STALE';end if;
  update public.business_suppliers set data=p_data,revision=revision+1,updated_at=now(),updated_by=auth.uid() where id=p_id returning * into r;
 end if;
 return to_jsonb(r);
end;$$;
create function public.business_supplier_product_save(p_workspace uuid,p_supplier uuid,p_id uuid,p_revision bigint,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.business_supplier_products;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_revision is null or not public.business_supplier_data_valid(p_data,true) then raise exception 'BUSINESS_INVALID';end if;
 if not exists(select 1 from public.business_suppliers where id=p_supplier and workspace_id=p_workspace and data->'active'='true') then raise exception 'SUPPLIER_UNAVAILABLE';end if;
 select * into r from public.business_supplier_products where id=p_id;
 if r.id is null then
  if p_revision<>0 then raise exception 'BUSINESS_STALE';end if;
  if (select count(*) from public.business_supplier_products where workspace_id=p_workspace)>=1000 then raise exception 'BUSINESS_LIMIT';end if;
  insert into public.business_supplier_products(id,workspace_id,supplier_id,data,updated_by) values(p_id,p_workspace,p_supplier,p_data,auth.uid()) returning * into r;
 else
  if r.workspace_id<>p_workspace or r.supplier_id<>p_supplier or r.revision<>p_revision then raise exception 'BUSINESS_STALE';end if;
  update public.business_supplier_products set data=p_data,revision=revision+1,updated_at=now(),updated_by=auth.uid() where id=p_id returning * into r;
 end if;
 return to_jsonb(r);
end;$$;

-- An additive RPC keeps the existing manual purchase API compatible.
create function public.business_supplier_purchase(p_workspace uuid,p_request uuid,p_purpose text,p_sources jsonb,p_adjustments jsonb,p_supplier uuid,p_supplier_revision bigint,p_products jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.business_suppliers; p public.business_supplier_products; prior public.business_purchase_supplier_snapshots;
 fingerprint text; plan jsonb; m jsonb; req jsonb; a jsonb; snaps jsonb:='[]'; result jsonb; d jsonb; lines jsonb:='[]'; line jsonb; idx integer:=0;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') or not public.business_can(p_workspace,'recipes.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_request is null or p_supplier is null or p_supplier_revision is null or jsonb_typeof(p_products) is distinct from 'array' or jsonb_typeof(p_adjustments) is distinct from 'array' then raise exception 'BUSINESS_INVALID';end if;
 if jsonb_array_length(p_products)>100 or jsonb_array_length(p_adjustments)>100 then raise exception 'BUSINESS_INVALID';end if;
 fingerprint:=encode(extensions.digest(jsonb_build_array(p_purpose,p_sources,p_adjustments,p_supplier,p_supplier_revision,p_products)::text,'sha256'),'hex');
 select * into prior from public.business_purchase_supplier_snapshots where request_id=p_request;
 if prior.request_id is not null then
  if prior.workspace_id<>p_workspace or prior.actor_id is distinct from auth.uid() or prior.input_hash<>fingerprint then raise exception 'BUSINESS_STALE';end if;
  return (select to_jsonb(r) from public.business_records r where id=p_request);
 end if;
 if exists(select 1 from public.business_records where id=p_request) then raise exception 'BUSINESS_STALE';end if;
 select * into s from public.business_suppliers where id=p_supplier and workspace_id=p_workspace;
 if s.id is null or s.data->'active'<>'true' then raise exception 'SUPPLIER_UNAVAILABLE';end if;
 if s.revision<>p_supplier_revision then raise exception 'BUSINESS_STALE';end if;
 plan:=public.business_menu_plan(p_workspace,p_purpose,p_sources);
 if (select count(distinct x->>'key') from jsonb_array_elements(p_products) x)<>jsonb_array_length(p_products) then raise exception 'BUSINESS_INVALID';end if;
 for m in select value from jsonb_array_elements(p_products) loop
  if jsonb_typeof(m) is distinct from 'object' or exists(select 1 from jsonb_object_keys(m) x where x not in ('key','id','revision'))
   or not public.chef_number_valid(m->'revision',1,1e12,false) or (m->>'revision')::numeric<>trunc((m->>'revision')::numeric) then raise exception 'BUSINESS_INVALID';end if;
  select value into req from jsonb_array_elements(plan->'requirements') where value->>'key'=m->>'key';
  select value into a from jsonb_array_elements(p_adjustments) where value->>'key'=m->>'key';
  select * into p from public.business_supplier_products where id=(m->>'id')::uuid and workspace_id=p_workspace and supplier_id=p_supplier;
  if p.id is null or p.data->'active'<>'true' then raise exception 'SUPPLIER_UNAVAILABLE';end if;
  if p.revision is distinct from (m->>'revision')::bigint then raise exception 'BUSINESS_STALE';end if;
  if req is null or a is null or a->'include' is distinct from 'true' or lower(btrim(req->>'unit'))<>lower(btrim(p.data->>'content_unit')) then raise exception 'SUPPLIER_UNIT';end if;
  if (a->>'pack_size')::numeric is distinct from (p.data->>'content_quantity')::numeric or btrim(a->>'pack_unit') is distinct from btrim(p.data->>'pack_unit') then raise exception 'SUPPLIER_PACK';end if;
  snaps:=snaps||jsonb_build_array(jsonb_build_object('key',m->>'key','id',p.id,'revision',p.revision,'data',p.data));
 end loop;
 result:=public.business_menu_purchase(p_workspace,p_request,p_purpose,p_sources,p_adjustments,btrim(s.data->>'name'));
 d:=result->'data';
 -- Preserve requirement order and line IDs. Prices remain unconfirmed on purpose.
 for req in select value from jsonb_array_elements(plan->'requirements') loop
  select value into a from jsonb_array_elements(p_adjustments) where value->>'key'=req->>'key';
  if a->'include'='true' and greatest(0,(req->>'required')::numeric-(a->>'stock')::numeric-(a->>'incoming')::numeric)>0 then
   line:=d->'lines'->idx;idx:=idx+1;
   select value into m from jsonb_array_elements(snaps) where value->>'key'=req->>'key';
   if m is not null then
    line:=line||jsonb_build_object('name',m->'data'->>'name','spec',left(concat_ws(' / ',req->>'name',req->>'spec',m->'data'->>'spec',(m->'data'->>'content_quantity')||' '||(req->>'unit')||' / '||(m->'data'->>'pack_unit')),300));
   end if;
   lines:=lines||jsonb_build_array(line);
  end if;
 end loop;
 if jsonb_array_length(snaps)>0 then
  result:=public.business_save_record(p_workspace,p_request,'purchase',result->>'title',d||jsonb_build_object('lines',lines),(result->>'revision')::bigint);
 end if;
 insert into public.business_purchase_supplier_snapshots(request_id,workspace_id,supplier,products,input_hash,actor_id)
 values(p_request,p_workspace,jsonb_build_object('id',s.id,'revision',s.revision,'data',s.data),snaps,fingerprint,auth.uid());
 return result;
end;$$;
revoke all on function public.business_supplier_save(uuid,uuid,bigint,jsonb),public.business_supplier_product_save(uuid,uuid,uuid,bigint,jsonb),public.business_supplier_purchase(uuid,uuid,text,jsonb,jsonb,uuid,bigint,jsonb) from public,anon;
grant execute on function public.business_supplier_save(uuid,uuid,bigint,jsonb),public.business_supplier_product_save(uuid,uuid,uuid,bigint,jsonb),public.business_supplier_purchase(uuid,uuid,text,jsonb,jsonb,uuid,bigint,jsonb) to authenticated;
commit;
