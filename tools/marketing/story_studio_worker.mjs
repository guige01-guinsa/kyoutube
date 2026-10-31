import { createHash } from 'node:crypto';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { agentRequest, decodeAgent, validate, draftSchema } from './story_studio_contract.mjs';
import { resolveChannel } from './worker.mjs';
import { researchRequest, decodeResearch } from './story_studio_research.mjs';
import { demoAssets } from './story_studio_demo.mjs';
import {reeditSpec, prepareNarration, speechAudio} from './story_studio_narration.mjs';
import {validateRecipeVisuals} from './story_studio_recipe.mjs';
import {cachedSpeech, SPEECH_CACHE_MAX_BYTES} from './story_studio_speech_cache.mjs';
import {executeStandardJob} from './story_studio_standard_worker.mjs';
import {fetchRecipeSource,recipeVideoId,findRecipeAlternative} from './story_studio_recipe_source.mjs';
import {validateStandardAudio} from './story_studio_standard.mjs';
import {runApprovedPipeline} from './story_studio_pipeline.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const REEDIT_MAX_PREVIEW_BYTES = 45000000;
const storageCodes = new Set(['EntityTooLarge','AccessDenied','InvalidMimeType','NoSuchBucket',
  'KeyAlreadyExists','ResourceAlreadyExists','DatabaseError','InternalError','unknown']);
export async function previewStoreFailure(response) {
  let code = 'unknown';
  try {
    const body = JSON.parse((await response.text()).slice(0, 16384));
    if (storageCodes.has(body?.code)) code = body.code;
    else if (storageCodes.has(body?.error)) code = body.error;
  } catch { /* Do not log provider messages, paths or credentials. */ }
  return `preview_store_http_${response.status}_${code}`;
}
const apiCodes = new Set(['invalid_api_key','insufficient_quota','rate_limit_exceeded','model_not_found',
  'permission_denied','insufficient_permissions','invalid_request_error','unsupported_parameter','unsupported_value',
  'missing_scope','missing_scope_model_request','missing_scope_responses_write','missing_scope_responses_read',
  'missing_scope_threads_read','missing_scope_threads_write','missing_scope_images_write',
  'project_model_denied','model_not_found_requested','model_not_found_other']);
export async function openaiJson(response, stage, limit = 200000, requestedModel = '') {
  if (!['responses','chat','images'].includes(stage)) throw new Error('invalid_api_stage');
  if (!response.ok) {
    let code = 'unknown';
    try {
      const body = (await response.text()).slice(0, 16384);
      const error = JSON.parse(body)?.error;
      if (apiCodes.has(error?.code)) code = error.code;
      else if (apiCodes.has(error?.type)) code = error.type;
      if (code === 'model_not_found') {
        const message = typeof error?.message === 'string' ? error.message : '';
        if (/does not have access to model|model[^.]*not allowed|not allowed[^.]*model/i.test(message)) code='project_model_denied';
        else if (requestedModel && message.includes(requestedModel)) code='model_not_found_requested';
        else if (/\bgpt-[a-z0-9.-]+\b/i.test(message)) code='model_not_found_other';
      }
      // Some 401 responses have no specific code. Classify locally; never log the message.
      if ([401,403].includes(response.status) && ['unknown','invalid_request_error','missing_scope'].includes(code)) {
        const message = typeof error?.message === 'string' ? error.message : '';
        if (/incorrect api key|invalid api key|api key.*(?:expired|revoked)/i.test(message)) code='invalid_api_key';
        else if (/insufficient permissions|missing scopes/i.test(message)) {
          code='insufficient_permissions';
          const missing=message.match(/missing scopes:\s*([a-z._, ]+)/i)?.[1] ?? '';
          const scopes=[['model.request','model_request'],['api.responses.write','responses_write'],
            ['api.responses.read','responses_read'],['api.threads.read','threads_read'],
            ['api.threads.write','threads_write'],['api.images.write','images_write']];
          for (const [scope,label] of scopes) if (missing.split(/[ ,]+/).map(s=>s.replace(/\.$/,'')).includes(scope)) {code=`missing_scope_${label}`;break;}
        }
      }
    } catch { /* Never echo provider bodies, credentials, prompts or arbitrary error text. */ }
    throw new Error(`openai_${stage}_http_${response.status}_${code}`);
  }
  return json(response, limit);
}
const reeditCodes = new Set(['invalid_voice_file','invalid_voice_format','invalid_voice_duration',
  'invalid_scroll_text','scroll_text_overflow','invalid_reedit_title','reedit_title_overflow',
  'korean_only_required','invalid_chunk_count','narration_too_fast_for_scroll',
  'edition_duration_out_of_bounds','output_already_exists','reedit_video_too_large','plan_too_large',
  'invalid_arguments','invalid_video_format','invalid_pixel_format','invalid_video_length',
  'renderer_timeout','renderer_command_failed','unknown']);
export function reeditFailureCode(result) {
  if (result?.error?.code === 'ETIMEDOUT') return 'renderer_timeout';
  const match = /^REEDIT_DIAGNOSTIC:([a-z_]+)$/m.exec(result?.stderr ?? '');
  return match && reeditCodes.has(match[1]) ? match[1] : 'unknown';
}
export function safeFailure(error) {
  const standardCodes = ['pipeline_invalid_followup','pipeline_chain_limit','invalid_target_job','target_job_mismatch','recipe_source_external_required','recipe_source_translation_required','recipe_alternative_unavailable','recipe_source_access','recipe_source_incomplete','recipe_source_cache','recipe_source_required','recipe_duration_review','recipe_visual_review','standard_shorten_script','standard_audio_quality_review',
    'standard_sample_changed','standard_video_quality_review','standard_unknown_failure',
    'standard_demo_not_ready','standard_render_failed','standard_invalid_plan',
    'standard_sources_required','standard_invalid_source','standard_six_scenes_required',
    'standard_invalid_scene','standard_unattributed_fact','standard_sample_listening_required',
    'speech_cache_invalid_audio','speech_cache_integrity','speech_cache_missing','speech_cache_capacity'];
  if (standardCodes.includes(error?.message)) return error.message;
  if (error?.message === 'standard_needs_review') {
    return standardCodes.includes(error.cause) ? error.cause : 'standard_unknown_failure';
  }
  if (['speech_cache_invalid_audio','speech_cache_invalid_record','speech_cache_missing',
    'speech_cache_integrity','speech_cache_read_failed','speech_cache_write_failed',
    'speech_cache_checkpoint_failed','speech_cache_capacity'].includes(error?.message)) return error.message;
  // runStudio and the CLI both sanitize errors. Preserve only known safe results.
  if (['runtime_timeouterror','runtime_aborterror','runtime_typeerror','runtime_syntaxerror',
    'transport_etimedout','transport_enotfound','transport_econnreset','transport_econnrefused',
    'transport_und_err_connect_timeout','transport_und_err_headers_timeout','transport_err_invalid_char'].includes(error?.message)) return error.message;
  const storage = /^preview_store_http_([45][0-9]{2})_([A-Za-z]+)$/.exec(error?.message ?? '');
  if (storage && storageCodes.has(storage[2])) return error.message;
  if (error?.message === 'invalid_reedit_source_video') return error.message;
  if (['invalid_speech_audio','preview_store_failed','preview_read_failed','preview_too_large',
    'reedit_source_changed','reedit_source_missing','unexpected_video_languages','invalid_video_size'].includes(error?.message)) return error.message;
  const reedit = /^narrated_reedit_failed_([a-z_]+)$/.exec(error?.message ?? '');
  if (reedit && reeditCodes.has(reedit[1])) return error.message;
  if (/^speech_http_[45][0-9]{2}$/.test(error?.message ?? '')) return error.message;
  const match = /^openai_(responses|chat|images)_http_[45][0-9]{2}_([a-z_]+)$/.exec(error?.message ?? '');
  if (match && (apiCodes.has(match[2]) || match[2] === 'unknown')) return error.message;
  if (['missing_studio_configuration','invalid_key_format'].includes(error?.message)) return error.message;
  if (['ETIMEDOUT','ENOTFOUND','ECONNRESET','ECONNREFUSED','UND_ERR_CONNECT_TIMEOUT','UND_ERR_HEADERS_TIMEOUT','ERR_INVALID_CHAR'].includes(error?.cause?.code)) return `transport_${error.cause.code.toLowerCase()}`;
  if (['TimeoutError','AbortError','TypeError','SyntaxError'].includes(error?.name)) return `runtime_${error.name.toLowerCase()}`;
  return 'studio_job_needs_review';
}
// Manual credential/model probe: no database access, image generation or upload, no retries.
export async function probeStudio(env = process.env, fetcher = fetch) {
  if (env.STORY_STUDIO_PREFLIGHT !== 'true' || env.STORY_STUDIO_DRY_RUN !== 'false') return {disabled:true};
  if (!env.OPENAI_API_KEY || !env.OPENAI_MARKETING_MODEL) throw new Error('missing_studio_configuration');
  if (!/^sk-[A-Za-z0-9_-]+$/.test(env.OPENAI_API_KEY)) throw new Error('invalid_key_format');
  // Use the production request builder, but keep the access probe's small limits.
  // HTTP acceptance is not a completed research memo or production-quality draft.
  const researchProbe = {...researchRequest({text_model:env.OPENAI_MARKETING_MODEL,
    brief:'Find official Korean tourism and culinary institution sources about bibimbap.'}),
    max_output_tokens:512,max_tool_calls:1};
  const requests = [
    ['responses','responses',researchProbe],
    ['chat','chat/completions',{model:env.OPENAI_MARKETING_MODEL,max_completion_tokens:128,
      messages:[{role:'user',content:'Reply with an object whose ok field is true.'}],
      response_format:{type:'json_schema',json_schema:{name:'connection_check',strict:true,
        schema:{type:'object',properties:{ok:{type:'boolean'}},required:['ok'],additionalProperties:false}}}}],
  ];
  const checked=[];
  for (const [stage,path,body] of requests) {
    await openaiJson(await fetcher(`https://api.openai.com/v1/${path}`,{method:'POST',
      headers:{Authorization:`Bearer ${env.OPENAI_API_KEY}`,'Content-Type':'application/json'},
      body:JSON.stringify(body),signal:AbortSignal.timeout(90000)}),stage,200000,body.model);
    checked.push(stage);
  }
  return {api_access_checked:checked,images_checked:false,uploaded:false};
}
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export function validateStandardRenderedVideo(plan,video,quality) {
 const q=quality?.video,recipe=plan?.profile==='ko-180-source-v1';
 if(q?.sha256!==sha256(video)||q?.audio!==true||!Array.isArray(q?.size)||q.size.join(',')!=='720,1280'||
  !Number.isFinite(q.seconds)||(recipe?q.seconds<=0||q.seconds>180||q.frames!==Math.round(q.seconds*24):
  q.frames!==1440||q.seconds<59.9||q.seconds>60)) throw new Error('standard_render_failed');
 if(recipe) validateRecipeVisuals(quality.visuals,plan.scenes?.length);
 return q;
}
async function json(response, limit = 200000) {
  if (!response.ok) throw new Error('remote_request_failed');
  const text = await response.text();
  if (text.length > limit) throw new Error('remote_response_too_large');
  return JSON.parse(text);
}
export async function executeJob(job, io) {
  if (!uuid.test(job.id) || !uuid.test(job.lease_token) || !['draft','improve','render','upload'].includes(job.kind)) throw new Error('invalid_job');
  await io.check(); // Revalidate lease, global pause and administrator before side effects.
  if (job.snapshot?.standard_profile === 'ko-60-v1') return executeStandardJob(job,io);
  if (job.kind === 'improve') return decodeAgent(await io.chat(agentRequest(job)), job.kind);
  if (job.kind === 'draft') {
    const research = decodeResearch(await io.research(researchRequest(job.snapshot)));
    await io.check();
    const draft = decodeAgent(await io.chat(agentRequest({...job,snapshot:{...job.snapshot,research}})),job.kind);
    return {...draft,research};
  }
  const e = job.snapshot.episode;
  const {research,...creative}=e.draft;
  validate(creative, draftSchema);
  if (job.kind === 'render') {
    if(job.request.sources_reviewed !== true) throw new Error('source_review_required');
    let videos;
    if (reeditSpec(job.snapshot)) {
      const prepared=await prepareNarration(job.snapshot,io);
      await io.check();
      videos=await io.reedit(prepared);
    } else {
    // Validate approved captures before any paid image request. Never draw fake UI.
    const demos = await demoAssets(job.snapshot);
    const images=[];
    for (const [index,prompt] of creative.panels.entries()) {
      await io.check();
      if (demos.has(index)) { images.push(demos.get(index)); continue; }
      images.push(await io.image({model:job.snapshot.image_model,
        prompt:`Original culinary webtoon panel, not an actual restaurant photograph. No lettering, logos or watermarks. Consistent character/style bible: ${creative.image_prompt}\nPanel: ${prompt}`,
        size:'1024x1536',quality:'low',n:1,output_format:'png'}));
    }
    videos=await io.render(images,job.snapshot);
    }
    const variants={};
    const outputLanguages=reeditSpec(job.snapshot) ? ['ko'] : ['ko','en','es'];
    if (Object.keys(videos).sort().join(',')!==[...outputLanguages].sort().join(',')) throw new Error('unexpected_video_languages');
    for(const language of outputLanguages) {
      const video=videos[language];
      const maxBytes = reeditSpec(job.snapshot) ? REEDIT_MAX_PREVIEW_BYTES : 104857600;
      if(!video?.length || video.length>maxBytes) throw new Error('invalid_video_size');
      await io.check();
      const path=`${job.id}/${language}.mp4`;
      await io.store(path,video);
      variants[language]={asset_path:path,sha256:sha256(video)};
    }
    return {variants};
  }
  const language=job.snapshot.language;
  if(!['ko','en','es'].includes(language)) throw new Error('invalid_language');
  const variant=e.variants?.[language];
  if (job.request.preview_reviewed !== true || job.request.asset_sha256 !== variant?.sha256 || variant.youtube_id ||
    !new RegExp(`^[0-9a-f-]{36}/${language}\\.mp4$`).test(variant?.asset_path ?? '')) throw new Error('preview_approval_required');
  const video = await io.load(variant.asset_path);
  if (sha256(video) !== variant.sha256) throw new Error('preview_changed');
  await io.check();
  const youtube_id = await io.upload(video, job.snapshot);
  if (!/^[A-Za-z0-9_-]{11}$/.test(youtube_id)) throw new Error('upload_uncertain');
  return { youtube_id, privacy: 'private' };
}

export async function runStudio(env = process.env, fetcher = fetch) {
  if (env.STORY_STUDIO_ENABLED !== 'true' || env.STORY_STUDIO_DRY_RUN !== 'false') return { disabled: true };
  if(env.STORY_STUDIO_JOB_ID && !uuid.test(env.STORY_STUDIO_JOB_ID)) throw new Error('invalid_target_job');
  for (const key of ['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','OPENAI_API_KEY','OPENAI_MARKETING_MODEL','OPENAI_STORY_IMAGE_MODEL',
    'YOUTUBE_CLIENT_ID','YOUTUBE_CLIENT_SECRET','YOUTUBE_REFRESH_TOKEN']) if (!env[key]) throw new Error('missing_studio_configuration');
  if (!env.YOUTUBE_CHANNEL_ID && !env.YOUTUBE_CHANNEL_HANDLE) throw new Error('missing_channel');
  const root = new URL(env.SUPABASE_URL);
  if (root.protocol !== 'https:' || !/^[a-z0-9]+\.supabase\.co$/.test(root.hostname)) throw new Error('invalid_backend');
  const headers = { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` };
  const rpc = (p_action, p = {}) => jsonPromise(fetcher(new URL('/rest/v1/rpc/story_studio_work', root), {
    method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(30000), body: JSON.stringify({p_action,p}) }));
  // A bundled real capture is required; no arbitrary URL or synthetic UI fallback.
  const standardDemo=async()=>{
    const manifest=JSON.parse(await readFile(new URL('../../assets/story_demos/standard-guide-v1.json',import.meta.url),'utf8'));
    if(manifest.file!=='bibimbap-draft.jpg' || !/^[a-f0-9]{64}$/.test(manifest.sha256 ?? '') || manifest.personal_data_removed!==true)
      throw new Error('standard_demo_not_ready');
    const bytes=await readFile(new URL('../../assets/story_demos/bibimbap-draft.jpg',import.meta.url));
    if(bytes.length>2000000 || sha256(bytes)!==manifest.sha256) throw new Error('standard_demo_not_ready');
    return bytes;
  };
  const standardCaptureReady=await standardDemo().then(()=>true,()=>false);
  await rpc('heartbeat', { text_model: env.OPENAI_MARKETING_MODEL, image_model: env.OPENAI_STORY_IMAGE_MODEL,
    standard_profile:'ko-60-v1',standard_capture_ready:standardCaptureReady });
  const job = await rpc('claim',env.STORY_STUDIO_JOB_ID?{job_id:env.STORY_STUDIO_JOB_ID}:{});
  if (!job) return { idle: true };
  if(env.STORY_STUDIO_JOB_ID && job.id!==env.STORY_STUDIO_JOB_ID) throw new Error('target_job_mismatch');
  const lease = { id: job.id, token: job.lease_token };
  let directory;
  try {
    if (job.snapshot.text_model !== env.OPENAI_MARKETING_MODEL || job.snapshot.image_model !== env.OPENAI_STORY_IMAGE_MODEL) throw new Error('model_configuration_changed');
    directory = await mkdtemp(join(tmpdir(), 'recipe-story-studio-'));
    const api = async (path, body, limit, timeout) => openaiJson(await fetcher(`https://api.openai.com/v1/${path}`, {
      method: 'POST', headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body), signal: AbortSignal.timeout(timeout) }), path === 'responses' ? 'responses' : path.startsWith('images/') ? 'images' : 'chat', limit, body.model);
    const storage = path => new URL(`/storage/v1/object/story-previews/${path}`, root);
    const standard=job.snapshot.standard_profile==='ko-60-v1';
    const checkpoint=async(action,key,metadata={})=>{
      const response=await fetcher(new URL(`/rest/v1/rpc/${standard?'story_standard_checkpoint':'story_speech_checkpoint'}`,root),{
        method:'POST',headers:{...headers,'Content-Type':'application/json'},signal:AbortSignal.timeout(30000),
        body:JSON.stringify({p_action:action,p:{...lease,key,...metadata}})});
      if(!response.ok) {
        let capacity=false;
        try {capacity=(await response.json()).message==='STORY_SPEECH_CAPACITY';} catch { /* no body logging */ }
        throw new Error(capacity?'speech_cache_capacity':'speech_cache_checkpoint_failed');
      }
      return json(response);
    };
    const speechStorage=path=>new URL(`/storage/v1/object/${standard?'story-standard-samples':'story-speech-cache'}/${path}`,root);
    const speechIO={
      check:()=>rpc('check',lease),reserve:key=>checkpoint('reserve',key),
      commit:(key,metadata)=>checkpoint('commit',key,metadata),
      generate:async(text,language,profile)=>{
        if(job.request.cached_only===true) throw new Error('speech_cache_missing');
        const audio=await speechAudio(text,language,env.OPENAI_API_KEY,fetcher,profile);
        if(standard) validateStandardAudio(audio,job.snapshot.project?.plan?.profile==='ko-180-source-v1'?30:9.5);
        return audio;
      },
      read:async path=>{
        const response=await fetcher(speechStorage(path),{headers,signal:AbortSignal.timeout(60000),redirect:'error'});
        if(!response.ok) {
          if(response.status===404) return null;
          if(response.status===400) {
            let body; try {body=await response.json();} catch { /* fail closed */ }
            if(body?.code==='NoSuchKey' || (String(body?.statusCode)==='404' && body?.error==='not_found')) return null;
          }
          throw new Error('speech_cache_read_failed');
        }
        if(Number(response.headers.get('content-length'))>SPEECH_CACHE_MAX_BYTES) throw new Error('speech_cache_invalid_audio');
        const bytes=Buffer.from(await response.arrayBuffer());
        if(bytes.length>SPEECH_CACHE_MAX_BYTES) throw new Error('speech_cache_invalid_audio');
        return bytes;
      },
      write:async(path,audio)=>{
        const response=await fetcher(speechStorage(path),{method:'POST',headers:{...headers,'Content-Type':'audio/wav','x-upsert':'false'},
          body:audio,signal:AbortSignal.timeout(60000),redirect:'error'});
        if(!response.ok) throw new Error('speech_cache_write_failed');
      },
    };
    const result = await executeJob(job, {
      check: () => rpc('check', lease),
      recipeSource:async url=>{
        const id=recipeVideoId(url),cacheUrl=new URL('/rest/v1/story_recipe_sources',root);
        cacheUrl.searchParams.set('video_id',`eq.${id}`);cacheUrl.searchParams.set('limit','1');
        const cached=await json(await fetcher(cacheUrl,{headers,signal:AbortSignal.timeout(15000)}));
        const record=Array.isArray(cached)?cached[0]:null;
        if(record && Date.now()-Date.parse(record.fetched_at)>=0 && Date.now()-Date.parse(record.fetched_at)<86400000) {
          if(record.source?.url!==url||typeof record.source.description!=='string'||sha256(Buffer.from(record.source.description))!==record.source.sha256) throw new Error('recipe_source_cache');
          return record.source;
        }
        await rpc('check',lease);const source=await fetchRecipeSource(url,env,fetcher);
        await rpc('check',lease);
        const saved=await fetcher(new URL('/rest/v1/story_recipe_sources',root),{
          method:'POST',headers:{...headers,'Content-Type':'application/json',Prefer:'resolution=merge-duplicates'},
          body:JSON.stringify({video_id:id,source,fetched_at:source.checked_at}),signal:AbortSignal.timeout(15000)});
        if(!saved.ok) throw new Error('recipe_source_cache');return source;
      },
      recipeAlternative:(url,food,reason)=>findRecipeAlternative(url,food,reason,env,fetcher),
      standardSpeech:(text,language,profile)=>cachedSpeech(text,language,speechIO,profile),
      standardDemo,
      standardStoreSample:async(path,audio)=>{
        if(path!==`${job.id}/sample.wav` || audio.length>2000000) throw new Error('invalid_speech_audio');
        await speechIO.write(path,audio);
        const saved=await speechIO.read(path);
        if(!saved || sha256(saved)!==sha256(audio)) throw new Error('speech_cache_integrity');
      },
      standardRender:async(plan,panels,audio)=>{
        await writeFile(join(directory,'plan.json'),JSON.stringify(plan));
        for(let i=0;i<plan.scenes.length;i++) {
          await writeFile(join(directory,`panel-${i}.png`),panels[i]);
          await writeFile(join(directory,`ko-${i}.wav`),audio[i]);
        }
        const rendered=spawnSync(env.STORY_PYTHON || 'python',
          [fileURLToPath(new URL(plan.profile==='ko-180-source-v1'?'./story_studio_recipe_render.py':'./story_studio_standard_render.py',import.meta.url)),directory],
          {timeout:360000,encoding:'utf8',maxBuffer:1000000});
        if(rendered.status!==0) throw new Error('standard_render_failed');
        const video=await readFile(join(directory,'ko.mp4'));
        const quality=JSON.parse(await readFile(join(directory,'quality.json'),'utf8'));
        validateStandardRenderedVideo(plan,video,quality);
        return {video,quality:{...quality.video,...(quality.visuals?{visuals:quality.visuals}:{})}};
      },
      chat: body => api('chat/completions', body, 200000, 180000),
      research:body=>api('responses',body,250000,180000),
      sourceEpisode: async id => {
        if (!uuid.test(id)) throw new Error('invalid_reedit_source');
        const query=new URL('/rest/v1/story_episodes',root);
        query.searchParams.set('id',`eq.${id}`);
        query.searchParams.set('series_id',`eq.${job.snapshot.series.id}`);
        query.searchParams.set('select','id,series_id,status,brief,variants');
        const rows=await json(await fetcher(query,{headers,signal:AbortSignal.timeout(30000)}));
        if (!Array.isArray(rows) || rows.length!==1) throw new Error('reedit_source_missing');
        return rows[0];
      },
      validateSource: async video => {
        await writeFile(join(directory,'source.mp4'),video);
        const checked=spawnSync(env.STORY_PYTHON || 'python',[
          fileURLToPath(new URL('./story_studio_reedit.py',import.meta.url)),
          '--validate-source',join(directory,'source.mp4')],
          {cwd:fileURLToPath(new URL('.',import.meta.url)),timeout:120000,encoding:'utf8',maxBuffer:100000});
        if (checked.status!==0) throw new Error('invalid_reedit_source_video');
        console.log('Re-edit source validated before paid speech.');
      },
      speech:async(text,language)=>{
        const audio=await cachedSpeech(text,language,speechIO);
        console.log('Re-edit speech chunk verified in private storage.');
        return audio;
      },
      reedit: async ({plan,voices}) => {
        console.log('Re-edit speech returned; starting offline video assembly.');
        await writeFile(join(directory,'narration.json'),JSON.stringify(plan));
        for (const language of Object.keys(plan)) for (const [i,audio] of voices[language].entries()) {
          await writeFile(join(directory,`${language}-${String(i).padStart(2,'0')}.wav`),audio);
        }
        const rendered=spawnSync(env.STORY_PYTHON || 'python',
          [fileURLToPath(new URL('./story_studio_reedit.py',import.meta.url)),directory],
          {timeout:900000,encoding:'utf8',maxBuffer:1000000});
        if (rendered.status!==0) throw new Error(`narrated_reedit_failed_${reeditFailureCode(rendered)}`);
        console.log('Re-edit video verified; preparing private preview storage.');
        return Object.fromEntries(await Promise.all(Object.keys(plan).map(async language=>[language,await readFile(join(directory,`${language}.mp4`))])));
      },
      image: async body => {
        const result = await api('images/generations', body, 30000000, 240000);
        const encoded = result.data?.[0]?.b64_json;
        if (typeof encoded !== 'string' || !/^[A-Za-z0-9+/=]+$/.test(encoded)) throw new Error('invalid_image');
        const bytes = Buffer.from(encoded, 'base64');
        if (!bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw new Error('invalid_image');
        return bytes;
      },
      render: async (images, snapshot) => {
        for(let i=0;i<images.length;i++) await writeFile(join(directory, `panel-${i}.png`), images[i]);
        await writeFile(join(directory, 'input.json'), JSON.stringify(snapshot));
        const rendered = spawnSync(env.STORY_PYTHON || 'python', [fileURLToPath(new URL('./story_studio_render.py', import.meta.url)),
          join(directory,'input.json'), directory],
          { timeout: 360000, encoding: 'utf8', maxBuffer: 1000000 });
        if (rendered.status !== 0) throw new Error('render_failed');
        return Object.fromEntries(await Promise.all(['ko','en','es'].map(async language=>[language,await readFile(join(directory,`${language}.mp4`))])));
      },
      store: async (path, video) => {
        const response = await fetcher(storage(path), { method:'POST', headers:{...headers,'Content-Type':'video/mp4','x-upsert':'false'},
          body:video, signal:AbortSignal.timeout(120000) });
        if (!response.ok) throw new Error(await previewStoreFailure(response));
      },
      load: async path => {
        const response = await fetcher(storage(path), { headers, signal: AbortSignal.timeout(120000) });
        if (!response.ok || Number(response.headers.get('content-length')) > 104857600) throw new Error('preview_read_failed');
        const bytes = Buffer.from(await response.arrayBuffer());
        if (bytes.length > 104857600) throw new Error('preview_too_large');
        return bytes;
      },
      upload: (video, snapshot) => privateUpload(video, snapshot, env, fetcher),
    });
    const completed=await rpc('complete', {...lease,result});
    const next=completed?.next_job_id;
    const automatic=job.snapshot?.project?.plan?.profile==='ko-180-source-v1' &&
      job.request.auto_private_upload===true && job.request.private_upload_confirmed===true;
    if(next && (!automatic||job.snapshot.standard_stage!=='render'||!uuid.test(next))) throw new Error('pipeline_invalid_followup');
    return { completed: job.id, kind: job.kind,...(next?{next_job_id:next,auto_private_upload:true}:{}) };
  } catch (error) {
    // Even a lost completion response must never cause a second paid call/upload.
    await rpc('fail', lease).catch(() => {});
    throw new Error(safeFailure(error));
  } finally {
    // Only this invocation's validated mkdtemp directory is ever removed.
    if (directory) await rm(directory, { recursive:true, force:true });
  }
}
async function jsonPromise(response) { return json(await response); }
export async function privateUpload(video, snapshot, env, fetcher = fetch) {
  const oauth = await json(await fetcher('https://oauth2.googleapis.com/token', { method:'POST', signal:AbortSignal.timeout(30000),
    body:new URLSearchParams({ client_id:env.YOUTUBE_CLIENT_ID, client_secret:env.YOUTUBE_CLIENT_SECRET,
      refresh_token:env.YOUTUBE_REFRESH_TOKEN, grant_type:'refresh_token' }) }));
  if (!oauth.access_token) throw new Error('youtube_auth_failed');
  const auth = { Authorization:`Bearer ${oauth.access_token}` };
  const yt = path => jsonPromise(fetcher(`https://www.googleapis.com/youtube/v3/${path}`, {headers:auth,signal:AbortSignal.timeout(30000)}));
  const channelId = await resolveChannel(env, yt);
  const disclosures = snapshot.project?.plan?.profile==='ko-180-source-v1' ? {
    ko:'원본 영상 레시피 안내 · AI 내레이션 · 재료표와 조리 안내 화면 · 창작 배경음악. 원본 영상의 출처는 아래에서 확인하세요.',
  } : snapshot.standard_profile==='ko-60-v1' ? {
    ko:'한국어 1분 음식 안내 · AI 내레이션 · 창작 삽화와 음악 · 앱 안내에는 실제 캡처를 사용했습니다. 삽화는 실제 조리 장면이나 역사 사료가 아닙니다.',
  } : reeditSpec(snapshot) ? {
    ko:'음식 정보 안내 · AI 내레이션 · 재사용한 AI 삽화와 창작 음악 · 삽화는 조리 실사나 역사 사료가 아닙니다. 가정용 조리 예시는 특정 업소의 공식 조리법이 아닙니다.',
    en:'Food guide · AI-generated narration · Reused AI illustrations and original music. Illustrations are not cooking footage or historical records. The home recipe is not an official restaurant recipe.',
    es:'Guía culinaria · Narración generada por IA · Ilustraciones de IA y música original reutilizadas. Las imágenes no son grabaciones de cocina ni documentos históricos. La receta casera no es una receta oficial de un restaurante.',
  } : { ko:'홍보용 창작 이야기 · AI 삽화 · 창작 음악 · 실제 이용자 후기가 아닙니다.',
    en:'Fictional promotional story · AI illustration · Original music · Not a customer testimonial.',
    es:'Historia promocional ficticia · Ilustración de IA · Música original · No es un testimonio real.' };
  const language=snapshot.language;
  if(!['ko','en','es'].includes(language)) throw new Error('invalid_language');
  const edition=language==='ko'?snapshot.episode.draft:snapshot.episode.draft.translations[language];
  const sourceLinks=(snapshot.episode.draft.research?.sources ?? []).map(s=>`${s.title}\n${s.url}`).join('\n');
  const metadata = { snippet: { title:edition.title, categoryId:'26', channelId,
    defaultLanguage:language, description:`${disclosures[language]}\n\nhttps://recipe-scout-workspace.web.app/\n\nSources / 출처 / Fuentes\n${sourceLinks}\n\n#RecipeScout`.slice(0,4800) },
    status:{ privacyStatus:'private', selfDeclaredMadeForKids:false, containsSyntheticMedia:true } };
  const init = await fetcher('https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status', {
    method:'POST', headers:{...auth,'Content-Type':'application/json','X-Upload-Content-Type':'video/mp4','X-Upload-Content-Length':String(video.length)},
    body:JSON.stringify(metadata), signal:AbortSignal.timeout(30000) });
  if (!init.ok) throw new Error('youtube_init_failed');
  const location = new URL(init.headers.get('location') || 'https://invalid.local');
  if (location.origin !== 'https://www.googleapis.com') throw new Error('invalid_upload_location');
  const uploaded = await json(await fetcher(location, {method:'PUT',headers:{'Content-Type':'video/mp4'},body:video,signal:AbortSignal.timeout(180000)}));
  if (!/^[A-Za-z0-9_-]{11}$/.test(uploaded.id ?? '')) throw new Error('upload_uncertain');
  const verified = await yt(`videos?part=status&id=${uploaded.id}`);
  if (verified.items?.[0]?.status?.privacyStatus !== 'private') throw new Error('upload_privacy_uncertain');
  return uploaded.id;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const run = process.env.STORY_STUDIO_PREFLIGHT === 'true' ? probeStudio :
    (env=process.env)=>runApprovedPipeline(env,scoped=>runStudio(scoped));
  run().then(result => console.log(JSON.stringify(result))).catch(error => {
    console.error(`Story studio stopped safely: ${safeFailure(error)}. Review before retry.`); process.exitCode = 1;
  });
}
