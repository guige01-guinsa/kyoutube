// Explicit, reviewed re-edits only. No image generation, arbitrary URLs or retries.
import {createHash} from 'node:crypto';

export const NARRATION_MODEL = 'gpt-4o-mini-tts';
export const RECIPE_VOICE_PROFILE = 'fictional-girl-8-ko-v1';
const languages = ['ko','en','es'];
const marker = /^\[ENCYCLOPEDIA_REEDIT:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):([0-9a-f]{64})\]$/;
export function reeditSpec(snapshot) {
  const brief = snapshot.episode?.brief ?? '';
  if (!brief.includes('[ENCYCLOPEDIA_REEDIT')) return null;
  const rows = brief.split(/\r?\n/).filter(line=>line.includes('[ENCYCLOPEDIA_REEDIT'));
  const match = rows.length === 1 && marker.exec(rows[0]);
  if (!match || snapshot.episode.id === match[1]) throw new Error('invalid_reedit_marker');
  return {episodeId:match[1],sha256:match[2]};
}
export function narrationChunks(chapters) {
  if (!Array.isArray(chapters) || chapters.length<3 || chapters.length>8) throw new Error('invalid_narration');
  const chunks=[];
  for (const chapter of chapters) {
    if (typeof chapter!=='string' || !chapter.trim() || [...chapter].length>1500 || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(chapter)) throw new Error('invalid_narration');
    // Preserve the reviewed text exactly, including punctuation and accents.
    let rest=chapter.trim();
    while (rest.length) {
      if (rest.length<=400) {chunks.push(rest);break;}
      const window=rest.slice(0,400);
      const candidates=[...window.matchAll(/[.!?。](?:[”’"']?)(?=\s)/g)];
      const boundary=candidates.at(-1);
      let cut=boundary && boundary.index>=180 ? boundary.index+boundary[0].length : window.lastIndexOf(' ');
      if (cut<100) throw new Error('narration_needs_sentence_breaks');
      chunks.push(rest.slice(0,cut)); rest=rest.slice(cut).trim();
    }
  }
  if (chunks.length>32) throw new Error('narration_too_many_chunks');
  return chunks;
}
export function narrationPlan(snapshot) {
  const draft=snapshot.episode.draft;
  // New narrated re-edits are Korean-only. Archived translations are not spoken.
  const plan=Object.fromEntries(['ko'].map(language=>{
    const edition=draft;
    return [language,{title:edition.title,chunks:narrationChunks(edition.chapters)}];
  }));
  if (Object.values(plan).reduce((n,v)=>n+v.chunks.join('').length,0)>32000) throw new Error('narration_too_large');
  return plan;
}
export function verifyReeditSource(source,snapshot,spec) {
  const variant=source?.variants?.ko;
  if (source?.id!==spec.episodeId || source.series_id!==snapshot.series.id ||
      !['preview','uploaded'].includes(source.status) || !source.brief?.split(/\r?\n/).includes('[APP_DEMO:bibimbap-v1]') ||
      !/^[0-9a-f-]{36}\/ko\.mp4$/.test(variant?.asset_path ?? '') || variant.sha256!==spec.sha256) throw new Error('reedit_source_changed');
  return variant.asset_path;
}
export async function prepareNarration(snapshot,io) {
  const spec=reeditSpec(snapshot);
  if (!spec) throw new Error('reedit_marker_required');
  const plan=narrationPlan(snapshot); // validate every edition before spending
  await io.check();
  const source=await io.sourceEpisode(spec.episodeId);
  const path=verifyReeditSource(source,snapshot,spec);
  const video=await io.load(path);
  if (createHash('sha256').update(video).digest('hex')!==spec.sha256) throw new Error('reedit_source_changed');
  await io.validateSource(video); // confirm 60s/720x1280/audio before any speech call
  const voices={};
  for (const language of Object.keys(plan)) {
    voices[language]=[];
    for (const text of plan[language].chunks) {
      await io.check();
      voices[language].push(await io.speech(text,language));
    }
  }
  return {video,plan,voices};
}
export function speechRequest(text,language,profile='documentary-v1') {
  if (!languages.includes(language) || typeof text!=='string' || !text.trim() || text.length>600) throw new Error('invalid_speech_input');
  if(!['documentary-v1',RECIPE_VOICE_PROFILE].includes(profile) || (profile===RECIPE_VOICE_PROFILE && language!=='ko')) throw new Error('invalid_speech_profile');
  const languageName={ko:'native Korean',en:'English',es:'Latin American Spanish'}[language];
  if(profile===RECIPE_VOICE_PROFILE) return {model:NARRATION_MODEL,voice:'shimmer',input:text,response_format:'wav',speed:1,
    instructions:'Read the provided text verbatim in native Korean. Perform an original fictional eight-year-old girl character: a light, bright, youthful feminine voice, naturally higher pitch, cheerful curiosity and gentle expressive intonation. Clear Korean diction and precise recipe quantities, units and ingredient names. Comfortable conversational pace, no baby talk, squealing or exaggerated cartoon delivery. No additions, singing, music or sound effects. Do not imitate any real person. Keep the same character voice throughout.'};
  return {model:NARRATION_MODEL,voice:'coral',input:text,response_format:'wav',speed:1,
    instructions:`Read the provided text verbatim in ${languageName}. Warm, clear, feminine documentary narrator. Calm professional voice acting, unhurried but not sleepy. Natural phrasing, careful recipe quantities and names. No additions, no music, no sound effects, no impersonation.`};
}
export async function speechAudio(text,language,key,fetcher=fetch,profile='documentary-v1') {
  const body=speechRequest(text,language,profile);
  if (!/^sk-[A-Za-z0-9_-]+$/.test(key ?? '')) throw new Error('invalid_key_format');
  const response=await fetcher('https://api.openai.com/v1/audio/speech',{
    method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},
    body:JSON.stringify(body),
    signal:AbortSignal.timeout(90000),redirect:'error'});
  if (!response.ok) throw new Error(`speech_http_${response.status}`); // never print provider bodies
  if (!/^audio\/(wav|x-wav|wave)(;|$)/i.test(response.headers.get('content-type') ?? '') ||
      Number(response.headers.get('content-length'))>12000000) throw new Error('invalid_speech_audio');
  const bytes=Buffer.from(await response.arrayBuffer());
  if (bytes.length<1000 || bytes.length>12000000 || bytes.toString('ascii',0,4)!=='RIFF' || bytes.toString('ascii',8,12)!=='WAVE') throw new Error('invalid_speech_audio');
  return bytes;
}
