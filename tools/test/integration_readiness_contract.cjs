// Disposable database; no production credentials or mutations.
const {PGlite}=require('../../.artifacts/business-db-runtime/node_modules/@electric-sql/pglite');
const fs=require('fs'),path=require('path');
(async()=>{
 const db=new PGlite();await db.waitReady;let passed=0;
 const source=name=>fs.readFileSync(path.join(__dirname,'../../supabase/migrations',name),'utf8');
 const q=async(sql,args=[]) => (await db.query(sql,args)).rows;
 const assert=v=>{if(!v)throw Error('Contract assertion failed');passed++;};
 const denied=async(sql,args=[])=>{try{await q(sql,args);}catch{passed++;return;}throw Error('Unexpectedly allowed');};
 try {
  await db.exec(`create role anon;create role authenticated;create schema auth;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
    grant usage on schema auth to authenticated,anon;
    create table public.profiles(id uuid primary key,role text);
    create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
    create table public.ops_admin_devices(user_id uuid,session_id uuid,token text unique,language text constraint ops_admin_devices_language_check check(language in ('ko','en')),expires_at timestamptz default now()+interval '30 days');`);
  for(const [name,fn] of [['0060_public_supplier_listings.sql','assert_supplier_directory_admin'],['0036_operations_observability.sql','assert_ops_admin']]) {
   const text=source(name),start=text.indexOf('create function public.'+fn+'()');
   await db.exec(text.slice(start,text.indexOf('$$;',start)+3));
  }
  await db.exec(source('0085_admin_integration_readiness.sql'));
  await db.exec(source('0086_ops_spanish_language.sql'));
  const user='11111111-1111-4111-8111-111111111111',session='22222222-2222-4222-8222-222222222222';
  await q('insert into public.profiles values ($1,\'user\')',[user]);
  await q('insert into auth.sessions values ($1,$2,null)',[session,user]);
  const login=async(claims={})=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[user,JSON.stringify({session_id:session,...claims})]);await db.exec('set role authenticated');};
  await login({aal:'aal2'});await denied('select public.admin_assert_integration_access()');
  await db.exec('reset role');await q("update public.profiles set role='admin'");
  await login({aal:'aal1'});await denied('select public.admin_assert_integration_access()');
  await login({aal:'aal2',is_anonymous:true});await denied('select public.admin_assert_integration_access()');
  await login({aal:'aal2'});assert((await q('select public.admin_assert_integration_access() as ok'))[0].ok);
  await q('select public.admin_register_ops_device($1,$2)',['synthetic-device-token-only','es']);
  await db.exec('reset role');assert((await q('select language from public.ops_admin_devices'))[0].language==='es');
  await login();await denied('select public.admin_register_ops_device($1,$2)',['synthetic-device-token-only','unknown']);
  await db.exec('reset role;set role anon');await denied('select public.admin_assert_integration_access()');
  console.log(JSON.stringify({passed}));
 }finally{await db.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
