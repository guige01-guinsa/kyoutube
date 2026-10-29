type Dependencies = {
  token: string;
  authorize: (jwt: string, jobId: string) => Promise<boolean>;
  fetcher?: typeof fetch;
};
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info'};
export function createDispatchHandler(deps: Dependencies) {
  return async (request: Request): Promise<Response> => {
    const reply = (status: number, state: string) => new Response(JSON.stringify({state}), {
      status, headers:{...cors,'Content-Type':'application/json'},
    });
    if (request.method === 'OPTIONS') return new Response(null,{status:204,headers:cors});
    if (request.method !== 'POST') return reply(405,'method_not_allowed');
    const jwt = request.headers.get('Authorization') ?? '';
    if (!jwt.startsWith('Bearer ')) return reply(401,'sign_in_required');
    // Unconfigured dispatch leaves the existing queue intact for scheduled execution.
    if (!deps.token) return reply(503,'scheduled_queue_only');
    try {
      const body = await request.text();
      if (body.length > 2000) return reply(400,'invalid_job');
      const {job_id} = JSON.parse(body);
      if (typeof job_id !== 'string' || !/^[0-9a-f-]{36}$/.test(job_id)) return reply(400,'invalid_job');
      // DB checks current administrator, MFA, job owner, approved queue state and
      // one dispatch reservation per job. It never creates or requeues a paid job.
      if (!await deps.authorize(jwt,job_id)) return reply(200,'already_requested_or_not_queued');
      const result = await (deps.fetcher ?? fetch)(
        'https://api.github.com/repos/guige01-guinsa/kyoutube/actions/workflows/story-studio-worker.yml/dispatches',{
          method:'POST',signal:AbortSignal.timeout(10000),
          headers:{Authorization:`Bearer ${deps.token}`,Accept:'application/vnd.github+json','Content-Type':'application/json','X-GitHub-Api-Version':'2026-03-10'},
          body:JSON.stringify({ref:'main',inputs:{dry_run:false,preflight:false}}),
        });
      return [200,204].includes(result.status) ? reply(200,'requested') : reply(503,'dispatch_uncertain_scheduled_queue_retained');
    } catch {
      // Do not leak provider bodies/tokens or automatically retry an uncertain dispatch.
      return reply(503,'dispatch_uncertain_scheduled_queue_retained');
    }
  };
}
