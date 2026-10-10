export type Delivery = { id: number; lease: string; event_id: number; token: string; language: string };
export type Dependencies = {
  secret: string;
  evaluate: () => Promise<void>;
  authorizePush: () => Promise<void>;
  claim: () => Promise<Delivery[]>;
  send: (delivery: Delivery) => Promise<'sent' | 'retry' | 'invalid_token'>;
  finish: (delivery: Delivery, result: 'sent' | 'retry' | 'invalid_token') => Promise<void>;
};

function authorized(actual: string, expected: string): boolean {
  if (expected.length < 32 || actual.length !== expected.length) return false;
  let difference = 0;
  for (let i = 0; i < expected.length; i++) difference |= actual.charCodeAt(i) ^ expected.charCodeAt(i);
  return difference === 0;
}

export function createMonitorHandler(deps: Dependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== 'POST') return new Response(null, { status: 405 });
    if (!authorized(request.headers.get('x-ops-monitor-secret') ?? '', deps.secret)) {
      return new Response(null, { status: 401 });
    }
    try {
      await deps.evaluate();
      await deps.authorizePush();
      const deliveries = await deps.claim();
      let sent = 0;
      let retry = 0;
      for (const delivery of deliveries) {
        let result: 'sent' | 'retry' | 'invalid_token';
        try { result = await deps.send(delivery); } catch (_) { result = 'retry'; }
        await deps.finish(delivery, result);
        if (result === 'sent') sent++;
        if (result === 'retry') retry++;
      }
      return Response.json({ evaluated: true, sent, retry }, { status: retry ? 503 : 200 });
    } catch (_) {
      // Never return provider responses, keys, registration tokens or exception text.
      return Response.json({ error: 'monitor_run_failed' }, { status: 503 });
    }
  };
}

export function pushPayload(delivery: Delivery) {
  const english = delivery.language === 'en';
  const spanish = delivery.language === 'es';
  return {
    message: {
      token: delivery.token,
      notification: {
        title: spanish ? 'Operaciones de Recipe Scout' : english ? 'Recipe Scout operations' : '레시피 스카우트 운영 알림',
        body: spanish ? 'Cambió un estado operativo. Abre la bandeja de administración.' : english ? 'An operational status changed. Open the admin inbox.' : '운영 상태가 변경되었습니다. 관리자 알림함을 확인해 주세요.',
      },
      data: { type: 'ops_alert', event_id: String(delivery.event_id) },
      android: { priority: 'high', ttl: '300s', notification: { tag: 'ops-' + delivery.event_id } },
      apns: { headers: { 'apns-collapse-id': 'ops-' + delivery.event_id } },
    },
  };
}
