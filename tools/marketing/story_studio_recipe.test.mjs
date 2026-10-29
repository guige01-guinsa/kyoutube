import test from 'node:test';
import assert from 'node:assert/strict';
import {makeRecipePlan,validateRecipePlan,recipePlanHash,boundedRecipeMap} from './story_studio_recipe.mjs';
export const recipeFixture=()=>({url:'https://www.youtube.com/watch?v=abcdefghijk',title:'합성 시험 레시피',channel:'검사 채널',servings:'2인분',ingredients:['검사 재료 200g','간장 2큰술(20g)','후추 약간'],steps:['재료를 순서대로 섞습니다.','팬에서 충분히 익힙니다.']});
export const recipePlanFixture=()=>makeRecipePlan({food:'검사 음식',presenter:'검사 진행자',recipe:recipeFixture(),intro:'안녕하세요. 원본 레시피를 확인합니다.',outro:'원본 영상도 함께 확인하세요.'});
test('source quantities and qualitative amounts survive unchanged in voice and captions',()=>{
 const p=recipePlanFixture();validateRecipePlan(p);
 assert.equal(p.scenes[1].spoken,'검사 재료 200g. 간장 2큰술(20g). 후추 약간.');
 assert.ok(!JSON.stringify(p).includes('30mL'));
 assert.equal(p.scenes[2].spoken,p.recipe.steps[0]);
});
test('changed amount, instruction, order or added ingredient is rejected before generation',()=>{
 for(const mutate of [p=>p.scenes[1].spoken+=' 설탕 10g.',p=>p.scenes[2].caption='순서 바꿈',p=>p.scenes.reverse(),p=>p.recipe.ingredients[0]='검사 재료 300g']) {
  const p=recipePlanFixture();mutate(p);assert.throws(()=>validateRecipePlan(p),/recipe_source_required/);
 }
});
test('JSON database key ordering does not invalidate source verification',()=>{
 const reorder=o=>Array.isArray(o)?o.map(reorder):o&&typeof o==='object'?Object.fromEntries(Object.entries(o).reverse().map(([k,v])=>[k,reorder(v)])):o;
 const p=recipePlanFixture();assert.equal(recipePlanHash(reorder(p)),recipePlanHash(p));
});
test('unsupported source, incomplete original or oversized recipe needs review',()=>{
 for(const mutate of [r=>r.url='https://example.com/watch?v=abcdefghijk',r=>r.steps=[],r=>r.ingredients.push('가'.repeat(101)),r=>r.extra=true]) {
  const r=recipeFixture();mutate(r);assert.throws(()=>makeRecipePlan({food:'음식',presenter:'진행자',recipe:r,intro:'안녕',outro:'안녕'}));
 }
});
test('bounded concurrency preserves order and drains active work without retry',async()=>{
 let active=0,peak=0;const called=[];
 await assert.rejects(boundedRecipeMap([0,1,2,3],async n=>{
  called.push(n);active++;peak=Math.max(peak,active);
  await new Promise(r=>setTimeout(r,n===0?5:30));active--;if(n===0)throw new Error('stop');return n;
 }),/stop/);
 assert.equal(peak,2);assert.equal(active,0);assert.deepEqual(called,[0,1]);
 assert.deepEqual(await boundedRecipeMap([2,1,0],async n=>n*2),[4,2,0]);
});
