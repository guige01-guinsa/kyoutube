-- Purchase review shares existing membership quotas and model selection.
-- No client role may reserve AI usage directly.
alter table public.ai_usage_reservations
  drop constraint ai_usage_reservations_endpoint_check;
alter table public.ai_usage_reservations
  add constraint ai_usage_reservations_endpoint_check check (
    endpoint in ('ai_recipe_assistant', 'ai_youtube_recipe_assistant', 'ai_purchase_request_review')
  );

-- Extend the installed function in place so later entitlement/security guards
-- (including migration 0055) are retained. Abort on an unexpected definition.
do $migration$
declare definition text;
  endpoint_guard text := $guard$if p_user_id is null or p_endpoint not in ('ai_recipe_assistant', 'ai_youtube_recipe_assistant') then$guard$;
  lock_line text := 'perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));';
begin
  definition := pg_get_functiondef('public.begin_ai_recipe_usage(uuid,text)'::regprocedure);
  if position(endpoint_guard in definition) = 0 or position(lock_line in definition) = 0 then
    raise exception 'UNEXPECTED_AI_RESERVATION_FUNCTION';
  end if;
  definition := replace(definition, endpoint_guard,
    $guard$if p_user_id is null or p_endpoint is null or p_endpoint not in ('ai_recipe_assistant', 'ai_youtube_recipe_assistant', 'ai_purchase_request_review') then$guard$);
  definition := replace(definition, lock_line, lock_line || $caps$
  -- Every review attempt counts toward its cost-control limits, even failures.
  -- The shared per-user lock makes reservation and both limits atomic.
  if p_endpoint = 'ai_purchase_request_review' then
    if (select count(*) from public.ai_usage_reservations r
        where r.user_id = p_user_id and r.endpoint = p_endpoint
          and r.created_at >= v_day_start) >= 5 then
      raise exception 'AI_QUOTA_DAILY';
    end if;
    if (select count(*) from public.ai_usage_reservations r
        where r.user_id = p_user_id and r.endpoint = p_endpoint
          and r.created_at >= v_month_start) >= 30 then
      raise exception 'AI_QUOTA_MONTHLY';
    end if;
  end if;


$caps$);
  execute definition;
end;
$migration$;

revoke all on function public.begin_ai_recipe_usage(uuid, text) from public, anon, authenticated;
grant execute on function public.begin_ai_recipe_usage(uuid, text) to service_role;
