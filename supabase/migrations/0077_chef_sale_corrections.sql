-- Personal sales: corrections and reversible voiding with immutable snapshots.
begin;
alter table public.chef_sales add column revision bigint not null default 1;
alter table public.chef_sales add column voided boolean not null default false;
revoke delete on public.chef_sales from authenticated;
revoke update(sale_date,quantity) on public.chef_sales from authenticated;
-- Legacy clients continue to see only sales that contribute to their totals.
alter policy chef_sales_read on public.chef_sales using(owner_id=auth.uid() and public.has_chef_paid_access() and not voided);

create table public.chef_sale_events (
 id bigint generated always as identity primary key,
 sale_id bigint not null, owner_id uuid not null references auth.users(id) on delete cascade,
 action text not null, reason text not null default '',
 before_data jsonb, after_data jsonb, recorded_at timestamptz not null default now()
);
create index chef_sale_events_owner on public.chef_sale_events(owner_id,sale_id,id);
alter table public.chef_sale_events enable row level security;
revoke all on public.chef_sale_events from public,anon,authenticated;
grant select on public.chef_sale_events to authenticated;
grant all on public.chef_sale_events to service_role;
create policy chef_sale_events_read on public.chef_sale_events for select to authenticated
 using(owner_id=auth.uid() and public.has_chef_paid_access());
insert into public.chef_sale_events(sale_id,owner_id,action,after_data)
 select id,owner_id,'baseline',to_jsonb(s) from public.chef_sales s;

create function public.record_chef_sale_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare action text;
begin
 if tg_op='INSERT' then
  action:='created';
 elsif tg_op='DELETE' then
  -- Account erasure still cascades. An erased user must not be recreated in an audit FK.
  if not exists(select 1 from auth.users where id=old.owner_id) then return old; end if;
  insert into public.chef_sale_events(sale_id,owner_id,action,before_data)
   values(old.id,old.owner_id,'removed_by_service',to_jsonb(old));
  return old;
 else
  action:=case when new.voided is distinct from old.voided then case when new.voided then 'voided' else 'restored' end else 'corrected' end;
 end if;
 insert into public.chef_sale_events(sale_id,owner_id,action,reason,before_data,after_data)
 values(new.id,new.owner_id,action,coalesce(current_setting('scout.sale_reason',true),''),
  case when tg_op='UPDATE' then to_jsonb(old) else null end,to_jsonb(new));
 return new;
end; $$;
revoke all on function public.record_chef_sale_event() from public,anon,authenticated;
create trigger chef_sale_event after insert or update or delete on public.chef_sales
 for each row execute function public.record_chef_sale_event();

create function public.chef_sale_manage(p_id bigint,p_revision bigint,p_action text,p_reason text,p_date date default null,p_quantity integer default null)
returns void language plpgsql security definer set search_path='' as $$
declare r public.chef_sales;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) or not public.has_chef_paid_access() then raise exception 'CHEF_PAID_REQUIRED'; end if;
 if p_action is null or p_action not in ('correct','void','restore') or p_reason is null or length(btrim(p_reason)) not between 1 and 300 then raise exception 'CHEF_INVALID'; end if;
 select * into r from public.chef_sales where id=p_id and owner_id=auth.uid() for update;
 if r.id is null or p_revision is null or r.revision<>p_revision then raise exception 'CHEF_REVISION_CONFLICT'; end if;
 if (p_action in ('correct','void') and r.voided) or (p_action='restore' and not r.voided) then raise exception 'CHEF_REVISION_CONFLICT'; end if;
 if p_action='correct' and (p_date is null or p_quantity is null or p_quantity not between 1 and 100000 or p_date not between date '2000-01-01' and date '2100-12-31') then raise exception 'CHEF_INVALID'; end if;
 perform set_config('scout.sale_reason',btrim(p_reason),true);
 update public.chef_sales set revision=revision+1,
  sale_date=case when p_action='correct' then p_date else sale_date end,
  quantity=case when p_action='correct' then p_quantity else quantity end,
  voided=case when p_action='void' then true when p_action='restore' then false else voided end where id=r.id;
 -- The stored sale price/cost and inventory are deliberately never rewritten.
end; $$;
revoke all on function public.chef_sale_manage(bigint,bigint,text,text,date,integer) from public,anon;
grant execute on function public.chef_sale_manage(bigint,bigint,text,text,date,integer) to authenticated;

create function public.chef_voided_sales(p_from date,p_until date,p_currency text,p_recipe uuid default null,p_before bigint default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) or not public.has_chef_paid_access() then raise exception 'CHEF_PAID_REQUIRED'; end if;
 if p_from is null or p_until is null or p_until<=p_from or p_until-p_from>366 or p_currency is null or p_currency not in ('KRW','USD') then raise exception 'CHEF_INVALID_PERIOD'; end if;
 return coalesce((select jsonb_agg(to_jsonb(s) order by s.id desc) from
  (select * from public.chef_sales where owner_id=auth.uid() and voided and currency=p_currency
    and sale_date>=p_from and sale_date<p_until and (p_recipe is null or recipe_id=p_recipe)
    and (p_before is null or id<p_before) order by id desc limit 50) s),'[]'::jsonb);
end; $$;
revoke all on function public.chef_voided_sales(date,date,text,uuid,bigint) from public,anon;
grant execute on function public.chef_voided_sales(date,date,text,uuid,bigint) to authenticated;
notify pgrst,'reload schema';
commit;
