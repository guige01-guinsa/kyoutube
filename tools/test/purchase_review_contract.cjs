// In-memory PostgreSQL only. No network, credentials or production database.
const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const { PGlite } = require('../../.artifacts/business-db-runtime/node_modules/@electric-sql/pglite');
const root = path.resolve(__dirname, '../..');
(async () => {
  const db = new PGlite(); await db.waitReady; let checks = 0;
  const ok = value => { assert.ok(value); checks++; };
  const q = async (sql, args = []) => (await db.query(sql, args)).rows;
  const user = '11111111-1111-4111-8111-111111111111';
  const source = fs.readFileSync(path.join(root, 'supabase/migrations/0031_memberships_and_ai_quotas.sql'), 'utf8');
  const fn = name => source.match(new RegExp('create or replace function public\\.' + name + '\\([\\s\\S]*?\\$\\$;'))[0];
  const denied = async (sql, args, message) => { let error; try { await q(sql, args); } catch (e) { error = e; } ok(error && (!message || error.message.includes(message))); };
  const reserve = endpoint => q('select * from public.begin_ai_recipe_usage($1,$2)', [user, endpoint]);
  const review = 'ai_purchase_request_review';
  try {
    await db.exec(`create role anon;create role authenticated;create role service_role;
      create schema auth;create table auth.users(id uuid primary key);
      insert into auth.users values('${user}');
      create function auth.role() returns text language sql as $$select current_setting('request.role',true)$$;
      grant usage on schema auth to service_role,authenticated;`);
    for (const name of ['membership_plans', 'member_entitlements', 'ai_usage_reservations']) {
      await db.exec(source.match(new RegExp('create table public\\.' + name + ' \\([\\s\\S]*?\n\\);'))[0]);
    }
    await db.exec(source.match(/create unique index ai_usage_one_in_flight_per_user_idx[\s\S]*?;/)[0]);
    // Apply the entitlement guard from 0055 to the baseline fixture before 0066.
    const policy = fs.readFileSync(path.join(root, 'supabase/migrations/0055_launch_membership_tiers.sql'), 'utf8');
    const strict = policy.match(/'and e\.valid_until > now\(\)[^']*'/)[0].slice(1, -1);
    await db.exec(fn('begin_ai_recipe_usage').replace('and (e.valid_until is null or e.valid_until > now())', strict));
    await db.exec(fn('finish_ai_recipe_usage'));
    await db.exec(fs.readFileSync(path.join(root, 'supabase/migrations/0066_purchase_request_ai_review.sql'), 'utf8'));
    const definition = (await q("select pg_get_functiondef('public.begin_ai_recipe_usage(uuid,text)'::regprocedure) text"))[0].text;
    ok(definition.includes(strict)); ok(definition.includes('AI_QUOTA_WEEKLY'));
    await db.exec(`insert into public.membership_plans(code,display_name,price_krw,billing_period,recipe_model,daily_ai_limit,weekly_ai_limit,monthly_ai_limit)
      values('free','Free',0,'none','gpt-4o-mini',1,5,10),('business_monthly','Business',14900,'monthly','gpt-5.4-mini',10,50,100);`);
    await q("select set_config('request.role','service_role',false)");
    await denied('select * from public.begin_ai_recipe_usage($1,$2)', [user, null], 'INVALID_AI_USAGE_REQUEST');
    const first = (await reserve(review))[0]; ok(first.recipe_model === 'gpt-4o-mini');
    await denied('select * from public.begin_ai_recipe_usage($1,$2)', [user, review], 'AI_IN_FLIGHT');
    await q('select public.finish_ai_recipe_usage($1,$2,true,$3,400,100)', [user, first.reservation_id, first.recipe_model]);
    await denied('select * from public.begin_ai_recipe_usage($1,$2)', [user, 'ai_recipe_assistant'], 'AI_QUOTA_DAILY');
    await q('delete from public.ai_usage_reservations');
    await q("insert into public.member_entitlements(user_id,plan_code,status,source,valid_until,started_at) values($1,'business_monthly','active','admin',now()+interval '1 month',now()-interval '1 day')", [user]);
    const paid = (await reserve(review))[0]; ok(paid.recipe_model === 'gpt-5.4-mini');
    await q('select public.finish_ai_recipe_usage($1,$2,false,$3,500,80)', [user, paid.reservation_id, paid.recipe_model]);
    const usage = (await q('select * from public.ai_usage_reservations'))[0]; ok(usage.status === 'failed' && usage.request_tokens === 500 && usage.response_tokens === 80);
    await q('delete from public.ai_usage_reservations');
    await q("insert into public.ai_usage_reservations(user_id,endpoint,plan_code,status,created_at) select $1,$2,'business_monthly','failed',date_trunc('day',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' from generate_series(1,5)", [user, review]);
    await denied('select * from public.begin_ai_recipe_usage($1,$2)', [user, review], 'AI_QUOTA_DAILY');
    await q('delete from public.ai_usage_reservations');
    // Other feature failures never consume this feature-specific daily cap.
    await q("insert into public.ai_usage_reservations(user_id,endpoint,plan_code,status,created_at) select $1,'ai_recipe_assistant','business_monthly','failed',now()-interval '1 hour' from generate_series(1,5)", [user]);
    ok((await reserve(review)).length === 1);
    await q('delete from public.ai_usage_reservations');
    await q("insert into public.ai_usage_reservations(user_id,endpoint,plan_code,status,created_at) select $1,$2,'business_monthly','failed',date_trunc('month',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul' from generate_series(1,30)", [user, review]);
    // On the first day of a month the daily guard legitimately fires first.
    const firstDay = (await q("select extract(day from now() at time zone 'Asia/Seoul')=1 value"))[0].value;
    await denied('select * from public.begin_ai_recipe_usage($1,$2)', [user, review], firstDay ? 'AI_QUOTA_DAILY' : 'AI_QUOTA_MONTHLY');
    await q('delete from public.ai_usage_reservations');
    await q("update public.member_entitlements set valid_until=null where user_id=$1", [user]);
    ok((await reserve(review))[0].plan_code === 'free');
    await db.exec('set role authenticated');
    await denied('select * from public.begin_ai_recipe_usage($1,$2)', [user, review], 'permission denied');
    await db.exec('reset role;set role anon');
    await denied('select * from public.begin_ai_recipe_usage($1,$2)', [user, review], 'permission denied');
    console.log(`PASS: ${checks} purchase review database checks`);
  } finally { await db.close(); }
})().catch(e => { console.error(e.message); process.exitCode = 1; });
