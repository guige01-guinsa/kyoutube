-- Server-side quota shared across administrators and Edge Function instances.
create table public.coupang_api_limits (
 action text primary key check (action in ('search','deeplink')),
 minute_start timestamptz not null,
 minute_count integer not null,
 day_start timestamptz not null,
 day_count integer not null
);
alter table public.coupang_api_limits enable row level security;
revoke all on public.coupang_api_limits from public,anon,authenticated;

create function public.admin_consume_coupang_api(p_action text) returns boolean
language plpgsql security definer set search_path='' as $$
declare
 current_time_value timestamptz := clock_timestamp();
 minute_value timestamptz := date_trunc('minute',current_time_value);
 day_value timestamptz := date_trunc('day',current_time_value at time zone 'UTC') at time zone 'UTC';
 limit_value integer;
 row_value public.coupang_api_limits;
begin
 perform public.assert_supplier_directory_admin();
 if coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
  raise exception 'ADMIN_REQUIRED';
 end if;
 if p_action is null or p_action not in ('search','deeplink') then
  raise exception 'COUPANG_INVALID_ACTION';
 end if;
 limit_value := case p_action when 'search' then 5 else 30 end;
 insert into public.coupang_api_limits values(p_action,minute_value,0,day_value,0)
 on conflict do nothing;
 select * into row_value from public.coupang_api_limits where action=p_action for update;
 if row_value.minute_start<>minute_value then row_value.minute_count:=0; end if;
 if row_value.day_start<>day_value then row_value.day_count:=0; end if;
 if row_value.minute_count>=limit_value or row_value.day_count>=500 then return false; end if;
 update public.coupang_api_limits set minute_start=minute_value,
  minute_count=row_value.minute_count+1,day_start=day_value,day_count=row_value.day_count+1
 where action=p_action;
 return true;
end; $$;
revoke all on function public.admin_consume_coupang_api(text) from public,anon;
grant execute on function public.admin_consume_coupang_api(text) to authenticated;
