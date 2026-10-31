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
  '20261025153000_speech_anon_guard_story_studio.sql','20261028180000_standard_pilot_story_studio.sql',
  '20261029120000_source_recipe_studio.sql','20261030000000_short_recipe_story_studio.sql'])
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
// New source profile shares the same access, quota and private publication gates.
await db.exec('reset role; update story_studio_config set daily_usd=2');
await role('authenticated');
const sourceId=randomUUID(),source={id:sourceId,series_id:series,food:'원본 음식',presenter:'진행자',intro:'안녕하세요.',outro:'원본을 확인하세요.',source_verified:true,
 recipe:{url:'https://www.youtube.com/watch?v=abcdefghijk',title:'합성 검사',channel:'시험',servings:'2인분',ingredients:['검사 재료 200g','간장 2큰술(20g)','후추 약간'],steps:['재료를 순서대로 섞습니다.','팬에서 충분히 익힙니다.']}};
await assert.rejects(call('import_recipe',{...source,source_verified:false}),/STORY_SOURCES_REQUIRED/);
await call('import_recipe',source);await call('import_recipe',source);
let sx=(await call('overview')).projects.find(p=>p.id===sourceId);
const {makeRecipePlan}=await import('./story_studio_recipe.mjs');
assert.deepEqual(sx.plan,makeRecipePlan(source));
const bad=structuredClone(sx.plan);bad.scenes[1].spoken+=' 설탕 50g.';
await assert.rejects(call('save_plan',{project_id:sourceId,revision:sx.revision,plan:bad}),/STORY_INVALID/);
const sr={...req('sample'),project_id:sourceId,revision:sx.revision};await call('sample',sr);
await role('service_role');let sj=await work('claim');
await work('complete',{id:sj.id,token:sj.lease_token,result:{path:`${sj.id}/sample.wav`,sha256:'d'.repeat(64),seconds:5}});
await role('authenticated');sx=(await call('overview')).projects.find(p=>p.id===sourceId);
await call('approve_sample',{project_id:sourceId,revision:sx.revision,sha256:'d'.repeat(64),listened:true});
sx=(await call('overview')).projects.find(p=>p.id===sourceId);
await call('render',{...req('render'),project_id:sourceId,revision:sx.revision});
await role('service_role');sj=await work('claim');
const completion={id:sj.id,token:sj.lease_token,result:{path:`${sj.id}/ko.mp4`,sha256:'e'.repeat(64),seconds:180,language:'ko'}};
await assert.rejects(work('complete',{...completion,result:{...completion.result,seconds:181}}),/STORY_INVALID/);
await assert.rejects(work('complete',{...completion,result:{...completion.result,seconds:0}}),/STORY_INVALID/);
await work('complete',{...completion,result:{...completion.result,seconds:20}});
await role('authenticated');assert.equal((await call('overview')).projects.find(p=>p.id===sourceId).status,'preview');
await role('authenticated',ordinary);await assert.rejects(call('import_recipe',{...source,id:randomUUID()}),/marketing_admin_required/);
console.log('Source recipe DB: original amounts, JS/SQL agreement, no duplicate import, access and 180s bound passed.');
// URL-only creation and one-step render retain the old cost and source gates.
await role('authenticated');
const autoId=randomUUID(),auto={id:autoId,series_id:series,food:'원본 음식',presenter:'진행자',source_url:source.recipe.url};
await call('create_source',auto);await call('create_source',auto);
await assert.rejects(call('create_source',{...auto,source_url:'https://www.youtube.com/watch?v=xxxxxxxxxxx'}),/STORY_CONFLICT/);
let ax=(await call('overview')).projects.find(p=>p.id===autoId);
assert.equal(ax.source_video_url,source.recipe.url);
await call('save_plan',{project_id:autoId,revision:ax.revision,plan:makeRecipePlan(source)});
ax=(await call('overview')).projects.find(p=>p.id===autoId);
const fast={id:randomUUID(),project_id:autoId,revision:ax.revision,quote_revision:1,cost_confirmed:true,sources_reviewed:true,voice_use_confirmed:true};
await assert.rejects(call('render_recipe',{...fast,cost_confirmed:false}),/STORY_COST_CONFIRMATION_REQUIRED/);
assert.equal((await call('overview')).projects.find(p=>p.id===autoId).status,'draft');
await assert.rejects(call('render_recipe',{...fast,voice_use_confirmed:false}),/STORY_SOURCES_REQUIRED/);
await call('render_recipe',fast);await call('render_recipe',fast);
const dispatch=async id=>(await db.query('select story_request_dispatch($1::uuid) as ok',[id])).rows[0].ok;
await role('authenticated',ordinary);await assert.rejects(dispatch(fast.id),/marketing_admin_required/);
await role('authenticated',admin,'aal1');await assert.rejects(dispatch(fast.id),/ADMIN_MFA_REQUIRED/);
await role('authenticated');assert.equal(await dispatch(randomUUID()),false);
assert.equal(await dispatch(fast.id),true);assert.equal(await dispatch(fast.id),false);
await assert.rejects(db.query('select * from story_recipe_sources'),/permission denied/);
await role('service_role');const fastJob=await work('claim');assert.equal(fastJob.id,fast.id);
assert.equal(fastJob.snapshot.project.sample.listened,false);
assert.equal(fastJob.snapshot.project.sample.review_mode,'existing_voice_without_sample');
await role('authenticated');assert.equal(await dispatch(fast.id),false);
console.log('Automatic source and render: idempotence, consent, cost rollback, private cache and single authorized dispatch passed.');
// A changed source remains a draft for review, never a fabricated approval.
await role('service_role');await work('fail',{id:fastJob.id,token:fastJob.lease_token});
await role('authenticated');
const fallbackId=randomUUID();await call('create_source',{...auto,id:fallbackId});
let fx=(await call('overview')).projects.find(p=>p.id===fallbackId);
await call('draft',{id:randomUUID(),project_id:fallbackId,revision:fx.revision,quote_revision:1,cost_confirmed:true});
await role('service_role');const fallbackJob=await work('claim');
assert.equal(fallbackJob.snapshot.standard_project_id,fallbackId);
const selectedUrl='https://www.youtube.com/watch?v=12345678901';
const selectedPlan=makeRecipePlan({...source,recipe:{...source.recipe,url:selectedUrl}});
const receipt={status:'human_source_review_required',selection:{requested_url:source.recipe.url,selected_url:selectedUrl,
 reason:'recipe_source_external_required',checked_candidates:3,method:'youtube_description_v1',requires_review:true}};
await work('complete',{id:fallbackJob.id,token:fallbackJob.lease_token,result:{plan:selectedPlan,source_receipt:receipt}});
await role('authenticated');fx=(await call('overview')).projects.find(p=>p.id===fallbackId);
assert.equal(fx.status,'draft');assert.equal(fx.source_video_url,source.recipe.url);
assert.equal(fx.plan.recipe.url,selectedUrl);assert.deepEqual(fx.source_receipt,receipt);
assert.equal(fx.sample_approved_by,null);assert.equal(fx.preview,null);
console.log('Alternative source DB: selected recipe and original request retained, human review required, no voice or upload approval.');
// Opt-in render and private upload share a runner while retaining old contracts.
await db.exec('reset role');
await db.exec(await readFile(new URL('../../supabase/migrations/20261031120000_fast_private_story_studio.sql',import.meta.url),'utf8'));
await db.exec("update story_jobs set created_at=now()-interval '2 days'; update story_studio_config set daily_usd=50,daily_jobs=20");
const pipelineProject=async()=>{
 await role('authenticated');const id=randomUUID();await call('import_recipe',{...source,id});
 return (await call('overview')).projects.find(x=>x.id===id);
};
const pipelineRequest=x=>({...req('render'),project_id:x.id,revision:x.revision,private_upload_confirmed:true,voice_use_confirmed:true,sources_reviewed:true});
const inspectPipeline=async(sql,args=[])=>{await db.exec('reset role');try{return await db.query(sql,args);}finally{await role('service_role');}};
let px=await pipelineProject(),pr=pipelineRequest(px);
await assert.rejects(call('fast_recipe',pr),/STORY_FAST_NOT_READY/);
await db.exec('reset role; update story_studio_config set fast_recipe_enabled=true');await role('authenticated');
await assert.rejects(call('fast_recipe',{...pr,private_upload_confirmed:false}),/STORY_PRIVATE_UPLOAD_CONFIRMATION_REQUIRED/);
await role('authenticated',ordinary);await assert.rejects(call('fast_recipe',pr),/marketing_admin_required/);
await role('authenticated',admin,'aal1');await assert.rejects(call('fast_recipe',pr),/ADMIN_MFA_REQUIRED/);
await role('authenticated');
const unrelated=await pipelineProject(),unrelatedRequest={...req('sample'),project_id:unrelated.id,revision:unrelated.revision};
await call('sample',unrelatedRequest);
await call('fast_recipe',pr);await call('fast_recipe',pr);
await role('service_role');assert.equal(await work('claim',{job_id:randomUUID()}),null);
let pj=await work('claim',{job_id:pr.id});assert.equal(pj.id,pr.id);
await db.exec('reset role; update story_studio_config set fast_recipe_enabled=false');await role('service_role');
await assert.rejects(work('check',{id:pj.id,token:pj.lease_token}),/STORY_FAST_NOT_READY/);
await db.exec('reset role; update story_studio_config set fast_recipe_enabled=true');await role('service_role');
const pictureResult=j=>({path:`${j.id}/ko.mp4`,sha256:'f'.repeat(64),seconds:90,language:'ko',recipe_preserved:true,
 voice_profile:'fictional-girl-8-ko-v1',visuals:{profile:'recipe-sketch-v2',scene_count:j.snapshot.project.plan.scenes.length,
 verified_frames:j.snapshot.project.plan.scenes.length,min_ink_fraction:.02}});
const finished=await work('complete',{id:pj.id,token:pj.lease_token,result:pictureResult(pj)});
assert.match(finished.next_job_id,/^[a-f0-9-]{36}$/);
let child=(await inspectPipeline('select * from story_jobs where pipeline_parent_id=$1',[pj.id])).rows[0];
assert.equal(child.reserved_usd,'0.0000');assert.equal(child.request.preview_reviewed,undefined);
assert.equal(child.request.private_upload_confirmed,true);assert.equal(child.pipeline_parent_id,pj.id);
assert.equal((await inspectPipeline('select status from story_jobs where id=$1',[unrelatedRequest.id])).rows[0].status,'queued');
const cj=await work('claim',{job_id:child.id});assert.equal(cj.id,child.id);
await assert.rejects(work('complete',{id:cj.id,token:cj.lease_token,result:{youtube_id:'abcdefghijk',privacy:'public'}}),/STORY_INVALID/);
await work('complete',{id:cj.id,token:cj.lease_token,result:{youtube_id:'abcdefghijk',privacy:'private'}});
await role('authenticated');px=(await call('overview')).projects.find(x=>x.id===px.id);
assert.equal(px.status,'uploaded');assert.equal(px.preview.target_ms,180000);assert.equal(px.preview.target_met,true);
assert.equal(px.preview.timing_scope,'approved_request_to_private_upload');assert.ok(px.preview.end_to_end_ms>=0);
await role('service_role');await assert.rejects(work('complete',{id:cj.id,token:cj.lease_token,result:{youtube_id:'abcdefghijk',privacy:'private'}}),/STORY_LEASE_LOST/);
assert.equal((await inspectPipeline('select count(*) n from story_jobs where pipeline_parent_id=$1',[pj.id])).rows[0].n,1);
const old=await work('claim',{job_id:unrelatedRequest.id});await work('fail',{id:old.id,token:old.lease_token});
// Queue/start delay is included; a fast renderer cannot turn a missed SLA green.
px=await pipelineProject();pr=pipelineRequest(px);await call('fast_recipe',pr);
await db.exec('reset role');await db.query("update story_jobs set created_at=now()-interval '181 seconds' where id=$1",[pr.id]);
await role('service_role');pj=await work('claim',{job_id:pr.id});
const next=await work('complete',{id:pj.id,token:pj.lease_token,result:pictureResult(pj)});
child=await work('claim',{job_id:next.next_job_id});await work('complete',{id:child.id,token:child.lease_token,result:{youtube_id:'klmnopqrstu',privacy:'private'}});
await role('authenticated');px=(await call('overview')).projects.find(x=>x.id===px.id);
assert.equal(px.preview.target_met,false);assert.ok(px.preview.end_to_end_ms>=181000);
// At or above three minutes requires a human decision, never automatic upload.
px=await pipelineProject();pr=pipelineRequest(px);await call('fast_recipe',pr);
await role('service_role');pj=await work('claim',{job_id:pr.id});
const held=await work('complete',{id:pj.id,token:pj.lease_token,result:{...pictureResult(pj),seconds:180}});
assert.equal(held.next_job_id,undefined);assert.equal(held.pipeline_state,'duration_review_required');
assert.equal((await inspectPipeline('select count(*) n from story_jobs where pipeline_parent_id=$1',[pj.id])).rows[0].n,0);
await role('authenticated');await assert.rejects(rpc('story_studio_work_before_fast','heartbeat',{}),/permission denied/);
console.log('Fast pipeline DB: explicit MFA consent, target-only leases, private-only followup, no duplicate upload, queue-inclusive 180s timing and duration review passed.');
await db.close();
