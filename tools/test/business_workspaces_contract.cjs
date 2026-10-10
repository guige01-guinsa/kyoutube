// Isolated PostgreSQL tests: default PGlite or --docker using the local Supabase engine.
// Docker mode creates and removes only a uniquely named empty test database.
const fs = require('fs');
const path = require('path');
const {PGlite} = require('../../.artifacts/business-db-runtime/node_modules/@electric-sql/pglite');
const {pgcrypto} = require('../../.artifacts/business-db-runtime/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.cjs');
const crypto=require('crypto');
const root=path.resolve(__dirname,'../..');
const reports=[];
if(process.argv.includes('--management')) process.argv.push('--fast','--cleanup','--meals');
if(process.argv.includes('--coupang')) process.argv.push('--meals');
if(process.argv.includes('--meals') && !process.argv.includes('--fast')) process.argv.push('--fast');
if(process.argv.includes('--fast') && !process.argv.includes('--inventory')) process.argv.push('--inventory');
if(process.argv.includes('--inventory') && !process.argv.includes('--suppliers')) process.argv.push('--suppliers');
if(process.argv.includes('--suppliers') && !process.argv.includes('--menu')) process.argv.push('--menu');
let db;
const docker=process.argv.includes('--docker');
let admin, testName;
async function close(){
 if(db){await db.close();db=null;}
 if(admin){
  if(testName && /^scout_contract_[0-9a-f]+$/.test(testName)) await admin.query('drop database if exists "'+testName+'"');
  await admin.end();admin=null;
 }
}
function ok(v,label){if(!v)throw Error(label);reports.push(label);}
async function q(sql,args=[]){try{return (await db.query(sql,args)).rows;}catch(e){e.message=sql.slice(0,100)+': '+e.message;throw e;}}
async function scalar(sql,args=[]){return Object.values((await q(sql,args))[0])[0];}
async function denied(sql,args,expected,label){try{await q(sql,args);}catch(e){if(expected && !String(e.message).includes(expected) && e.code!==expected)throw Error(label+': '+e.message);reports.push(label);return;}throw Error(label+': unexpectedly allowed');}
async function login(id,anonymous=false){await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({sub:id,role:'authenticated',is_anonymous:anonymous,user_metadata:{role:'admin'}})]);await db.exec('set role authenticated');}
(async()=>{
 if(docker){
  const {Client}=require('../../.artifacts/business-db-runtime/node_modules/pg');
  const {execFileSync}=require('child_process');
  // Keep local runtime credentials in memory; never print status output or URLs.
  let local;
  try { local=JSON.parse(execFileSync('cmd.exe',['/d','/c','npx supabase@latest status --output json'],{cwd:root,encoding:'utf8',stdio:['ignore','pipe','pipe']})); }
  catch { throw Error('Local Supabase status is unavailable'); }
  const url=new URL(local.DB_URL);
  if(!['127.0.0.1','localhost'].includes(url.hostname))throw Error('Only loopback databases are allowed');
  admin=new Client({connectionString:url.toString()});await admin.connect();
  testName='scout_contract_'+crypto.randomBytes(8).toString('hex');
  await admin.query('create database "'+testName+'"');url.pathname='/'+testName;
  const client=new Client({connectionString:url.toString()});await client.connect();
  db={query:(sql,args)=>client.query(sql,args),exec:sql=>client.query(sql),close:()=>client.end()};
 }else{db=new PGlite({extensions:{pgcrypto}});await db.waitReady;}
 if(!docker) await db.exec('create role anon;create role authenticated;create role service_role;');
 await db.exec(`
 create schema auth;create schema extensions;create extension pgcrypto with schema extensions;
 create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 grant usage on schema auth to authenticated,anon;
 create table public.recipes_creator(id uuid primary key,author_id uuid,title text,ingredients jsonb,steps jsonb,tips text);
 alter table public.recipes_creator enable row level security;
 grant select on public.recipes_creator to authenticated;
 create policy own_recipe on public.recipes_creator for select to authenticated using(author_id=auth.uid());
 create table public.membership_plans(code text primary key,is_active boolean);
 create table public.member_entitlements(user_id uuid,plan_code text,status text,valid_until timestamptz,started_at timestamptz);
 insert into public.membership_plans values('free',true),('paid_monthly',true),('paid_annual',true),('business_monthly',true);`);
 const feature=fs.readFileSync(path.join(root,'supabase/migrations/0054_membership_feature_profiles.sql'),'utf8');
 await db.exec(feature);
 await db.exec(`update public.membership_feature_profiles set is_active=true where code='business';insert into public.membership_plan_feature_profiles values('business_monthly','business');`);
 const chef=fs.readFileSync(path.join(root,'supabase/migrations/0037_chef_workspaces.sql'),'utf8');
 await db.exec(chef.match(/create function public[.]chef_number_valid[\s\S]+?\$\$;/)[0]);
 const migration=fs.readFileSync(path.join(root,'supabase/migrations/0062_business_workspaces.sql'),'utf8');
 await db.exec(migration);reports.push('migration compiles with actual membership snapshot and pgcrypto');
 if(process.argv.includes('--samples')) {
  await db.exec('create table public.profiles(id uuid primary key references auth.users,role text);');
  const mfa=fs.readFileSync(path.join(root,'supabase/migrations/0047_admin_mfa.sql'),'utf8');
  await db.exec(mfa.slice(0,mfa.indexOf('DO $migration$')));
  const samples=fs.readFileSync(path.join(root,'supabase/migrations/0063_business_test_campaigns.sql'),'utf8');
  await db.exec(samples);reports.push('business test campaign migration compiles');
  await require('./business_test_campaign_checks.cjs')({db,q,scalar,denied,ok,crypto,fs,root});
 }
 if(process.argv.includes('--menu')) { await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0067_business_menu_lifecycle.sql'),'utf8')); reports.push('menu lifecycle migration compiles'); }
 if(process.argv.includes('--suppliers')) { await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0068_business_suppliers.sql'),'utf8')); reports.push('shared supplier migration compiles'); }
 if(process.argv.includes('--staff')) {
  await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0064_business_member_profiles.sql'),'utf8'));
  reports.push('owner staff profile migration compiles');
 }
 const [owner,buyer,cook,manager,other,owner2]=Array.from({length:6},()=>crypto.randomUUID());
 for(const [i,id] of [owner,buyer,cook,manager,other,owner2].entries())await q('insert into auth.users values($1,$2,now())',[id,`staff${i}@example.test`]);
 for(const id of [owner,owner2])await q("insert into public.member_entitlements values($1,'business_monthly','active',now()+interval '1 month',now()-interval '1 day')",[id]);
 await db.exec('set role anon');await denied('select public.business_create($1,$2)',['No','Anon'],'42501','anonymous RPC execution denied');
 await login(other);await denied('select public.business_create($1,$2)',['No','Free'],'BUSINESS_PLAN','free account cannot create paid team');
 await login(owner,true);await denied('select public.business_create($1,$2)',['No','Anonymous'],'BUSINESS_AUTH','anonymous auth identity rejected');
 await login(owner);const workspace=await scalar('select public.business_create($1,$2)',['Test Kitchen','Owner']);
 const grants={buyer:['recipes.read','purchasing.read','purchasing.write'],cook:['recipes.read','recipes.write','purchasing.read'],manager:['recipes.read','purchasing.read','finance.read','finance.write','purchases.approve']};
 let buyerInvite;
 for(const [id,email,permissions] of [[buyer,'staff1@example.test',grants.buyer],[cook,'staff2@example.test',grants.cook],[manager,'staff3@example.test',grants.manager]]){
 await login(owner);const invite=await scalar('select public.business_invite($1,$2,$3)',[workspace,email,permissions]);
 if(id===buyer){buyerInvite=invite;await denied('select token_hash from public.business_invites',[],'42501','invitation hash is not exposed to owner');await login(other);await denied('select public.business_accept($1,$2)',[invite.token,'Wrong'],'BUSINESS_INVITE_INVALID','wrong email cannot redeem invitation');}
 await login(id);ok(await scalar('select public.business_accept($1,$2)',[invite.token,email])===workspace,'invitation accepted for '+email);
 await denied('select public.business_accept($1,$2)',[invite.token,email],'BUSINESS_INVITE_INVALID','invitation replay blocked for '+email);
 }
 await login(buyer);ok(await scalar('select count(*)::int from public.business_access_events')===0,'staff cannot read owner access audit');await denied('select public.business_member_update($1,$2,$3,true)',[workspace,buyer,grants.manager],'BUSINESS_DENIED','staff cannot self-promote');
 await denied('select public.business_invite($1,$2,$3)',[workspace,'another@example.test',grants.buyer],'BUSINESS_DENIED','staff cannot invite');
 await denied('insert into public.business_members values($1,$2,$3,$4,true,now())',[workspace,other,'Hacked',grants.manager],'42501','direct membership writes denied');
 await login(cook);let recipe=await scalar('select public.business_save_record($1,$2,$3,$4,$5,0)',[workspace,crypto.randomUUID(),'recipe','비빔밥',{ingredients:'밥 120g\n달걀 1개',steps:'익혀 담습니다.',notes:'연구',servings:1}]);
 let need=await scalar('select public.business_request_ingredients($1,$2,$3,$4)',[workspace,recipe.id,recipe.revision,crypto.randomUUID()]);
 const again=await scalar('select public.business_request_ingredients($1,$2,$3,$4)',[workspace,recipe.id,recipe.revision,need.id]);ok(again.id===need.id,'handover retries reuse one purchase draft');
 ok(need.data.lines.every(l=>l.quantity===null && l.unit===''),'cooking handover never assumes purchase units');
 await denied('select public.business_save_record($1,$2,$3,$4,$5,$6)',[workspace,need.id,'purchase',need.title,need.data,need.revision],'BUSINESS_DENIED','cook cannot modify purchase quantities');
 await login(buyer);need.data.supplier='Farm';need.data.lines.forEach(l=>{l.quantity=2;l.unit='kg';l.price=5000;});
 need=await scalar('select public.business_save_record($1,$2,$3,$4,$5,$6)',[workspace,need.id,'purchase',need.title,need.data,need.revision]);
 await denied('select public.business_purchase_transition($1,$2,$3,$4)',[workspace,need.id,need.revision,'approved'],'BUSINESS_TRANSITION','purchaser cannot bypass required approval');
 need=await scalar('select public.business_purchase_transition($1,$2,$3,$4)',[workspace,need.id,need.revision,'review']);
 await denied('select public.business_save_record($1,$2,$3,$4,$5,$6)',[workspace,need.id,'purchase','Changed',need.data,need.revision],'BUSINESS_FROZEN','submitted request is frozen');
 await login(manager);need=await scalar('select public.business_purchase_transition($1,$2,$3,$4)',[workspace,need.id,need.revision,'approved']);
 await denied('select public.business_purchase_transition($1,$2,$3,$4)',[workspace,need.id,need.revision,'sent'],'BUSINESS_TRANSITION','approver cannot impersonate purchaser');
 await login(buyer);await scalar('select public.business_document($1,$2,$3)',[workspace,need.id,need.revision]);reports.push('approved shared document access verified');
 need=await scalar('select public.business_purchase_transition($1,$2,$3,$4)',[workspace,need.id,need.revision,'sent']);
 need=await scalar('select public.business_purchase_transition($1,$2,$3,$4)',[workspace,need.id,need.revision,'received']);
 await denied('select public.business_purchase_transition($1,$2,$3,$4)',[workspace,need.id,need.revision,'draft'],'BUSINESS_TRANSITION','received purchase cannot revert to editable draft');
 await login(manager);let cost=await scalar('select public.business_save_record($1,$2,$3,$4,$5,0)',[workspace,crypto.randomUUID(),'cost','비빔밥 원가',{recipe_id:recipe.id,unit_cost:3000,unit_price:5000,currency:'KRW',notes:''}]);
 let sale=await scalar('select public.business_save_record($1,$2,$3,$4,$5,0)',[workspace,crypto.randomUUID(),'sale','비빔밥 판매',{cost_id:cost.id,date:'2026-09-18',quantity:2,unit_cost:0,unit_price:999999,currency:'USD'}]);
 ok(sale.data.unit_cost===3000 && sale.data.unit_price===5000 && sale.data.currency==='KRW','sale price and cost snapshot come from server cost record');
 cost.data.unit_price=6000;cost=await scalar('select public.business_save_record($1,$2,$3,$4,$5,$6)',[workspace,cost.id,'cost',cost.title,cost.data,cost.revision]);
 await scalar('select public.business_archive_record($1,$2,$3)',[workspace,cost.id,cost.revision]);
 await denied('select public.business_save_record($1,$2,$3,$4,$5,0)',[workspace,crypto.randomUUID(),'sale','Archived price',{cost_id:cost.id,date:'2026-09-18',quantity:1}],'BUSINESS_SOURCE','archived price cannot be used for new sales');
 sale.data.quantity=3;sale=await scalar('select public.business_save_record($1,$2,$3,$4,$5,$6)',[workspace,sale.id,'sale',sale.title,sale.data,sale.revision]);
 ok(sale.data.unit_price===5000,'past sales can be corrected after price is archived and preserve snapshot');
 let total=await scalar('select public.business_sales_totals($1,$2,$3,$4)',[workspace,'2026-09-01','2026-10-01','KRW']);ok(total.revenue===15000 && total.cost===9000,'business sales totals use records and currency');
 await login(buyer);ok(await scalar("select count(*)::int from public.business_records where kind in ('cost','sale')")===0,'purchaser RLS hides financial records');
 await denied('select public.business_sales_totals($1,$2,$3,$4)',[workspace,'2026-09-01','2026-10-01','KRW'],'BUSINESS_DENIED','purchaser cannot call financial aggregate');
 await denied('select public.business_versions($1,$2)',[workspace,cost.id],'BUSINESS_DENIED','purchaser cannot read financial history');
 await login(cook);await denied('select public.business_save_record($1,$2,$3,$4,$5,0)',[workspace,recipe.id,'recipe',recipe.title,recipe.data],'BUSINESS_STALE','stale recipe updates rejected');
 await login(manager);await scalar('select public.business_archive_record($1,$2,$3)',[workspace,sale.id,sale.revision]);total=await scalar('select public.business_sales_totals($1,$2,$3,$4)',[workspace,'2026-09-01','2026-10-01','KRW']);ok(total.revenue===0,'voided sale excluded from totals');
 await login(owner2);const second=await scalar('select public.business_create($1,$2)',['Other Kitchen','Other owner']);
 await denied('select public.business_save_record($1,$2,$3,$4,$5,$6)',[second,recipe.id,'recipe',recipe.title,recipe.data,recipe.revision],'BUSINESS_NOT_FOUND','record ID cannot be reassigned across businesses');
 ok(await scalar('select count(*)::int from public.business_records where workspace_id=$1',[workspace])===0,'other business cannot read shared records');
 await login(owner);await scalar('select public.business_member_update($1,$2,$3,false)',[workspace,buyer,grants.buyer]);
 await login(buyer);ok(await scalar('select count(*)::int from public.business_records where workspace_id=$1',[workspace])===0,'revocation removes record access immediately');
 await denied('select public.business_context($1)',[workspace],'BUSINESS_DENIED','revoked staff cannot read context');
 await denied('select public.business_document($1,$2,$3)',[workspace,need.id,need.revision],'BUSINESS_DENIED','revocation blocks PDF export recheck');
 await login(owner);await denied('select public.business_member_update($1,$2,$3,false)',[workspace,owner,grants.buyer],'BUSINESS_OWNER_FIXED','owner cannot remove their own authority');
 const history=await scalar('select public.business_versions($1,$2)',[workspace,need.id]);ok(history.length===6 && history.every(h=>h.actor_name),'purchase changes have named immutable history');

 await login(owner);
 const expiredInvite=await scalar('select public.business_invite($1,$2,$3)',[workspace,'staff4@example.test',grants.buyer]);
 await db.exec('reset role');await q("update public.business_invites set expires_at=now()-interval '1 second' where id=$1",[expiredInvite.id]);
 await login(other);await denied('select public.business_accept($1,$2)',[expiredInvite.token,'Expired'],'BUSINESS_INVITE_INVALID','expired invitation blocked');
 await login(owner);const revokeInvite=await scalar('select public.business_invite($1,$2,$3)',[workspace,'staff4@example.test',grants.buyer]);await scalar('select public.business_invite_revoke($1)',[revokeInvite.id]);
 await login(other);await denied('select public.business_accept($1,$2)',[revokeInvite.token,'Revoked'],'BUSINESS_INVITE_INVALID','revoked invitation blocked');
 await login(owner);await denied('select public.business_invite($1,$2,$3)',[workspace,'staff4@example.test',['finance.write']],'BUSINESS_INVALID','write grant without read rejected');
 await denied('select public.business_invite($1,$2,$3)',[workspace,'staff4@example.test',['owner']],'BUSINESS_INVALID','invented owner permission rejected');
 const personal=crypto.randomUUID();await db.exec('reset role');await q('insert into public.recipes_creator values($1,$2,$3,$4,$5,$6)',[personal,owner,'개인 레시피',JSON.stringify(['두부 1/2모']),JSON.stringify(['익혀 담기']),'개인 팁']);
 await login(cook);await denied('select public.business_import_recipe($1,$2)',[workspace,personal],'BUSINESS_SOURCE','staff cannot import another user’s personal recipe');
 await login(owner);const imported=await scalar('select public.business_import_recipe($1,$2)',[workspace,personal]);ok(imported.data.ingredients==='두부 1/2모' && imported.data.steps==='익혀 담기','personal recipe copied only by its owner');
 ok(await scalar('select count(*)::int from public.recipes_creator where id=$1',[personal])===1,'shared copy retains personal original');
 let incomplete=await scalar('select public.business_request_ingredients($1,$2,$3,$4)',[workspace,imported.id,imported.revision,crypto.randomUUID()]);
 await denied('select public.business_purchase_transition($1,$2,$3,$4)',[workspace,incomplete.id,incomplete.revision,'review'],'BUSINESS_PURCHASE_INCOMPLETE','missing purchase quantities block submission');
 await denied('select public.business_document($1,$2,$3)',[workspace,incomplete.id,incomplete.revision],'BUSINESS_PURCHASE_INCOMPLETE','missing purchase quantities block PDF output');
 const bad={...imported.data,unit_cost:3};await denied('select public.business_save_record($1,$2,$3,$4,$5,$6)',[workspace,imported.id,'recipe',imported.title,bad,imported.revision],'BUSINESS_INVALID','financial data cannot be hidden in structured recipe fields');
 await denied('select public.business_save_record($1,$2,$3,$4,$5,0)',[workspace,crypto.randomUUID(),'meal','Wrong source',{date:'2026-09-18',servings:2,recipe_ids:[crypto.randomUUID()],notes:''}],'BUSINESS_SOURCE','meal plan cannot link inaccessible source IDs');
 await scalar('select public.business_settings($1,$2,false)',[workspace,'Test Kitchen']);
 incomplete.data.supplier='Farm';incomplete.data.lines.forEach(l=>{l.quantity=1;l.unit='box';});incomplete=await scalar('select public.business_save_record($1,$2,$3,$4,$5,$6)',[workspace,incomplete.id,'purchase',incomplete.title,incomplete.data,incomplete.revision]);
 incomplete=await scalar('select public.business_purchase_transition($1,$2,$3,$4)',[workspace,incomplete.id,incomplete.revision,'approved']);ok(incomplete.status==='approved','owner can disable approval for small teams');
 await denied('select public.business_data_valid($1,$2)',['recipe',{}],'42501','internal validation helper is not executable by members');
 await login(owner);ok(await scalar('select count(*)::int from public.business_access_events where workspace_id=$1',[workspace])>0,'owner can review immutable staff access audit');
 await db.exec('reset role');
 await q("with added as (insert into auth.users(id,email,email_confirmed_at) select gen_random_uuid(),'capacity-'||n||'@example.test',now() from generate_series(1,27) n returning id) insert into public.business_members(workspace_id,user_id,display_name,permissions) select $1,id,'Capacity fixture',array['recipes.read']::text[] from added",[workspace]);
 await login(owner);await denied('select public.business_member_update($1,$2,$3,true)',[workspace,buyer,grants.buyer],'BUSINESS_LIMIT','restoring staff cannot bypass active-member limit');
 await db.exec('reset role');await q("update public.member_entitlements set valid_until=now()-interval '1 hour' where user_id=$1",[owner]);
 await login(manager);ok(await scalar("select count(*)::int from public.business_records where kind='cost'")===0,'expired owner plan blocks shared financial read');
 await denied('select public.business_save_record($1,$2,$3,$4,$5,$6)',[workspace,cost.id,'cost',cost.title,cost.data,cost.revision],'BUSINESS_DENIED','expired owner plan blocks shared financial write');
 if(process.argv.includes('--staff')) await require('./business_member_profile_checks.cjs')({db,q,scalar,denied,ok,login,workspace,owner,buyer,cook,owner2,second,crypto,samples:process.argv.includes('--samples')});
 if(process.argv.includes('--menu')) await require('./business_menu_checks.cjs')({db,q,scalar,denied,ok,login,workspace,owner,buyer,cook,manager,other,owner2,second,crypto});
 if(process.argv.includes('--suppliers')) await require('./business_supplier_checks.cjs')({db,q,scalar,denied,ok,login,workspace,owner,buyer,cook,manager,other,owner2,second,crypto});
 if(process.argv.includes('--inventory')) {
  await db.exec('reset role');
  await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0069_business_inventory.sql'),'utf8'));
  reports.push('inventory migration compiles after legacy purchases');
  await require('./business_inventory_checks.cjs')({db,q,scalar,denied,ok,login,workspace,owner,buyer,cook,manager,other,owner2,second,crypto});
 }
 if(process.argv.includes('--fast')) {
  await db.exec('reset role');
  await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0070_business_menu_fast_purchase.sql'),'utf8'));
  if(process.argv.includes('--meals')) await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0072_business_meal_planning.sql'),'utf8'));
  await require('./business_menu_fast_checks.cjs')({db,q,scalar,denied,ok,login,workspace,owner,buyer,cook,manager,other,owner2,second,crypto});
 }
 if(process.argv.includes('--meals')) {
  await db.exec('reset role');
  await require('./business_meal_checks.cjs')({db,q,scalar,denied,ok,login,workspace,owner,buyer,cook,manager,other,owner2,second,crypto});
 }
 if(process.argv.includes('--coupang')) await require('./coupang_planning_checks.cjs')({db,q,scalar,denied,ok,login,crypto,fs,root,workspace,owner,buyer,cook,other});
 if(process.argv.includes('--live-probe')) {
  if(!process.argv.includes('--fast')) throw Error('Live probe requires --fast');
  await db.exec('reset role;alter table auth.users add column raw_app_meta_data jsonb,add column raw_user_meta_data jsonb;alter table public.member_entitlements add column source text;create unique index probe_entitlement_user on public.member_entitlements(user_id);');
  let sql=fs.readFileSync(path.join(root,'.artifacts/v79-live-probe.sql'),'utf8');
  for(const name of ['OWNER_ID','BUYER_ID','COOK_ID']) sql=sql.replaceAll(name,crypto.randomUUID());
  const output=await db.exec(sql);
  const results=Array.isArray(output)?output:[output];
  const probe=results.find(x=>x?.rows?.[0]?.checks)?.rows[0].checks;
  ok(Array.isArray(probe)&&probe.length>=14&&probe.every(x=>x.ok),'production transaction probe validated on isolated PostgreSQL');
 }
 if(process.argv.includes('--cleanup')) await require('./purchase_cleanup_checks.cjs')({db,q,scalar,denied,ok,login,crypto,fs,root});
 if(process.argv.includes('--management')) await require('./management_lifecycle_checks.cjs')({db,q,scalar,denied,ok,login,crypto,fs,root,workspace,owner,buyer,cook,other});
 if(process.argv.includes('--workflow')) await require('./workflow_continuity_checks.cjs')({db,q,scalar,denied,ok,login,crypto,fs,root,workspace,owner,buyer,other});
 const result={verified:true,...(process.argv.includes('--meals')?{mealMigrationSha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'supabase/migrations/0072_business_meal_planning.sql'))).digest('hex')}:{}),...(process.argv.includes('--fast')?{fastMigrationSha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'supabase/migrations/0070_business_menu_fast_purchase.sql'))).digest('hex')}:{}),...(process.argv.includes('--inventory')?{inventoryMigrationSha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'supabase/migrations/0069_business_inventory.sql'))).digest('hex')}:{}),...(process.argv.includes('--suppliers')?{supplierMigrationSha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'supabase/migrations/0068_business_suppliers.sql'))).digest('hex')}:{}),...(process.argv.includes('--menu')?{menuMigrationSha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'supabase/migrations/0067_business_menu_lifecycle.sql'))).digest('hex')}:{}),engine:docker?'Supabase Docker PostgreSQL 17 + pgcrypto (isolated fixture database)':'PGlite PostgreSQL + pgcrypto',checks:reports.length,checksPassed:reports,sourceSha256:crypto.createHash('sha256').update(migration).digest('hex'),productionWrites:0};fs.writeFileSync(path.join(root,process.argv.includes('--meals') ? (docker?'.artifacts/business-meals-docker-contract.json':'.artifacts/business-meals-contract.json') : process.argv.includes('--fast') ? (docker?'.artifacts/business-menu-fast-docker-contract.json':'.artifacts/business-menu-fast-contract.json') : process.argv.includes('--inventory') ? (process.argv.includes('--staff')?'.artifacts/business-inventory-contract.json':'.artifacts/business-inventory-base-contract.json') : process.argv.includes('--suppliers') ? (docker?'.artifacts/business-suppliers-docker-contract.json':'.artifacts/business-suppliers-contract.json') : process.argv.includes('--menu') ? (docker?'.artifacts/business-menu-docker-contract.json':'.artifacts/business-menu-contract.json') : process.argv.includes('--staff') ? (docker?'.artifacts/business-staff-docker-contract.json':'.artifacts/business-staff-contract.json') : process.argv.includes('--samples') ? (docker?'.artifacts/business-samples-docker-contract.json':'.artifacts/business-samples-contract.json') : (docker?'.artifacts/business-docker-contract.json':'.artifacts/business-db-contract.json')),JSON.stringify(result,null,2));console.log(JSON.stringify({verified:true,checks:reports.length,productionWrites:0}));await close();
})().catch(async e=>{console.error('CONTRACT FAILED: '+e.message);await close();process.exitCode=1;});
