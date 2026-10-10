// Disposable PostgreSQL: no production access, users or records.
const {PGlite}=require('../../.artifacts/business-db-runtime/node_modules/@electric-sql/pglite');
const fs=require('fs'),path=require('path'),crypto=require('crypto');
(async()=>{
 const db=new PGlite(); await db.waitReady; let checks=0;
 const q=async(s,p=[]) => (await db.query(s,p)).rows;
 const assert=(v)=>{if(!v)throw Error('Contract failed');checks++;};
 const denied=async(s,p,code)=>{try{await q(s,p);}catch(e){assert(!code||e.code===code);return;}throw Error('Unexpectedly allowed');};
 try {
  await db.exec(`create role anon;create role authenticated;create schema auth;
   create table auth.users(id uuid primary key);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
   grant usage on schema auth to authenticated,anon;`);
  await db.exec(fs.readFileSync(path.join(__dirname,'../../supabase/migrations/0084_shopping_preparation_sync.sql'),'utf8'));
  const a=crypto.randomUUID(),b=crypto.randomUUID();await q('insert into auth.users values($1),($2)',[a,b]);
  const login=async(id,anonymous=false)=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({is_anonymous:anonymous})]);await db.exec('set role authenticated');};
  const value={fingerprint:'example',selected:[],edits:{},confirmed:false};
  await login(a);let r=await q('select public.save_shopping_preparation($1,$2) as draft',[0,value]);assert(r[0].draft.revision===1);
  await denied('select public.save_shopping_preparation($1,$2)',[0,value],'40001');
  r=await q('select public.save_shopping_preparation($1,$2) as draft',[1,{...value,confirmed:true}]);assert(r[0].draft.revision===2);
  await denied('select public.save_shopping_preparation($1,$2)',[1,value],'40001');
  await denied('update public.shopping_preparation_drafts set revision=99',[],'42501');
  await denied('delete from public.shopping_preparation_drafts',[],'42501');
  await denied('select public.save_shopping_preparation($1,$2)',[2,{}],'22023');
  await denied('select public.save_shopping_preparation($1,$2)',[2,{...value,extra:'x'.repeat(524288)}],'22023');
  await login(b);assert((await q('select * from public.shopping_preparation_drafts')).length===0);
  await q('select public.save_shopping_preparation($1,$2)',[0,value]);assert((await q('select * from public.shopping_preparation_drafts'))[0].owner_id===b);
  await login(a,true);assert((await q('select * from public.shopping_preparation_drafts')).length===0);
  await denied('select public.save_shopping_preparation($1,$2)',[2,value],'42501');
  await db.exec('reset role;set role anon');await denied('select public.save_shopping_preparation($1,$2)',[0,value],'42501');
  await db.exec('reset role');await q('delete from auth.users where id=$1',[a]);assert((await q('select * from public.shopping_preparation_drafts')).length===1);
  console.log(JSON.stringify({passed:checks}));
 }finally{await db.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
