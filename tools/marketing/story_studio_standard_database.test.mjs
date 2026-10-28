// Isolated real PostgreSQL-compatible tests; never touches live Supabase.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.env.MARKETING_PGLITE_PATH).href);
const db=new PGlite(),admin=randomUUID(),ordinary=randomUUID(),series=randomUUID(),project=randomUUID();
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema auth; create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
grant usage on schema auth to authenticated;
create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,metadata jsonb);
alter table storage.objects enable row level security; grant usage on schema storage to authenticated; grant select on storage.objects to authenticated;
insert into auth.users values('${admin}'),('${ordinary}');`);
for(const name of ['20261007053241_marketing_automation.sql','20261023130000_story_studio.sql',
  '20261024180000_korean_reedit_story_studio.sql','20261025150000_speech_cache_story_studio.sql',
  '20261025153000_speech_anon_guard_story_studio.sql','20261028180000_standard_pilot_story_studio.sql'])
  await db.exec(await readFile(new URL(`../../supabase/migrations/${name}`,import.meta.url),'utf8'));
await db.query('insert into marketing_admins values($1)',[admin]);
const role=async(name,user=admin,aal='aal2')=>db.exec(`reset role; set role ${name}; select set_config('request.jwt.claim.sub','${user}',false); select set_config('request.jwt.claims','{"aal":"${aal}"}',false);`);
const rpc=async(fn,action,p={})=>(await db.query(`select ${fn}($1,$2::jsonb) as v`,[action,JSON.stringify(p)])).rows[0].v;
const call=(action,p)=>rpc('story_standard',action,p);
const work=(action,p)=>rpc('story_studio_work',action,p);
const current=async()=>(await call('overview')).projects.find(x=>x.id===project);
await role('anon');await assert.rejects(call('overview'),/permission denied/);
await role('authenticated',ordinary);await assert.rejects(call('overview'),/marketing_admin_required/);
await role('authenticated',admin,'aal1');await assert.rejects(call('overview'),/ADMIN_MFA_REQUIRED/);
await role('authenticated');await assert.rejects(db.query('select * from story_standard_projects'),/permission denied/);
await assert.rejects(work('claim'),/permission denied/);
await assert.rejects(rpc('story_studio_work_before_standard','claim'),/permission denied/);
await rpc('story_studio','create_series',{id:series,title:'검사 시리즈',language:'ko',bible:'검사용 인물'});
const creation={id:project,series_id:series,food:'검사 음식',presenter:'허구 진행자'};
await call('create',creation);await call('create',creation);
await assert.rejects(call('create',{...creation,food:'다른 음식'}),/STORY_CONFLICT/);
const plan={profile:'ko-60-v1',language:'ko',food:'검사 음식',title:'검사 원고',presenter:'허구 진행자',
 sources:[{id:'one',title:'검사1',url:'https://example.com/one',note:'검사용'},
  {id:'two',title:'검사2',url:'https://example.org/two',note:'검사용'}],
 scenes:['greeting','food_fact','ingredients','cooking','app_demo','closing'].map(role=>({role,spoken:'검사용 한국어입니다.',caption:'시험 장면',visual:'검사용 도형',source_ids:['one']}))};
for(const invalid of [{...plan,extra:true},{...plan,title:12},
 {...plan,scenes:plan.scenes.map((s,i)=>i===0?{...s,spoken:'English only'}:s)},
 {...plan,scenes:plan.scenes.map((s,i)=>i===0?{...s,source_ids:['one','one']}:s)}]) {
 await assert.rejects(call('save_plan',{project_id:project,revision:1,plan:invalid}),/STORY_INVALID/);
}
await call('save_plan',{project_id:project,revision:1,plan});
let x=await current();assert.equal(x.status,'draft');
const req=(stage,row=x)=>({id:randomUUID(),project_id:project,revision:row.revision,quote_revision:1,cost_confirmed:true,sources_reviewed:true});
await assert.rejects(call('sample',req('sample')),/STORY_NOT_READY/);
await db.exec("reset role; update story_studio_config set enabled=true,standard_enabled=true,text_model='text',image_model='image',draft_usd=.1,sample_usd=.1,render_usd=.2,improve_usd=.1,usd_krw=1800,daily_usd=2,daily_jobs=20");
await role('service_role');await work('heartbeat',{text_model:'text',image_model:'image',standard_profile:'ko-60-v1'});
await role('authenticated');
await assert.rejects(call('sample',{...req('sample'),cost_confirmed:false}),/STORY_COST_CONFIRMATION_REQUIRED/);
await assert.rejects(call('sample',{...req('sample'),quote_revision:9}),/STORY_QUOTE_CHANGED/);
await assert.rejects(call('sample',{...req('sample'),sources_reviewed:false}),/STORY_SOURCES_REQUIRED/);
const sample=req('sample');await call('sample',sample);await call('sample',sample);
await assert.rejects(call('sample',{...sample,sources_reviewed:false}),/STORY_CONFLICT/);
await role('service_role');let job=await work('claim');assert.equal(job.id,sample.id);assert.equal(await work('claim'),null);
const lease={id:job.id,token:job.lease_token};
const checkpoint=(action,p)=>rpc('story_standard_checkpoint',action,{...lease,...p});
let cache=await checkpoint('reserve',{key:'a'.repeat(64)});assert.equal(cache.can_generate,true);
assert.equal((await checkpoint('reserve',{key:'a'.repeat(64)})).can_generate,false);
await assert.rejects(checkpoint('commit',{key:'a'.repeat(64),bytes:4000,sha256:'b'.repeat(64)}),/STORY_INVALID/);
await db.exec('reset role');await db.query("insert into storage.objects(bucket_id,name,metadata) values('story-standard-samples',$1,'{\"size\":4000}')",[cache.path]);
await role('service_role');await checkpoint('commit',{key:'a'.repeat(64),bytes:4000,sha256:'b'.repeat(64)});
assert.equal((await checkpoint('reserve',{key:'a'.repeat(64)})).status,'ready');
await assert.rejects(work('complete',{...lease,result:{path:`${job.id}/sample.wav`,sha256:'b'.repeat(64),seconds:10}}),/STORY_INVALID/);
await work('complete',{...lease,result:{path:`${job.id}/sample.wav`,sha256:'b'.repeat(64),seconds:7}});
await role('authenticated');x=await current();assert.equal(x.status,'sample_review');
await assert.rejects(call('render',req('render')),/STORY_SAMPLE_REQUIRED/);
await assert.rejects(call('approve_sample',{project_id:project,revision:x.revision,sha256:'a'.repeat(64),listened:true}),/STORY_SAMPLE_REQUIRED/);
await call('approve_sample',{project_id:project,revision:x.revision,sha256:'b'.repeat(64),listened:true});
x=await current();await assert.rejects(call('render',req('render')),/STORY_DEMO_REQUIRED/);
await role('service_role');await work('heartbeat',{text_model:'text',image_model:'image',standard_profile:'ko-60-v1',standard_capture_ready:true});
await role('authenticated');const render=req('render');await call('render',render);
await role('service_role');job=await work('claim');
assert.equal(job.snapshot.project.sample_approved_by,admin);
const reused=await rpc('story_standard_checkpoint','reserve',{id:job.id,token:job.lease_token,key:'a'.repeat(64)});
assert.equal(reused.status,'ready');assert.equal(reused.can_generate,false);assert.equal(reused.sha256,'b'.repeat(64));
await assert.rejects(work('complete',{id:job.id,token:job.lease_token,result:{path:`${job.id}/ko.mp4`,sha256:'c'.repeat(64),seconds:61,language:'ko'}}),/STORY_INVALID/);
await work('complete',{id:job.id,token:job.lease_token,result:{path:`${job.id}/ko.mp4`,sha256:'c'.repeat(64),seconds:60,language:'ko'}});
await role('authenticated');x=await current();assert.equal(x.status,'preview');
await assert.rejects(call('upload',{...req('upload'),preview_reviewed:false,sha256:'c'.repeat(64)}),/STORY_PREVIEW_REQUIRED/);
const upload={...req('upload'),preview_reviewed:true,sha256:'c'.repeat(64)};await call('upload',upload);await call('upload',upload);
await role('service_role');job=await work('claim');
await assert.rejects(work('complete',{id:job.id,token:job.lease_token,result:{privacy:'public',youtube_id:'abcdefghijk'}}),/STORY_INVALID/);
await work('complete',{id:job.id,token:job.lease_token,result:{privacy:'private',youtube_id:'abcdefghijk'}});
await role('authenticated');assert.equal((await current()).status,'uploaded');
assert.equal((await call('overview')).jobs.length,3);
// Shared budgets see these jobs too; legacy queue cannot spend outside pilot totals.
await db.exec('reset role; update story_studio_config set daily_usd=.3');
await role('authenticated');await assert.rejects(rpc('story_studio','improve',{id:randomUUID(),series_id:series,revision:1,quote_revision:1,cost_confirmed:true,feedback:'검사'}),/STORY_BUDGET_LIMIT/);
await role('authenticated',ordinary);assert.equal((await db.query("select * from storage.objects where bucket_id='story-standard-samples'")).rows.length,0);
await role('authenticated',admin,'aal1');assert.equal((await db.query("select * from storage.objects where bucket_id='story-standard-samples'")).rows.length,0);
await role('authenticated');assert.equal((await db.query("select * from storage.objects where bucket_id='story-standard-samples'")).rows.length,1);
console.log('Standard pilot DB: access, shared reservations, idempotency, cache, listening, exact duration and private publication passed.');
await db.close();
