import test from 'node:test';
import assert from 'node:assert/strict';
import { agentRequest, decodeAgent, draftSchema, improvementSchema, validate } from './story_studio_contract.mjs';
import { executeJob, runStudio, sha256, privateUpload, openaiJson, probeStudio } from './story_studio_worker.mjs';
import { creative, draft, researchResponse } from './story_studio_fixture.mjs';
import {decodeResearch,researchRequest} from './story_studio_research.mjs';
import {demoAssets} from './story_studio_demo.mjs';

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
    assert.equal(body.input[0].content,researchRequest(snapshot).input[0].content);
    return Response.json({error:{code:'insufficient_quota'}},{status:429});
  };
  const env={STORY_STUDIO_PREFLIGHT:'true',OPENAI_API_KEY:'sk-test-only',OPENAI_MARKETING_MODEL:'configured-text'};
  assert.deepEqual(await probeStudio(env,fetcher),{disabled:true}); assert.equal(calls,0);
  await assert.rejects(probeStudio({...env,STORY_STUDIO_DRY_RUN:'false'},fetcher),{message:'openai_responses_http_429_insufficient_quota'});
  assert.equal(calls,1);
});
test('model access diagnostics never echo project ids, model names or arbitrary provider text',async()=>{
  for(const [message,expected] of [
    ['Project private-project does not have access to model configured-text','project_model_denied'],
    ['The model configured-text does not exist','model_not_found_requested'],
    ['The model gpt-private-other does not exist','model_not_found_other'],
    ['Unrecognized private error','model_not_found'],
  ]) await assert.rejects(openaiJson(Response.json({error:{code:'model_not_found',message}},{status:403}),
    'responses',200000,'configured-text'),{message:`openai_responses_http_403_${expected}`});
});

test('production draft transport keeps configured model and credentials separate from database requests',async()=>{
  const env={STORY_STUDIO_ENABLED:'true',STORY_STUDIO_DRY_RUN:'false',
    SUPABASE_URL:'https://test.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'database-test',
    OPENAI_API_KEY:'sk-test-only',OPENAI_MARKETING_MODEL:'configured-text',OPENAI_STORY_IMAGE_MODEL:'configured-image',
    YOUTUBE_CLIENT_ID:'unused',YOUTUBE_CLIENT_SECRET:'unused',YOUTUBE_REFRESH_TOKEN:'unused',YOUTUBE_CHANNEL_ID:'unused'};
  const calls=[];
  const result=await runStudio(env,async(url,options)=>{
    const parsed=new URL(url); const body=JSON.parse(options.body); calls.push(parsed.hostname);
    if(parsed.hostname==='test.supabase.co') {
      assert.equal(options.headers.Authorization,'Bearer database-test');
      if(body.p_action==='claim') return Response.json({...base,kind:'draft'});
      if(body.p_action==='complete') assert.equal(body.p.result.title,creative.title);
      return Response.json({});
    }
    assert.equal(parsed.hostname,'api.openai.com');
    assert.equal(options.headers.Authorization,'Bearer sk-test-only');
    assert.equal(body.model,env.OPENAI_MARKETING_MODEL);
    if(parsed.pathname==='/v1/responses') {
      assert.equal(body.max_output_tokens,3500); assert.equal(body.store,false);
      return Response.json(researchResponse);
    }
    assert.equal(parsed.pathname,'/v1/chat/completions');
    return Response.json(completion(creative));
  });
  assert.deepEqual(result,{completed:id,kind:'draft'});
  assert.equal(calls.filter(x=>x==='api.openai.com').length,2);
});
test('generic 401 responses distinguish missing scope from invalid key without exposing message',async()=>{
  const cases=[
    ['You have insufficient permissions. Missing scopes: api.responses.write. Private context follows.','missing_scope_responses_write'],
    ['You have insufficient permissions. Missing scopes: model.request.','missing_scope_model_request'],
    ['You have insufficient permissions. Missing scopes: private.unknown.','insufficient_permissions'],
    ['Incorrect API key provided: sk-test-secret','invalid_api_key'],
    ['Unexpected private context','invalid_request_error'],
  ];
  for(const [message,code] of cases) await assert.rejects(openaiJson(Response.json({error:{type:'invalid_request_error',code:null,message}},{status:401}),'responses'),
    {message:`openai_responses_http_401_${code}`});
});
test('successful probe touches only two text endpoints, with bounded output and no stored content',async()=>{
  const paths=[];
  const result=await probeStudio({STORY_STUDIO_PREFLIGHT:'true',STORY_STUDIO_DRY_RUN:'false',OPENAI_API_KEY:'sk-test-only',OPENAI_MARKETING_MODEL:'configured-text'},async(url,options)=>{
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
test('explicit demo template substitutes two verified captures and only buys four images',async()=>{
  const demoSnapshot={...snapshot,episode:{...snapshot.episode,brief:'[APP_DEMO:bibimbap-v1]\nUse the real app.'}};
  const demos=await demoAssets(demoSnapshot);
  let calls=0;
  await executeJob({...base,kind:'render',snapshot:demoSnapshot},{check:async()=>{},image:async()=>{calls++;return Buffer.from('image');},
    render:async images=>{assert.equal(images.length,6);assert.deepEqual(images[2],demos.get(2));assert.deepEqual(images[3],demos.get(3));
      return Object.fromEntries(['ko','en','es'].map(l=>[l,Buffer.from('video')]));},store:async()=>{}});
  assert.equal(calls,4);
});
test('unknown demo markers fail before paid calls; model panel text cannot opt in',async()=>{
  let calls=0;
  for (const brief of ['[APP_DEMO:../../secret]','prefix [APP_DEMO:bibimbap-v1]',
    '[APP_DEMO:bibimbap-v1]\n[APP_DEMO:bibimbap-v1]']) {
    await assert.rejects(executeJob({...base,kind:'render',snapshot:{...snapshot,episode:{...snapshot.episode,brief}}},
      {check:async()=>{},image:async()=>{calls++;}}),{message:'invalid_demo_template'});
  }
  assert.equal(calls,0);
  assert.equal((await demoAssets({episode:{draft:{panels:['[APP_DEMO:bibimbap-v1]']}}})).size,0);
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
