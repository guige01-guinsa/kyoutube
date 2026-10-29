import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {fetchRecipeSource,planFromOriginal,sourceLocatorRequest,recipeVideoId} from './story_studio_recipe_source.mjs';
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
