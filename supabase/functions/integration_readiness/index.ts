import {createClient} from "npm:@supabase/supabase-js@2.112.3";
import {fetchWithTimeout} from "../_shared/http.ts";
import {createReadinessHandler} from "./handler.ts";
Deno.serve(createReadinessHandler({getEnv:(key)=>Deno.env.get(key),authorize:async(authorization)=>{
 const client=createClient(Deno.env.get("SUPABASE_URL")??"",Deno.env.get("SUPABASE_ANON_KEY")??"",{
  auth:{persistSession:false,autoRefreshToken:false},global:{fetch:fetchWithTimeout,headers:{Authorization:authorization}},
 });
 const {data:{user},error}=await client.auth.getUser();
 if(error||!user||user.is_anonymous)return false;
 const gate=await client.rpc("admin_assert_integration_access");
 return !gate.error&&gate.data===true;
}}));
