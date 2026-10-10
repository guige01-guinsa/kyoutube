import { createClient } from 'npm:@supabase/supabase-js@2.112.3';
import { discoveryHandler, DiscoveryError } from './handler.ts';
const env=(k:string)=>Deno.env.get(k) ?? '';
Deno.serve(discoveryHandler({
  key:()=>env('OPENAI_API_KEY'),
  reserve:async(authorization)=>{
    const c=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{
      global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
    const {data:{user},error:authError}=await c.auth.getUser();
    if(authError || !user || user.is_anonymous) throw new DiscoveryError('unauthorized',401);
    const {data,error}=await c.rpc('admin_reserve_supplier_search');
    if(error) {
      if(error.message.includes('SEARCH_QUOTA')) throw new DiscoveryError('search_quota',429);
      if(error.message.includes('ADMIN_MFA_REQUIRED')) throw new DiscoveryError('admin_mfa_required',403);
      throw new DiscoveryError('admin_required',403);
    }
    return String(data);
  },
  finish:async(id,outcome,usage)=>{
    const c=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
    const {error}=await c.from('supplier_discovery_runs').update({outcome,...usage}).eq('id',id).eq('outcome','started');
    if(error) throw new Error('Search accounting unavailable');
  },
}));
