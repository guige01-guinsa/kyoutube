const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// One approved render and its server-created private upload share the runner.
// Never drain the general queue, retry paid work or follow a third job.
export async function runApprovedPipeline(env,run) {
 if(env.STORY_STUDIO_JOB_ID && !uuid.test(env.STORY_STUDIO_JOB_ID)) throw new Error('invalid_target_job');
 const first=await run(env);
 if(!first.next_job_id) return first;
 if(first.kind!=='render'||first.auto_private_upload!==true||!uuid.test(first.next_job_id)||first.next_job_id===first.completed)
  throw new Error('pipeline_invalid_followup');
 const second=await run({...env,STORY_STUDIO_JOB_ID:first.next_job_id});
 if(second.next_job_id) throw new Error('pipeline_chain_limit');
 return {...second,pipeline_jobs:[first.completed,...(second.completed?[second.completed]:[])]};
}
