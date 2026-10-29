import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {makeRecipePlan,recipePlanHash} from './story_studio_recipe.mjs';
import {executeStandardJob} from './story_studio_standard_worker.mjs';
const digest=b=>createHash('sha256').update(b).digest('hex');
function wav(seconds=6) {
 const size=seconds*16000;
 const b=Buffer.alloc(size+44);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);
 b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(8000,24);b.writeUInt32LE(16000,28);
 b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(size,40);
 for(let i=44;i<b.length;i+=2)b.writeInt16LE(2000,i);return b;
}
function setup(stage='render') {
 const plan=makeRecipePlan({food:'검사 음식',presenter:'진행자',intro:'안녕하세요.',outro:'원본을 확인해 주세요.',
  recipe:{url:'https://www.youtube.com/watch?v=abcdefghijk',title:'검사 영상',channel:'검사',servings:'2인분',ingredients:Array.from({length:12},(_,i)=>`검사 재료${i} 20g`),steps:Array.from({length:9},(_,i)=>`원본 ${i+1}단계입니다.`)}});
 const project={id:randomUUID(),plan,sample_approved_by:randomUUID(),sample:{plan_hash:recipePlanHash(plan),sha256:digest(wav())}};
 const job={id:randomUUID(),created_at:new Date(Date.now()-1000).toISOString(),request:{sources_reviewed:true},snapshot:{standard_profile:'ko-60-v1',standard_stage:stage,standard_project_id:project.id,project}};
 const calls=[];const io={check:async()=>{},standardDemo:async()=>Buffer.from('demo'),standardSpeech:async s=>{calls.push(s);return wav(calls.length===1?6:10);},
  standardStoreSample:async()=>calls.push('sample'),
  standardRender:async(p,panels,audio)=>{assert.equal(audio.length,p.scenes.length);const video=Buffer.from('video');return {video,quality:{seconds:162.667,sha256:digest(video)}};},
  store:async()=>calls.push('store'),image:async()=>{throw new Error('no image generation');}};
 return {job,io,calls};
}
test('source render uses exact script, zero new illustrations, cached voice and queue-inclusive timing',async()=>{
 const {job,io,calls}=setup();const r=await executeStandardJob(job,io);
 assert.deepEqual(calls.slice(0,-1),job.snapshot.project.plan.scenes.map(s=>s.spoken));
 assert.equal(r.new_illustrations,0);assert.equal(r.recipe_preserved,true);assert.ok(r.queue_wait_ms>=1000);assert.equal(r.target_met,true);
});
test('source sample still costs only one voice and requires no images',async()=>{
 const {job,io,calls}=setup('sample');const r=await executeStandardJob(job,io);
 assert.equal(calls.length,2);assert.equal(r.seconds,6);assert.equal(calls[1],'sample');
});
test('source mutation, source review missing and changed sample stop before new speech',async()=>{
 for(const mutation of [j=>j.request.sources_reviewed=false,j=>j.snapshot.project.plan.scenes[1].spoken+='설탕 10g',j=>j.snapshot.project.sample.plan_hash='0'.repeat(64)]) {
  const {job,io,calls}=setup();mutation(job);await assert.rejects(executeStandardJob(job,io));assert.equal(calls.length,0);
 }
 const {job,io,calls}=setup();job.snapshot.project.sample.sha256='0'.repeat(64);
 await assert.rejects(executeStandardJob(job,io),/standard_sample_changed/);assert.equal(calls.length,1);
});
test('queue delay above five minutes is not reported as on-target',async()=>{
 const {job,io}=setup();job.created_at=new Date(Date.now()-310000).toISOString();
 assert.equal((await executeStandardJob(job,io)).target_met,false);
});

test('explicit existing voice consent needs no sample and never asserts listening',async()=>{
 const {job,io,calls}=setup();job.request.voice_use_confirmed=true;
 job.snapshot.project.sample={review_mode:'existing_voice_without_sample',listened:false};
 const result=await executeStandardJob(job,io);assert.equal(result.language,'ko');assert.ok(calls.length>1);
 const denied=setup();denied.job.snapshot.project.sample={review_mode:'existing_voice_without_sample',listened:false};
 await assert.rejects(executeStandardJob(denied.job,denied.io),/standard_sample_listening_required/);
 assert.equal(denied.calls.length,0);
});

test('five-minute target includes script processing and both queues but not human review',async()=>{
 const {job,io}=setup();job.snapshot.project.source_video_url=job.snapshot.project.plan.recipe.url;
 job.snapshot.project.source_receipt={automation_ms:305000};
 const result=await executeStandardJob(job,io);assert.equal(result.target_met,false);assert.ok(result.total_elapsed_ms>=306000);
 const missing=setup();missing.job.snapshot.project.source_video_url=job.snapshot.project.plan.recipe.url;
 assert.equal((await executeStandardJob(missing.job,missing.io)).target_met,null);
});
