-- Explicit denial in addition to the paid RLS filter.
create or replace function public.chef_sales_totals(p_from date,p_until date,p_currency text,p_recipe_id uuid default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if not public.has_chef_paid_access() then raise exception 'CHEF_PAID_REQUIRED'; end if;
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
