import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST,OPTIONS"
};

const JSON_HEADERS = {
  "Content-Type": "application/json",
  ...CORS_HEADERS
};

type GuardrailStage = "normal" | "warning" | "high" | "stop" | "anonymous";
type AssistantErrorCode =
  | "invalid_input"
  | "unauthorized"
  | "budget_stop"
  | "provider_error"
  | "provider_timeout"
  | "feedback_invalid"
  | "feedback_store_failed";

type SummaryResponseData = {
  summary: string;
  tips: string[];
  cautions: string[];
  ingredients?: string[];
  steps?: string[];
  engine: string;
  degraded: boolean;
  errorCode?: AssistantErrorCode;
};

function getEnv(name: string): string {
  return Deno.env.get(name) ?? "";
}

function getNumberEnv(name: string, fallback: number): number {
  const raw = Number(getEnv(name));
  return Number.isFinite(raw) ? raw : fallback;
}

function getSupabaseConfig(): {
  supabaseUrl: string;
  serviceRoleKey: string;
  anonKey: string;
} {
  const supabaseUrl = getEnv("SUPABASE_URL").trim();
  const serviceRoleKey = (getEnv("SUPABASE_SERVICE_ROLE_KEY") || getEnv("SERVICE_ROLE_KEY")).trim();
  const anonKey = (getEnv("SUPABASE_ANON_KEY") || getEnv("ANON_KEY") || serviceRoleKey).trim();

  if (supabaseUrl.length === 0 || serviceRoleKey.length === 0) {
    throw new Error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY/SERVICE_ROLE_KEY is missing");
  }

  return { supabaseUrl, serviceRoleKey, anonKey };
}

function getBearerToken(req: Request): string | null {
  const authHeader = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!authHeader) {
    return null;
  }

  const [scheme, token] = authHeader.split(" ");
  if (!scheme || !token || scheme.toLowerCase() !== "bearer" || token.trim().length === 0) {
    return null;
  }

  return token.trim();
}

async function getAuthenticatedUserId(req: Request): Promise<string | null> {
  const token = getBearerToken(req);
  if (!token) {
    return null;
  }

  const { supabaseUrl, anonKey } = getSupabaseConfig();
  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    method: "GET",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${token}`
    }
  });

  if (!response.ok) {
    return null;
  }

  const data = await response.json().catch(() => null);
  const userId = typeof data?.id === "string" ? data.id.trim() : "";
  return userId.length > 0 ? userId : null;
}

async function restRequest(path: string, init: RequestInit): Promise<Response> {
  const { supabaseUrl, serviceRoleKey } = getSupabaseConfig();
  const headers = new Headers(init.headers ?? {});
  headers.set("apikey", serviceRoleKey);
  headers.set("Authorization", `Bearer ${serviceRoleKey}`);

  if (!headers.has("Content-Type") && init.body) {
    headers.set("Content-Type", "application/json");
  }

  return fetch(`${supabaseUrl}${path}`, {
    ...init,
    headers
  });
}

async function ensureProfileExists(userId: string): Promise<boolean> {
  const selectParams = new URLSearchParams();
  selectParams.set("select", "id");
  selectParams.set("id", `eq.${userId}`);
  selectParams.set("limit", "1");

  const selectResponse = await restRequest(`/rest/v1/profiles?${selectParams.toString()}`, {
    method: "GET"
  });
  if (!selectResponse.ok) {
    return false;
  }

  const rows = await selectResponse.json().catch(() => []);
  if (Array.isArray(rows) && rows.length > 0) {
    return true;
  }

  const insertResponse = await restRequest("/rest/v1/profiles", {
    method: "POST",
    headers: {
      Prefer: "return=minimal"
    },
    body: JSON.stringify({
      id: userId,
      role: "user"
    })
  });

  return insertResponse.ok;
}

function calculateStage(totalCostKrw: number): GuardrailStage {
  if (totalCostKrw >= 50000) {
    return "stop";
  }
  if (totalCostKrw >= 45000) {
    return "high";
  }
  if (totalCostKrw >= 35000) {
    return "warning";
  }
  return "normal";
}

async function inferGuardrailStage(userId: string | null, currentCostKrw: number): Promise<GuardrailStage> {
  if (!userId) {
    return "anonymous";
  }

  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(0, 0, 0, 0);

  const params = new URLSearchParams();
  params.set("select", "cost_krw");
  params.set("user_id", `eq.${userId}`);
  params.set("created_at", `gte.${monthStart.toISOString()}`);
  params.set("limit", "5000");

  const response = await restRequest(`/rest/v1/ai_usage_logs?${params.toString()}`, {
    method: "GET"
  });

  if (!response.ok) {
    return "normal";
  }

  const rows = await response.json().catch(() => []);
  const monthlyCost = Array.isArray(rows)
    ? rows.reduce((sum: number, row: Record<string, unknown>) => {
      const value = Number(row.cost_krw ?? 0);
      return sum + (Number.isFinite(value) ? value : 0);
    }, 0)
    : 0;

  return calculateStage(monthlyCost + currentCostKrw);
}

async function logUsage(params: {
  userId: string | null;
  endpoint: string;
  model: string;
  requestTokens: number;
  responseTokens: number;
  requestChars: number;
  responseChars: number;
  latencyMs: number;
  costKrw: number;
  status: string;
  guardrailStage: GuardrailStage;
  errorCode?: AssistantErrorCode;
  errorMessage?: string;
  meta?: Record<string, unknown>;
}): Promise<void> {
  let effectiveUserId: string | null = params.userId;
  if (effectiveUserId) {
    const profileReady = await ensureProfileExists(effectiveUserId);
    if (!profileReady) {
      effectiveUserId = null;
    }
  }

  const meta: Record<string, unknown> = {
    ...(params.meta ?? {}),
  };
  if (params.errorCode) {
    meta.error_code = params.errorCode;
  }
  if (params.errorMessage) {
    meta.error_message = params.errorMessage;
  }

  const response = await restRequest("/rest/v1/ai_usage_logs", {
    method: "POST",
    headers: {
      Prefer: "return=minimal"
    },
    body: JSON.stringify({
      user_id: effectiveUserId,
      endpoint: params.endpoint,
      model: params.model,
      request_tokens: params.requestTokens,
      response_tokens: params.responseTokens,
      request_chars: params.requestChars,
      response_chars: params.responseChars,
      latency_ms: params.latencyMs,
      cost_krw: params.costKrw,
      status: params.status,
      guardrail_stage: params.guardrailStage,
      meta
    })
  });

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    console.warn(`ai_usage_logs insert failed: ${text}`);
  }
}

async function logFeedback(params: {
  userId: string | null;
  liked: boolean;
  summary: string;
  note?: string;
  recipeId?: string;
}): Promise<boolean> {
  let effectiveUserId: string | null = params.userId;
  if (effectiveUserId) {
    const profileReady = await ensureProfileExists(effectiveUserId);
    if (!profileReady) {
      effectiveUserId = null;
    }
  }

  const response = await restRequest("/rest/v1/ai_assistant_feedback", {
    method: "POST",
    headers: {
      Prefer: "return=minimal"
    },
    body: JSON.stringify({
      user_id: effectiveUserId,
      liked: params.liked,
      summary: params.summary,
      note: params.note ?? null,
      recipe_id: params.recipeId ?? null,
    })
  });

  return response.ok;
}

function okResponse(data: unknown, status = 200): Response {
  return new Response(
    JSON.stringify({
      status: "ok",
      data
    }),
    {
      status,
      headers: JSON_HEADERS
    }
  );
}

function errorResponse(status: number, code: AssistantErrorCode, message: string, details: unknown = null): Response {
  return new Response(
    JSON.stringify({
      status: "error",
      code,
      message,
      details
    }),
    {
      status,
      headers: JSON_HEADERS
    }
  );
}

function toStringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((item) => String(item ?? "").trim())
    .filter((item) => item.length > 0)
    .slice(0, 30);
}

function compactText(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
}

function summarizeText(input: string, maxLength: number): string {
  const clean = compactText(input);
  if (clean.length <= maxLength) {
    return clean;
  }

  return `${clean.slice(0, Math.max(40, maxLength - 1)).trim()}…`;
}

function buildTips(ingredients: string[], steps: string[]): string[] {
  const joinedIngredients = ingredients.join(" ").toLowerCase();
  const joinedSteps = steps.join(" ").toLowerCase();
  const tips: string[] = [];

  if (joinedSteps.includes("볶") || joinedSteps.includes("stir")) {
    tips.push("팬을 충분히 예열한 뒤 재료를 넣으면 수분이 덜 생기고 식감이 좋아집니다.");
  }

  if (joinedSteps.includes("끓") || joinedSteps.includes("boil") || joinedSteps.includes("찌개")) {
    tips.push("간은 처음부터 세게 하지 말고 마지막 1~2분 전에 맞추면 실패 확률이 낮습니다.");
  }

  if (joinedIngredients.includes("마늘") || joinedIngredients.includes("garlic")) {
    tips.push("마늘은 타기 쉬우므로 중약불에서 향을 먼저 내고 주재료를 넣어 주세요.");
  }

  if (joinedIngredients.includes("고추") || joinedIngredients.includes("청양")) {
    tips.push("매운 재료는 절반만 먼저 넣고 마지막에 추가해 맵기 강도를 조절해 보세요.");
  }

  if (tips.length === 0) {
    tips.push("재료 손질을 먼저 끝내고 조리를 시작하면 전체 조리 시간을 줄일 수 있습니다.");
  }

  return tips.slice(0, 3);
}

function buildCautions(ingredients: string[], steps: string[]): string[] {
  const joinedIngredients = ingredients.join(" ").toLowerCase();
  const joinedSteps = steps.join(" ").toLowerCase();
  const cautions: string[] = [];

  if (joinedIngredients.includes("생닭") || joinedIngredients.includes("닭") || joinedIngredients.includes("chicken")) {
    cautions.push("닭고기는 중심부까지 완전히 익혀 주세요.");
  }

  if (joinedIngredients.includes("돼지") || joinedIngredients.includes("pork")) {
    cautions.push("돼지고기는 붉은 기가 남지 않도록 충분히 가열해 주세요.");
  }

  if (joinedSteps.includes("튀") || joinedSteps.includes("fry")) {
    cautions.push("튀김 조리 시 기름이 튈 수 있으니 물기를 충분히 제거해 주세요.");
  }

  return cautions.slice(0, 2);
}

function buildRuleBasedSummary(params: {
  title: string;
  recipeText: string;
  ingredients: string[];
  steps: string[];
  maxSummaryLength: number;
  degraded: boolean;
  errorCode?: AssistantErrorCode;
}): SummaryResponseData {
  const blocks: string[] = [];
  if (params.title.length > 0) {
    blocks.push(`요리명: ${params.title}`);
  }
  if (params.recipeText.length > 0) {
    blocks.push(params.recipeText);
  }
  if (params.ingredients.length > 0) {
    blocks.push(`주요 재료: ${params.ingredients.slice(0, 8).join(", ")}`);
  }
  if (params.steps.length > 0) {
    blocks.push(`핵심 순서: ${params.steps.slice(0, 3).join(" / ")}`);
  }

  const composed = blocks.join(" ");

  return {
    summary: summarizeText(composed, params.maxSummaryLength),
    tips: buildTips(params.ingredients, params.steps),
    cautions: buildCautions(params.ingredients, params.steps),
    engine: "rule-based-v1",
    degraded: params.degraded,
    errorCode: params.errorCode,
  };
}

function buildRuleBasedDraft(params: {
  title: string;
  recipeText: string;
  ingredients: string[];
  steps: string[];
  maxSummaryLength: number;
  degraded: boolean;
  errorCode?: AssistantErrorCode;
}): SummaryResponseData {
  const baseSummary = buildRuleBasedSummary({
    ...params,
    degraded: params.degraded,
    errorCode: params.errorCode,
  });

  const inferredIngredients = inferIngredientsFromVideoContext({
    title: params.title,
    recipeText: params.recipeText,
  });

  const inferredSteps = inferStepsFromTitle(params.title);

  const fallbackIngredients = params.ingredients.length > 0
    ? params.ingredients.slice(0, 12)
    : (inferredIngredients.length > 0
      ? inferredIngredients
      : [
        "주재료 1인분",
        "양념 재료 적당량",
        "식용유 1큰술",
        "소금 약간",
      ]);

  const fallbackSteps = params.steps.length > 0
    ? params.steps.slice(0, 8)
    : (inferredSteps.length > 0
      ? inferredSteps
      : [
        "재료를 손질하고 필요한 양념을 미리 준비합니다.",
        "중불에서 재료를 볶거나 익히며 간을 맞춥니다.",
        "마지막에 맛을 조정해 완성합니다.",
      ]);

  return {
    ...baseSummary,
    ingredients: fallbackIngredients,
    steps: fallbackSteps,
  };
}

function inferIngredientsFromVideoContext(params: {
  title: string;
  recipeText: string;
}): string[] {
  const context = `${params.title} ${params.recipeText}`.toLowerCase();
  const channel = extractChannelHint(params.recipeText);

  const inferred = new Set<string>();
  const addAll = (items: string[]) => items.forEach((item) => inferred.add(item));

  const ingredientPatterns: Array<{ patterns: string[]; ingredients: string[] }> = [
    {
      patterns: ["볶음밥", "fried rice", "계란밥"],
      ingredients: ["밥 1공기", "계란 2개", "대파 1/3대", "간장 1큰술"],
    },
    {
      patterns: ["김치", "kimchi"],
      ingredients: ["김치 1컵", "고춧가루 1작은술"],
    },
    {
      patterns: ["된장", "된장찌개", "miso"],
      ingredients: ["된장 1.5큰술", "두부 1/2모", "애호박 1/4개"],
    },
    {
      patterns: ["파스타", "pasta", "알리오", "토마토"],
      ingredients: ["파스타 면 1인분", "마늘 4쪽", "올리브오일 2큰술"],
    },
    {
      patterns: ["닭", "치킨", "chicken"],
      ingredients: ["닭고기 250g", "후추 약간"],
    },
    {
      patterns: ["돼지", "삼겹", "목살", "pork"],
      ingredients: ["돼지고기 250g", "다진 마늘 1큰술"],
    },
    {
      patterns: ["다이어트", "저칼로리", "샐러드", "protein"],
      ingredients: ["닭가슴살 150g", "양상추 한 줌", "방울토마토 6개"],
    },
    {
      patterns: ["자취", "초간단", "1분", "전자레인지"],
      ingredients: ["즉석밥 1개", "계란 1개", "참기름 1작은술"],
    },
  ];

  for (const pattern of ingredientPatterns) {
    if (pattern.patterns.some((token) => context.includes(token))) {
      addAll(pattern.ingredients);
    }
  }

  const channelPatterns: Array<{ patterns: string[]; ingredients: string[] }> = [
    {
      patterns: ["백종원", "paik", "paik's"],
      ingredients: ["진간장 1큰술", "설탕 1작은술", "대파 1/2대"],
    },
    {
      patterns: ["만개의레시피", "10000recipe", "만개"],
      ingredients: ["국간장 1작은술", "참기름 1작은술"],
    },
    {
      patterns: ["자취", "혼밥", "single"],
      ingredients: ["소금 약간", "식용유 1큰술"],
    },
  ];

  for (const channelPattern of channelPatterns) {
    if (channelPattern.patterns.some((token) => channel.includes(token))) {
      addAll(channelPattern.ingredients);
    }
  }

  addAll(["소금 약간", "식용유 1큰술"]);

  return Array.from(inferred).slice(0, 12);
}

function inferStepsFromTitle(title: string): string[] {
  const normalized = title.toLowerCase();

  if (normalized.includes("볶음") || normalized.includes("볶음밥")) {
    return [
      "팬을 예열한 뒤 식용유를 두르고 향채를 먼저 볶아 향을 냅니다.",
      "주재료를 넣어 볶다가 간장/소금으로 간을 맞춥니다.",
      "마지막에 불을 줄이고 맛을 정리해 완성합니다.",
    ];
  }

  if (normalized.includes("찌개") || normalized.includes("탕") || normalized.includes("국")) {
    return [
      "재료를 손질해 냄비에 물과 함께 넣고 끓입니다.",
      "중불에서 재료가 익을 때까지 끓인 뒤 양념으로 간을 맞춥니다.",
      "마지막 1~2분에 농도와 간을 조정해 완성합니다.",
    ];
  }

  if (normalized.includes("샐러드")) {
    return [
      "채소와 단백질 재료를 세척 및 손질합니다.",
      "드레싱 재료를 섞어 간을 맞춥니다.",
      "먹기 직전에 드레싱을 버무려 완성합니다.",
    ];
  }

  return [];
}

function extractChannelHint(recipeText: string): string {
  const match = recipeText.match(/채널\s*:\s*([^\n\r]+)/i);
  if (!match || match.length < 2) {
    return "";
  }

  return match[1].trim().toLowerCase();
}

async function tryOpenAiSummary(params: {
  title: string;
  recipeText: string;
  ingredients: string[];
  steps: string[];
  maxSummaryLength: number;
}): Promise<SummaryResponseData | null> {
  const apiKey = getEnv("OPENAI_API_KEY").trim();
  if (!apiKey) {
    return null;
  }

  const model = getEnv("OPENAI_MODEL").trim() || "gpt-4o-mini";
  const prompt = [
    "당신은 요리 보조 도우미입니다.",
    "한국어로 응답하고 반드시 JSON만 반환하세요.",
    `summary는 최대 ${params.maxSummaryLength}자`,
    "JSON 형식: {\"summary\":string,\"tips\":string[],\"cautions\":string[]}",
    `title: ${params.title}`,
    `recipeText: ${params.recipeText}`,
    `ingredients: ${params.ingredients.join(", ")}`,
    `steps: ${params.steps.join(" / ")}`,
  ].join("\n");

  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        input: prompt,
        temperature: 0.3,
      }),
    });

    if (!response.ok) {
      return null;
    }

    const body = await response.json().catch(() => null);
    const outputText = typeof body?.output_text === "string"
      ? body.output_text
      : "";

    if (!outputText.trim()) {
      return null;
    }

    const parsed = JSON.parse(outputText);
    const summary = typeof parsed?.summary === "string"
      ? compactText(parsed.summary)
      : "";
    if (!summary) {
      return null;
    }

    const tips = toStringList(parsed?.tips).slice(0, 3);
    const cautions = toStringList(parsed?.cautions).slice(0, 2);

    return {
      summary: summarizeText(summary, params.maxSummaryLength),
      tips,
      cautions,
      engine: `openai:${model}`,
      degraded: false,
    };
  } catch (_) {
    return null;
  }
}

async function tryOpenAiDraft(params: {
  title: string;
  recipeText: string;
  ingredients: string[];
  steps: string[];
  maxSummaryLength: number;
}): Promise<SummaryResponseData | null> {
  const apiKey = getEnv("OPENAI_API_KEY").trim();
  if (!apiKey) {
    return null;
  }

  const model = getEnv("OPENAI_MODEL").trim() || "gpt-4o-mini";
  const prompt = [
    "당신은 유튜브 요리 영상 기반 레시피 초안 생성 도우미입니다.",
    "한국어로 응답하고 반드시 JSON만 반환하세요.",
    "JSON 형식: {\"summary\":string,\"ingredients\":string[],\"steps\":string[],\"tips\":string[],\"cautions\":string[]}",
    "ingredients는 4~12개, steps는 3~8개로 작성하세요.",
    `summary는 최대 ${params.maxSummaryLength}자`,
    `title: ${params.title}`,
    `recipeText: ${params.recipeText}`,
    `ingredients: ${params.ingredients.join(", ")}`,
    `steps: ${params.steps.join(" / ")}`,
  ].join("\n");

  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        input: prompt,
        temperature: 0.3,
      }),
    });

    if (!response.ok) {
      return null;
    }

    const body = await response.json().catch(() => null);
    const outputText = typeof body?.output_text === "string"
      ? body.output_text
      : "";

    if (!outputText.trim()) {
      return null;
    }

    const parsed = JSON.parse(outputText);
    const summary = typeof parsed?.summary === "string"
      ? compactText(parsed.summary)
      : "";
    const ingredients = toStringList(parsed?.ingredients).slice(0, 12);
    const steps = toStringList(parsed?.steps).slice(0, 8);
    const tips = toStringList(parsed?.tips).slice(0, 3);
    const cautions = toStringList(parsed?.cautions).slice(0, 2);

    if (!summary || ingredients.length === 0 || steps.length === 0) {
      return null;
    }

    return {
      summary: summarizeText(summary, params.maxSummaryLength),
      ingredients,
      steps,
      tips,
      cautions,
      engine: `openai:${model}`,
      degraded: false,
    };
  } catch (_) {
    return null;
  }
}

serve(async (req) => {
  const startedAt = Date.now();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return errorResponse(405, "invalid_input", "Method not allowed");
  }

  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return errorResponse(400, "invalid_input", "Request body must be valid JSON object");
  }

  const userId = await getAuthenticatedUserId(req);
  const action = typeof body.action === "string" ? body.action.trim().toLowerCase() : "summarize";

  if (action !== "summarize" && action !== "regenerate" && action !== "feedback" && action !== "draft_recipe") {
    return errorResponse(400, "invalid_input", "action must be summarize, regenerate, feedback, or draft_recipe");
  }

  if (action === "feedback") {
    if (!userId) {
      return errorResponse(401, "unauthorized", "authentication required for feedback");
    }

    const liked = Boolean((body as Record<string, unknown>).liked);
    const summary = typeof body.summary === "string" ? body.summary.trim() : "";
    const note = typeof body.note === "string" ? body.note.trim() : "";
    const recipeId = typeof body.recipeId === "string" ? body.recipeId.trim() : "";

    if (summary.length < 8) {
      return errorResponse(400, "feedback_invalid", "summary must be at least 8 characters");
    }

    const saved = await logFeedback({
      userId,
      liked,
      summary: summary.slice(0, 500),
      note: note.slice(0, 200),
      recipeId: recipeId.slice(0, 80),
    });

    if (!saved) {
      return errorResponse(500, "feedback_store_failed", "failed to store feedback");
    }

    return okResponse({ saved: true }, 200);
  }

  const title = typeof body.title === "string" ? body.title.trim() : "";
  const recipeText = typeof body.recipeText === "string" ? body.recipeText.trim() : "";
  const ingredients = toStringList((body as Record<string, unknown>).ingredients);
  const steps = toStringList((body as Record<string, unknown>).steps);
  const regenerateReason = typeof body.regenerate_reason === "string"
    ? body.regenerate_reason.trim().toLowerCase()
    : "";
  const previousSummary = typeof body.previous_summary === "string"
    ? body.previous_summary.trim()
    : "";
  const regenerateAttemptRaw = Number((body as Record<string, unknown>).regenerate_attempt ?? 0);
  const regenerateAttempt = Number.isFinite(regenerateAttemptRaw)
    ? Math.max(0, Math.min(20, Math.trunc(regenerateAttemptRaw)))
    : 0;
  const userFeedbackContext = typeof body.user_feedback_context === "string"
    ? body.user_feedback_context.trim().toLowerCase()
    : "";

  if (recipeText.length === 0 && title.length === 0 && ingredients.length === 0 && steps.length === 0) {
    return errorResponse(400, "invalid_input", "At least one of title, recipeText, ingredients, or steps is required");
  }

  const rawMaxLength = Number((body as Record<string, unknown>).maxSummaryLength ?? 180);
  const maxSummaryLength = Number.isFinite(rawMaxLength)
    ? Math.max(80, Math.min(260, Math.trunc(rawMaxLength)))
    : 180;

  const requestChars = JSON.stringify(body).length;
  const requestTokens = Math.ceil(requestChars / 4);
  const requestKrwPer1k = getNumberEnv("AI_REQUEST_KRW_PER_1K", 0.3);
  const responseKrwPer1k = getNumberEnv("AI_RESPONSE_KRW_PER_1K", 0.6);
  const estimatedResponseTokens = action === "draft_recipe"
    ? Math.ceil(maxSummaryLength / 4) + 260
    : Math.ceil(maxSummaryLength / 4) + 40;
  const estimatedCost = (requestTokens / 1000) * requestKrwPer1k + (estimatedResponseTokens / 1000) * responseKrwPer1k;
  const estimatedCostKrw = Math.round(estimatedCost * 100) / 100;
  const guardrailStage = await inferGuardrailStage(userId, estimatedCostKrw);

  if (guardrailStage === "stop") {
    const fallback = action === "draft_recipe"
      ? buildRuleBasedDraft({
        title,
        recipeText,
        ingredients,
        steps,
        maxSummaryLength,
        degraded: true,
        errorCode: "budget_stop",
      })
      : buildRuleBasedSummary({
        title,
        recipeText,
        ingredients,
        steps,
        maxSummaryLength,
        degraded: true,
        errorCode: "budget_stop",
      });

    const responseChars = JSON.stringify(fallback).length;
    const responseTokens = Math.ceil(responseChars / 4);
    const latencyMs = Math.max(1, Date.now() - startedAt);
    const costKrw = Math.round((((requestTokens / 1000) * requestKrwPer1k) + ((responseTokens / 1000) * responseKrwPer1k)) * 100) / 100;
    await logUsage({
      userId,
      endpoint: "ai_recipe_assistant",
      model: fallback.engine,
      requestTokens,
      responseTokens,
      requestChars,
      responseChars,
      latencyMs,
      costKrw,
      status: "blocked",
      guardrailStage,
      errorCode: "budget_stop",
      errorMessage: "monthly budget stop threshold reached",
      meta: {
        action_type: action,
        regenerate_reason: regenerateReason || null,
        regenerate_attempt: regenerateAttempt,
        user_feedback_context: userFeedbackContext || null,
        previous_summary: previousSummary.slice(0, 200) || null,
      },
    });

    return okResponse(fallback, 200);
  }

  let responseData = action === "draft_recipe"
    ? await tryOpenAiDraft({
      title,
      recipeText,
      ingredients,
      steps,
      maxSummaryLength,
    })
    : await tryOpenAiSummary({
      title,
      recipeText,
      ingredients,
      steps,
      maxSummaryLength,
    });

  let errorCode: AssistantErrorCode | undefined;
  if (!responseData) {
    errorCode = "provider_error";
    responseData = action === "draft_recipe"
      ? buildRuleBasedDraft({
        title,
        recipeText,
        ingredients,
        steps,
        maxSummaryLength,
        degraded: true,
        errorCode,
      })
      : buildRuleBasedSummary({
        title,
        recipeText,
        ingredients,
        steps,
        maxSummaryLength,
        degraded: true,
        errorCode,
      });
  }

  const responseChars = JSON.stringify(responseData).length;
  const responseTokens = Math.ceil(responseChars / 4);
  const latencyMs = Math.max(1, Date.now() - startedAt);
  const costKrw = Math.round((((requestTokens / 1000) * requestKrwPer1k) + ((responseTokens / 1000) * responseKrwPer1k)) * 100) / 100;

  await logUsage({
    userId,
    endpoint: "ai_recipe_assistant",
    model: responseData.engine,
    requestTokens,
    responseTokens,
    requestChars,
    responseChars,
    latencyMs,
    costKrw,
    status: responseData.degraded ? "degraded" : "ok",
    guardrailStage,
    errorCode,
    errorMessage: errorCode ? "provider fallback applied" : undefined,
    meta: {
      action_type: action,
      regenerate_reason: regenerateReason || null,
      regenerate_attempt: regenerateAttempt,
      user_feedback_context: userFeedbackContext || null,
      previous_summary: previousSummary.slice(0, 200) || null,
    },
  });

  return okResponse(responseData, 200);
});