import { createClient } from 'npm:@supabase/supabase-js@2.112.3';
import { importPKCS8, SignJWT } from 'npm:jose@5.9.6';
import { createMonitorHandler, pushPayload } from './handler.ts';

const client = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(8000) }) },
});
async function rpc(name: string, params = {}) {
  const { data, error } = await client.rpc(name, params);
  if (error) throw new Error('monitor_database_error');
  return data;
}

// Each request has its own short-lived OAuth token; no credentials are logged.
Deno.serve(async (request) => {
  let accessToken = '';
  let projectId = '';
  const response = await createMonitorHandler({
    secret: Deno.env.get('OPS_MONITOR_SECRET') ?? '',
    evaluate: () => rpc('evaluate_ops_alerts'),
    authorizePush: async () => {
      const account = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT_JSON') ?? '{}');
      projectId = account.project_id;
      if (typeof projectId !== 'string' || !/^[a-z][a-z0-9-]{4,62}$/.test(projectId) ||
        typeof account.client_email !== 'string' || typeof account.private_key !== 'string') throw new Error('fcm_config');
      const tokenUrl = 'https://oauth2.googleapis.com/token';
      const key = await importPKCS8(account.private_key, 'RS256');
      const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
        .setProtectedHeader({ alg: 'RS256', typ: 'JWT' }).setIssuer(account.client_email)
        .setAudience(tokenUrl).setIssuedAt().setExpirationTime('10m').sign(key);
      const response = await fetch(tokenUrl, { method: 'POST', signal: AbortSignal.timeout(8000),
        body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }) });
      const body = await response.json();
      if (!response.ok || typeof body.access_token !== 'string') throw new Error('fcm_auth');
      accessToken = body.access_token;
    },
    claim: () => rpc('claim_ops_push'),
    send: async (delivery) => {
      const response = await fetch('https://fcm.googleapis.com/v1/projects/' + projectId + '/messages:send', {
        method: 'POST', signal: AbortSignal.timeout(5000),
        headers: { Authorization: 'Bearer ' + accessToken, 'Content-Type': 'application/json' },
        body: JSON.stringify(pushPayload(delivery)),
      });
      if (response.ok) return 'sent';
      const body = await response.json().catch(() => ({}));
      const details = body?.error?.details;
      if (Array.isArray(details) && details.some((d: { errorCode?: string }) => d.errorCode === 'UNREGISTERED')) return 'invalid_token';
      return 'retry';
    },
    finish: (delivery, result) => rpc('finish_ops_push', { p_id: delivery.id, p_lease: delivery.lease, p_result: result }),
  })(request);
  if (response.status === 200 || response.status === 503) {
    try { await rpc('record_ops_dispatch_status', { p_ok: response.ok }); } catch (_) { /* Next run retries. */ }
  }
  return response;
});
