import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {fetchRecipeSource,planFromOriginal,sourceLocatorRequest,recipeVideoId,assertRecipeSourceReady,findRecipeAlternative} from './story_studio_recipe_source.mjs';
import {executeStandardJob} from './story_studio_standard_worker.mjs';
const url='https://www.youtube.com/watch?v=abcdefghijk';
const description='검사 음식 2인분\n[재료]\n재료 200g\n간장 2큰술(20g)\n후추 약간\n[만드는 법]\n재료를 순서대로 섞습니다.\n팬에서 충분히 익힙니다.';
const source={id:'abcdefghijk',url,title:'검사 영상',channel:'원본 채널',description,sha256:createHash('sha256').update(description).digest('hex'),checked_at:'2026-10-29T00:00:00Z',view_count:'12345'};
const located={complete:true,ingredients:{start:2,end:4},steps:{start:6,end:7},servings_line:0,intro:'안녕하세요.',outro:'원본도 확인하세요.'};
const response=x=>({choices:[{finish_reason:'stop',message:{content:JSON.stringify(x)}}]});
const job={id:randomUUID(),snapshot:{project:{source_video_url:url,food:'검사 음식',presenter:'진행자'}}};
test('source locator copies only original lines even if model adds rewritten recipe fields',()=>{
 const r=planFromOriginal(job,source,response({...located,ingredients_text:['간장 30mL']}));
 assert.deepEqual(r.plan.recipe.ingredients,['재료 200g','간장 2큰술(20g)','후추 약간']);
 assert.deepEqual(r.plan.recipe.steps,['재료를 순서대로 섞습니다.','팬에서 충분히 익힙니다.']);
 assert.equal(r.source_receipt.status,'human_source_review_required');
 assert.equal(sourceLocatorRequest('configured',source,'검사 음식').model,'configured');
});
test('missing original, wrong source and invalid ranges never produce a substitute recipe',()=>{
 for(const p of [{...located,complete:false},{...located,steps:{start:6,end:999}},{...located,servings_line:-1},{...located,ingredients:null},{...located,steps:{start:6.5,end:7}},{...located,intro:'Hello'}]) {
  assert.throws(()=>planFromOriginal(job,source,response(p)),/recipe_source_incomplete/);
 }
 assert.throws(()=>planFromOriginal(job,{...source,url:'https://www.youtube.com/watch?v=xxxxxxxxxxx'},response(located)),/recipe_source_required/);
 assert.throws(()=>recipeVideoId('https://evil.example/watch?v=abcdefghijk'));
});
test('official source fetch requests exactly one ID and never downloads video or captions',async()=>{
 const calls=[];
 const fetcher=async(target,init)=>{
  calls.push(String(target));
  if(calls.length===1)return new Response(JSON.stringify({access_token:'test-only'}));
  assert.equal(init.headers.Authorization,'Bearer test-only');
  return new Response(JSON.stringify({items:[{id:'abcdefghijk',snippet:{title:'검사 영상',channelTitle:'원본 채널',description},statistics:{viewCount:'12345'}}]}));
 };
 const r=await fetchRecipeSource(url,{YOUTUBE_CLIENT_ID:'fixture',YOUTUBE_CLIENT_SECRET:'fixture',YOUTUBE_REFRESH_TOKEN:'fixture'},fetcher);
 assert.equal(r.description,description);assert.equal(calls.length,2);
 assert.match(calls[1],/^https:\/\/www.googleapis.com\/youtube\/v3\/videos\?/);
 assert.equal(r.sha256,source.sha256);
});

const alternative={...source,id:'12345678901',url:'https://www.youtube.com/watch?v=12345678901',title:'검사 음식 레시피',
 description:'검사 음식 2인분\n[재료]\n재료 200g\n간장 2큰술(20g)\n후추 약간\n[만드는 법]\n재료를 순서대로 섞습니다.\n팬에서 충분히 익힙니다.'};
const linked={...source,description:'한국 음식 조리법: https://creator.example/recipe\n뉴스레터: https://creator.example/news\n영상 재료는 홈페이지에서 확인하세요.'};
const selection={requested_url:url,selected_url:alternative.url,reason:'recipe_source_external_required',checked_candidates:3,method:'youtube_description_v1',requires_review:true};
test('link-only and unsupported-language descriptions stop before an AI request is built',()=>{
 assert.throws(()=>sourceLocatorRequest('configured',linked,'검사 음식'),/recipe_source_external_required/);
 assert.throws(()=>assertRecipeSourceReady({...source,description:'Ingredients: pork 200g, water 2 cups. Simmer for 20 minutes.'}),/recipe_source_translation_required/);
 assert.equal(assertRecipeSourceReady(source),source);
});
test('one bounded official search selects a relevant Korean description, not the most popular unrelated dish',async()=>{
 const calls=[];
 const ids=['xxxxxxxxxxx','12345678901','yyyyyyyyyyy'];
 const fetcher=async(target,init)=>{
  calls.push(String(target));
  if(calls.length===1)return Response.json({access_token:'test-only'});
  assert.equal(init.headers.Authorization,'Bearer test-only');assert.equal(init.redirect,'error');
  const u=new URL(target);assert.equal(u.origin,'https://www.googleapis.com');
  if(u.pathname.endsWith('/search')) {
   assert.equal(u.searchParams.get('maxResults'),'5');assert.equal(u.searchParams.get('type'),'video');
   assert.equal(u.searchParams.get('relevanceLanguage'),'ko');
   return Response.json({nextPageToken:'must-not-follow',items:[...ids,'abcdefghijk','https://private.test'].map(videoId=>({id:{videoId}}))});
  }
  assert.equal(u.searchParams.get('id'),ids.join(','));
  return Response.json({items:[
   {id:ids[0],snippet:{title:'다른 음식 레시피',channelTitle:'유명 채널',description:alternative.description},statistics:{viewCount:'99999999'}},
   {id:ids[1],snippet:{title:alternative.title,channelTitle:'원본 채널',description:alternative.description},statistics:{viewCount:'12345'}},
   {id:ids[2],snippet:{title:alternative.title,channelTitle:'부족한 자료',description:linked.description}}
  ]});
 };
 const result=await findRecipeAlternative(url,'검사 음식','recipe_source_external_required',{},fetcher);
 assert.equal(calls.length,3);assert.equal(result.url,alternative.url);assert.deepEqual(result.selection,selection);
 assert.equal(result.description,alternative.description);
 assert.equal(result.channel,'원본 채널');
});
test('no eligible candidate stops without a second search, page scraping, or guessed recipe',async()=>{
 let calls=0;
 const fetcher=async()=>{
  calls++;
  if(calls===1)return Response.json({access_token:'test-only'});
  if(calls===2)return Response.json({items:[{id:{videoId:'12345678901'}}]});
  return Response.json({items:[{id:'12345678901',snippet:{title:alternative.title,channelTitle:'채널',description:linked.description}}]});
 };
 await assert.rejects(findRecipeAlternative(url,'검사 음식','recipe_source_external_required',{},fetcher),/recipe_alternative_unavailable/);
 assert.equal(calls,3);
});
test('changed reference requires selection evidence and copies only that single selected recipe',()=>{
 const selected={...alternative,selection};
 assert.throws(()=>planFromOriginal(job,alternative,response(located)),/recipe_source_required/);
 for(const patch of [{requested_url:alternative.url},{selected_url:url},{checked_candidates:6},{requires_review:false},{reason:'invented'}])
  assert.throws(()=>planFromOriginal(job,{...selected,selection:{...selection,...patch}},response(located)),/recipe_source_required/);
 const result=planFromOriginal(job,selected,response(located));
 assert.equal(result.plan.recipe.url,alternative.url);assert.deepEqual(result.source_receipt.selection,selection);
 assert.deepEqual(result.plan.recipe.ingredients,['재료 200g','간장 2큰술(20g)','후추 약간']);
 assert.equal(result.plan.sources.length,1);assert.equal(result.plan.sources[0].url,alternative.url);
});
function draftJob() {
 const p={...job.snapshot.project,id:randomUUID()};
 return {id:randomUUID(),created_at:new Date().toISOString(),snapshot:{project:p,standard_profile:'ko-60-v1',standard_stage:'draft',standard_project_id:p.id,text_model:'configured'}};
}
test('fallback resolves metadata before the sole paid draft call; incomplete AI output is never retried',async()=>{
 for(const complete of [true,false]) {
  const calls=[];
  const io={check:async()=>{},recipeSource:async()=>linked,
   recipeAlternative:async(requested,food,reason)=>{calls.push('search');assert.equal(requested,url);assert.equal(reason,selection.reason);return {...alternative,selection};},
   chat:async body=>{calls.push('paid');assert.match(body.messages[1].content,/검사 음식 레시피/);return response({...located,complete});}};
  if(complete) assert.equal((await executeStandardJob(draftJob(),io)).plan.recipe.url,alternative.url);
  else await assert.rejects(executeStandardJob(draftJob(),io),/recipe_source_incomplete/);
  assert.deepEqual(calls,['search','paid']);
 }
});
test('unavailable alternatives and access errors do not make an AI call',async()=>{
 let paid=0,search=0;
 const io={check:async()=>{},recipeSource:async()=>linked,recipeAlternative:async()=>{search++;throw new Error('recipe_alternative_unavailable');},chat:async()=>{paid++;}};
 await assert.rejects(executeStandardJob(draftJob(),io),/recipe_alternative_unavailable/);
 io.recipeSource=async()=>{throw new Error('recipe_source_access');};
 await assert.rejects(executeStandardJob(draftJob(),io),/recipe_source_access/);
 assert.equal(search,1);assert.equal(paid,0);
});
test('usable requested source has priority and does not trigger an alternative search',async()=>{
 let search=0,paid=0;
 const result=await executeStandardJob(draftJob(),{check:async()=>{},recipeSource:async()=>source,
  recipeAlternative:async()=>{search++;},chat:async()=>{paid++;return response(located);}});
 assert.equal(result.plan.recipe.url,url);assert.equal(search,0);assert.equal(paid,1);
 assert.equal(result.source_receipt.selection,undefined);
});
