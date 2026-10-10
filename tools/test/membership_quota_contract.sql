\set ON_ERROR_STOP on

begin;

insert into auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('11111111-1111-4111-8111-111111111111', 'authenticated',
   'authenticated', 'membership-free@test.invalid', '{}'::jsonb,
   '{}'::jsonb, now(), now()),
  ('22222222-2222-4222-8222-222222222222', 'authenticated',
   'authenticated', 'membership-paid@test.invalid', '{}'::jsonb,
   '{}'::jsonb, now(), now());

insert into public.profiles (id, role, display_name) values
  ('11111111-1111-4111-8111-111111111111', 'user', 'Free test'),
  ('22222222-2222-4222-8222-222222222222', 'user', 'Paid test');

select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare
  v_first record;
  v_second record;
  v_paid record;
  v_error text;
begin
  select * into v_first
  from public.begin_ai_recipe_usage(
    '11111111-1111-4111-8111-111111111111',
    'ai_recipe_assistant'
  );

  if v_first.plan_code <> 'free'
     or v_first.recipe_model <> 'gpt-4o-mini'
     or v_first.daily_limit <> 1
     or v_first.weekly_limit <> 5
     or v_first.monthly_limit <> 10 then
    raise exception 'FREE_PLAN_ASSERTION_FAILED';
  end if;

  perform public.finish_ai_recipe_usage(
    '11111111-1111-4111-8111-111111111111',
    v_first.reservation_id,
    false,
    v_first.recipe_model
  );

  select * into v_second
  from public.begin_ai_recipe_usage(
    '11111111-1111-4111-8111-111111111111',
    'ai_youtube_recipe_assistant'
  );

  perform public.finish_ai_recipe_usage(
    '11111111-1111-4111-8111-111111111111',
    v_second.reservation_id,
    true,
    v_second.recipe_model,
    120,
    240
  );

  begin
    perform public.begin_ai_recipe_usage(
      '11111111-1111-4111-8111-111111111111',
      'ai_recipe_assistant'
    );
  exception when others then
    v_error := sqlerrm;
  end;

  if v_error is distinct from 'AI_QUOTA_DAILY' then
    raise exception 'FREE_DAILY_LIMIT_ASSERTION_FAILED: %', v_error;
  end if;

  insert into public.member_entitlements (
    user_id, plan_code, status, source, started_at, valid_until
  ) values (
    '22222222-2222-4222-8222-222222222222',
    'paid_monthly', 'active', 'admin', now(), now() + interval '31 days'
  );

  select * into v_paid
  from public.begin_ai_recipe_usage(
    '22222222-2222-4222-8222-222222222222',
    'ai_recipe_assistant'
  );

  if v_paid.plan_code <> 'paid_monthly'
     or v_paid.recipe_model <> 'gpt-5.4-mini'
     or v_paid.daily_limit <> 10
     or v_paid.weekly_limit <> 50
     or v_paid.monthly_limit <> 100 then
    raise exception 'PAID_PLAN_ASSERTION_FAILED';
  end if;
end;
$$;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  true
);

do $$
declare
  v_membership record;
  v_error text;
begin
  select * into v_membership from public.get_my_membership();
  if v_membership.plan_code <> 'free'
     or v_membership.daily_used <> 1
     or v_membership.monthly_used <> 1 then
    raise exception 'MEMBERSHIP_STATUS_ASSERTION_FAILED';
  end if;

  begin
    update public.profiles
    set role = 'admin'
    where id = '11111111-1111-4111-8111-111111111111';
  exception when others then
    v_error := sqlerrm;
  end;

  if v_error is distinct from 'PROFILE_ROLE_SERVER_MANAGED' then
    raise exception 'ROLE_ESCALATION_ASSERTION_FAILED: %', v_error;
  end if;
end;
$$;

rollback;

select 'membership quota contract passed' as result;
