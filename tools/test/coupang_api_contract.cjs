// Isolated PostgreSQL only; no deployed database or Coupang calls.
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const { PGlite } = require('../../.artifacts/business-db-runtime/node_modules/@electric-sql/pglite');
const root = path.resolve(__dirname, '../..');
(async () => {
  const db = new PGlite();
  let checks = 0;
  const ok = (condition) => { assert.ok(condition); checks++; };
  const deny = async (sql) => {
    let rejected = false;
    try { await db.query(sql); } catch { rejected = true; }
    ok(rejected);
  };
  const login = async (id, aal = 'aal2', anonymous = false) => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claims',$1,false)", [JSON.stringify({ sub:id, aal, is_anonymous:anonymous })]);
    await db.exec('set role authenticated');
  };
  const admin = '11111111-1111-4111-8111-111111111111';
  const member = '22222222-2222-4222-8222-222222222222';
  const second = '33333333-3333-4333-8333-333333333333';
  const consume = async (action) => (await db.query('select public.admin_consume_coupang_api($1) allowed', [action])).rows[0].allowed;
  try {
    await db.exec(`create role anon; create role authenticated; create schema auth;
      create table public.profiles(id uuid, role text);
      insert into public.profiles values('${admin}','admin'),('${member}','member'),('${second}','admin');
      create function auth.jwt() returns jsonb language sql as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
      create function auth.uid() returns uuid language sql as $$select (auth.jwt()->>'sub')::uuid$$;
      grant usage on schema auth to authenticated;`);
    const base = fs.readFileSync(path.join(root, 'supabase/migrations/0060_public_supplier_listings.sql'), 'utf8');
    await db.exec(base.match(/create function public.assert_supplier_directory_admin\(\)[\s\S]*?\$\$;/)[0]);
    await db.exec('revoke all on function public.assert_supplier_directory_admin() from public,anon,authenticated;');
    await db.exec(fs.readFileSync(path.join(root, 'supabase/migrations/0073_coupang_partner_api.sql'), 'utf8'));
    await db.exec('set role anon');
    await deny("select public.admin_consume_coupang_api('search')");
    await login(member); await deny("select public.admin_consume_coupang_api('search')");
    await login(admin,'aal1'); await deny("select public.admin_consume_coupang_api('search')");
    await login(admin,'aal2',true); await deny("select public.admin_consume_coupang_api('search')");
    await login(admin);
    await deny("select public.admin_consume_coupang_api('other')");
    await deny('select public.admin_consume_coupang_api(null)');
    await deny('select * from public.coupang_api_limits');
    await deny('delete from public.coupang_api_limits');
    for (let i=0; i<5; i++) ok(await consume('search'));
    ok(!await consume('search'));
    await login(second); ok(!await consume('search')); // Global, not per administrator.
    ok(await consume('deeplink'));
    await db.exec('reset role');
    await db.exec("update public.coupang_api_limits set minute_start=minute_start-interval '2 minutes'");
    await login(admin); ok(await consume('search'));
    await db.exec('reset role');
    await db.exec("update public.coupang_api_limits set day_count=500,minute_start=minute_start-interval '2 minutes' where action='search'");
    await login(admin); ok(!await consume('search'));
    await db.exec('reset role');
    await db.exec("update public.coupang_api_limits set day_start=day_start-interval '1 day' where action='search'");
    await login(admin); ok(await consume('search'));
    console.log(`Coupang API database contract: ${checks} checks passed`);
  } finally { await db.close(); }
})().catch((error) => { console.error(error); process.exitCode=1; });
