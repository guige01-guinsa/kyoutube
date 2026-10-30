import {pathToFileURL} from 'node:url';
import {resolveChannel} from './worker.mjs';

// No upload, generation, or queue operation. Private video metadata is written
// only to the existing failed job, never to public Actions logs or artifacts.
export async function diagnoseYoutube(env,fetcher=fetch) {
 const root=new URL(env.SUPABASE_URL),headers={apikey:env.SUPABASE_SERVICE_ROLE_KEY,Authorization:`Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`};
 const target=new URL('/rest/v1/story_jobs',root);
 target.search=new URLSearchParams({kind:'eq.upload',status:'eq.needs_review','snapshot->>standard_profile':'eq.ko-60-v1',order:'created_at.desc',limit:'1',select:'id,created_at,snapshot,result'}).toString();
 const jobs=await fetcher(target,{headers,signal:AbortSignal.timeout(20000)});
 if(!jobs.ok)throw new Error('diagnostic_job_read_failed');
 const job=(await jobs.json())[0];if(!job)throw new Error('diagnostic_job_missing');
 const report={read_only:true,checked_at:new Date().toISOString(),youtube_requests:[],matching_videos:[]};
 const allowed=new Set(['invalid_grant','invalid_client','access_denied','insufficientPermissions','quotaExceeded','dailyLimitExceeded','youtubeSignupRequired','forbidden']);
 const reason=data=>{const r=data?.error?.errors?.[0]?.reason??(typeof data?.error==='string'?data.error:null);return allowed.has(r)?r:'unknown';};
 try {
  const response=await fetcher('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({client_id:env.YOUTUBE_CLIENT_ID,client_secret:env.YOUTUBE_CLIENT_SECRET,refresh_token:env.YOUTUBE_REFRESH_TOKEN,grant_type:'refresh_token'}),signal:AbortSignal.timeout(20000)});
  const data=await response.json();report.oauth_status=response.status;
  if(!response.ok||typeof data.access_token!=='string') {report.oauth_error=reason(data);throw new Error('oauth_unavailable');}
  const auth={Authorization:`Bearer ${data.access_token}`};
  const yt=async path=>{
   if(!/^(channels|playlistItems|videos)\?/.test(path))throw new Error('read_only_endpoint_required');
   const r=await fetcher(`https://www.googleapis.com/youtube/v3/${path}`,{headers:auth,signal:AbortSignal.timeout(20000)}),body=await r.json();
   report.youtube_requests.push({endpoint:path.split('?')[0],status:r.status,...(!r.ok?{reason:reason(body)}:{})});
   if(!r.ok)throw new Error('youtube_read_failed');return body;
  };
  report.verified_channel_id=await resolveChannel(env,yt);
  const channel=await yt('channels?part=contentDetails&mine=true');
  const playlist=channel.items?.find(c=>c.id===report.verified_channel_id)?.contentDetails?.relatedPlaylists?.uploads;
  if(!playlist)throw new Error('uploads_playlist_missing');
  const listed=await yt(`playlistItems?part=contentDetails&maxResults=10&playlistId=${encodeURIComponent(playlist)}`);
  const ids=listed.items?.map(x=>x.contentDetails?.videoId).filter(id=>/^[A-Za-z0-9_-]{11}$/.test(id??''))??[];
  if(ids.length) {
   const videos=await yt(`videos?part=snippet,status,contentDetails&id=${ids.join(',')}`);
   report.matching_videos=(videos.items??[]).filter(v=>v.snippet?.title===job.snapshot?.project?.plan?.title&&Date.parse(v.snippet?.publishedAt)>Date.parse(job.created_at)-600000)
    .map(v=>({id:v.id,title:v.snippet.title,published_at:v.snippet.publishedAt,privacy:v.status?.privacyStatus,upload_status:v.status?.uploadStatus,duration:v.contentDetails?.duration}));
  }
 }catch(error) {
  report.outcome=['oauth_unavailable','youtube_read_failed','uploads_playlist_missing'].includes(error.message)?error.message:'channel_verification_or_transport_failed';
 }
 const update=new URL('/rest/v1/story_jobs',root);update.search=new URLSearchParams({id:`eq.${job.id}`,status:'eq.needs_review'}).toString();
 const saved=await fetcher(update,{method:'PATCH',headers:{...headers,'Content-Type':'application/json',Prefer:'return=representation'},body:JSON.stringify({result:{...(job.result??{}),youtube_readonly_diagnostic:report}}),signal:AbortSignal.timeout(20000)});
 if(!saved.ok||(await saved.json()).length!==1)throw new Error('diagnostic_report_not_saved');
 return {recorded:true,oauth_status:report.oauth_status,outcome:report.outcome??'read_only_check_complete',matches:report.matching_videos.length};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
 diagnoseYoutube(process.env).then(x=>console.log(JSON.stringify(x))).catch(()=>{console.error('Read-only diagnostic did not complete. No upload was attempted.');process.exitCode=1;});
}
