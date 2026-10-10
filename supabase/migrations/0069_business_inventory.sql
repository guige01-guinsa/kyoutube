-- Explicit receipts, returns, stock movements and cooking reservations.
-- Historical receipt flags are deliberately not converted into stock.
begin;
create table public.business_stock_items (
 id uuid primary key, workspace_id uuid not null references public.business_workspaces on delete cascade,
 name text not null, spec text not null, unit text not null, created_at timestamptz not null default now(),
 unique(workspace_id,id)
);
create unique index business_stock_identity on public.business_stock_items(workspace_id,lower(btrim(name)),lower(btrim(spec)),lower(btrim(unit)));
create table public.business_stock_reservations (
 id uuid primary key, workspace_id uuid not null, item_id uuid not null,
 purpose text not null, quantity numeric not null, remaining numeric not null, revision bigint not null default 1,
 actor_id uuid references auth.users on delete set null, created_at timestamptz not null default now(),
 foreign key(workspace_id,item_id) references public.business_stock_items(workspace_id,id) on delete cascade,
 check(quantity>0 and remaining>=0 and remaining<=quantity)
);
create table public.business_stock_events (
 id uuid primary key, workspace_id uuid not null, item_id uuid not null,
 kind text not null check(kind in ('adjust','reserve','release','consume','receive','return')),
 delta numeric not null, reserved_delta numeric not null default 0, reason text not null,
 request_id uuid references public.business_records on delete set null, line_id uuid,
 receipt_id uuid references public.business_stock_events, reservation_id uuid references public.business_stock_reservations on delete cascade,
 purchase_quantity numeric, factor numeric, snapshot jsonb not null default '{}',
 actor_id uuid references auth.users on delete set null, created_at timestamptz not null default now(),
 foreign key(workspace_id,item_id) references public.business_stock_items(workspace_id,id) on delete cascade
);
create index business_stock_events_item on public.business_stock_events(workspace_id,item_id,created_at desc,id);
create index business_stock_events_request on public.business_stock_events(workspace_id,request_id,line_id);
create index business_stock_events_receipt on public.business_stock_events(receipt_id) where receipt_id is not null;
create index business_stock_reservations_open on public.business_stock_reservations(workspace_id,item_id) where remaining>0;
create table public.business_receiving_closures (
 request_id uuid primary key references public.business_records on delete cascade,
 workspace_id uuid not null references public.business_workspaces on delete cascade,
 reason text not null, shortage boolean not null, snapshot jsonb not null,
 actor_id uuid references auth.users on delete set null, created_at timestamptz not null default now()
);
create table public.business_stock_actions (
 id uuid primary key, workspace_id uuid not null references public.business_workspaces on delete cascade,
 actor_id uuid references auth.users on delete set null, fingerprint text not null, result jsonb not null,
 created_at timestamptz not null default now()
);
alter table public.business_stock_items enable row level security;
alter table public.business_stock_reservations enable row level security;
alter table public.business_stock_events enable row level security;
alter table public.business_receiving_closures enable row level security;
alter table public.business_stock_actions enable row level security;
revoke all on public.business_stock_items,public.business_stock_reservations,public.business_stock_events,public.business_receiving_closures,public.business_stock_actions from public,anon,authenticated;
grant select on public.business_stock_items,public.business_stock_reservations,public.business_stock_events,public.business_receiving_closures to authenticated;
grant all on public.business_stock_items,public.business_stock_reservations,public.business_stock_events,public.business_receiving_closures,public.business_stock_actions to service_role;
create policy business_stock_item_read on public.business_stock_items for select to authenticated using(public.business_can(workspace_id,'purchasing.read'));
create policy business_stock_reservation_read on public.business_stock_reservations for select to authenticated using(public.business_can(workspace_id,'purchasing.read'));
create policy business_stock_event_read on public.business_stock_events for select to authenticated using(public.business_can(workspace_id,'purchasing.read'));
create policy business_receiving_closure_read on public.business_receiving_closures for select to authenticated using(public.business_can(workspace_id,'purchasing.read'));

create function public.business_stock_balance(p_workspace uuid,p_item uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('on_hand',b.n,'reserved',r.n,'available',b.n-r.n) from
 (select coalesce(sum(delta),0) n from public.business_stock_events where workspace_id=p_workspace and item_id=p_item) b,
 (select coalesce(sum(remaining),0) n from public.business_stock_reservations where workspace_id=p_workspace and item_id=p_item) r;
$$;
revoke all on function public.business_stock_balance(uuid,uuid) from public,anon,authenticated;
create function public.business_stock_overview(p_workspace uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 return coalesce((select jsonb_agg(to_jsonb(i)||public.business_stock_balance(p_workspace,i.id) order by i.name,i.spec,i.unit,i.id) from public.business_stock_items i where workspace_id=p_workspace),'[]');
end;$$;
create function public.business_receiving_overview(p_workspace uuid,p_request uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.business_records; l jsonb; received numeric; returned numeric; lines jsonb:='[]'; closure jsonb; mapping public.business_stock_events;
begin
 if not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 select * into r from public.business_records where id=p_request and workspace_id=p_workspace and kind='purchase';
 if r.id is null then raise exception 'BUSINESS_NOT_FOUND';end if;
 for l in select value from jsonb_array_elements(r.data->'lines') loop
  select coalesce(sum(purchase_quantity) filter(where kind='receive'),0),coalesce(sum(purchase_quantity) filter(where kind='return'),0)
  into received,returned from public.business_stock_events where workspace_id=p_workspace and request_id=p_request and line_id=(l->>'id')::uuid;
  select * into mapping from public.business_stock_events where workspace_id=p_workspace and request_id=p_request and line_id=(l->>'id')::uuid and kind='receive' order by created_at,id limit 1;
  lines:=lines||jsonb_build_array(l||jsonb_build_object('mapped_item',mapping.item_id,'mapped_factor',mapping.factor,'received',received,'returned',returned,'net',received-returned,'outstanding',greatest(0,coalesce((l->>'quantity')::numeric,0)-received+returned)));
 end loop;
 select to_jsonb(c)-'actor_id' into closure from public.business_receiving_closures c where request_id=p_request and workspace_id=p_workspace;
 return jsonb_build_object('request_id',r.id,'title',r.title,'revision',r.revision,'status',r.status,'lines',lines,'closure',closure,
  'legacy',r.status='received' and closure is null);
end;$$;

-- Retain approval/sharing/cancellation behavior, but require reviewed line receipts for closing.
alter function public.business_purchase_transition(uuid,uuid,bigint,text) rename to business_purchase_transition_before_inventory;
revoke all on function public.business_purchase_transition_before_inventory(uuid,uuid,bigint,text) from public,anon,authenticated;
create function public.business_purchase_transition(p_workspace uuid,p_id uuid,p_revision bigint,p_status text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_status='received' then raise exception 'INVENTORY_RECEIPT_REQUIRED';end if;
 return public.business_purchase_transition_before_inventory(p_workspace,p_id,p_revision,p_status);
end;$$;

create function public.business_stock_action(p_workspace uuid,p_id uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare keys text[]; k text; prior public.business_stock_actions; fingerprint text; result jsonb;
 item public.business_stock_items; reservation public.business_stock_reservations; receipt public.business_stock_events;
 r public.business_records; line jsonb; prior_line public.business_stock_events; balance jsonb;
 v_quantity numeric; v_factor numeric; v_delta numeric:=0; v_reserved_delta numeric:=0; event_kind text; reason text;
 v_request_id uuid; v_line_id uuid; v_receipt_id uuid; v_reservation_id uuid; snapshot jsonb:='{}'; received numeric; returned numeric; overview jsonb; shortage boolean;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_action in ('reserve','release','consume') then
  if not (public.business_can(p_workspace,'recipes.write') or public.business_can(p_workspace,'purchasing.write')) then raise exception 'BUSINESS_DENIED';end if;
 elsif not public.business_can(p_workspace,'purchasing.write') then raise exception 'BUSINESS_DENIED';end if;
 keys:=case p_action when 'item' then array['name','spec','unit'] when 'adjust' then array['item','quantity','reason']
  when 'reserve' then array['item','quantity','reason'] when 'release' then array['reservation','revision','reason']
  when 'consume' then array['reservation','revision','quantity','reason']
  when 'receive' then array['request','revision','line','item','quantity','factor','confirmed','reason']
  when 'return' then array['receipt','quantity','reason'] when 'close' then array['request','revision','shortage_accepted','reason'] else null end;
 if keys is null or p_id is null or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>8192
  or exists(select 1 from jsonb_object_keys(p_data) x where not x=any(keys)) then raise exception 'BUSINESS_INVALID';end if;
 fingerprint:=encode(extensions.digest(jsonb_build_array(p_action,p_data)::text,'sha256'),'hex');
 select * into prior from public.business_stock_actions where id=p_id;
 if prior.id is not null then
  if prior.workspace_id<>p_workspace or prior.actor_id is distinct from auth.uid() or prior.fingerprint<>fingerprint then raise exception 'BUSINESS_STALE';end if;
  return prior.result;
 end if;
 if p_action='item' then
  foreach k in array keys loop
   if jsonb_typeof(p_data->k) is distinct from 'string' or length(p_data->>k)>(case k when 'unit' then 30 else 120 end) or (p_data->>k)~'[[:cntrl:]]' then raise exception 'BUSINESS_INVALID';end if;
  end loop;
  if length(btrim(p_data->>'name'))=0 or length(btrim(p_data->>'unit'))=0 then raise exception 'BUSINESS_INVALID';end if;
  select * into item from public.business_stock_items where workspace_id=p_workspace and lower(btrim(name))=lower(btrim(p_data->>'name')) and lower(btrim(spec))=lower(btrim(p_data->>'spec')) and lower(btrim(unit))=lower(btrim(p_data->>'unit'));
  if item.id is null then
   if (select count(*) from public.business_stock_items where workspace_id=p_workspace)>=1000 then raise exception 'BUSINESS_LIMIT';end if;
   insert into public.business_stock_items(id,workspace_id,name,spec,unit) values(p_id,p_workspace,btrim(p_data->>'name'),btrim(p_data->>'spec'),btrim(p_data->>'unit')) returning * into item;
  end if;
  result:=to_jsonb(item);
 else
  reason:=btrim(p_data->>'reason');
  if jsonb_typeof(p_data->'reason') is distinct from 'string' or length(reason) not between 1 and 500 then raise exception 'INVENTORY_REASON';end if;
  if p_action in ('receive','close','consume','release') and (not public.chef_number_valid(p_data->'revision',1,1e12,false) or (p_data->>'revision')::numeric<>trunc((p_data->>'revision')::numeric)) then raise exception 'BUSINESS_INVALID';end if;
  if p_action in ('receive','close') then
   select * into r from public.business_records where id=(p_data->>'request')::uuid and workspace_id=p_workspace and kind='purchase';
   if r.id is null or r.status<>'sent' then raise exception 'INVENTORY_PURCHASE_STATE';end if;
   if r.revision is distinct from (p_data->>'revision')::bigint then raise exception 'BUSINESS_STALE';end if;
   v_request_id:=r.id;
  end if;
  if p_action='close' then
   overview:=public.business_receiving_overview(p_workspace,r.id);
   shortage:=exists(select 1 from jsonb_array_elements(overview->'lines') l where (l->>'outstanding')::numeric>0);
   if shortage and p_data->'shortage_accepted' is distinct from 'true'::jsonb then raise exception 'INVENTORY_SHORTAGE';end if;
   result:=public.business_purchase_transition_before_inventory(p_workspace,r.id,r.revision,'received');
   insert into public.business_receiving_closures(request_id,workspace_id,reason,shortage,snapshot,actor_id) values(r.id,p_workspace,reason,shortage,overview,auth.uid());
  else
   if p_action<>'release' and (not public.business_menu_number_valid(p_data->'quantity',case when p_action='adjust' then -1e9 else 0.000001 end,1e9) or (p_data->>'quantity')::numeric=0) then raise exception 'BUSINESS_INVALID';end if;
   v_quantity:=(p_data->>'quantity')::numeric;
   event_kind:=p_action;
   if p_action in ('release','consume') then
    select * into reservation from public.business_stock_reservations where id=(p_data->>'reservation')::uuid and workspace_id=p_workspace;
    if reservation.id is null then raise exception 'BUSINESS_NOT_FOUND';end if;
    if reservation.revision is distinct from (p_data->>'revision')::bigint then raise exception 'BUSINESS_STALE';end if;
    if reservation.remaining<=0 then raise exception 'INVENTORY_RESERVATION';end if;
    select * into item from public.business_stock_items where id=reservation.item_id and workspace_id=p_workspace;
    v_reservation_id:=reservation.id;
    if p_action='release' then v_quantity:=reservation.remaining;end if;
    if v_quantity>reservation.remaining then raise exception 'INVENTORY_RESERVATION';end if;
    v_reserved_delta:=-v_quantity;
    if p_action='consume' then v_delta:=-v_quantity;end if;
    snapshot:=jsonb_build_object('reservation_purpose',reservation.purpose);
   elsif p_action='return' then
    select * into receipt from public.business_stock_events where id=(p_data->>'receipt')::uuid and workspace_id=p_workspace and kind='receive';
    if receipt.id is null then raise exception 'BUSINESS_NOT_FOUND';end if;
    select coalesce(sum(purchase_quantity),0) into returned from public.business_stock_events where business_stock_events.receipt_id=receipt.id and kind='return';
    if v_quantity>receipt.purchase_quantity-returned then raise exception 'INVENTORY_RETURN';end if;
    select * into item from public.business_stock_items where id=receipt.item_id and workspace_id=p_workspace;
    v_receipt_id:=receipt.id;v_request_id:=receipt.request_id;v_line_id:=receipt.line_id;v_factor:=receipt.factor;
    v_delta:=-v_quantity*v_factor;snapshot:=receipt.snapshot;
   else
    select * into item from public.business_stock_items where id=(p_data->>'item')::uuid and workspace_id=p_workspace;
    if item.id is null then raise exception 'BUSINESS_NOT_FOUND';end if;
    if p_action='receive' then
     if p_data->'confirmed' is distinct from 'true'::jsonb or not public.business_menu_number_valid(p_data->'factor',0.000001,1e9) then raise exception 'INVENTORY_CONVERSION';end if;
     select value into line from jsonb_array_elements(r.data->'lines') where value->>'id'=p_data->>'line';
     if line is null then raise exception 'BUSINESS_NOT_FOUND';end if;
     v_line_id:=(line->>'id')::uuid;v_factor:=(p_data->>'factor')::numeric;
     select coalesce(sum(case when kind='receive' then purchase_quantity when kind='return' then -purchase_quantity else 0 end),0) into received from public.business_stock_events where workspace_id=p_workspace and request_id=r.id and business_stock_events.line_id=v_line_id;
     if v_quantity+received>(line->>'quantity')::numeric then raise exception 'INVENTORY_OVER_RECEIPT';end if;
     select * into prior_line from public.business_stock_events where workspace_id=p_workspace and request_id=r.id and business_stock_events.line_id=v_line_id and kind='receive' order by created_at,id limit 1;
     if prior_line.id is not null and (prior_line.item_id<>item.id or prior_line.factor<>v_factor) then raise exception 'INVENTORY_CONVERSION';end if;
     v_delta:=v_quantity*v_factor;snapshot:=jsonb_build_object('supplier',r.data->>'supplier','line',line,'item_name',item.name,'item_spec',item.spec,'item_unit',item.unit);
    elsif p_action='reserve' then v_reserved_delta:=v_quantity;
    else v_delta:=v_quantity;end if;
   end if;
   if item.id is null then raise exception 'BUSINESS_NOT_FOUND';end if;
   balance:=public.business_stock_balance(p_workspace,item.id);
   if abs(v_delta)>1e9 or v_delta<>round(v_delta,6) then raise exception 'INVENTORY_CONVERSION';end if;
   if (balance->>'on_hand')::numeric+v_delta>1e9 then raise exception 'BUSINESS_LIMIT';end if;
   if (balance->>'available')::numeric+v_delta-v_reserved_delta<0 then raise exception 'INVENTORY_STOCK';end if;
   if p_action='reserve' then
    if (select count(*) from public.business_stock_reservations where workspace_id=p_workspace and remaining>0)>=1000 then raise exception 'BUSINESS_LIMIT';end if;
    insert into public.business_stock_reservations(id,workspace_id,item_id,purpose,quantity,remaining,actor_id) values(p_id,p_workspace,item.id,reason,v_quantity,v_quantity,auth.uid());v_reservation_id:=p_id;
   elsif p_action in ('consume','release') then
    update public.business_stock_reservations set remaining=remaining-v_quantity,revision=revision+1 where id=reservation.id;
   end if;
   insert into public.business_stock_events(id,workspace_id,item_id,kind,delta,reserved_delta,reason,request_id,line_id,receipt_id,reservation_id,purchase_quantity,factor,snapshot,actor_id)
    values(p_id,p_workspace,item.id,event_kind,v_delta,v_reserved_delta,reason,v_request_id,v_line_id,v_receipt_id,v_reservation_id,case when p_action in ('receive','return') then v_quantity end,v_factor,snapshot,auth.uid());
   result:=jsonb_build_object('id',p_id,'item',item.id,'balance',public.business_stock_balance(p_workspace,item.id));
  end if;
 end if;
 insert into public.business_stock_actions(id,workspace_id,actor_id,fingerprint,result) values(p_id,p_workspace,auth.uid(),fingerprint,result);
 return result;
end;$$;

create function public.business_stock_purchase_hints(p_workspace uuid,p_requirements jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare req jsonb; item public.business_stock_items; key text; result jsonb:='[]'; open_requests jsonb;
begin
 if not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 if jsonb_typeof(p_requirements) is distinct from 'array' then raise exception 'BUSINESS_INVALID';end if;
 if jsonb_array_length(p_requirements)>100 or octet_length(p_requirements::text)>131072 then raise exception 'BUSINESS_INVALID';end if;
 for req in select value from jsonb_array_elements(p_requirements) loop
  if jsonb_typeof(req->'name') is distinct from 'string' or jsonb_typeof(req->'spec') is distinct from 'string' or jsonb_typeof(req->'unit') is distinct from 'string' then raise exception 'BUSINESS_INVALID';end if;
  key:=encode(extensions.digest(jsonb_build_array(lower(btrim(req->>'name')),lower(btrim(req->>'spec')),lower(btrim(req->>'unit')))::text,'sha256'),'hex');
  select * into item from public.business_stock_items where workspace_id=p_workspace and lower(btrim(name))=lower(btrim(req->>'name')) and lower(btrim(spec))=lower(btrim(req->>'spec')) and lower(btrim(unit))=lower(btrim(req->>'unit'));
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into open_requests from (select r.id,r.title,r.status from public.business_records r join public.business_purchase_bases b on b.request_id=r.id and b.workspace_id=r.workspace_id where r.workspace_id=p_workspace and r.status in ('draft','review','approved','sent')
   and exists(select 1 from jsonb_array_elements(b.requirements) q where q->>'key'=key and exists(select 1 from jsonb_array_elements(b.adjustments) a where a->>'key'=key and a->'include'='true')) order by r.updated_at desc,r.id limit 5) x;
  result:=result||jsonb_build_array(jsonb_build_object('key',key,'item',case when item.id is not null then to_jsonb(item)||public.business_stock_balance(p_workspace,item.id) else null end,'open_requests',open_requests));
 end loop;
 return result;
end;$$;
revoke all on function public.business_stock_overview(uuid),public.business_receiving_overview(uuid,uuid),public.business_purchase_transition(uuid,uuid,bigint,text),public.business_stock_action(uuid,uuid,text,jsonb),public.business_stock_purchase_hints(uuid,jsonb) from public,anon;
grant execute on function public.business_stock_overview(uuid),public.business_receiving_overview(uuid,uuid),public.business_purchase_transition(uuid,uuid,bigint,text),public.business_stock_action(uuid,uuid,text,jsonb),public.business_stock_purchase_hints(uuid,jsonb) to authenticated;
create function public.business_stock_events_page(p_workspace uuid,p_item uuid default null,p_request uuid default null,p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_offset is null or p_offset<0 or p_offset>1000000 then raise exception 'BUSINESS_INVALID';end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id) from (
  select e.*,i.name item_name,i.unit item_unit,case when e.kind='receive' then e.purchase_quantity-coalesce((select sum(t.purchase_quantity) from public.business_stock_events t where t.workspace_id=p_workspace and t.receipt_id=e.id and t.kind='return'),0) end returnable
  from public.business_stock_events e join public.business_stock_items i on i.workspace_id=e.workspace_id and i.id=e.item_id
  where e.workspace_id=p_workspace and (p_item is null or e.item_id=p_item) and (p_request is null or e.request_id=p_request)
  order by e.created_at desc,e.id limit 50 offset p_offset
 ) x),'[]');
end;$$;
revoke all on function public.business_stock_events_page(uuid,uuid,uuid,integer) from public,anon;
grant execute on function public.business_stock_events_page(uuid,uuid,uuid,integer) to authenticated;

commit;
