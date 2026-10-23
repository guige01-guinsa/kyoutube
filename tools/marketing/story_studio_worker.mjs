import { createHash } from 'node:crypto';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { agentRequest, decodeAgent, validate, draftSchema } from './story_studio_contract.mjs';
import { resolveChannel } from './worker.mjs';
import { researchRequest, decodeResearch } from './story_studio_research.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const apiCodes = new Set(['invalid_api_key','insufficient_quota','rate_limit_exceeded','model_not_found',
  'permission_denied','insufficient_permissions','invalid_request_error','unsupported_parameter','unsupported_value']);
export async function openaiJson(response, stage, limit = 200000) {
  if (!['responses','chat','images'].includes(stage)) throw new Error('invalid_api_stage');
  if (!response.ok) {
    let code = 'unknown';
    try {
      const body = (await response.text()).slice(0, 16384);
      const error = JSON.parse(body)?.error;
      if (apiCodes.has(error?.code)) code = error.code;
      else if (apiCodes.has(error?.type)) code = error.type;
    } catch { /* Never echo provider bodies, credentials, prompts or arbitrary error text. */ }
    throw new Error(`openai_${stage}_http_${response.status}_${code}`);
  }
  return json(response, limit);
}
function safeFailure(error) {
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
  const requests = [
    ['responses','responses',{model:env.OPENAI_MARKETING_MODEL,store:false,max_output_tokens:512,max_tool_calls:1,
      tools:[{type:'web_search',search_context_size:'low'}],tool_choice:'required',
      input:'Find one official Korean tourism source about bibimbap. Reply with its title only.'}],
    ['chat','chat/completions',{model:env.OPENAI_MARKETING_MODEL,max_completion_tokens:128,
      messages:[{role:'user',content:'Reply with an object whose ok field is true.'}],
      response_format:{type:'json_schema',json_schema:{name:'connection_check',strict:true,
        schema:{type:'object',properties:{ok:{type:'boolean'}},required:['ok'],additionalProperties:false}}}}],
  ];
  const checked=[];
  for (const [stage,path,body] of requests) {
    await openaiJson(await fetcher(`https://api.openai.com/v1/${path}`,{method:'POST',
      headers:{Authorization:`Bearer ${env.OPENAI_API_KEY}`,'Content-Type':'application/json'},
      body:JSON.stringify(body),signal:AbortSignal.timeout(90000)}),stage);
    checked.push(stage);
  }
  return {api_access_checked:checked,images_checked:false,uploaded:false};
}
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
async function json(response, limit = 200000) {
  if (!response.ok) throw new Error('remote_request_failed');
  const text = await response.text();
  if (text.length > limit) throw new Error('remote_response_too_large');
  return JSON.parse(text);
}
export async function executeJob(job, io) {
  if (!uuid.test(job.id) || !uuid.test(job.lease_token) || !['draft','improve','render','upload'].includes(job.kind)) throw new Error('invalid_job');
  await io.check(); // Revalidate lease, global pause and administrator before side effects.
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
    const images=[];
    for (const prompt of creative.panels) {
      await io.check();
      images.push(await io.image({model:job.snapshot.image_model,
        prompt:`Original culinary webtoon panel, not an actual restaurant photograph. No lettering, logos or watermarks. Consistent character/style bible: ${creative.image_prompt}\nPanel: ${prompt}`,
        size:'1024x1536',quality:'low',n:1,output_format:'png'}));
    }
    const videos=await io.render(images,job.snapshot);
    const variants={};
    for(const language of ['ko','en','es']) {
      const video=videos[language];
      if(!video?.length || video.length>104857600) throw new Error('invalid_video_size');
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
  for (const key of ['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','OPENAI_API_KEY','OPENAI_MARKETING_MODEL','OPENAI_STORY_IMAGE_MODEL',
    'YOUTUBE_CLIENT_ID','YOUTUBE_CLIENT_SECRET','YOUTUBE_REFRESH_TOKEN']) if (!env[key]) throw new Error('missing_studio_configuration');
  if (!env.YOUTUBE_CHANNEL_ID && !env.YOUTUBE_CHANNEL_HANDLE) throw new Error('missing_channel');
  const root = new URL(env.SUPABASE_URL);
  if (root.protocol !== 'https:' || !/^[a-z0-9]+\.supabase\.co$/.test(root.hostname)) throw new Error('invalid_backend');
  const headers = { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` };
  const rpc = (p_action, p = {}) => jsonPromise(fetcher(new URL('/rest/v1/rpc/story_studio_work', root), {
    method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(30000), body: JSON.stringify({p_action,p}) }));
  await rpc('heartbeat', { text_model: env.OPENAI_MARKETING_MODEL, image_model: env.OPENAI_STORY_IMAGE_MODEL });
  const job = await rpc('claim');
  if (!job) return { idle: true };
  const lease = { id: job.id, token: job.lease_token };
  let directory;
  try {
    if (job.snapshot.text_model !== env.OPENAI_MARKETING_MODEL || job.snapshot.image_model !== env.OPENAI_STORY_IMAGE_MODEL) throw new Error('model_configuration_changed');
    directory = await mkdtemp(join(tmpdir(), 'recipe-story-studio-'));
    const api = async (path, body, limit, timeout) => openaiJson(await fetcher(`https://api.openai.com/v1/${path}`, {
      method: 'POST', headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body), signal: AbortSignal.timeout(timeout) }), path === 'responses' ? 'responses' : path.startsWith('images/') ? 'images' : 'chat', limit);
    const storage = path => new URL(`/storage/v1/object/story-previews/${path}`, root);
    const result = await executeJob(job, {
      check: () => rpc('check', lease),
      chat: body => api('chat/completions', body, 200000, 180000),
      research:body=>api('responses',body,250000,180000),
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
        if (!response.ok) throw new Error('preview_store_failed');
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
    await rpc('complete', {...lease,result});
    return { completed: job.id, kind: job.kind };
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
  const disclosures = { ko:'홍보용 창작 이야기 · AI 삽화 · 창작 음악 · 실제 이용자 후기가 아닙니다.',
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
  const run = process.env.STORY_STUDIO_PREFLIGHT === 'true' ? probeStudio : runStudio;
  run().then(result => console.log(JSON.stringify(result))).catch(error => {
    console.error(`Story studio stopped safely: ${safeFailure(error)}. Review before retry.`); process.exitCode = 1;
  });
}
