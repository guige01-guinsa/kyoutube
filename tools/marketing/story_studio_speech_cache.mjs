import {createHash} from 'node:crypto';
import {speechRequest} from './story_studio_narration.mjs';

export const SPEECH_CACHE_MAX_BYTES=12000000;
export const speechDigest=bytes=>createHash('sha256').update(bytes).digest('hex');
export function speechCacheKey(text,language,profile='documentary-v1') {
  // Only a digest leaves the worker; exact text AND every voice setting participate.
  return speechDigest(JSON.stringify({version:1,language,request:speechRequest(text,language,profile)}));
}
export function validateCachedSpeech(bytes) {
  const bad=()=>{throw new Error('speech_cache_invalid_audio');};
  if (!Buffer.isBuffer(bytes) || bytes.length<1000 || bytes.length>SPEECH_CACHE_MAX_BYTES ||
      bytes.toString('ascii',0,4)!=='RIFF' || bytes.toString('ascii',8,12)!=='WAVE') bad();
  let format,frames;
  for(let offset=12;offset+8<=bytes.length;) {
    const type=bytes.toString('ascii',offset,offset+4), size=bytes.readUInt32LE(offset+4), start=offset+8;
    if(type==='fmt ') {
      if(size<16 || start+size>bytes.length || format) bad();
      format={pcm:bytes.readUInt16LE(start),channels:bytes.readUInt16LE(start+2),rate:bytes.readUInt32LE(start+4),
        byteRate:bytes.readUInt32LE(start+8),align:bytes.readUInt16LE(start+12),bits:bytes.readUInt16LE(start+14)};
    }
    if(type==='data') {
      if(!format || frames!==undefined) bad();
      // Streaming WAV uses an unknown size sentinel. Never pad a truncated payload.
      if(size!==0xffffffff && start+size>bytes.length) bad();
      frames=size===0xffffffff?bytes.length-start:size;
      break;
    }
    if(start+size>bytes.length) bad();
    offset=start+size+(size%2);
  }
  if(!format || frames===undefined || format.pcm!==1 || ![1,2].includes(format.channels) ||
      format.bits!==16 || format.rate<8000 || format.rate>48000 || format.align!==format.channels*2 ||
      format.byteRate!==format.rate*format.align || frames%format.align ||
      frames/format.byteRate<0.5 || frames/format.byteRate>90) bad();
  return {sha256:speechDigest(bytes),bytes:bytes.length};
}

// No automatic paid retries. A later separately approved job can resume a reservation.
export async function cachedSpeech(text,language,io,profile='documentary-v1') {
  const key=speechCacheKey(text,language,profile);
  await io.check();
  const entry=await io.reserve(key);
  if(!entry || !['pending','ready'].includes(entry.status) ||
      !/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f]{64}\.wav$/.test(entry.path ?? '') ||
      !entry.path.endsWith(`/${key}.wav`)) throw new Error('speech_cache_invalid_record');
  let audio=await io.read(entry.path);
  if(audio===null) {
    if(entry.status==='ready' || entry.can_generate!==true) throw new Error('speech_cache_missing');
    await io.check();
    audio=await io.generate(text,language,profile);
    validateCachedSpeech(audio);
    await io.check();
    await io.write(entry.path,audio); // Immutable, no upsert. Persist before next paid chunk.
    const saved=await io.read(entry.path);
    if(saved===null || speechDigest(saved)!==speechDigest(audio)) throw new Error('speech_cache_integrity');
  }
  const metadata=validateCachedSpeech(audio);
  if(entry.status==='ready') {
    if(entry.sha256!==metadata.sha256 || entry.bytes!==metadata.bytes) throw new Error('speech_cache_integrity');
  } else {
    await io.check();
    await io.commit(key,metadata); // Recovers an upload whose acknowledgement was lost.
  }
  return audio;
}
