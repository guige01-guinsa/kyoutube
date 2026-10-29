import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {executeJob,safeFailure,validateStandardRenderedVideo} from './story_studio_worker.mjs';
import {researchResponse} from './story_studio_fixture.mjs';
const digest=b=>createHash('sha256').update(b).digest('hex');
test('actual renderer adapter accepts concise recipes and rejects overlong, empty or corrupt files',()=>{
 const video=Buffer.from('validated fixture'),plan={profile:'ko-180-source-v1'};
 const q={sha256:digest(video),audio:true,size:[720,1280],seconds:24,frames:576};
 assert.equal(validateStandardRenderedVideo(plan,video,{video:q}),q);
 for(const change of [{seconds:0,frames:0},{seconds:181,frames:4344},{sha256:'0'.repeat(64)},{audio:false},{frames:575}])
  assert.throws(()=>validateStandardRenderedVideo(plan,video,{video:{...q,...change}}),/standard_render_failed/);
 assert.throws(()=>validateStandardRenderedVideo({profile:'ko-60-v1'},video,{video:q}),/standard_render_failed/);
});
test('bundled demo is the unchanged reviewed generic app guidance crop',async()=>{
 const manifest=JSON.parse(await readFile(new URL('../../assets/story_demos/standard-guide-v1.json',import.meta.url),'utf8'));
 assert.equal(manifest.file,'bibimbap-draft.jpg');assert.equal(manifest.personal_data_removed,true);
 const bytes=await readFile(new URL('../../assets/story_demos/bibimbap-draft.jpg',import.meta.url));
 assert.equal(digest(bytes),manifest.sha256);assert.ok(bytes.length<2000000);
});
test('standard diagnostics preserve safe reasons without leaking provider bodies',()=>{
 assert.equal(safeFailure(new Error('standard_needs_review',{cause:'standard_shorten_script'})),'standard_shorten_script');
 assert.equal(safeFailure(new Error('standard_needs_review',{cause:'private provider response'})),'standard_unknown_failure');
 assert.equal(safeFailure(new Error('standard_demo_not_ready')),'standard_demo_not_ready');
});
const plan=()=>({profile:'ko-60-v1',language:'ko',food:'검사 음식',title:'시험 원고',presenter:'허구 진행자',
 sources:[1,2].map(i=>({id:`source-${i}`,title:`시험${i}`,url:`https://example.com/${i}`,note:'검사용'})),
 scenes:['greeting','food_fact','ingredients','cooking','app_demo','closing'].map(role=>({role,spoken:'검사 문장입니다.',caption:'검사용',visual:'도형',source_ids:['source-1']}))});
function wav() {
 const b=Buffer.alloc(16044);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);
 b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(8000,24);b.writeUInt32LE(16000,28);
 b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(16000,40);
 for(let i=44;i<b.length;i+=2)b.writeInt16LE(2000,i);return b;
}
function setup(stage) {
 const project={id:randomUUID(),food:'검사 음식',presenter:'허구 진행자',plan:plan(),sample:{sha256:digest(wav())},sample_approved_by:randomUUID()};
 const job={id:randomUUID(),lease_token:randomUUID(),kind:stage==='sample'?'render':stage,
  request:{sources_reviewed:true},snapshot:{standard_profile:'ko-60-v1',standard_stage:stage,standard_project_id:project.id,
   project,series:{id:randomUUID()},text_model:'configured-text',image_model:'configured-image'}};
 const calls=[];const io={check:async()=>{},research:async()=>researchResponse,
  chat:async body=>{calls.push(body);return {choices:[{finish_reason:'stop',message:{content:JSON.stringify({title:'시험 원고',
   scenes:plan().scenes.map(({role,...v})=>v)})}}]};},
  standardSpeech:async(_,lang)=>{assert.equal(lang,'ko');calls.push('speech');return wav();},
  standardStoreSample:async()=>calls.push('store-sample'),standardDemo:async()=>{calls.push('demo');return Buffer.from('real-capture');},
  image:async()=>{calls.push('image');return Buffer.from('image');},
  standardRender:async(p,images,audio)=>{assert.equal(images.length,6);assert.equal(audio.length,6);calls.push('render');const video=Buffer.from('video');return {video,quality:{seconds:60,sha256:digest(video)}};},
  store:async()=>calls.push('store-video'),upload:async()=>{calls.push('upload');return 'abcdefghijk';}};
 return {job,io,calls};
}
test('standard draft shares queue but generates no translation editions',async()=>{
 const {job,io,calls}=setup('draft');const result=await executeJob(job,io);
 assert.equal(result.plan.language,'ko');assert.ok(!('translations' in result.plan));
 assert.equal(calls.length,1);assert.equal(calls[0].model,'configured-text');
});
test('sample job buys only one voice and never images or upload',async()=>{
 const {job,io,calls}=setup('sample');const result=await executeJob(job,io);
 assert.deepEqual(calls,['speech','store-sample']);assert.equal(result.path,`${job.id}/sample.wav`);assert.equal(result.seconds,1);
});
test('render rejects a missing capture before any new paid asset call',async()=>{
 const {job,io,calls}=setup('render');io.standardDemo=async()=>{throw new Error('missing');};
 await assert.rejects(executeJob(job,io));assert.deepEqual(calls,[]);
});
test('render uses one real capture, five illustrations, Korean cached voice and no upload',async()=>{
 const {job,io,calls}=setup('render');const result=await executeJob(job,io);
 assert.equal(calls.filter(v=>v==='image').length,5);assert.equal(calls.filter(v=>v==='speech').length,6);
 assert.ok(!calls.includes('upload'));assert.equal(result.language,'ko');assert.equal(result.path,`${job.id}/ko.mp4`);
 assert.ok(Number.isSafeInteger(result.production_ms) && result.production_ms>=0);
 assert.equal(result.voice_metrics.length,6);assert.match(result.plan_hash,/^[0-9a-f]{64}$/);
});
test('unapproved speech sample blocks rendering',async()=>{
 const {job,io,calls}=setup('render');job.snapshot.project.sample_approved_by=null;
 await assert.rejects(executeJob(job,io));assert.deepEqual(calls,[]);
});
test('private upload requires exact preview identity and no generation',async()=>{
 const {job,io,calls}=setup('upload'),video=Buffer.from('approved');
 job.snapshot.project.preview={path:`${randomUUID()}/ko.mp4`,sha256:digest(video)};
 job.request={preview_reviewed:true,sha256:digest(video)};io.load=async()=>video;
 assert.deepEqual(await executeJob(job,io),{youtube_id:'abcdefghijk',privacy:'private'});assert.deepEqual(calls,['upload']);
});
