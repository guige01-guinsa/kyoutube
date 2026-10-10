// Uses real kitchen migrations in an isolated in-memory PostgreSQL instance.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {PGlite}=require('../../.artifacts/business-db-runtime/node_modules/@electric-sql/pglite');
const root=path.resolve(__dirname,'../..'),db=new PGlite(),checks=[];
const q=async(s,a=[]) => (await db.query(s,a)).rows;
const scalar=async(s,a=[]) => Object.values((await q(s,a))[0])[0];
const ok=(v,label)=>{if(!v)throw Error(label);checks.push(label);};
async function denied(s,a,code,label){try{await q(s,a);}catch(e){if(String(e.message).includes(code)||e.code===code){checks.push(label);return;}throw e;}throw Error(label+' unexpectedly accepted');}
async function login(id,anonymous=false){await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({is_anonymous:anonymous})]);await db.exec('set role authenticated');}
const m=n=>fs.readFileSync(path.join(root,'supabase/migrations',n),'utf8');
(async()=>{try{
 await db.exec(`create role anon;create role authenticated;create role service_role;
 create schema auth;create table auth.users(id uuid primary key);create table public.profiles(id uuid primary key references auth.users(id));
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 grant usage on schema auth to authenticated,anon;`);
 for(const name of ['0007_kitchen_foundation.sql','0014_kitchen_shopping_completion_atomic.sql','0015_fix_kitchen_rpc_ledger_aliases.sql','0016_fix_kitchen_item_normalized_name.sql','0017_fix_kitchen_completion_canonical_name.sql','0018_kitchen_shopping_item_review.sql','0019_reject_direct_shopping_status_write.sql','0029_expand_kitchen_shopping_unit_guards.sql','0051_shopping_assistant.sql','0058_fix_shopping_create_units.sql','0075_manual_shopping_lists.sql']) await db.exec(m(name));
 checks.push('Actual kitchen, purchase and manual migrations compile together');
 const owner=crypto.randomUUID(),other=crypto.randomUUID();
 for(const id of [owner,other]) {await q('insert into auth.users values($1)',[id]);await q('insert into public.profiles values($1)',[id]);}
 await login(owner);
 const old=await q('select * from public.create_kitchen_shopping_list($1,$2,$3)',['user:fixture',[{name:'carrot',ingredient_text:'carrot 1 kg',quantity:1,unit:'kg'}],crypto.randomUUID()]);
 const oldSnapshot=await scalar('select to_jsonb(l) from public.kitchen_shopping_lists l where id=$1',[old[0].list_id]);
 const items=[{name:'carrot',quantity:500,unit:'g',specification:''},{name:'soy sauce',quantity:2,unit:'bottle',specification:'1L per bottle'}];
 const key=crypto.randomUUID(),create=(data=items,k=key)=>scalar('select public.create_manual_shopping_list($1,$2)',[data,k]);
 const id=await create();ok(id!==old[0].list_id,'Manual list does not overwrite recipe list');
 ok(await create()===id,'Same request is replayed without duplicate rows');
 ok(await scalar('select count(*)::int from public.kitchen_shopping_items where list_id=$1',[id])===2,'Each planned ingredient is inserted once');
 const rows=await q('select * from public.kitchen_shopping_items where list_id=$1 order by name',[id]);
 ok(rows.every(r=>r.status==='pending'&&!r.is_checked&&r.review_status==='confirmed'&&r.revision===0),'Planned ingredients do not count as purchased');
 ok(rows[1].purchase_specification==='1L per bottle'&&rows[1].unit==='bottle'&&Number(rows[1].quantity)===2,'Package specification and quantity are preserved without guessed conversion');
 ok(await scalar('select source_recipe_id is null from public.kitchen_shopping_lists where id=$1',[id]),'No fake recipe reference');
 ok(await scalar('select count(*)::int from public.kitchen_ingredients')===0&&await scalar('select count(*)::int from public.shopping_purchase_records')===0,'Creating list does not modify stock or purchase records');
 ok(JSON.stringify(await scalar('select to_jsonb(l) from public.kitchen_shopping_lists l where id=$1',[old[0].list_id]))===JSON.stringify(oldSnapshot),'Existing recipe list unchanged');
 await denied('select public.create_manual_shopping_list($1,$2)',[[{...items[0],quantity:800}],key],'MANUAL_KEY_CONFLICT','Changed payload cannot reuse request key');
 for(const bad of [[],[{...items[0],quantity:0}],[{...items[0],quantity:-1}],[{...items[0],quantity:0.0000001}],[{...items[0],unit:'cup'}],[{...items[0],owner_id:other}],[{...items[0],quantity:null}],[{...items[0],name:''}],[{...items[0],specification:'x'.repeat(121)}],Array(101).fill(items[0]),[items[0],{...items[1],unit:'bad'}]])
   await denied('select public.create_manual_shopping_list($1,$2)',[bad,crypto.randomUUID()],'MANUAL_INVALID','Invalid input rejected atomically '+checks.length);
 ok(await scalar('select count(*)::int from public.kitchen_shopping_lists')===2,'Failed submissions leave no partial lists');
 await denied('update public.kitchen_shopping_items set purchase_specification=$1 where id=$2',['changed',rows[1].id],'MANUAL_SPECIFICATION_IMMUTABLE','Specification cannot silently change after review');
 await denied('delete from public.manual_shopping_submissions where request_key=$1',[key],'42501','Client cannot delete replay protection');
 await login(other);ok(await scalar('select count(*)::int from public.manual_shopping_submissions')===0,'Submission history is owner scoped');
 const otherId=await create();ok(otherId!==id,'Request key is scoped to account');
 await login(owner,true);await denied('select public.create_manual_shopping_list($1,$2)',[items,crypto.randomUUID()],'MANUAL_AUTH_REQUIRED','Anonymous user cannot submit');
 await login(owner);
 const request={name:'carrot',product_name:'',quantity:500,unit:'g',currency:'KRW',items:[{id:rows[0].id,revision:0,quantity:500}]};
 const purchase=await scalar('select public.record_shopping_purchase($1,$2)',[crypto.randomUUID(),request]);
 ok(!!purchase,'Manual ingredient uses real existing purchase recording');
 await scalar('select public.set_kitchen_shopping_item_status($1,$2,$3)',[rows[1].id,'skipped',0]);
 const completion=await q('select * from public.complete_kitchen_shopping_list($1,$2)',[id,crypto.randomUUID()]);
 ok(completion[0].status==='completed','Manual list uses existing completion flow');
 ok(Number(await scalar("select quantity from public.kitchen_ingredients where normalized_name='carrot'"))===500,'Only purchased amount enters stock on completion');
 await q('select * from public.complete_kitchen_shopping_list($1,$2)',[id,crypto.randomUUID()]);
 ok(Number(await scalar("select quantity from public.kitchen_ingredients where normalized_name='carrot'"))===500,'Repeat completion never doubles stock');
 ok(await create()===id,'Replay does not recreate even a completed list');
 await db.exec('reset role');await q('delete from public.kitchen_shopping_lists where id=$1',[otherId]);await login(other);
 await denied('select public.create_manual_shopping_list($1,$2)',[items,key],'MANUAL_LIST_REMOVED','Deleted list cannot be recreated by stale replay');
 await db.exec('set role anon');await denied('select public.create_manual_shopping_list($1,$2)',[items,key],'42501','Public RPC execution denied');
 fs.writeFileSync(path.join(root,'.artifacts/manual-shopping-db.json'),JSON.stringify({verified:true,productionWrites:0,checks},null,2));console.log(JSON.stringify({passed:checks.length,verified:true}));
}finally{await db.close();}})().catch(e=>{console.error(e.message);process.exitCode=1;});
