import {createHash} from 'node:crypto';
import {RECIPE_PROFILE,validateRecipePlan,recipePlanHash,boundedRecipeMap,validateRecipeVisuals} from './story_studio_recipe.mjs';
import {RECIPE_VOICE_PROFILE} from './story_studio_narration.mjs';
import {validateStandardAudio} from './story_studio_standard.mjs';
const digest=b=>createHash('sha256').update(b).digest('hex');
export async function executeRecipeJob(job,io) {
 const project=job.snapshot.project,plan=validateRecipePlan(project.plan),stage=job.snapshot.standard_stage;
 if(!['sample','render'].includes(stage)||job.request.sources_reviewed!==true) throw new Error('recipe_source_required');
 await io.check();
 const started=Date.now(),plan_hash=recipePlanHash(plan);
 const existingVoice=job.request.voice_use_confirmed===true&&project.sample?.review_mode==='existing_voice_without_sample';
 if(stage==='render'&&(!project.sample_approved_by||(!existingVoice&&project.sample?.plan_hash!==plan_hash))) throw new Error('standard_sample_listening_required');
 // Offline sketches are rendered per scene; the capture is retained for legacy IO.
 const demo=stage==='render'?await io.standardDemo():null;
 const selected=stage==='sample'?plan.scenes.slice(0,1):plan.scenes;
 const speechStarted=Date.now();
 const loadVoice=async(scene,index)=>{
  await io.check();const bytes=await io.standardSpeech(scene.spoken,'ko',RECIPE_VOICE_PROFILE);
  const info=validateStandardAudio(bytes,index===0?9.5:30);
  if(bytes.length>2000000) throw new Error('standard_audio_quality_review');
  if(stage==='render'&&!existingVoice&&index===0&&info.sha256!==project.sample.sha256) throw new Error('standard_sample_changed');
  return {bytes,info};
 };
 // Verify the cached approved first voice before requesting any other voice.
 const first=await loadVoice(selected[0],0);
 const audio=[first,...await boundedRecipeMap(selected.slice(1),(scene,index)=>loadVoice(scene,index+1))];
 const speech_ms=Date.now()-speechStarted;
 await io.check();let output;
 if(stage==='sample') {
  const path=`${job.id}/sample.wav`;await io.standardStoreSample(path,audio[0].bytes);
  output={path,...audio[0].info,voice_profile:RECIPE_VOICE_PROFILE};
 } else {
  // Renderer derives frame-aligned durations from the actual voice, never fixed gaps.
  const duration=audio.reduce((sum,a)=>sum+Math.ceil((a.info.seconds+.4)*24)/24,0);
  if(duration>180||duration<=0) throw new Error('recipe_duration_review');
  const {video,quality}=await io.standardRender(plan,plan.scenes.map(()=>demo),audio.map(a=>a.bytes));
  if(quality.sha256!==digest(video)||quality.seconds>180||quality.seconds<=0) throw new Error('standard_video_quality_review');
  validateRecipeVisuals(quality.visuals,plan.scenes.length);
  await io.check();const path=`${job.id}/ko.mp4`;await io.store(path,video);
  output={path,sha256:digest(video),seconds:quality.seconds,language:'ko',bytes:video.length,visuals:quality.visuals,voice_profile:RECIPE_VOICE_PROFILE};
 }
 const production_ms=Date.now()-started;
 const created=Date.parse(job.created_at ?? '');
 const queue_wait_ms=Number.isFinite(created)?Math.max(0,started-created):null;
 const draft_ms=project.source_video_url ? project.source_receipt?.automation_ms : 0;
 const total_elapsed_ms=queue_wait_ms!==null&&Number.isFinite(draft_ms)&&draft_ms>=0 ? draft_ms+queue_wait_ms+production_ms : null;
 return {...output,plan_hash,profile:RECIPE_PROFILE,production_ms,speech_ms,
  queue_wait_ms,draft_ms: draft_ms ?? null,total_elapsed_ms,
  timing_scope:'draft_and_render_including_queues_excluding_human_review',
  target_ms:300000,target_met:total_elapsed_ms===null?null:total_elapsed_ms<=300000,new_illustrations:0,
  offline_sketches:stage==='render'?plan.scenes.length:0,
  recipe_preserved:true,voice_metrics:audio.map((a,index)=>({index,...a.info}))};
}
