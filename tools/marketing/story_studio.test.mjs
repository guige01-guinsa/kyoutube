import test from 'node:test';
import assert from 'node:assert/strict';
import { agentRequest, decodeAgent, draftSchema, improvementSchema, validate } from './story_studio_contract.mjs';
import { executeJob, runStudio, sha256, privateUpload, openaiJson, probeStudio } from './story_studio_worker.mjs';
import { creative, draft, researchResponse } from './story_studio_fixture.mjs';
import {decodeResearch,researchRequest} from './story_studio_research.mjs';

const id = '11111111-1111-4111-8111-111111111111';
const snapshot = { series:{language:'ko',bible:'No magical notebook'},recipe:{settings:{font_size:40,scene_seconds:10,music_gain:1}},language:'ko',
  text_model:'configured-text',image_model:'configured-image',history:[{summary:'Resolved past'}],
  episode:{number:4,draft,variants:Object.fromEntries(['ko','en','es'].map(l=>[l,{asset_path:`${id}/${l}.mp4`,sha256:sha256(Buffer.from('video'))}]))} };
const base = {id,lease_token:id,snapshot,request:{sources_reviewed:true,preview_reviewed:true,asset_sha256:snapshot.episode.variants.ko.sha256}};
const completion = content => ({choices:[{finish_reason:'stop',message:{content:JSON.stringify(content)}}]});

test('API diagnostics expose only allowlisted codes, never secrets or provider text',async()=>{
  await assert.rejects(openaiJson(Response.json({error:{code:'model_not_found',message:'secret raw body'}},{status:404}),'responses'),
    {message:'openai_responses_http_404_model_not_found'});
  await assert.rejects(openaiJson(Response.json({error:{code:'sk-sensitive',message:'secret raw body'}},{status:403}),'chat'),
    {message:'openai_chat_http_403_unknown'});
  await assert.rejects(openaiJson(new Response('secret raw body',{status:502}),'images'),
    {message:'openai_images_http_502_unknown'});
});
test('manual probe is disabled by default and stops on first rejected request without retries',async()=>{
  let calls=0;
  const fetcher=async(url,options)=>{
    calls++; assert.equal(url,'https://api.openai.com/v1/responses');
    const body=JSON.parse(options.body);
    assert.equal(body.max_tool_calls,1); assert.equal(body.max_output_tokens,512);
    return Response.json({error:{code:'insufficient_quota'}},{status:429});
  };
  const env={STORY_STUDIO_PREFLIGHT:'true',OPENAI_API_KEY:'test-only',OPENAI_MARKETING_MODEL:'configured-text'};
  assert.deepEqual(await probeStudio(env,fetcher),{disabled:true}); assert.equal(calls,0);
  await assert.rejects(probeStudio({...env,STORY_STUDIO_DRY_RUN:'false'},fetcher),{message:'openai_responses_http_429_insufficient_quota'});
  assert.equal(calls,1);
});
test('successful probe touches only two text endpoints, with bounded output and no stored content',async()=>{
  const paths=[];
  const result=await probeStudio({STORY_STUDIO_PREFLIGHT:'true',STORY_STUDIO_DRY_RUN:'false',OPENAI_API_KEY:'test-only',OPENAI_MARKETING_MODEL:'configured-text'},async(url,options)=>{
    paths.push(new URL(url).pathname); const body=JSON.parse(options.body);
    if(paths.length===1) assert.equal(body.store,false);
    else {assert.equal(body.max_completion_tokens,128);assert.equal(body.response_format.json_schema.strict,true);}
    return Response.json({});
  });
  assert.deepEqual(paths,['/v1/responses','/v1/chat/completions']);
  assert.deepEqual(result,{api_access_checked:['responses','chat'],images_checked:false,uploaded:false});
});
test('draft schema rejects extra instructions, missing fields and oversized captions', () => {
  validate(creative,draftSchema);
  for (const invalid of [{...creative,code:'run()'},{...creative,summary:null},{...creative,captions:['x']},{...creative,captions:Array(6).fill('x'.repeat(61))}])
    assert.throws(()=>validate(invalid,draftSchema));
});
test('improvements are bounded data only',()=>{
  validate({settings:snapshot.recipe.settings,instructions:'Improve rhythm',reason:'Clearer captions'},improvementSchema);
  assert.throws(()=>validate({settings:{...snapshot.recipe.settings,font_size:999},instructions:'x',reason:'x'},improvementSchema));
});
test('all three languages retain history and structured output; unsupported language rejected',()=>{
  for (const language of ['ko','en','es']) {
    const request = agentRequest({...base,kind:'draft',snapshot:{...snapshot,series:{...snapshot.series,language}}});
    assert.equal(request.model,'configured-text');
    assert.equal(request.response_format.json_schema.strict,true);
    assert.match(request.messages[1].content,/Resolved past/);
  }
  assert.throws(()=>agentRequest({...base,kind:'draft',snapshot:{...snapshot,series:{language:'fr'}}}));
});
test('refusal, truncation and malformed JSON never become drafts',()=>{
  assert.deepEqual(decodeAgent(completion(creative),'draft'),creative);
  for (const response of [{choices:[{finish_reason:'length',message:{content:'{}'}}]},
    {choices:[{finish_reason:'stop',message:{refusal:'No',content:'{}'}}]},{}]) assert.throws(()=>decodeAgent(response,'draft'));
});
test('default disabled and dry run make no calls',async()=>{
  const fail=()=>{throw new Error('unexpected network');};
  assert.deepEqual(await runStudio({},fail),{disabled:true});
  assert.deepEqual(await runStudio({STORY_STUDIO_ENABLED:'true'},fail),{disabled:true});
});
test('draft agent cannot render or upload',async()=>{
  let checks=0;
  const result=await executeJob({...base,kind:'draft'}, {check:async()=>checks++,research:async()=>researchResponse,chat:async()=>completion(creative)});
  assert.equal(result.title,creative.title);
  assert.equal(result.research.status,'human_review_required');
  assert.equal(checks,2);
});
test('render produces a private preview only',async()=>{
  const stored=[]; let imageCalls=0;
  const result=await executeJob({...base,kind:'render'},{check:async()=>{},image:async()=>{imageCalls++;return Buffer.from('image');},
    render:async images=>{assert.equal(images.length,6);return {ko:Buffer.from('video'),en:Buffer.from('video'),es:Buffer.from('video')};},store:async(path)=>{stored.push(path);}});
  assert.equal(imageCalls,6); assert.equal(stored.length,3);
  assert.equal(result.variants.ko.sha256,sha256(Buffer.from('video')));
});
test('upload requires exact reviewed preview and never retries',async()=>{
  let calls=0;
  const io={check:async()=>{},load:async()=>Buffer.from('video'),upload:async()=>{calls++;return 'ZB8zJymlxCw';}};
  await assert.rejects(executeJob({...base,kind:'upload',request:{preview_reviewed:false}},io));
  await assert.rejects(executeJob({...base,kind:'upload'},{...io,load:async()=>Buffer.from('changed')}));
  assert.equal(calls,0);
  assert.deepEqual(await executeJob({...base,kind:'upload'},io),{youtube_id:'ZB8zJymlxCw',privacy:'private'});
  calls=0;
  await assert.rejects(executeJob({...base,kind:'upload'},{...io,upload:async()=>{calls++;throw new Error('lost response');}}));
  assert.equal(calls,1);
});
test('YouTube upload forces private, labels AI and verifies visibility',async()=>{
  let metadata;
  const channel='UC'+'a'.repeat(22);
  const fetcher=async(url, options)=>{
    const path=String(url);
    if(path.includes('oauth2')) return Response.json({access_token:'test-token'});
    if(path.includes('channels?')) return Response.json({items:[{id:channel}]});
    if(path.includes('uploadType=')) {
      metadata=JSON.parse(options.body);
      return new Response('',{headers:{location:'https://www.googleapis.com/upload/test'}});
    }
    if(options?.method==='PUT') return Response.json({id:'ZB8zJymlxCw'});
    if(path.includes('videos?')) return Response.json({items:[{status:{privacyStatus:'private'}}]});
    throw new Error('unexpected endpoint');
  };
  await privateUpload(Buffer.from('video'),snapshot,{YOUTUBE_CHANNEL_ID:channel},fetcher);
  assert.equal(metadata.status.privacyStatus,'private');
  assert.equal(metadata.status.containsSyntheticMedia,true);
});
test('research requires attributable sources and has a bounded search request',()=>{
  assert.equal(researchRequest(snapshot).max_tool_calls,3);
  assert.equal(decodeResearch(researchResponse).sources.length,2);
  assert.throws(()=>decodeResearch({status:'completed',output:[]}));
  assert.throws(()=>decodeResearch({...researchResponse,status:'incomplete'}));
});
