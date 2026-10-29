// Opt-in Korean pilot workflow. No network, credentials, publication or live queue
// registration here. The server adapter must supply atomic authorization/claim.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {speechRequest} from './story_studio_narration.mjs';
import {speechCacheKey, validateCachedSpeech} from './story_studio_speech_cache.mjs';
import {RECIPE_PROFILE,validateRecipePlan,recipePlanHash} from './story_studio_recipe.mjs';

export const STANDARD_PROFILE = 'ko-60-v1';
export const STANDARD_SECONDS = 60;
export const STANDARD_STAGES = ['sample', 'render'];
const digest = value => createHash('sha256').update(value).digest('hex');
const fail = code => {throw new Error(code);};
const text = (value, max) => typeof value === 'string' && value.trim().length > 0 &&
  [...value].length <= max && !/[\u0000-\u001f]/.test(value);
const id = value => typeof value === 'string' && /^[a-z0-9-]{1,60}$/.test(value);
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const exact = (value, keys) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value,k));
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])])) : value;

export function validateStandardPlan(plan) {
  if(plan?.profile===RECIPE_PROFILE) return validateRecipePlan(plan);
  if (!exact(plan,['profile','language','food','title','presenter','sources','scenes']) ||
      plan.profile !== STANDARD_PROFILE || plan.language !== 'ko' || !text(plan.food,30) ||
      !text(plan.title,45) || !text(plan.presenter,500)) fail('standard_invalid_plan');
  if (!Array.isArray(plan.sources) || plan.sources.length < 2 || plan.sources.length > 8) fail('standard_sources_required');
  const sourceIds = new Set();
  for (const source of plan.sources) {
    if (!exact(source,['id','title','url','note']) || !id(source.id) || sourceIds.has(source.id) ||
        !text(source.title,200) || !text(source.url,1000) || !text(source.note,1000)) fail('standard_invalid_source');
    let url; try {url = new URL(source.url);} catch {fail('standard_invalid_source');}
    // URLs are attribution only; this module never fetches supplied URLs.
    if (url.protocol !== 'https:' || url.username || url.password) fail('standard_invalid_source');
    sourceIds.add(source.id);
  }
  if (!Array.isArray(plan.scenes) || plan.scenes.length !== 6) fail('standard_six_scenes_required');
  const roles=['greeting','food_fact','ingredients','cooking','app_demo','closing'];
  for (const [index,scene] of plan.scenes.entries()) {
    if (!exact(scene,['role','spoken','caption','visual','source_ids']) || scene.role !== roles[index] ||
        !text(scene.spoken,50) || !/[가-힣]/.test(scene.spoken) || !text(scene.caption,60) ||
        !text(scene.visual,1000) || !Array.isArray(scene.source_ids) ||
        new Set(scene.source_ids).size !== scene.source_ids.length ||
        scene.source_ids.some(ref=>!sourceIds.has(ref))) fail('standard_invalid_scene');
    if ([1,2,3].includes(index) && scene.source_ids.length === 0) fail('standard_unattributed_fact');
  }
  return plan;
}

export function standardPlanHash(plan) {
  if(plan?.profile===RECIPE_PROFILE) return recipePlanHash(plan);
  validateStandardPlan(plan);
  // A changed voice setting, source, image brief or wording invalidates approval.
  return digest(JSON.stringify(canonical({plan,voice:speechRequest('설정 확인','ko')})));
}

export function standardChecklist(plan) {
  const planHash=standardPlanHash(plan);
  if(plan.profile===RECIPE_PROFILE) return {
    profile:RECIPE_PROFILE,plan_hash:planHash,languages:['ko'],seconds_range:[150,180],target_ms:300000,
    stages:['source_and_script_review','existing_voice_consent_or_sample_review','render','full_review','private_upload_approval'],
    scene_timing:'measured_speech',voice_max_seconds:30,max_unique_speech_requests:plan.scenes.length,
    automatic_retries:0,auto_upload:false,new_illustrations:0,cost_status:'quote_and_actual_billing_required',
    scenes:plan.scenes.map((scene,index)=>({index,speech_key:speechCacheKey(scene.spoken,'ko')}))};
  return {profile:STANDARD_PROFILE,plan_hash:planHash,languages:['ko'],seconds:60,
    stages:['source_and_script_review','sample','sample_listening_review','render','full_review','private_upload_approval'],
    sample_scene:0,scene_seconds:10,voice_max_seconds:9.5,
    max_unique_speech_requests:6,automatic_retries:0,auto_upload:false,
    cost_status:'quote_and_actual_billing_required',
    scenes:plan.scenes.map((scene,index)=>({index,start:index*10,end:(index+1)*10,
      speech_key:speechCacheKey(scene.spoken,'ko')}))};
}

function audioInfo(bytes,maxSeconds=9.5) {
  const metadata=validateCachedSpeech(bytes);
  let rate,channels;
  for (let offset=12;offset+8<=bytes.length;) {
    const type=bytes.toString('ascii',offset,offset+4), size=bytes.readUInt32LE(offset+4), start=offset+8;
    if (type==='fmt ') {channels=bytes.readUInt16LE(start+2);rate=bytes.readUInt32LE(start+4);}
    if (type==='data') {
      const pcmBytes=size===0xffffffff?bytes.length-start:size;
      const seconds=pcmBytes/(rate*channels*2);
      if (seconds>maxSeconds) fail('standard_shorten_script'); // Never truncate or speed up speech.
      let peak=0,clipped=0,total=0;
      for(let p=start;p<start+pcmBytes;p+=2) {
        const sample=Math.abs(bytes.readInt16LE(p)); peak=Math.max(peak,sample);
        if(sample>=32760) clipped++; total++;
      }
      if(peak<100 || clipped/total>.01) fail('standard_audio_quality_review');
      return {...metadata,seconds};
    }
    offset=start+size+(size%2);
  }
  fail('standard_audio_quality_review');
}

export function validateStandardAudio(bytes,maxSeconds=9.5) { return audioInfo(bytes,maxSeconds); }

// The adapter's claimOnce must persist before any paid call and deny repeated or
// uncertain attempts. check must revalidate administrator, lease and reservation.
// cachedSpeech must use the existing immutable private speech checkpoint adapter.
export async function executeStandardStage(request,io) {
  const {plan,stage,approval}=request;
  const planHash=standardPlanHash(plan);
  if (!STANDARD_STAGES.includes(stage) || !approval || approval.stage!==stage ||
      approval.plan_hash!==planHash || !id(approval.attempt_id) || approval.sources_reviewed!==true)
    fail('standard_approval_required');
  // This acknowledgement is only a request; authorization belongs to the server.
  await io.authorize({stage,plan_hash:planHash,approval});
  let reviewed;
  if(stage==='render') {
    reviewed=await io.reviewedSample(planHash);
    if(!reviewed || reviewed.plan_hash!==planHash || reviewed.listened!==true || !hash(reviewed.sha256))
      fail('standard_sample_listening_required');
  }
  if(await io.claimOnce(approval.attempt_id,planHash,stage)!==true) fail('standard_attempt_already_claimed');
  const started=Date.now();
  try {
    await io.check();
    // Validate all six licensed illustrations / actual app captures BEFORE speech.
    const visuals=stage==='render'?await io.prepareVisuals(plan,planHash):null;
    const audio=[],metrics=[];
    for(const index of stage==='sample'?[0]:[0,1,2,3,4,5]) {
      await io.check();
      const bytes=await io.cachedSpeech(plan.scenes[index].spoken,'ko');
      const info=audioInfo(bytes);
      // A reviewed sample must never silently be regenerated with a new voice.
      if(index===0 && reviewed && reviewed.sha256!==info.sha256) fail('standard_sample_changed');
      audio.push(bytes);metrics.push({index,...info});
    }
    await io.check();
    const artifact=stage==='sample'?await io.saveSample(audio[0],planHash):
      await io.assemble({plan,plan_hash:planHash,visuals,audio,seconds:60});
    // Renderer adapter must independently decode and measure the complete video.
    if(stage==='render') {
      const qa=await io.inspectVideo(artifact);
      if(!qa || !Number.isFinite(qa.seconds) || qa.seconds<59.9 || qa.seconds>60 ||
          qa.language!=='ko' || qa.audio!==true || qa.width!==720 || qa.height!==1280 ||
          !Number.isSafeInteger(qa.bytes) || qa.bytes<=0 || qa.bytes>45000000 || !hash(qa.sha256))
        fail('standard_video_quality_review');
    }
    await io.check();
    const result={plan_hash:planHash,stage,artifact,metrics,elapsed_ms:Date.now()-started,
      next:stage==='sample'?'sample_listening_review':'full_review',uploaded:false};
    await io.complete(approval.attempt_id,result);
    return result;
  } catch (error) {
    // Keep reservation and uncertain artifacts. Never automatically call again.
    const allowed=new Set(['standard_shorten_script','standard_audio_quality_review',
      'standard_sample_changed','standard_video_quality_review','speech_cache_invalid_audio',
      'speech_cache_integrity','speech_cache_missing','speech_cache_capacity',
      'standard_demo_not_ready','standard_render_failed']);
    const reason=allowed.has(error?.message)?error.message:'standard_unknown_failure';
    await io.needsReview(approval.attempt_id,{stage,reason,elapsed_ms:Date.now()-started}).catch(()=>{});
    throw new Error('standard_needs_review', {cause:reason});
  }
}

if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  try {
    if(process.argv.length!==4 || process.argv[2]!=='--check-plan') fail('invalid_arguments');
    const raw=await readFile(process.argv[3],'utf8');
    if(Buffer.byteLength(raw)>50000) fail('plan_too_large');
    console.log(JSON.stringify(standardChecklist(JSON.parse(raw)),null,2));
  } catch {console.error('Standard plan needs review. No paid request was made.');process.exitCode=1;}
}
