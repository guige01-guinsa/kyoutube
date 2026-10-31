import test from 'node:test';
import assert from 'node:assert/strict';
import {runApprovedPipeline} from './story_studio_pipeline.mjs';
const render='11111111-1111-4111-8111-111111111111',upload='22222222-2222-4222-8222-222222222222';
test('one runner follows only the server-created approved private upload',async()=>{
 const targets=[];
 const result=await runApprovedPipeline({STORY_STUDIO_JOB_ID:render},async env=>{
  targets.push(env.STORY_STUDIO_JOB_ID);
  return targets.length===1?{completed:render,kind:'render',auto_private_upload:true,next_job_id:upload}:{completed:upload,kind:'upload'};
 });
 assert.deepEqual(targets,[render,upload]);assert.deepEqual(result.pipeline_jobs,[render,upload]);
});
test('no opt-in, invalid target, cycles and third jobs cannot drain the queue',async()=>{
 let calls=0;
 await assert.rejects(runApprovedPipeline({STORY_STUDIO_JOB_ID:'bad'},()=>{calls++;}),/invalid_target_job/);
 assert.equal(calls,0);
 for(const value of [undefined,false]) await assert.rejects(runApprovedPipeline({},async()=>({completed:render,kind:'render',next_job_id:upload,auto_private_upload:value})),/pipeline_invalid_followup/);
 await assert.rejects(runApprovedPipeline({},async()=>({completed:render,kind:'render',next_job_id:render,auto_private_upload:true})),/pipeline_invalid_followup/);
 calls=0;
 await assert.rejects(runApprovedPipeline({},async()=>{calls++;return {completed:render,kind:'render',next_job_id:upload,auto_private_upload:true};}),/pipeline_chain_limit/);
 assert.equal(calls,2);
});
test('failure is never retried and ordinary jobs stay single-step',async()=>{
 let calls=0;
 await assert.rejects(runApprovedPipeline({},async()=>{calls++;throw new Error('uncertain');}),/uncertain/);
 assert.equal(calls,1);
 const result=await runApprovedPipeline({},async()=>({idle:true}));assert.deepEqual(result,{idle:true});
});
