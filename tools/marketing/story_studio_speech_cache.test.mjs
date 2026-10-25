import test from 'node:test';
import assert from 'node:assert/strict';
import {cachedSpeech,speechCacheKey,validateCachedSpeech} from './story_studio_speech_cache.mjs';

function wav() {
  const b=Buffer.alloc(48044); b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);
  b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(24000,24);
  b.writeUInt32LE(48000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(48000,40);
  return b;
}
function fixture() {
  const entries=new Map(),objects=new Map(); let generations=0, job=1;
  const io={check:async()=>{},reserve:async key=>{
    const old=entries.get(key), fresh=!old || (old.status==='pending' && old.job!==job);
    const entry=old ?? {status:'pending',path:`${'a'.repeat(36)}/${'b'.repeat(36)}/${key}.wav`};
    entry.job=job;entries.set(key,entry);return {...entry,can_generate:fresh};
  },read:async path=>objects.get(path)??null,
  write:async(path,audio)=>{assert.equal(objects.has(path),false);objects.set(path,audio);},
  generate:async()=>{generations++;return wav();},
  commit:async(key,meta)=>Object.assign(entries.get(key),meta,{status:'ready'})};
  return {io,entries,objects,count:()=>generations,next:()=>{job++;}};
}
test('partial failure resumes only missing speech after separate job approval',async()=>{
  const f=fixture(); await cachedSpeech('첫 문단','ko',f.io);
  const generate=f.io.generate;
  f.io.generate=async()=>{throw new DOMException('timeout','TimeoutError');};
  await assert.rejects(cachedSpeech('둘째 문단','ko',f.io),{name:'TimeoutError'});
  // Same job cannot repeat an uncertain request.
  f.io.generate=generate;
  await assert.rejects(cachedSpeech('둘째 문단','ko',f.io),/speech_cache_missing/);
  f.next(); await cachedSpeech('첫 문단','ko',f.io);await cachedSpeech('둘째 문단','ko',f.io);
  assert.equal(f.count(),2);assert.equal(f.entries.size,2);
});
test('exact text, language and voice request identity; no raw text in storage key',()=>{
  assert.match(speechCacheKey('비빔밥','ko'),/^[a-f0-9]{64}$/);
  assert.notEqual(speechCacheKey('비빔밥','ko'),speechCacheKey('비빔밥!','ko'));
  assert.notEqual(speechCacheKey('Recipe','ko'),speechCacheKey('Recipe','en'));
});
test('lost commit/upload acknowledgement recovers persisted audio without generation',async()=>{
  const f=fixture(),commit=f.io.commit;
  f.io.commit=async()=>{throw new Error('lost reply');};
  await assert.rejects(cachedSpeech('안내','ko',f.io)); f.next();f.io.commit=commit;
  await cachedSpeech('안내','ko',f.io);assert.equal(f.count(),1);
});
test('missing/corrupt ready cache stops instead of paying again',async()=>{
  for(const corruption of ['missing','modified','invalid']) {
    const f=fixture();await cachedSpeech('안내','ko',f.io);const path=[...f.objects.keys()][0];
    if(corruption==='missing') f.objects.delete(path);
    else {const b=Buffer.from(f.objects.get(path));b[corruption==='invalid'?0:100]^=1;f.objects.set(path,b);}
    f.next();await assert.rejects(cachedSpeech('안내','ko',f.io),/speech_cache_/);assert.equal(f.count(),1);
  }
});
test('write/readback/lease/quota failures stop before next paid request',async()=>{
  for(const step of ['write','read','check','reserve']) {
    const f=fixture();f.io[step]=async()=>{throw new Error('blocked');};
    await assert.rejects(cachedSpeech('안내','ko',f.io));assert.equal(f.count(),step==='write'?1:0);
  }
  const f=fixture();let reads=0;f.io.read=async()=>++reads===1?null:Buffer.from('bad');
  await assert.rejects(cachedSpeech('안내','ko',f.io),/speech_cache_integrity/);
  assert.equal(f.count(),1);
});
test('PCM WAV validates actual data; supports streaming size sentinel but not truncation',()=>{
  assert.equal(validateCachedSpeech(wav()).bytes,48044);
  const streamed=wav();streamed.writeUInt32LE(0xffffffff,40);validateCachedSpeech(streamed);
  for(const b of [wav().subarray(0,2000),Buffer.alloc(1000)]) assert.throws(()=>validateCachedSpeech(b));
  const bad=wav();bad.writeUInt16LE(3,20);assert.throws(()=>validateCachedSpeech(bad));
});
