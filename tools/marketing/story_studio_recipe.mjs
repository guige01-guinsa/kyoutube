// Recipe-first profile. The approved source strings, not an LLM paraphrase,
// supply every ingredient and cooking instruction in captions AND narration.
import {createHash} from 'node:crypto';
import {speechRequest,RECIPE_VOICE_PROFILE} from './story_studio_narration.mjs';
export const RECIPE_PROFILE='ko-180-source-v1';
export const RECIPE_VISUAL_PROFILE='recipe-sketch-v2';
export function validateRecipeVisuals(v,count) {
 if(!Number.isInteger(count)||count<4||count>20||v?.profile!==RECIPE_VISUAL_PROFILE || v.scene_count!==count || v.verified_frames!==count ||
  !Number.isFinite(v.min_ink_fraction)||v.min_ink_fraction<.003||v.min_ink_fraction>.4)
  throw new Error('recipe_visual_review');
 return v;
}
const fail=()=>{throw new Error('recipe_source_required');};
const canonical=o=>Array.isArray(o)?o.map(canonical):o&&typeof o==='object'?Object.fromEntries(Object.keys(o).sort().map(k=>[k,canonical(o[k])])):o;
const same=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
const clean=(s,n)=>typeof s==='string' && s.trim()===s && s.length>0 && [...s].length<=n && !/[\u0000-\u001f]/.test(s);
const exact=(o,keys)=>o && !Array.isArray(o) && Object.keys(o).sort().join(',')===[...keys].sort().join(',');
export function validateRecipe(r) {
 if(!exact(r,['url','title','channel','servings','ingredients','steps']) ||
  !/^https:\/\/www\.youtube\.com\/watch\?v=[A-Za-z0-9_-]{11}$/.test(r.url) ||
  !clean(r.title,150)||!clean(r.channel,80)||!clean(r.servings,60)||
  !Array.isArray(r.ingredients)||r.ingredients.length<2||r.ingredients.length>24||
  r.ingredients.some(s=>!clean(s,100))||!Array.isArray(r.steps)||r.steps.length<1||r.steps.length>12||
  r.steps.some(s=>!clean(s,160))) fail();
 return r;
}
export function recipeScenes(recipe,intro,outro) {
 const r=validateRecipe(recipe);
 if(!clean(intro,50)||!clean(outro,80)) fail();
 const scene=(role,spoken,caption)=>({role,spoken,caption,visual:'source_recipe_card',source_ids:['original-video']});
 const scenes=[scene('greeting',intro,'원본 영상 레시피 · '+r.servings)];
 for(let i=0;i<r.ingredients.length;i+=3) {
  const lines=r.ingredients.slice(i,i+3);
  scenes.push(scene('ingredients',lines.join('. ')+'.',lines.join(' / ')));
 }
 for(const [i,step] of r.steps.entries()) scenes.push(scene('cooking',step,`${i+1}. ${step}`));
 scenes.push(scene('source',`${r.channel}의 원본 영상을 함께 확인해 주세요.`,r.title+' / '+r.url));
 scenes.push(scene('closing',outro,'레시피 스카우트 · 원본과 대조한 레시피'));
 if(scenes.length>20 || scenes.some(s=>[...s.spoken].length>180)) fail();
 return scenes;
}
export function makeRecipePlan({food,presenter,recipe,intro,outro}) {
 if(!clean(food,30)||!clean(presenter,500)) fail();
 return {profile:RECIPE_PROFILE,language:'ko',food,title:`${food} · 원본 레시피`,presenter,
  sources:[{id:'original-video',title:recipe.title,url:recipe.url,note:'관리자가 원본의 재료·분량·단위·선택 사항·조리 순서를 직접 대조한 뒤 제작합니다.'}],
  recipe,scenes:recipeScenes(recipe,intro,outro)};
}
export function validateRecipePlan(p) {
 if(!exact(p,['profile','language','food','title','presenter','sources','recipe','scenes'])||p.profile!==RECIPE_PROFILE||p.language!=='ko'||!clean(p.title,45)||!clean(p.food,30)||!clean(p.presenter,500)||!Array.isArray(p.scenes)||p.scenes.length<4) fail();
 const expected=makeRecipePlan({food:p.food,presenter:p.presenter,recipe:p.recipe,intro:p.scenes[0]?.spoken,outro:p.scenes.at(-1)?.spoken});
 if(p.title!==expected.title||!same(p.sources,expected.sources)||!same(p.scenes,expected.scenes)) fail();
 return p;
}
export function recipePlanHash(p) {
 validateRecipePlan(p);
 return createHash('sha256').update(JSON.stringify(canonical({plan:p,visual_profile:RECIPE_VISUAL_PROFILE,voice:speechRequest('설정 확인','ko',RECIPE_VOICE_PROFILE)}))).digest('hex');
}
// At most two paid requests in flight. On failure, drain in-flight checkpoints,
// stop scheduling new requests and never retry. Order is stable.
export async function boundedRecipeMap(items,fn,limit=2) {
 if(!Number.isInteger(limit)||limit<1||limit>2) throw new Error('invalid_concurrency');
 const out=new Array(items.length);let next=0,failure;
 await Promise.all(Array.from({length:Math.min(limit,items.length)},async()=>{
  while(!failure) {const index=next++;if(index>=items.length) return;
   try {out[index]=await fn(items[index],index);} catch(e) {failure??=e;}
  }
 }));
 if(failure) throw failure;return out;
}
