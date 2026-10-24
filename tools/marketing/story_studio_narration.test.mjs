import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {reeditSpec,narrationChunks,narrationPlan,verifyReeditSource,prepareNarration,speechAudio} from './story_studio_narration.mjs';
import {executeJob,reeditFailureCode,safeFailure} from './story_studio_worker.mjs';
import {draft} from './story_studio_fixture.mjs';
const id='11111111-1111-4111-8111-111111111111';
const video=Buffer.from('approved video');
const hash=createHash('sha256').update(video).digest('hex');
const edition={title:'Food guide',chapters:['One paragraph.','Second paragraph.','Third paragraph.']};
const snapshot={series:{id:'same-series'},episode:{id:'different-id',brief:`[ENCYCLOPEDIA_REEDIT:${id}:${hash}]`,
  draft:{...edition,translations:{en:edition,es:edition}}}};
const source={id,series_id:'same-series',status:'uploaded',brief:'[APP_DEMO:bibimbap-v1]',variants:{ko:{asset_path:`${id}/ko.mp4`,sha256:hash}}};
test('renderer diagnostics expose only exact safe codes, never private stderr',()=>{
  assert.equal(reeditFailureCode({stderr:'REEDIT_DIAGNOSTIC:invalid_voice_duration\n'}),'invalid_voice_duration');
  assert.equal(reeditFailureCode({error:{code:'ETIMEDOUT'}}),'renderer_timeout');
  for(const stderr of ['private transcript and credential','REEDIT_DIAGNOSTIC:private_secret',
    'REEDIT_DIAGNOSTIC:invalid_voice_duration /private/file']) {
    assert.equal(reeditFailureCode({stderr}),'unknown');
  }
  assert.equal(safeFailure(new Error('narrated_reedit_failed_invalid_voice_duration')),
    'narrated_reedit_failed_invalid_voice_duration');
  assert.equal(safeFailure(new Error('narrated_reedit_failed_private_secret')),'studio_job_needs_review');
});
test('only exact single opt-in marker permits re-edit',()=>{
  assert.equal(reeditSpec({episode:{brief:'normal'}}),null);
  assert.equal(reeditSpec(snapshot).episodeId,id);
  for(const brief of ['[ENCYCLOPEDIA_REEDIT:bad]',`prefix ${snapshot.episode.brief}`,`${snapshot.episode.brief}\n${snapshot.episode.brief}`])
    assert.throws(()=>reeditSpec({...snapshot,episode:{...snapshot.episode,brief}}));
});
test('chunking preserves all text, punctuation and Spanish accents',()=>{
  const text=('¿Qué cocinó? Un tazón de arroz, maíz y piña. ').repeat(25).trim();
  const chunks=narrationChunks([text,'둘째 문단입니다.','끝입니다.']);
  assert.ok(chunks.every(s=>s.length<=400));
  assert.equal(chunks.slice(0,-2).join(' '),text);
  assert.throws(()=>narrationChunks(['x'.repeat(1600),'a','b']));
});
test('source must remain same-series approved demo, correct path and hash',()=>{
  const spec=reeditSpec(snapshot);
  assert.equal(verifyReeditSource(source,snapshot,spec),`${id}/ko.mp4`);
  for(const change of [{series_id:'other'},{status:'rendering'},{brief:''},{variants:{ko:{asset_path:'../../secret',sha256:hash}}}])
    assert.throws(()=>verifyReeditSource({...source,...change},snapshot,spec));
});
test('all sources are checked before any paid calls; only speech is called',async()=>{
  let checked=0,spoken=0,validated=false;
  const io={check:async()=>checked++,sourceEpisode:async()=>source,load:async()=>video,
    validateSource:async()=>{validated=true;},speech:async()=>{assert.ok(validated);spoken++;return Buffer.from('wav');}};
  const result=await prepareNarration(snapshot,io);
  assert.equal(spoken,3);assert.equal(checked,4);assert.equal(result.video,video);
  spoken=0;
  await assert.rejects(prepareNarration(snapshot,{...io,load:async()=>Buffer.from('changed')}));
  assert.equal(spoken,0);
  assert.deepEqual(Object.keys(narrationPlan(snapshot)),['ko']);
});
test('speech permission failure is safe and never retried',async()=>{
  let calls=0;
  await assert.rejects(speechAudio('Hello','en','sk-test',async(url,options)=>{
    calls++;assert.equal(url,'https://api.openai.com/v1/audio/speech');
    assert.equal(JSON.parse(options.body).voice,'coral');
    return new Response('private provider details',{status:403});
  }),{message:'speech_http_403'});
  assert.equal(calls,1);
});
test('invalid language, oversized input and fake WAV cannot be used',async()=>{
  await assert.rejects(speechAudio('Hello','xx','sk-test',()=>assert.fail('network')));
  await assert.rejects(speechAudio('a'.repeat(601),'ko','sk-test',()=>assert.fail('network')));
  await assert.rejects(speechAudio('Hello','ko','sk-test',async()=>new Response('not wav',{headers:{'content-type':'audio/wav'}})));
});
test('reviewed re-edit uses existing render gate and stores previews without images or uploads',async()=>{
  const reviewed={...draft,chapters:edition.chapters,translations:{
    en:{...draft.translations.en,chapters:edition.chapters},es:{...draft.translations.es,chapters:edition.chapters}}};
  const job={id:'22222222-2222-4222-8222-222222222222',lease_token:id,kind:'render',
    request:{sources_reviewed:true},snapshot:{...snapshot,episode:{...snapshot.episode,draft:reviewed}}};
  const stored=[];
  const io={check:async()=>{},sourceEpisode:async()=>source,load:async()=>video,
    validateSource:async()=>{},speech:async()=>Buffer.from('audio'),
    reedit:async()=>({ko:Buffer.from('ko')}),
    store:async(path)=>stored.push(path),image:()=>assert.fail('no image generation'),
    render:()=>assert.fail('no ordinary render'),upload:()=>assert.fail('no upload')};
  const result=await executeJob(job,io);
  assert.equal(stored.length,1);assert.deepEqual(Object.keys(result.variants),['ko']);
  assert.ok(stored.every(path=>path.startsWith(job.id+'/')));
  await assert.rejects(executeJob({...job,request:{sources_reviewed:false}},io),{message:'source_review_required'});
  await assert.rejects(executeJob(job,{...io,reedit:async()=>({ko:Buffer.from('ko'),en:Buffer.from('en')})}),{message:'unexpected_video_languages'});
});

test('Korean-only re-edit never accesses archived translations or speaks other languages',async()=>{
  const korean={...snapshot,episode:{...snapshot.episode,draft:{...edition}}};
  Object.defineProperty(korean.episode.draft,'translations',{get(){assert.fail('translations must not be accessed');}});
  const spoken=[];
  const result=await prepareNarration(korean,{check:async()=>{},sourceEpisode:async()=>source,
    load:async()=>video,validateSource:async()=>{},speech:async(text,language)=>{spoken.push(language);return Buffer.from('wav');}});
  assert.deepEqual(spoken,['ko','ko','ko']);
  assert.deepEqual(Object.keys(result.voices),['ko']);
});
