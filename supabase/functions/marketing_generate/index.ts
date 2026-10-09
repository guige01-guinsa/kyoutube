import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import { buildPrompt, parseContent, topics } from './content.ts';

const headers = { 'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return json({ message: 'POST 요청이 필요합니다.' }, 405);
  if (Deno.env.get('MARKETING_GENERATION_ENABLED') !== 'true') {
    return json({ message: '마케팅 초안 생성은 현재 중지되어 있습니다.' }, 503);
  }
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const apiKey = Deno.env.get('OPENAI_API_KEY');
  const model = Deno.env.get('OPENAI_MARKETING_MODEL');
  if (!url || !serviceKey || !anonKey) return json({ message: '서버 설정을 확인하세요.' }, 503);
  const token = request.headers.get('Authorization')?.match(/^Bearer (.+)$/)?.[1];
  if (!token) return json({ message: '로그인이 필요합니다.' }, 401);
  const db = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: { user }, error: authError } = await db.auth.getUser(token);
  if (authError || !user) return json({ message: '로그인이 필요합니다.' }, 401);
  const { data: admin, error: adminError } = await db.from('marketing_admins').select('user_id').eq('user_id', user.id).maybeSingle();
  if (adminError || !admin) return json({ message: '마케팅 관리자 권한이 필요합니다.' }, 403);
  const userDb = createClient(url, anonKey, { auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } } });
  const { error: accessError } = await userDb.rpc('assert_marketing_access');
  if (accessError) return json({ message: '관리자 2단계 인증을 완료해 주세요.' }, 403);
  if (!apiKey || !model) return json({ message: 'AI 키와 마케팅 모델 설정이 필요합니다.' }, 503);
  const body = await request.json().catch(() => null);
  const topic = body?.topic;
  if (typeof topic !== 'string' || !Object.hasOwn(topics, topic)) return json({ message: '주제를 선택하세요.' }, 400);
  const { data: reserved, error: limitError } = await db.rpc('reserve_marketing_generation');
  if (limitError || !reserved) return json({ message: '하루 생성 한도(5회)에 도달했거나 설정 확인이 필요합니다.' }, 429);
  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST', signal: AbortSignal.timeout(45000),
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, max_completion_tokens: 1200, response_format: { type: 'json_object' },
        messages: [{ role: 'system', content: 'Write factual Korean app marketing drafts using only supplied facts.' },
          { role: 'user', content: buildPrompt(topic as keyof typeof topics) }] }),
    });
    if (!response.ok) return json({ message: 'AI 키·모델·결제 설정을 확인하세요.' }, 502);
    const payload = await response.json();
    const content = parseContent(JSON.parse(payload.choices?.[0]?.message?.content ?? 'null'));
    // The CTA is controlled by the server, not by model output.
    content.scenes[2] = '채널 프로필의 링크에서 Recipe Scout 확인';
    const { data, error } = await db.from('marketing_campaigns').insert({ ...content, topic, created_by: user.id }).select().single();
    if (error) throw new Error('save_failed');
    return json({ data });
  } catch {
    return json({ message: '초안 생성에 실패했습니다. 잠시 후 다시 시도하세요.' }, 502);
  }
});
