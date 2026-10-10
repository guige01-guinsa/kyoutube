import { createMonitorHandler, pushPayload, type Dependencies, type Delivery } from './handler.ts';
const secret = 'a'.repeat(40);
const delivery: Delivery = { id: 1, lease: 'lease', event_id: 7, token: 'private-token', language: 'ko' };
Deno.test('Spanish operational push contains no business data', () => {
  const payload=pushPayload({...delivery,language:'es'});
  if(payload.message.notification.title!=='Operaciones de Recipe Scout' ||
     !payload.message.notification.body.startsWith('Cambió') ||
     Object.keys(payload.message.data).sort().join(',')!=='event_id,type') throw new Error('Unexpected Spanish notification');
});
function check(value: unknown, message = 'assertion failed'): asserts value { if (!value) throw new Error(message); }
function setup() {
  const calls: string[] = [];
  const deps: Dependencies = { secret,
    evaluate: async () => { calls.push('evaluate'); }, authorizePush: async () => { calls.push('auth'); },
    claim: async () => [delivery], send: async () => 'sent',
    finish: async (_, result) => { calls.push(result); } };
  return { deps, calls };
}
function request(value = secret) { return new Request('https://local.test', { method: 'POST', headers: { 'x-ops-monitor-secret': value } }); }
Deno.test('unauthorized scheduler cannot evaluate or send', async () => {
  const { deps, calls } = setup();
  check((await createMonitorHandler(deps)(request('bad'))).status === 401); check(calls.length === 0);
  deps.secret = ''; check((await createMonitorHandler(deps)(request(''))).status === 401);
});
Deno.test('successful dispatch finishes the leased delivery', async () => {
  const { deps, calls } = setup(); check((await createMonitorHandler(deps)(request())).status === 200);
  check(calls.join(',') === 'evaluate,auth,sent');
});
Deno.test('push outage preserves inbox evaluation and reports retry', async () => {
  const { deps, calls } = setup(); deps.send = async () => { throw new Error('secret exception'); };
  const response = await createMonitorHandler(deps)(request()); check(response.status === 503);
  check(calls.includes('evaluate') && calls.includes('retry')); check(!(await response.text()).includes('secret'));
});
Deno.test('missing FCM credentials does not consume deliveries', async () => {
  const { deps, calls } = setup(); deps.authorizePush = async () => { throw new Error('private key'); };
  deps.claim = async () => { throw new Error('must not claim'); };
  const response = await createMonitorHandler(deps)(request()); check(response.status === 503);
  check(calls.join(',') === 'evaluate'); check(!(await response.text()).includes('private'));
});
Deno.test('push contains no operational metrics and collapses retries', () => {
  const payload = pushPayload(delivery); check(payload.message.data.type === 'ops_alert');
  check(payload.message.android.notification.tag === 'ops-7');
  check(!JSON.stringify(payload).includes('total_usd'));
});
