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

const JSON_HEADERS = {
  "Content-Type": "application/json"
};

function getEnv(name: string): string {
  return Deno.env.get(name) ?? "";
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
        title: "간장계란밥",
        summary: "공공 API 키 미설정 상태의 기본 샘플",
        ingredients: ["밥 1공기", "달걀 1개", "간장 1큰술"],
        steps: ["달걀 프라이를 굽는다", "밥 위에 올리고 간장을 넣어 비빈다"],
        calories: 520,
        image_url: null
      }
    ];
  }

  const url = `${apiBaseUrl.replace(/\/$/, "")}/${apiKey}/COOKRCP01/json/1/${size}`;
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Public API request failed: ${response.status}`);
  }

  const payload = await response.json();
  const rows = Array.isArray(payload?.COOKRCP01?.row) ? payload.COOKRCP01.row : [];

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
    return new Response("ok", {
      headers: {
        ...JSON_HEADERS,
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
      }
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ message: "Use POST to run sync" }), {
      status: 405,
      headers: JSON_HEADERS
    });
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
