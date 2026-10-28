import test from 'node:test';
import assert from 'node:assert/strict';
import {standardPlanHash,standardChecklist,validateStandardAudio,executeStandardStage} from './story_studio_standard.mjs';
import {createHash} from 'node:crypto';

const plan=()=>({profile:'ko-60-v1',language:'ko',food:'합성 시험 음식',title:'검사용 원고',presenter:'허구의 진행자',
  sources:[{id:'one',title:'합성 출처',url:'https://example.com/one',note:'검사용'},
    {id:'two',title:'합성 출처',url:'https://example.org/two',note:'검사용'}],
  scenes:['greeting','food_fact','ingredients','cooking','app_demo','closing'].map(role=>({role,
    spoken:'이 문장은 합성 시험용입니다.',caption:'합성 시험 장면',visual:'검사용 도형',source_ids:['one']}))});
function wav(seconds=1,value=1000) {
  const bytes=Buffer.alloc(44+8000*2*seconds);
  bytes.write('RIFF');bytes.writeUInt32LE(bytes.length-8,4);bytes.write('WAVEfmt ',8);
  bytes.writeUInt32LE(16,16);bytes.writeUInt16LE(1,20);bytes.writeUInt16LE(1,22);
  bytes.writeUInt32LE(8000,24);bytes.writeUInt32LE(16000,28);bytes.writeUInt16LE(2,32);bytes.writeUInt16LE(16,34);
  bytes.write('data',36);bytes.writeUInt32LE(bytes.length-44,40);
  for(let i=44;i<bytes.length;i+=2) bytes.writeInt16LE(value,i);
  return bytes;
}
function setup(stage='sample') {
  const p=plan(),plan_hash=standardPlanHash(p),audio=wav(),calls=[],claims=new Set();
  const request={plan:p,stage,approval:{stage,plan_hash,attempt_id:'attempt-one',sources_reviewed:true}};
  const io={authorize:async()=>{},check:async()=>{},
    claimOnce:async id=>{if(claims.has(id))return false;claims.add(id);return true;},
    reviewedSample:async()=>({plan_hash,listened:true,sha256:createHash('sha256').update(audio).digest('hex')}),
    prepareVisuals:async()=>{calls.push('visuals');return [];},
    cachedSpeech:async(_,language)=>{assert.equal(language,'ko');calls.push('speech');return audio;},
    saveSample:async()=>{calls.push('sample');return 'private-sample';},
    assemble:async()=>{calls.push('assemble');return 'private-video';},
    inspectVideo:async()=>({seconds:60,language:'ko',audio:true,width:720,height:1280,bytes:5000,sha256:'a'.repeat(64)}),
    complete:async()=>calls.push('complete'),needsReview:async()=>calls.push('needs_review')};
  return {request,io,calls};
}
test('only Korean 60-second profile; six slots; no automatic publication',()=>{
  const result=standardChecklist(plan());assert.deepEqual(result.languages,['ko']);assert.equal(result.seconds,60);
  assert.equal(result.auto_upload,false);assert.equal(result.max_unique_speech_requests,6);
  for(const change of [{language:'en'},{profile:'ko-300-v1'},{translations:{}},{scenes:[]}])
    assert.throws(()=>standardChecklist({...plan(),...change}));
});
test('missing, duplicate, insecure or unattributed sources rejected',()=>{
  const p=plan();p.sources[1]=p.sources[0];assert.throws(()=>standardChecklist(p));
  const q=plan();q.scenes[1].source_ids=[];assert.throws(()=>standardChecklist(q));
  const r=plan();r.sources[0].url='http://example.com';assert.throws(()=>standardChecklist(r));
});
test('spoken length and source changes invalidate plan approval',()=>{
  const p=plan(),before=standardPlanHash(p);p.sources[0].note='수정';assert.notEqual(standardPlanHash(p),before);
  p.scenes[0].spoken='가'.repeat(51);assert.throws(()=>standardChecklist(p));
});
test('canonical hash does not depend on object property order',()=>{
  const p=plan();assert.equal(standardPlanHash(p),standardPlanHash(Object.fromEntries(Object.entries(p).reverse())));
});
test('only sample produced before listening review',async()=>{
  const {request,io,calls}=setup();const result=await executeStandardStage(request,io);
  assert.equal(result.next,'sample_listening_review');assert.deepEqual(calls,['speech','sample','complete']);
});
test('render refuses missing listening approval before paid calls',async()=>{
  const {request,io,calls}=setup('render');io.reviewedSample=async()=>null;
  await assert.rejects(executeStandardStage(request,io),/listening_required/);assert.deepEqual(calls,[]);
});
test('stale manuscript approval rejected before server authorization',async()=>{
  const {request,io,calls}=setup();request.plan.scenes[0].spoken='수정된 원고입니다.';
  await assert.rejects(executeStandardStage(request,io),/approval_required/);assert.deepEqual(calls,[]);
});
test('server rejects expired or over-budget approval',async()=>{
  const {request,io,calls}=setup();io.authorize=async()=>{throw new Error('budget');};
  await assert.rejects(executeStandardStage(request,io),/budget/);assert.deepEqual(calls,[]);
});
test('same attempt cannot run twice',async()=>{
  const {request,io,calls}=setup();await executeStandardStage(request,io);
  await assert.rejects(executeStandardStage(request,io),/already_claimed/);assert.equal(calls.filter(v=>v==='speech').length,1);
});
test('render preflights visuals before six cached speech reads',async()=>{
  const {request,io,calls}=setup('render');const result=await executeStandardStage(request,io);
  assert.equal(calls[0],'visuals');assert.equal(calls.filter(v=>v==='speech').length,6);assert.equal(result.uploaded,false);
});
test('changed reviewed sample stops without generating remaining voice',async()=>{
  const {request,io,calls}=setup('render');io.reviewedSample=async()=>({plan_hash:request.approval.plan_hash,listened:true,sha256:'0'.repeat(64)});
  await assert.rejects(executeStandardStage(request,io),/needs_review/);
  assert.deepEqual(calls,['visuals','speech','needs_review']);
});
test('long, silent and clipped audio rejected, not shortened',()=>{
  for(const audio of [wav(10),wav(1,0),wav(1,32767)]) assert.throws(()=>validateStandardAudio(audio));
  assert.equal(validateStandardAudio(wav(9.5)).seconds,9.5);
});
test('malformed media and video longer than one minute fail closed',async()=>{
  assert.throws(()=>validateStandardAudio(Buffer.alloc(4000)));
  const {request,io,calls}=setup('render');io.inspectVideo=async()=>({seconds:60.1});
  await assert.rejects(executeStandardStage(request,io));assert.equal(calls.at(-1),'needs_review');assert.ok(!calls.includes('complete'));
});
test('lost completion acknowledgement never automatically retries',async()=>{
  const {request,io,calls}=setup();io.complete=async()=>{throw new Error('secret provider body');};
  await assert.rejects(executeStandardStage(request,io),{message:'standard_needs_review'});
  await assert.rejects(executeStandardStage(request,io),/already_claimed/);
  assert.equal(calls.filter(v=>v==='speech').length,1);
});
test('safe diagnosis is recorded without provider text or manuscript',async()=>{
  const {request,io}=setup();let diagnosis;
  io.cachedSpeech=async()=>wav(10);
  io.needsReview=async(_,value)=>{diagnosis=value;};
  await assert.rejects(executeStandardStage(request,io));
  assert.equal(diagnosis.reason,'standard_shorten_script');
  assert.deepEqual(Object.keys(diagnosis).sort(),['elapsed_ms','reason','stage']);
});
test('missing visual approval stops before any speech request',async()=>{
  const {request,io,calls}=setup('render');
  io.prepareVisuals=async()=>{throw new Error('private asset details');};
  await assert.rejects(executeStandardStage(request,io),{message:'standard_needs_review'});
  assert.deepEqual(calls,['needs_review']);
});
