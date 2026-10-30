import test from 'node:test';
import assert from 'node:assert/strict';
import {diagnoseYoutube} from './youtube_readonly_diagnostic.mjs';
const env={SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'fixture-private',YOUTUBE_CLIENT_ID:'fixture',YOUTUBE_CLIENT_SECRET:'fixture',YOUTUBE_REFRESH_TOKEN:'fixture',YOUTUBE_CHANNEL_HANDLE:'@fixture'};
for(const expired of [true,false])test(`read-only diagnostic never uploads and keeps private metadata out of logs (${expired})`,async()=>{
 let saved;const methods=[];
 const fetcher=async(target,init={})=>{
  const u=new URL(target),method=init.method??'GET';methods.push({url:u.toString(),method});
  if(u.hostname==='fixture.supabase.co') {
   if(method==='PATCH'){saved=JSON.parse(init.body).result.youtube_readonly_diagnostic;return Response.json([{id:'fixture-job'}]);}
   return Response.json([{id:'fixture-job',created_at:'2026-10-30T00:00:00Z',snapshot:{project:{plan:{title:'fixture video'}}}}]);
  }
  if(u.hostname==='oauth2.googleapis.com')return expired?Response.json({error:'invalid_grant',error_description:'must not log provider text'},{status:400}):Response.json({access_token:'must-not-leak'});
  assert.equal(method,'GET');assert.equal(u.pathname.startsWith('/upload/'),false);
  if(u.pathname.endsWith('/channels'))return Response.json({items:[{id:'UC'+'a'.repeat(22),contentDetails:{relatedPlaylists:{uploads:'fixture-list'}}}]});
  if(u.pathname.endsWith('/playlistItems'))return Response.json({items:[{contentDetails:{videoId:'abcdefghijk'}}]});
  return Response.json({items:[{id:'abcdefghijk',snippet:{title:'fixture video',publishedAt:'2026-10-30T00:01:00Z'},status:{privacyStatus:'private',uploadStatus:'processed'},contentDetails:{duration:'PT1M36S'}}]});
 };
 const result=await diagnoseYoutube(env,fetcher);
 assert.equal(result.recorded,true);assert.equal(JSON.stringify(result).includes('abcdefghijk'),false);assert.equal(JSON.stringify(result).includes('must-not-leak'),false);
 if(expired){assert.equal(saved.oauth_error,'invalid_grant');assert.equal(saved.youtube_requests.length,0);}
 else{assert.equal(saved.matching_videos[0].id,'abcdefghijk');assert.equal(saved.matching_videos[0].privacy,'private');}
 assert.equal(methods.filter(x=>x.method==='POST').length,1);
});
