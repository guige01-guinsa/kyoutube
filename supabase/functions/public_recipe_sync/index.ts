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

type CatalogRecipeInput = Omit<PublicRecipeRow, "image_url"> & {
  image_url?: string | null;
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

function buildImageUrl(sourceId: string): string {
  return `https://picsum.photos/seed/${encodeURIComponent(sourceId)}/640/360`;
}

function withImage(row: CatalogRecipeInput): PublicRecipeRow {
  return {
    ...row,
    image_url: (row.image_url ?? "").trim().length > 0 ? row.image_url : buildImageUrl(row.source_id)
  };
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

const PUBLIC_RECIPE_CATALOG: PublicRecipeRow[] = [
  {
    source_id: "local-kimchi-fried-rice",
    title: "김치볶음밥",
    summary: "가장 빠르게 만들 수 있는 대표 한 끼",
    ingredients: ["밥", "김치", "대파", "달걀"],
    steps: ["김치를 먼저 볶는다", "밥을 넣고 함께 볶는다", "달걀 프라이를 올린다"],
    calories: 620,
    image_url: null
  },
  {
    source_id: "local-egg-fried-rice",
    title: "계란볶음밥",
    summary: "계란 향이 살아 있는 기본 볶음밥",
    ingredients: ["밥", "달걀", "양파", "간장"],
    steps: ["계란을 먼저 볶는다", "밥과 양파를 넣는다", "간장으로 간한다"],
    calories: 580,
    image_url: null
  },
  {
    source_id: "local-tuna-fried-rice",
    title: "참치볶음밥",
    summary: "참치와 김치가 잘 어울리는 볶음밥",
    ingredients: ["밥", "참치", "김치", "대파"],
    steps: ["참치 기름을 살짝 볶는다", "김치와 밥을 넣는다", "고르게 섞어 마무리한다"],
    calories: 610,
    image_url: null
  },
  {
    source_id: "local-shrimp-fried-rice",
    title: "새우볶음밥",
    summary: "새우와 채소를 더한 간단한 볶음밥",
    ingredients: ["밥", "새우", "당근", "달걀"],
    steps: ["새우를 먼저 익힌다", "채소와 밥을 넣는다", "후추로 마무리한다"],
    calories: 540,
    image_url: null
  },
  {
    source_id: "local-kimchi-jjigae",
    title: "김치찌개",
    summary: "많이 찾는 대표 국물 요리",
    ingredients: ["김치", "돼지고기", "두부", "대파"],
    steps: ["돼지고기를 볶는다", "김치와 물을 넣는다", "두부를 넣고 끓인다"],
    calories: 450,
    image_url: null
  },
  {
    source_id: "local-soybean-paste-jjigae",
    title: "된장찌개",
    summary: "구수한 집밥 느낌의 된장 국물",
    ingredients: ["된장", "두부", "감자", "애호박"],
    steps: ["된장을 푼다", "감자와 채소를 넣는다", "두부를 넣고 끓인다"],
    calories: 390,
    image_url: null
  },
  {
    source_id: "local-soft-tofu-jjigae",
    title: "순두부찌개",
    summary: "부드럽고 얼큰한 국물 요리",
    ingredients: ["순두부", "고춧가루", "계란", "바지락"],
    steps: ["양념을 볶는다", "육수를 붓는다", "순두부와 계란을 넣는다"],
    calories: 410,
    image_url: null
  },
  {
    source_id: "local-budae-jjigae",
    title: "부대찌개",
    summary: "햄과 소시지로 든든하게 끓이는 찌개",
    ingredients: ["햄", "소시지", "김치", "라면사리"],
    steps: ["재료를 넓게 담는다", "육수와 양념을 넣는다", "끓여서 사리를 익힌다"],
    calories: 690,
    image_url: null
  },
  {
    source_id: "local-braised-mackerel",
    title: "고등어조림",
    summary: "밥반찬으로 인기 있는 조림",
    ingredients: ["고등어", "무", "간장", "고추"],
    steps: ["양념장을 만든다", "무와 고등어를 넣는다", "자작하게 졸인다"],
    calories: 430,
    image_url: null
  },
  {
    source_id: "local-braised-tofu",
    title: "두부조림",
    summary: "간단하지만 자주 찾는 밥반찬",
    ingredients: ["두부", "간장", "대파", "고춧가루"],
    steps: ["두부를 노릇하게 굽는다", "양념장을 붓는다", "약불로 졸인다"],
    calories: 290,
    image_url: null
  },
  {
    source_id: "local-braised-potatoes",
    title: "감자조림",
    summary: "달짝지근한 도시락 반찬",
    ingredients: ["감자", "간장", "올리고당", "마늘"],
    steps: ["감자를 썬다", "양념과 함께 볶는다", "국물이 졸아들 때까지 익힌다"],
    calories: 300,
    image_url: null
  },
  {
    source_id: "local-bulgogi",
    title: "소불고기",
    summary: "불고기 양념으로 익히는 대표 메뉴",
    ingredients: ["소고기", "양파", "대파", "간장"],
    steps: ["양념에 재운다", "채소와 함께 볶는다", "윤기가 나면 완성한다"],
    calories: 530,
    image_url: null
  },
  {
    source_id: "local-spicy-pork",
    title: "제육볶음",
    summary: "매콤하게 볶아 먹는 든든한 한 끼",
    ingredients: ["돼지고기", "고추장", "양파", "대파"],
    steps: ["양념에 재운다", "센불에 볶는다", "채소를 넣고 마무리한다"],
    calories: 640,
    image_url: null
  },
  {
    source_id: "local-stir-fried-anchovy",
    title: "멸치볶음",
    summary: "도시락과 밑반찬의 기본",
    ingredients: ["멸치", "간장", "올리고당", "견과류"],
    steps: ["멸치를 볶는다", "양념을 넣어 졸인다", "견과류를 섞는다"],
    calories: 220,
    image_url: null
  },
  {
    source_id: "local-japchae",
    title: "잡채",
    summary: "명절과 손님상에 자주 올라가는 메뉴",
    ingredients: ["당면", "시금치", "당근", "소고기"],
    steps: ["재료를 각각 볶는다", "당면에 양념을 섞는다", "모든 재료를 버무린다"],
    calories: 520,
    image_url: null
  },
  {
    source_id: "local-bibimbap",
    title: "비빔밥",
    summary: "여러 나물을 한 그릇에 담는 대표 메뉴",
    ingredients: ["밥", "나물", "계란", "고추장"],
    steps: ["나물을 준비한다", "밥 위에 올린다", "고추장과 함께 비빈다"],
    calories: 560,
    image_url: null
  },
  {
    source_id: "local-spaghetti-korean-style",
    title: "토마토파스타",
    summary: "간편하게 찾는 면 요리",
    ingredients: ["파스타", "토마토소스", "양파", "마늘"],
    steps: ["면을 삶는다", "소스를 볶는다", "면과 함께 버무린다"],
    calories: 640,
    image_url: null
  },
  {
    source_id: "local-soybean-sprout-soup",
    title: "콩나물국",
    summary: "아침에 부담 없이 찾는 맑은 국",
    ingredients: ["콩나물", "대파", "마늘", "소금"],
    steps: ["콩나물을 씻는다", "물을 끓인다", "간을 맞춰 마무리한다"],
    calories: 140,
    image_url: null
  },
  {
    source_id: "local-seaweed-soup",
    title: "미역국",
    summary: "생일과 일상 모두에 잘 맞는 국물",
    ingredients: ["미역", "소고기", "참기름", "국간장"],
    steps: ["미역을 불린다", "소고기를 볶는다", "물과 함께 끓인다"],
    calories: 240,
    image_url: null
  },
  {
    source_id: "local-chicken-salad",
    title: "닭가슴살 샐러드",
    summary: "가볍게 먹기 좋은 단백질 중심 메뉴",
    ingredients: ["닭가슴살", "양상추", "방울토마토", "올리브오일"],
    steps: ["닭가슴살을 익힌다", "채소를 손질한다", "드레싱과 함께 버무린다"],
    calories: 380,
    image_url: null
  },
  {
    source_id: "local-stir-fried-veg",
    title: "채소볶음",
    summary: "냉장고 재료를 활용하기 좋은 반찬",
    ingredients: ["양파", "당근", "애호박", "버섯"],
    steps: ["채소를 썬다", "센불에 볶는다", "간장으로 마무리한다"],
    calories: 170,
    image_url: null
  },
  {
    source_id: "local-pancake",
    title: "부추전",
    summary: "비 오는 날 찾기 좋은 전 요리",
    ingredients: ["부추", "밀가루", "달걀", "물"],
    steps: ["반죽을 만든다", "부추를 넣는다", "노릇하게 부친다"],
    calories: 460,
    image_url: null
  }
].map(withImage);

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
    const size = Number(body?.size ?? PUBLIC_RECIPE_CATALOG.length);
    const safeSize = Number.isFinite(size) ? Math.max(1, Math.min(size, PUBLIC_RECIPE_CATALOG.length)) : PUBLIC_RECIPE_CATALOG.length;

    const rows = PUBLIC_RECIPE_CATALOG.slice(0, safeSize);
    const upserted = await upsertRecipes(rows);

    return new Response(
      JSON.stringify({
        status: "ok",
        fetched: rows.length,
        upserted
      }),
      {
        headers: JSON_HEADERS
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
        headers: JSON_HEADERS
      }
    );
  }
});
