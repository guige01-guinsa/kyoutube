create table public.chef_sales (
  id bigint generated always as identity primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  recipe_id uuid references public.recipes_creator(id) on delete set null,
  recipe_title text not null,
  workspace_revision bigint not null,
  sale_date date not null check(sale_date between date '2000-01-01' and date '2100-12-31'),
  quantity integer not null check(quantity between 1 and 100000),
  currency text not null check(currency in ('KRW','USD')),
  unit_price numeric not null check(unit_price >= 0 and unit_price < 1e40),
  unit_cost numeric not null check(unit_cost >= 0 and unit_cost < 1e40),
  markup_percent numeric not null check(markup_percent between 0 and 100),
  request_key text not null check(length(request_key) between 1 and 80),
  created_at timestamptz not null default now(),
  unique(owner_id,request_key)
);
create index chef_sales_period_idx on public.chef_sales(owner_id,currency,sale_date,id);
alter table public.chef_sales enable row level security;
revoke all on public.chef_sales from anon,authenticated;
grant select,delete on public.chef_sales to authenticated;
grant update(sale_date,quantity) on public.chef_sales to authenticated;
grant all on public.chef_sales to service_role;
create policy chef_sales_read on public.chef_sales for select to authenticated using(owner_id=auth.uid());
create policy chef_sales_edit on public.chef_sales for update to authenticated
  using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy chef_sales_remove on public.chef_sales for delete to authenticated using(owner_id=auth.uid());

create function public.chef_cost_per_serving(d jsonb)
returns numeric language plpgsql immutable set search_path='' as $$
declare item jsonb; total numeric := (d->>'extraCost')::numeric; factor numeric; pack_factor numeric;
begin
  if not public.chef_document_valid(d) or d->>'baseServings' is null or
     d->>'targetServings' is null or jsonb_array_length(d->'ingredients')=0 then return null; end if;
  for item in select value from jsonb_array_elements(d->'ingredients') loop
    if item->>'quantity' is null or item->>'purchaseQuantity' is null or item->>'purchasePrice' is null then return null; end if;
    if not (
      (item->>'unit' in ('g','kg') and item->>'purchaseUnit' in ('g','kg')) or
      (item->>'unit' in ('ml','l') and item->>'purchaseUnit' in ('ml','l')) or
      (item->>'unit'='each' and item->>'purchaseUnit'='each')
    ) then return null; end if;
    factor := case when item->>'unit' in ('kg','l') then 1000 else 1 end;
    pack_factor := case when item->>'purchaseUnit' in ('kg','l') then 1000 else 1 end;
    total := total + (item->>'quantity')::numeric / ((item->>'yieldPercent')::numeric/100)
      * factor / pack_factor / (item->>'purchaseQuantity')::numeric * (item->>'purchasePrice')::numeric;
  end loop;
  return total / (d->>'baseServings')::numeric;
end;
$$;
revoke all on function public.chef_cost_per_serving(jsonb) from public;

create function public.record_chef_sale(p_recipe_id uuid,p_expected_revision bigint,
  p_sale_date date,p_quantity integer,p_request_key text)
returns bigint language plpgsql security definer set search_path='' as $$
declare uid uuid := auth.uid(); work public.chef_workspaces%rowtype;
  prior public.chef_sales%rowtype; cost numeric; markup numeric; price numeric; new_id bigint;
begin
  if uid is null then raise exception 'CHEF_LOGIN_REQUIRED'; end if;
  if p_request_key is null or length(p_request_key) not between 1 and 80 or
     p_sale_date is null or p_sale_date not between date '2000-01-01' and date '2100-12-31' or
     p_quantity is null or p_quantity not between 1 and 100000 then raise exception 'CHEF_INVALID_SALE'; end if;
  perform 1 from public.recipes_creator where id=p_recipe_id and author_id=uid for update;
  if not found then raise exception 'CHEF_RECIPE_NOT_OWNED'; end if;
  select * into work from public.chef_workspaces where recipe_id=p_recipe_id and owner_id=uid for update;
  if not found then raise exception 'CHEF_COST_REQUIRED'; end if;
  select * into prior from public.chef_sales where owner_id=uid and request_key=p_request_key;
  if found then
    if prior.recipe_id=p_recipe_id and prior.sale_date=p_sale_date and prior.quantity=p_quantity then return prior.id; end if;
    raise exception 'CHEF_REQUEST_REUSED';
  end if;
  if p_expected_revision is distinct from work.revision then raise exception 'CHEF_REVISION_CONFLICT'; end if;
  cost := public.chef_cost_per_serving(work.document);
  if cost is null then raise exception 'CHEF_COST_REQUIRED'; end if;
  markup := coalesce((work.document->>'markupPercent')::numeric,0);
  if markup not between 0 and 100 then raise exception 'CHEF_INVALID_SALE'; end if;
  price := round(cost*(1+markup/100),case when work.document->>'currency'='KRW' then 0 else 2 end);
  insert into public.chef_sales(owner_id,recipe_id,recipe_title,workspace_revision,sale_date,quantity,currency,
    unit_price,unit_cost,markup_percent,request_key)
  values(uid,p_recipe_id,work.document->>'title',work.revision,p_sale_date,p_quantity,work.document->>'currency',
    price,cost,markup,p_request_key) returning id into new_id;
  return new_id;
end;
$$;
revoke all on function public.record_chef_sale(uuid,bigint,date,integer,text) from public,anon;
grant execute on function public.record_chef_sale(uuid,bigint,date,integer,text) to authenticated;

create function public.chef_sales_totals(p_from date,p_until date,p_currency text,p_recipe_id uuid default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if p_from is null or p_until is null or p_until <= p_from or p_until-p_from > 366 or
    p_currency is null or p_currency not in ('KRW','USD') then raise exception 'CHEF_INVALID_PERIOD'; end if;
  select jsonb_build_object('quantity',coalesce(sum(quantity),0),
    'revenue',coalesce(sum(quantity*unit_price),0),'cost',coalesce(sum(quantity*unit_cost),0))
  into result from public.chef_sales
  where owner_id=auth.uid() and currency=p_currency and sale_date>=p_from and sale_date<p_until
    and (p_recipe_id is null or recipe_id=p_recipe_id);
  return result;
end;
$$;
revoke all on function public.chef_sales_totals(date,date,text,uuid) from public,anon;
grant execute on function public.chef_sales_totals(date,date,text,uuid) to authenticated;
