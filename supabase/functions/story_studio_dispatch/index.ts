import {createClient} from 'npm:@supabase/supabase-js@2.112.3';
import {createDispatchHandler} from './handler.ts';
Deno.serve(createDispatchHandler({
  token:Deno.env.get('STORY_STUDIO_GITHUB_DISPATCH_TOKEN') ?? '',
  authorize:async(jwt,jobId)=>{
    const client=createClient(Deno.env.get('SUPABASE_URL') ?? '',Deno.env.get('SUPABASE_ANON_KEY') ?? '',{
      auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:jwt}},
    });
    const {data,error}=await client.rpc('story_request_dispatch',{p_job_id:jobId});
    if(error) throw new Error('dispatch_not_authorized');
    return data===true;
  },
}));
