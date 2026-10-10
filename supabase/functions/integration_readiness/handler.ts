const cors = {"Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, apikey, x-client-info, content-type", "Access-Control-Allow-Methods":"GET, OPTIONS"};
// Reports presence/shape only. "configured" deliberately does not claim a live
// purchase, valid third-party permissions, or successful push delivery.
export function integrationChecks(get: (key:string)=>string|undefined) {
  const present = (key:string) => !!get(key)?.trim();
  const account = (key:string) => {
    try {
      const v=JSON.parse(get(key) ?? "{}");
      return typeof v.client_email === "string" && v.client_email.endsWith(".iam.gserviceaccount.com") &&
        typeof v.private_key === "string" && v.private_key.includes("BEGIN PRIVATE KEY") && typeof v.project_id === "string";
    } catch {return false;}
  };
  return [
    {id:"recipe_ai",configured:present("OPENAI_API_KEY")},
    {id:"youtube_search",configured:present("YOUTUBE_DATA_API_KEY")||present("YOUTUBE_API_KEY")},
    {id:"video_ai",configured:present("GEMINI_API_KEY")&&get("VIDEO_ANALYSIS_ENABLED")==="true"},
    {id:"coupang",configured:present("COUPANG_PARTNERS_ACCESS_KEY")&&present("COUPANG_PARTNERS_SECRET_KEY")},
    {id:"play_billing",configured:account("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")},
    {id:"play_notifications",configured:present("GOOGLE_PLAY_RTDN_AUDIENCE")&&present("GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT_EMAIL")},
    {id:"operations_push",configured:account("FCM_SERVICE_ACCOUNT_JSON")&&(get("OPS_MONITOR_SECRET")?.length??0)>=32},
  ];
}
export function createReadinessHandler(deps:{authorize:(auth:string)=>Promise<boolean>;getEnv:(key:string)=>string|undefined}) {
  const reply=(value:unknown,status=200)=>Response.json(value,{status,headers:{...cors,"Cache-Control":"no-store"}});
  return async (req:Request) => {
    if(req.method==="OPTIONS")return new Response(null,{headers:cors});
    if(req.method!=="GET")return reply({error:"method_not_allowed"},405);
    const auth=req.headers.get("authorization")??"";
    if(!/^Bearer\s+\S+$/i.test(auth))return reply({error:"unauthorized"},401);
    try {
      if(!await deps.authorize(auth))return reply({error:"admin_mfa_required"},403);
      return reply({checked_at:new Date().toISOString(),checks:integrationChecks(deps.getEnv)});
    }catch{return reply({error:"readiness_unavailable"},503);}
  };
}
