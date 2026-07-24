import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type PublicRecipeRow = {
  source_id: string;
  title: string;
  summary: string;
  ingredients: string[];
  steps: string[];
  calories: number | null;
  image_url: string | null;
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-worker-secret",
  "Access-Control-Allow-Methods": "POST,OPTIONS"
};

const JSON_HEADERS = {
  "Content-Type": "application/json",
  ...CORS_HEADERS
};

function getEnv(name: string): string {
  return Deno.env.get(name) ?? "";
}

function requireWorkerSecret(req: Request): { ok: true } | { ok: false; response: Response } {
  const expected = getEnv("PUBLIC_RECIPE_SYNC_WORKER_SECRET").trim();
  if (expected.length === 0) {
    return {
      ok: false,
      response: new Response(
        JSON.stringify({
          status: "error",
          message: "PUBLIC_RECIPE_SYNC_WORKER_SECRET is not configured"
        }),
        {
          status: 500,
          headers: JSON_HEADERS
        }
      )
    };
  }

  const actual = (req.headers.get("x-worker-secret") ?? "").trim();
  if (actual !== expected) {
    return {
      ok: false,
      response: new Response(
        JSON.stringify({
          status: "error",
          message: "Invalid worker secret"
        }),
        {
          status: 401,
          headers: JSON_HEADERS
        }
      )
    };
  }

  return { ok: true };
}

function buildCookRcpApiUrl(start: number, end: number): string {
  const apiBaseUrl = getEnv("FOOD_API_BASE_URL").trim();
  const apiKey = getEnv("FOOD_API_KEY").trim();
  const apiUrlTemplate = getEnv("FOOD_API_URL_TEMPLATE").trim();

  if (apiUrlTemplate.length > 0) {
    return apiUrlTemplate
      .replaceAll("{API_KEY}", apiKey)
      .replaceAll("{SVC_NO}", "COOKRCP01")
      .replaceAll("{START}", String(start))
      .replaceAll("{END}", String(end));
  }

  if (apiBaseUrl.includes("{API_KEY}") || apiBaseUrl.includes("{START}") || apiBaseUrl.includes("{END}")) {
    return apiBaseUrl
      .replaceAll("{API_KEY}", apiKey)
      .replaceAll("{SVC_NO}", "COOKRCP01")
      .replaceAll("{START}", String(start))
      .replaceAll("{END}", String(end));
  }

  return `${apiBaseUrl.replace(/\/$/, "")}/${apiKey}/COOKRCP01/json/${start}/${end}`;
}

function splitIngredients(text: string): string[] {
  return text
    .split(/[,\n]/g)
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
}

function pickSteps(record: Record<string, unknown>): string[] {
  const steps: string[] = [];

  for (let i = 1; i <= 20; i += 1) {
    const key = `MANUAL${String(i).padStart(2, "0")}`;
    const value = String(record[key] ?? "").trim();
    if (value.length > 0) {
      steps.push(value);
    }
  }

  return steps;
}

function mapRecord(record: Record<string, unknown>): PublicRecipeRow | null {
  const sourceId = String(record.RCP_SEQ ?? record.id ?? "").trim();
  const title = String(record.RCP_NM ?? record.RCP_NM_KO ?? record.title ?? "").trim();

  if (sourceId.length === 0 || title.length === 0) {
    return null;
  }

  const summary = String(
    record.HASH_TAG ?? record.RCP_PAT2 ?? record.summary ?? ""
  ).trim();
  const ingredients = splitIngredients(String(record.RCP_PARTS_DTLS ?? record.ingredients ?? ""));
  const steps = pickSteps(record);
  const caloriesRaw = String(record.INFO_ENG ?? record.calories ?? "").trim();
  const calories = caloriesRaw.length > 0 ? Number(caloriesRaw) : null;
  const imageUrl = String(record.ATT_FILE_NO_MAIN ?? record.image_url ?? "").trim();

  return {
    source_id: sourceId,
    title,
    summary,
    ingredients,
    steps,
    calories: Number.isFinite(calories) ? calories : null,
    image_url: imageUrl.length > 0 ? imageUrl : null
  };
}

async function loadFromPublicApi(size: number): Promise<PublicRecipeRow[]> {
  const apiBaseUrl = getEnv("FOOD_API_BASE_URL");
  const apiKey = getEnv("FOOD_API_KEY");

  if (apiBaseUrl.length === 0 || apiKey.length === 0) {
    return [
      {
        source_id: "fallback-001",
        title: "고등어조림",
        summary: "공공 API 키 미설정 상태의 조림 검색 샘플",
        ingredients: ["고등어", "무", "고추장", "간장"],
        steps: ["양념장을 만든다", "고등어와 무를 넣고 조린다"],
        calories: 410,
        image_url: null
      },
      {
        source_id: "fallback-002",
        title: "생선조림",
        summary: "양념 국물로 자작하게 조리는 생선 요리",
        ingredients: ["생선", "간장", "마늘", "대파"],
        steps: ["생선 손질", "양념과 함께 중약불로 조린다"],
        calories: 360,
        image_url: null
      },
      {
        source_id: "fallback-003",
        title: "명태 조림",
        summary: "말린 명태를 감칠맛 있게 조린 밥반찬",
        ingredients: ["명태", "고춧가루", "간장", "올리고당"],
        steps: ["명태를 불린다", "양념을 넣고 조림 농도로 졸인다"],
        calories: 330,
        image_url: null
      },
      {
        source_id: "fallback-004",
        title: "조림 된장",
        summary: "된장 기반으로 짭짤하게 조려낸 소스 스타일",
        ingredients: ["된장", "양파", "다진 마늘", "물"],
        steps: ["된장을 푼다", "재료를 넣고 걸쭉해질 때까지 조린다"],
        calories: 210,
        image_url: null
      },
      {
        source_id: "fallback-005",
        title: "감자탕",
        summary: "감자가 들어간 얼큰한 국물 요리",
        ingredients: ["감자", "돼지등뼈", "우거지"],
        steps: ["뼈를 삶아 잡내를 제거한다", "감자와 함께 푹 끓인다"],
        calories: 520,
        image_url: null
      },
      {
        source_id: "fallback-006",
        title: "감자볶음밥",
        summary: "잘게 썬 감자를 넣은 고소한 볶음밥",
        ingredients: ["감자", "밥", "달걀", "간장"],
        steps: ["감자를 볶는다", "밥을 넣고 볶아 마무리한다"],
        calories: 460,
        image_url: null
      },
      {
        source_id: "fallback-007",
        title: "튀긴감자요리",
        summary: "바삭하게 튀긴 감자 스낵",
        ingredients: ["감자", "식용유", "소금"],
        steps: ["감자를 채 썬다", "노릇하게 튀긴다"],
        calories: 430,
        image_url: null
      }
    ];
  }

  const url = buildCookRcpApiUrl(1, size);
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Public API request failed: ${response.status}`);
  }

  const payload = await response.json();
  const rows = Array.isArray(payload?.COOKRCP01?.row)
    ? payload.COOKRCP01.row
    : (Array.isArray(payload?.row) ? payload.row : []);

  return rows
    .map((item: Record<string, unknown>) => mapRecord(item))
    .filter((item: PublicRecipeRow | null): item is PublicRecipeRow => item !== null);
}

async function upsertRecipes(rows: PublicRecipeRow[]): Promise<number> {
  if (rows.length === 0) {
    return 0;
  }

  const supabaseUrl = getEnv("SUPABASE_URL");
  const serviceRoleKey = getEnv("SUPABASE_SERVICE_ROLE_KEY") || getEnv("SERVICE_ROLE_KEY");

  if (supabaseUrl.length === 0 || serviceRoleKey.length === 0) {
    throw new Error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing");
  }

  const response = await fetch(
    `${supabaseUrl}/rest/v1/recipes_public?on_conflict=source_id`,
    {
      method: "POST",
      headers: {
        ...JSON_HEADERS,
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        Prefer: "resolution=merge-duplicates,return=representation"
      },
      body: JSON.stringify(rows)
    }
  );

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`Upsert failed: ${response.status} ${message}`);
  }

  const data = await response.json();
  return Array.isArray(data) ? data.length : 0;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ message: "Use POST to run sync" }), {
      status: 405,
      headers: JSON_HEADERS
    });
  }

  const secretCheck = requireWorkerSecret(req);
  if (!secretCheck.ok) {
    return secretCheck.response;
  }

  try {
    const body = await req.json().catch(() => ({}));
    const size = Number(body?.size ?? 30);
    const safeSize = Number.isFinite(size) ? Math.max(1, Math.min(size, 200)) : 30;

    const rows = await loadFromPublicApi(safeSize);
    const upserted = await upsertRecipes(rows);

    return new Response(
      JSON.stringify({
        status: "ok",
        fetched: rows.length,
        upserted
      }),
      {
        headers: {
          ...JSON_HEADERS,
          "Access-Control-Allow-Origin": "*"
        }
      }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        status: "error",
        message: error instanceof Error ? error.message : "Unknown error"
      }),
      {
        status: 500,
        headers: {
          ...JSON_HEADERS,
          "Access-Control-Allow-Origin": "*"
        }
      }
    );
  }
});
