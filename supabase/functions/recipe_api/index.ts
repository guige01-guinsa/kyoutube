import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type RecipePayload = {
  title: string;
  summary: string | null;
  ingredients: unknown[];
  steps: unknown[];
  tips: string | null;
  youtube_url: string | null;
  image_path: string | null;
  is_published: boolean;
};

type PublicRecipeRow = {
  id: string;
  source_id: string | null;
  title: string;
  summary: string | null;
  ingredients: unknown[];
  steps: unknown[];
  calories: number | null;
  image_url: string | null;
  created_at: string;
  updated_at: string;
};

const FUNCTION_NAME = "recipe_api";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET,POST,PATCH,DELETE,OPTIONS"
};

const JSON_HEADERS = {
  "Content-Type": "application/json",
  ...CORS_HEADERS
};

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

function errorResponse(
  status: number,
  message: string,
  details: unknown = null
): Response {
  return new Response(
    JSON.stringify({
      status: "error",
      message,
      details
    }),
    {
      status,
      headers: JSON_HEADERS
    }
  );
}

function getEnv(name: string): string {
  return Deno.env.get(name) ?? "";
}

function scoreLocalRecipe(row: PublicRecipeRow, tokens: string[], search: string): number {
  if (tokens.length === 0) {
    return 0;
  }

  const text = buildSearchText(row);
  let score = 0;
  let matchedTokens = 0;

  for (const token of tokens) {
    const candidates = expandKeywordToken(token).concat(expandAiToken(token));
    let tokenMatched = false;

    for (const candidate of candidates) {
      if (text.title.includes(candidate)) {
        score += candidate === token ? 18 : 10;
        tokenMatched = true;
      }
      if (text.summary.includes(candidate)) {
        score += candidate === token ? 10 : 6;
        tokenMatched = true;
      }
      if (text.ingredients.includes(candidate)) {
        score += candidate === token ? 14 : 8;
        tokenMatched = true;
      }
      if (text.steps.includes(candidate)) {
        score += candidate === token ? 8 : 4;
        tokenMatched = true;
      }
      if (text.compact.includes(compactSearchText(candidate))) {
        score += candidate === token ? 12 : 6;
        tokenMatched = true;
      }
    }

    if (tokenMatched) {
      matchedTokens += 1;
    }
  }

  const compactQuery = compactSearchText(search);
  if (compactQuery.length > 1 && text.compact.includes(compactQuery)) {
    score += 20;
  }

  return score + matchedTokens * 2;
}

function getSupabaseConfig(): {
  supabaseUrl: string;
  serviceRoleKey: string;
  anonKey: string;
} {
  const supabaseUrl = getEnv("SUPABASE_URL");
  const serviceRoleKey = getEnv("SUPABASE_SERVICE_ROLE_KEY") || getEnv("SERVICE_ROLE_KEY");
  const anonKey = getEnv("SUPABASE_ANON_KEY") || serviceRoleKey;

  if (supabaseUrl.length === 0 || serviceRoleKey.length === 0) {
    throw new Error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY/SERVICE_ROLE_KEY is missing");
  }

  return { supabaseUrl, serviceRoleKey, anonKey };
}

function getRouteId(pathname: string): string | null {
  const segments = pathname.split("/").filter((value) => value.length > 0);
  const functionIndex = segments.findIndex((value) => value === FUNCTION_NAME);
  const routeSegments = functionIndex >= 0 ? segments.slice(functionIndex + 1) : segments;

  if (routeSegments.length > 1) {
    return "__INVALID_PATH__";
  }

  return routeSegments.length === 1 ? decodeURIComponent(routeSegments[0]) : null;
}

function parseType(method: string, url: URL): { type?: string; error?: Response } {
  const rawType = url.searchParams.get("type");
  const type = rawType && rawType.trim().length > 0
    ? rawType.trim().toLowerCase()
    : (method === "GET" ? "public" : "");

  if (type.length === 0) {
    return {
      error: errorResponse(400, "type query parameter is required")
    };
  }

  if (type !== "public" && type !== "creator" && type !== "kitchen") {
    return {
      error: errorResponse(400, "type must be one of: public, creator, kitchen")
    };
  }

  return { type };
}

function parsePagination(url: URL): { limit: number; offset: number; error?: Response } {
  const rawLimit = url.searchParams.get("limit");
  const rawOffset = url.searchParams.get("offset");

  const limit = rawLimit === null ? 20 : Number(rawLimit);
  const offset = rawOffset === null ? 0 : Number(rawOffset);

  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    return {
      limit,
      offset,
      error: errorResponse(400, "limit must be an integer between 1 and 100")
    };
  }

  if (!Number.isInteger(offset) || offset < 0) {
    return {
      limit,
      offset,
      error: errorResponse(400, "offset must be an integer >= 0")
    };
  }

  return { limit, offset };
}

function parseSearchMode(url: URL): "keyword" | "ai" {
  const rawMode = (url.searchParams.get("search_mode") ?? "").trim().toLowerCase();
  return rawMode === "ai" ? "ai" : "keyword";
}

function tokenizeSearch(search: string): string[] {
  return search
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .split(/\s+/)
    .map((token) => normalizeSearchToken(token))
    .filter((token) => token.length > 0 && !isSearchStopWord(token))
    .slice(0, 8);
}

function normalizeSearchToken(token: string): string {
  const trimmed = token.trim();
  if (trimmed.length < 3) {
    return trimmed;
  }

  return trimmed.replace(/(으로|에서|에게|까지|부터|하고|이며|이다|은|는|이|가|을|를|와|과|의|로|에|도|만|랑)$/u, "");
}

function isSearchStopWord(token: string): boolean {
  return ["레시피", "요리", "음식", "만들기", "만드는법", "방법"].includes(token);
}

function compactSearchText(value: string): string {
  return value.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
}

function toStringList(values: unknown): string[] {
  if (!Array.isArray(values)) {
    return [];
  }

  return values
    .map((value) => String(value ?? "").trim())
    .filter((value) => value.length > 0);
}

function buildSearchText(row: PublicRecipeRow): {
  title: string;
  summary: string;
  ingredients: string;
  steps: string;
  all: string;
  compact: string;
} {
  const title = (row.title ?? "").toLowerCase();
  const summary = (row.summary ?? "").toLowerCase();
  const ingredients = toStringList(row.ingredients).join(" ").toLowerCase();
  const steps = toStringList(row.steps).join(" ").toLowerCase();

  return {
    title,
    summary,
    ingredients,
    steps,
    all: `${title} ${summary} ${ingredients} ${steps}`.trim(),
    compact: compactSearchText(`${title} ${summary} ${ingredients} ${steps}`),
  };
}

function isFallbackSample(row: PublicRecipeRow): boolean {
  const sourceId = String(row.source_id ?? "").toLowerCase();
  if (sourceId.startsWith("fallback-")) {
    return true;
  }

  const summary = String(row.summary ?? "").toLowerCase();
  return summary.includes("공공 api 키 미설정");
}

function preferRealRows(rows: PublicRecipeRow[]): PublicRecipeRow[] {
  const realRows = rows.filter((row) => !isFallbackSample(row));
  return realRows.length > 0 ? realRows : rows;
}

function ensureImageUrl(row: PublicRecipeRow): PublicRecipeRow {
  if ((row.image_url ?? "").trim().length > 0) {
    return row;
  }

  const seed = String(row.source_id ?? row.title ?? "recipe").trim();
  return {
    ...row,
    image_url: `https://picsum.photos/seed/${encodeURIComponent(seed)}/640/360`,
  };
}

function expandKeywordToken(token: string): string[] {
  const dictionary: Record<string, string[]> = {
    "계란": ["달걀"],
    "달걀": ["계란"],
    "닭": ["닭고기", "치킨", "chicken"],
    "닭고기": ["닭"],
    "치킨": ["닭", "닭고기", "chicken"],
    "돼지": ["돼지고기", "삼겹살", "목살", "pork"],
    "돼지고기": ["돼지", "삼겹살", "목살"],
    "소고기": ["한우", "쇠고기", "불고기", "beef"],
    "쇠고기": ["소고기", "한우", "불고기", "beef"],
    "소불고기": ["불고기", "소고기"],
    "밥": ["쌀", "볶음밥", "덮밥", "죽"],
    "쌀": ["밥", "라이스", "rice"],
    "새우": ["shrimp", "해물"],
    "오징어": ["squid", "해물"],
    "두부": ["tofu"],
    "김치": ["배추김치", "묵은지"],
    "볶음": ["볶아", "볶는", "볶는다", "볶은", "볶기", "볶다"],
    "굽기": ["굽는", "굽는다", "구워", "구운", "굽다"],
    "구이": ["굽는", "굽는다", "구워", "구운", "굽다"],
    "끓이기": ["끓는", "끓인다", "끓여", "끓인", "끓이다"],
    "찌기": ["찌는", "찐다", "쪄", "찐", "찌다"],
    "튀기기": ["튀기는", "튀긴", "튀겨", "튀기다"],
    "무침": ["무쳐", "무치는", "무친", "무치다"],
    "조림": ["졸임", "조려", "조리는", "조린", "조리다"],
    "졸임": ["조림", "조려", "조리는", "조린", "조리다"],
  };

  return [token, ...(dictionary[token] ?? [])].map((value) => value.toLowerCase());
}

function expandAiToken(token: string): string[] {
  const dictionary: Record<string, string[]> = {
    "찌개": ["탕", "국", "전골", "스튜"],
    "조림": ["졸임", "조려", "braised", "브레이즈", "자작"],
    "졸임": ["조림", "조려", "braised", "브레이즈", "자작"],
    "조려": ["조림", "졸임", "braised", "브레이즈", "자작"],
    "볶음": ["볶음밥", "볶다", "stir fry"],
    "샐러드": ["salad", "채소", "vegetable"],
    "치킨": ["닭", "닭가슴살", "chicken"],
    "돼지": ["삼겹살", "목살", "pork"],
    "소고기": ["한우", "불고기", "beef"],
    "다이어트": ["저칼로리", "단백질", "담백"],
    "매운": ["매콤", "얼큰", "spicy"],
    "간단": ["초간단", "빠른", "quick"],
  };

  const extras = dictionary[token] ?? [];
  return [...expandKeywordToken(token), ...extras.map((item) => item.toLowerCase())];
}

function scoreKeywordSearch(row: PublicRecipeRow, tokens: string[], search: string): number {
  return scoreLocalRecipe(row, tokens, search);
}

function scoreAiSearch(row: PublicRecipeRow, tokens: string[]): number {
  return scoreLocalRecipe(row, tokens, tokens.join(" "));
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

function hasBearerToken(req: Request): boolean {
  return getBearerToken(req) != null;
}

function creatorAuthRequiredResponse(): Response {
  return errorResponse(
    401,
    "CREATOR_AUTH_REQUIRED: creator API requires authentication; anonymous usage is limited to local draft only",
    {
      policy: "local_draft_only",
      allow_anonymous_server_save: false,
    }
  );
}

async function getAuthenticatedUserId(req: Request): Promise<{ userId?: string; error?: Response }> {
  const token = getBearerToken(req);
  if (!token) {
    return {
      error: errorResponse(401, "Authorization Bearer token is required")
    };
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
    const details = await response.text();
    return {
      error: errorResponse(401, "Invalid or expired access token", details)
    };
  }

  const data = await response.json();
  const userId = typeof data?.id === "string" ? data.id : "";

  if (userId.length === 0) {
    return {
      error: errorResponse(401, "Authenticated user id was not found")
    };
  }

  return { userId };
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

async function persistPublicRecipes(rows: PublicRecipeRow[]): Promise<PublicRecipeRow[]> {
  if (rows.length === 0) {
    return [];
  }

  const response = await restRequest("/rest/v1/recipes_public?on_conflict=source_id", {
    method: "POST",
    headers: {
      Prefer: "resolution=merge-duplicates,return=representation"
    },
    body: JSON.stringify(rows.map((row) => ({
      source_id: row.source_id,
      title: row.title,
      summary: row.summary,
      ingredients: row.ingredients,
      steps: row.steps,
      calories: row.calories,
      image_url: row.image_url,
    }))),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Failed to persist public search results: ${details}`);
  }

  const data = await response.json();
  return Array.isArray(data) ? data as PublicRecipeRow[] : [];
}

async function parseRecipePayload(req: Request): Promise<{ payload?: RecipePayload; error?: Response }> {
  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return {
      error: errorResponse(400, "Request body must be valid JSON object")
    };
  }

  const title = typeof body.title === "string" ? body.title.trim() : "";
  const ingredients = (body as Record<string, unknown>).ingredients;
  const steps = (body as Record<string, unknown>).steps;

  if (title.length === 0) {
    return {
      error: errorResponse(400, "title is required and must be non-empty")
    };
  }

  if (!Array.isArray(ingredients)) {
    return {
      error: errorResponse(400, "ingredients is required and must be an array")
    };
  }

  if (!Array.isArray(steps)) {
    return {
      error: errorResponse(400, "steps is required and must be an array")
    };
  }

  const summary = typeof body.summary === "string" ? body.summary.trim() : "";
  const tips = typeof body.tips === "string" ? body.tips.trim() : "";
  const youtubeUrl = typeof body.youtube_url === "string" ? body.youtube_url.trim() : "";
  const imagePath = typeof body.image_path === "string" ? body.image_path.trim() : "";

  return {
    payload: {
      title,
      summary: summary.length > 0 ? summary : null,
      ingredients,
      steps,
      tips: tips.length > 0 ? tips : null,
      youtube_url: youtubeUrl.length > 0 ? youtubeUrl : null,
      image_path: imagePath.length > 0 ? imagePath : null,
      is_published: typeof body.is_published === "boolean" ? body.is_published : true
    }
  };
}

async function listPublicRecipes(url: URL): Promise<Response> {
  const { limit, offset, error } = parsePagination(url);
  if (error) {
    return error;
  }

  const search = (url.searchParams.get("search") ?? "").trim();
  const tokens = tokenizeSearch(search);
  const effectiveLimit = limit;
  const params = new URLSearchParams();
  params.set("select", "id,source_id,title,summary,ingredients,steps,calories,image_url,created_at,updated_at");
  params.set("order", "created_at.desc");
  params.set("limit", String(tokens.length === 0 ? effectiveLimit : 100));
  params.set("offset", String(tokens.length === 0 ? offset : 0));

  const response = await restRequest(`/rest/v1/recipes_public?${params.toString()}`, {
    method: "GET"
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to fetch public recipes", details);
  }

  const data = await response.json();
  if (!Array.isArray(data)) {
    return okResponse([], 200);
  }

  const localRows = preferRealRows(data as PublicRecipeRow[]);
  const normalizedRows = localRows.map(ensureImageUrl);

  if (tokens.length === 0) {
    return okResponse(normalizedRows.slice(0, effectiveLimit), 200);
  }

  const ranked = normalizedRows
    .map((row: PublicRecipeRow) => ({
      row,
      score: scoreKeywordSearch(row, tokens, search),
    }))
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(offset, offset + effectiveLimit)
    .map((item) => item.row);

  if (ranked.length > 0) {
    return okResponse(ranked, 200);
  }

  // When query tokens have no direct match, return recent rows as a fallback
  // so users still see discoverable public recipes instead of an empty result.
  return okResponse(normalizedRows.slice(offset, offset + effectiveLimit), 200);
}

async function getPublicRecipeDetail(id: string): Promise<Response> {
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id);

  if (isUuid) {
    const params = new URLSearchParams();
    params.set("select", "id,source_id,title,summary,ingredients,steps,calories,image_url,created_at,updated_at");
    params.set("id", `eq.${id}`);
    params.set("limit", "1");

    const response = await restRequest(`/rest/v1/recipes_public?${params.toString()}`, {
      method: "GET"
    });

    if (!response.ok) {
      const details = await response.text();
      return errorResponse(500, "Failed to fetch recipe detail", details);
    }

    const rows = await response.json();
    if (Array.isArray(rows) && rows.length > 0) {
      return okResponse(ensureImageUrl(rows[0] as PublicRecipeRow), 200);
    }
  }

  const sourceParams = new URLSearchParams();
  sourceParams.set("select", "id,source_id,title,summary,ingredients,steps,calories,image_url,created_at,updated_at");
  sourceParams.set("source_id", `eq.${id}`);
  sourceParams.set("limit", "1");

  const sourceResponse = await restRequest(`/rest/v1/recipes_public?${sourceParams.toString()}`, {
    method: "GET"
  });

  if (!sourceResponse.ok) {
    const details = await sourceResponse.text();
    return errorResponse(500, "Failed to fetch recipe detail", details);
  }

  const sourceRows = await sourceResponse.json();
  if (Array.isArray(sourceRows) && sourceRows.length > 0) {
    return okResponse(ensureImageUrl(sourceRows[0] as PublicRecipeRow), 200);
  }

  return errorResponse(404, "Public recipe not found", { id });
}

async function listCreatorRecipes(url: URL, userId: string): Promise<Response> {
  const { limit, offset, error } = parsePagination(url);
  if (error) {
    return error;
  }

  const search = (url.searchParams.get("search") ?? "").trim();
  const params = new URLSearchParams();
  params.set(
    "select",
    "id,author_id,title,summary,ingredients,steps,tips,youtube_url,image_path,is_published,created_at,updated_at"
  );
  params.set("author_id", `eq.${userId}`);
  params.set("order", "created_at.desc");
  params.set("limit", String(limit));
  params.set("offset", String(offset));

  if (search.length > 0) {
    params.set("title", `ilike.*${search}*`);
  }

  const response = await restRequest(`/rest/v1/recipes_creator?${params.toString()}`, {
    method: "GET"
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to fetch creator recipes", details);
  }

  const data = await response.json();
  return okResponse(data, 200);
}

async function getCreatorRecipeDetail(id: string, userId: string): Promise<Response> {
  const params = new URLSearchParams();
  params.set(
    'select',
    'id,author_id,title,summary,ingredients,steps,tips,youtube_url,image_path,is_published,created_at,updated_at',
  );
  params.set('id', `eq.${id}`);
  params.set('author_id', `eq.${userId}`);
  params.set('limit', '1');

  const response = await restRequest(`/rest/v1/recipes_creator?${params.toString()}`, {
    method: 'GET',
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, 'Failed to fetch creator recipe detail', details);
  }

  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return errorResponse(404, 'Creator recipe not found', { id });
  }

  return okResponse(rows[0], 200);
}

async function ensureCreatorOwner(id: string, userId: string): Promise<{ error?: Response }> {
  const params = new URLSearchParams();
  params.set("select", "id,author_id");
  params.set("id", `eq.${id}`);
  params.set("limit", "1");

  const response = await restRequest(`/rest/v1/recipes_creator?${params.toString()}`, {
    method: "GET"
  });

  if (!response.ok) {
    const details = await response.text();
    return {
      error: errorResponse(500, "Failed to verify recipe ownership", details)
    };
  }

  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return {
      error: errorResponse(404, "Creator recipe not found", { id })
    };
  }

  if (rows[0].author_id !== userId) {
    return {
      error: errorResponse(403, "You are not allowed to modify this recipe", { id })
    };
  }

  return {};
}

async function ensureProfileExists(userId: string): Promise<{ error?: Response }> {
  const params = new URLSearchParams();
  params.set("select", "id");
  params.set("id", `eq.${userId}`);
  params.set("limit", "1");

  const selectResponse = await restRequest(`/rest/v1/profiles?${params.toString()}`, {
    method: "GET"
  });

  if (!selectResponse.ok) {
    const details = await selectResponse.text();
    return {
      error: errorResponse(500, "Failed to check profile", details)
    };
  }

  const rows = await selectResponse.json();
  if (Array.isArray(rows) && rows.length > 0) {
    return {};
  }

  const insertResponse = await restRequest("/rest/v1/profiles", {
    method: "POST",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify({
      id: userId,
      role: "creator"
    })
  });

  if (!insertResponse.ok) {
    const details = await insertResponse.text();
    return {
      error: errorResponse(500, "Failed to create profile for user", details)
    };
  }

  return {};
}

async function createCreatorRecipe(req: Request, userId: string): Promise<Response> {
  const profile = await ensureProfileExists(userId);
  if (profile.error) {
    return profile.error;
  }

  const parsed = await parseRecipePayload(req);
  if (parsed.error || !parsed.payload) {
    return parsed.error ?? errorResponse(400, "Invalid recipe payload");
  }

  const payload = {
    author_id: userId,
    ...parsed.payload
  };

  const response = await restRequest("/rest/v1/recipes_creator", {
    method: "POST",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to create creator recipe", details);
  }

  const rows = await response.json();
  return okResponse(Array.isArray(rows) ? rows[0] : rows, 201);
}

async function patchCreatorRecipe(req: Request, id: string, userId: string): Promise<Response> {
  const ownership = await ensureCreatorOwner(id, userId);
  if (ownership.error) {
    return ownership.error;
  }

  const parsed = await parseRecipePayload(req);
  if (parsed.error || !parsed.payload) {
    return parsed.error ?? errorResponse(400, "Invalid recipe payload");
  }

  const payload = {
    ...parsed.payload,
    updated_at: new Date().toISOString()
  };

  const params = new URLSearchParams();
  params.set("id", `eq.${id}`);

  const response = await restRequest(`/rest/v1/recipes_creator?${params.toString()}`, {
    method: "PATCH",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to update creator recipe", details);
  }

  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return errorResponse(404, "Creator recipe not found", { id });
  }

  return okResponse(rows[0], 200);
}

async function deleteCreatorRecipe(id: string, userId: string): Promise<Response> {
  const ownership = await ensureCreatorOwner(id, userId);
  if (ownership.error) {
    return ownership.error;
  }

  const params = new URLSearchParams();
  params.set("id", `eq.${id}`);

  const response = await restRequest(`/rest/v1/recipes_creator?${params.toString()}`, {
    method: "DELETE",
    headers: {
      Prefer: "return=representation"
    }
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to delete creator recipe", details);
  }

  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return errorResponse(404, "Creator recipe not found", { id });
  }

  return okResponse({ deleted: rows[0] }, 200);
}

function normalizeIngredientName(value: string): string {
  return value.trim().toLowerCase();
}

async function restCount(path: string): Promise<number> {
  const response = await restRequest(path, {
    method: "GET",
    headers: {
      Prefer: "count=exact"
    }
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Count query failed: ${details}`);
  }

  const range = response.headers.get("content-range") ?? response.headers.get("Content-Range") ?? "";
  const match = range.match(/\/(\d+)$/);
  if (match) {
    return Number(match[1]);
  }

  const rows = await response.json();
  return Array.isArray(rows) ? rows.length : 0;
}

async function buildKitchenSummary(userId: string): Promise<Record<string, number>> {
  const now = new Date();
  const in3Days = new Date(now);
  in3Days.setDate(now.getDate() + 3);

  const today = now.toISOString().slice(0, 10);
  const soon = in3Days.toISOString().slice(0, 10);
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();

  const ingredientCount = await restCount(`/rest/v1/kitchen_ingredients?select=id&owner_id=eq.${userId}`);
  const expiringSoonCount = await restCount(
    `/rest/v1/kitchen_ingredients?select=id&owner_id=eq.${userId}&expires_on=gte.${today}&expires_on=lte.${soon}`
  );
  const activeShoppingListCount = await restCount(
    `/rest/v1/kitchen_shopping_lists?select=id&owner_id=eq.${userId}&status=eq.active`
  );

  let openShoppingItemCount = 0;
  const activeListResponse = await restRequest(
    `/rest/v1/kitchen_shopping_lists?select=id&owner_id=eq.${userId}&status=eq.active&limit=200`,
    { method: "GET" }
  );
  if (!activeListResponse.ok) {
    const details = await activeListResponse.text();
    throw new Error(`Failed to fetch active shopping lists: ${details}`);
  }

  const activeLists = await activeListResponse.json();
  const activeIds = Array.isArray(activeLists)
    ? activeLists
      .map((row: Record<string, unknown>) => String(row.id ?? "").trim())
      .filter((value: string) => value.length > 0)
    : [];

  if (activeIds.length > 0) {
    const listFilter = activeIds.join(",");
    openShoppingItemCount = await restCount(
      `/rest/v1/kitchen_shopping_items?select=id&owner_id=eq.${userId}&is_checked=eq.false&list_id=in.(${listFilter})`
    );
  }

  const recentCookCount7d = await restCount(
    `/rest/v1/kitchen_cook_sessions?select=id&owner_id=eq.${userId}&created_at=gte.${encodeURIComponent(sevenDaysAgo)}`
  );

  return {
    ingredient_count: ingredientCount,
    expiring_soon_count: expiringSoonCount,
    active_shopping_list_count: activeShoppingListCount,
    open_shopping_item_count: openShoppingItemCount,
    recent_cook_count_7d: recentCookCount7d,
  };
}

async function listKitchenIngredients(url: URL, userId: string): Promise<Response> {
  const { limit, offset, error } = parsePagination(url);
  if (error) {
    return error;
  }

  const query = (url.searchParams.get("q") ?? "").trim();
  const params = new URLSearchParams();
  params.set("select", "id,owner_id,name,normalized_name,quantity,unit,storage_location,expires_on,note,created_at,updated_at");
  params.set("owner_id", `eq.${userId}`);
  params.set("order", "expires_on.asc.nullslast,updated_at.desc");
  params.set("limit", String(limit));
  params.set("offset", String(offset));

  if (query.length > 0) {
    params.set("or", `(name.ilike.*${query}*,normalized_name.ilike.*${query.toLowerCase()}*)`);
  }

  const response = await restRequest(`/rest/v1/kitchen_ingredients?${params.toString()}`, {
    method: "GET"
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to fetch kitchen ingredients", details);
  }

  return okResponse(await response.json(), 200);
}

async function listKitchenShoppingLists(url: URL, userId: string): Promise<Response> {
  const { limit, offset, error } = parsePagination(url);
  if (error) {
    return error;
  }

  const status = (url.searchParams.get("status") ?? "active").trim().toLowerCase();
  if (status.length > 0 && status !== "active" && status !== "completed" && status !== "archived" && status !== "all") {
    return errorResponse(400, "Unsupported shopping list status", { status });
  }

  const listParams = new URLSearchParams();
  listParams.set("select", "id,owner_id,status,title,source_recipe_id,created_at,updated_at");
  listParams.set("owner_id", `eq.${userId}`);
  if (status !== "all") {
    listParams.set("status", `eq.${status}`);
  }
  listParams.set("order", "created_at.desc");
  listParams.set("limit", String(limit));
  listParams.set("offset", String(offset));

  const listResponse = await restRequest(`/rest/v1/kitchen_shopping_lists?${listParams.toString()}`, {
    method: "GET"
  });

  if (!listResponse.ok) {
    const details = await listResponse.text();
    return errorResponse(500, "Failed to fetch shopping lists", details);
  }

  const listsRaw = await listResponse.json();
  const lists = Array.isArray(listsRaw) ? listsRaw as Array<Record<string, unknown>> : [];

  if (lists.length === 0) {
    return okResponse([], 200);
  }

  const listIds = lists
    .map((row) => String(row.id ?? "").trim())
    .filter((value) => value.length > 0);

  if (listIds.length === 0) {
    return okResponse([], 200);
  }

  const itemParams = new URLSearchParams();
  itemParams.set("select", "id,list_id,owner_id,name,normalized_name,quantity,unit,is_checked,created_at,updated_at");
  itemParams.set("owner_id", `eq.${userId}`);
  itemParams.set("list_id", `in.(${listIds.join(",")})`);
  itemParams.set("order", "created_at.asc,id.asc");

  const itemResponse = await restRequest(`/rest/v1/kitchen_shopping_items?${itemParams.toString()}`, {
    method: "GET"
  });

  if (!itemResponse.ok) {
    const details = await itemResponse.text();
    return errorResponse(500, "Failed to fetch shopping items", details);
  }

  const itemsRaw = await itemResponse.json();
  const items = Array.isArray(itemsRaw) ? itemsRaw as Array<Record<string, unknown>> : [];
  const itemMap = new Map<string, Array<Record<string, unknown>>>();

  for (const item of items) {
    const listId = String(item.list_id ?? "").trim();
    if (listId.length === 0) {
      continue;
    }

    if (!itemMap.has(listId)) {
      itemMap.set(listId, []);
    }

    itemMap.get(listId)!.push(item);
  }

  const merged = lists.map((list) => {
    const listId = String(list.id ?? "").trim();
    const listItems = itemMap.get(listId) ?? [];
    const openItemCount = listItems.filter((row) => row.is_checked !== true).length;

    return {
      ...list,
      items: listItems,
      open_item_count: openItemCount,
      item_count: listItems.length,
    };
  });

  return okResponse(merged, 200);
}

async function createKitchenIngredient(req: Request, userId: string): Promise<Response> {
  const body = await req.json().catch(() => null);
  const name = typeof body?.name === "string" ? body.name.trim() : "";
  if (name.length === 0) {
    return errorResponse(400, "name is required");
  }

  const payload = {
    owner_id: userId,
    name,
    normalized_name: normalizeIngredientName(name),
    quantity: typeof body?.quantity === "number" ? body.quantity : null,
    unit: typeof body?.unit === "string" ? body.unit.trim() || null : null,
    storage_location: typeof body?.storage_location === "string" ? body.storage_location.trim() || null : null,
    expires_on: typeof body?.expires_on === "string" ? body.expires_on : null,
    note: typeof body?.note === "string" ? body.note.trim() || null : null,
  };

  const response = await restRequest("/rest/v1/kitchen_ingredients", {
    method: "POST",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to create kitchen ingredient", details);
  }

  const rows = await response.json();
  return okResponse(Array.isArray(rows) ? rows[0] : rows, 201);
}

async function patchKitchenIngredient(req: Request, id: string, userId: string): Promise<Response> {
  const body = await req.json().catch(() => null);
  const payload: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };

  if (typeof body?.name === "string" && body.name.trim().length > 0) {
    payload.name = body.name.trim();
    payload.normalized_name = normalizeIngredientName(body.name.trim());
  }
  if (typeof body?.quantity === "number" || body?.quantity === null) {
    payload.quantity = body.quantity;
  }
  if (typeof body?.unit === "string" || body?.unit === null) {
    payload.unit = typeof body.unit === "string" ? body.unit.trim() || null : null;
  }
  if (typeof body?.storage_location === "string" || body?.storage_location === null) {
    payload.storage_location = typeof body.storage_location === "string"
      ? body.storage_location.trim() || null
      : null;
  }
  if (typeof body?.expires_on === "string" || body?.expires_on === null) {
    payload.expires_on = body.expires_on;
  }
  if (typeof body?.note === "string" || body?.note === null) {
    payload.note = typeof body.note === "string" ? body.note.trim() || null : null;
  }

  const params = new URLSearchParams();
  params.set("id", `eq.${id}`);
  params.set("owner_id", `eq.${userId}`);

  const response = await restRequest(`/rest/v1/kitchen_ingredients?${params.toString()}`, {
    method: "PATCH",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to update kitchen ingredient", details);
  }

  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return errorResponse(404, "Kitchen ingredient not found", { id });
  }

  return okResponse(rows[0], 200);
}

async function deleteKitchenIngredient(id: string, userId: string): Promise<Response> {
  const params = new URLSearchParams();
  params.set("id", `eq.${id}`);
  params.set("owner_id", `eq.${userId}`);

  const response = await restRequest(`/rest/v1/kitchen_ingredients?${params.toString()}`, {
    method: "DELETE",
    headers: {
      Prefer: "return=representation"
    }
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to delete kitchen ingredient", details);
  }

  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return errorResponse(404, "Kitchen ingredient not found", { id });
  }

  return okResponse({ deleted: rows[0] }, 200);
}

async function createShoppingFromRecipe(req: Request, userId: string): Promise<Response> {
  const body = await req.json().catch(() => null);
  const recipeType = typeof body?.recipe_type === "string" ? body.recipe_type.trim() : "";
  const recipeId = typeof body?.recipe_id === "string" ? body.recipe_id.trim() : "";
  const recipeTitle = typeof body?.recipe_title === "string" ? body.recipe_title.trim() : "";
  const requiredIngredients = Array.isArray(body?.required_ingredients)
    ? body.required_ingredients.map((value: unknown) => String(value ?? "").trim()).filter((value: string) => value.length > 0)
    : [];

  if (recipeType.length === 0 || recipeId.length === 0 || requiredIngredients.length === 0) {
    return errorResponse(400, "recipe_type, recipe_id, required_ingredients are required");
  }

  const sourceRecipeId = `${recipeType}:${recipeId}`;

  async function loadShoppingItems(listId: string): Promise<Array<Record<string, unknown>>> {
    const params = new URLSearchParams();
    params.set("select", "id,list_id,name,normalized_name,quantity,unit,is_checked");
    params.set("owner_id", `eq.${userId}`);
    params.set("list_id", `eq.${listId}`);
    params.set("order", "created_at.asc");
    params.set("limit", "300");

    const response = await restRequest(`/rest/v1/kitchen_shopping_items?${params.toString()}`, {
      method: "GET"
    });

    if (!response.ok) {
      return [];
    }

    const rows = await response.json();
    return Array.isArray(rows) ? rows as Array<Record<string, unknown>> : [];
  }

  // Reuse existing active list for the same source recipe to avoid duplicate active lists.
  const activeListParams = new URLSearchParams();
  activeListParams.set("select", "id,owner_id,status,title,source_recipe_id,updated_at");
  activeListParams.set("owner_id", `eq.${userId}`);
  activeListParams.set("source_recipe_id", `eq.${sourceRecipeId}`);
  activeListParams.set("status", "eq.active");
  activeListParams.set("order", "updated_at.desc");
  activeListParams.set("limit", "1");

  const activeListResponse = await restRequest(`/rest/v1/kitchen_shopping_lists?${activeListParams.toString()}`, {
    method: "GET"
  });
  let reusableEmptyActiveList: Record<string, unknown> | null = null;

  if (activeListResponse.ok) {
    const activeRows = await activeListResponse.json();
    if (Array.isArray(activeRows) && activeRows.length > 0) {
      const activeList = activeRows[0] as Record<string, unknown>;
      const listId = String(activeList.id ?? "");
      let items = await loadShoppingItems(listId);
      let openCount = items.filter((item) => item.is_checked !== true).length;
      let resetFromFullyChecked = false;

      // If user requests shopping again and the active list is fully checked,
      // reset checks so the same list becomes actionable immediately.
      if (items.length > 0 && openCount === 0) {
        const resetItemParams = new URLSearchParams();
        resetItemParams.set("owner_id", `eq.${userId}`);
        resetItemParams.set("list_id", `eq.${listId}`);
        await restRequest(`/rest/v1/kitchen_shopping_items?${resetItemParams.toString()}`, {
          method: "PATCH",
          body: JSON.stringify({
            is_checked: false,
            updated_at: new Date().toISOString(),
          })
        });

        const listUpdateParams = new URLSearchParams();
        listUpdateParams.set("id", `eq.${listId}`);
        listUpdateParams.set("owner_id", `eq.${userId}`);
        await restRequest(`/rest/v1/kitchen_shopping_lists?${listUpdateParams.toString()}`, {
          method: "PATCH",
          body: JSON.stringify({
            updated_at: new Date().toISOString(),
          })
        });

        items = await loadShoppingItems(listId);
        openCount = items.filter((item) => item.is_checked !== true).length;
        resetFromFullyChecked = true;
      }

      if (items.length === 0) {
        reusableEmptyActiveList = activeList;
      } else {
        return okResponse({
          shopping_list: activeList,
          items,
          missing_count: openCount,
          reused_active_list: true,
          reset_from_fully_checked: resetFromFullyChecked,
          no_missing_items: false,
        }, 200);
      }
    }
  }

  // If a completed list exists for the same source recipe, reopen it and reset all checks.
  const completedListParams = new URLSearchParams();
  completedListParams.set("select", "id,owner_id,status,title,source_recipe_id,updated_at");
  completedListParams.set("owner_id", `eq.${userId}`);
  completedListParams.set("source_recipe_id", `eq.${sourceRecipeId}`);
  completedListParams.set("status", "eq.completed");
  completedListParams.set("order", "updated_at.desc");
  completedListParams.set("limit", "1");

  const completedListResponse = await restRequest(`/rest/v1/kitchen_shopping_lists?${completedListParams.toString()}`, {
    method: "GET"
  });

  if (completedListResponse.ok) {
    const completedRows = await completedListResponse.json();
    if (Array.isArray(completedRows) && completedRows.length > 0) {
      const completedList = completedRows[0] as Record<string, unknown>;
      const listId = String(completedList.id ?? "");

      const reopenParams = new URLSearchParams();
      reopenParams.set("id", `eq.${listId}`);
      reopenParams.set("owner_id", `eq.${userId}`);
      const reopenResponse = await restRequest(`/rest/v1/kitchen_shopping_lists?${reopenParams.toString()}`, {
        method: "PATCH",
        headers: {
          Prefer: "return=representation"
        },
        body: JSON.stringify({
          status: "active",
          updated_at: new Date().toISOString(),
        })
      });

      if (!reopenResponse.ok) {
        const details = await reopenResponse.text();
        return errorResponse(500, "Failed to reopen completed shopping list", details);
      }

      const resetItemParams = new URLSearchParams();
      resetItemParams.set("owner_id", `eq.${userId}`);
      resetItemParams.set("list_id", `eq.${listId}`);
      await restRequest(`/rest/v1/kitchen_shopping_items?${resetItemParams.toString()}`, {
        method: "PATCH",
        body: JSON.stringify({
          is_checked: false,
          updated_at: new Date().toISOString(),
        })
      });

      const reopenedRows = await reopenResponse.json();
      const reopenedList = Array.isArray(reopenedRows) && reopenedRows.length > 0
        ? reopenedRows[0] as Record<string, unknown>
        : completedList;
      const reopenedItems = await loadShoppingItems(listId);

      return okResponse({
        shopping_list: reopenedList,
        items: reopenedItems,
        missing_count: reopenedItems.length,
        reopened_from_completed: true,
        no_missing_items: reopenedItems.length === 0,
      }, 200);
    }
  }

  const ingredientParams = new URLSearchParams();
  ingredientParams.set("select", "normalized_name");
  ingredientParams.set("owner_id", `eq.${userId}`);
  const ingredientResponse = await restRequest(`/rest/v1/kitchen_ingredients?${ingredientParams.toString()}`, {
    method: "GET"
  });

  if (!ingredientResponse.ok) {
    const details = await ingredientResponse.text();
    return errorResponse(500, "Failed to load kitchen ingredients", details);
  }

  const ownedRows = await ingredientResponse.json();
  const ownedSet = new Set(
    (Array.isArray(ownedRows) ? ownedRows : [])
      .map((row: Record<string, unknown>) => String(row.normalized_name ?? "").trim())
      .filter((value: string) => value.length > 0)
  );

  const deduped = new Map<string, string>();
  for (const ingredient of requiredIngredients) {
    const normalized = normalizeIngredientName(ingredient);
    if (normalized.length > 0 && !deduped.has(normalized)) {
      deduped.set(normalized, ingredient);
    }
  }

  const missing = [...deduped.entries()]
    .filter(([normalized]) => !ownedSet.has(normalized))
    .map(([normalized, original]) => ({ normalized, original }));

  if (missing.length === 0) {
    return okResponse({
      shopping_list: null,
      items: [],
      missing_count: 0,
      no_missing_items: true,
    }, 200);
  }

  if (reusableEmptyActiveList != null) {
    const listId = String(reusableEmptyActiveList.id ?? "");
    if (listId.length > 0) {
      const itemPayload = missing.map((item) => ({
        list_id: listId,
        owner_id: userId,
        name: item.original,
        normalized_name: item.normalized,
        quantity: null,
        unit: null,
        is_checked: false,
      }));

      const itemResponse = await restRequest("/rest/v1/kitchen_shopping_items", {
        method: "POST",
        headers: {
          Prefer: "return=representation"
        },
        body: JSON.stringify(itemPayload)
      });

      if (!itemResponse.ok) {
        const details = await itemResponse.text();
        return errorResponse(500, "Failed to create shopping items", details);
      }

      const listUpdateParams = new URLSearchParams();
      listUpdateParams.set("id", `eq.${listId}`);
      listUpdateParams.set("owner_id", `eq.${userId}`);
      await restRequest(`/rest/v1/kitchen_shopping_lists?${listUpdateParams.toString()}`, {
        method: "PATCH",
        body: JSON.stringify({
          updated_at: new Date().toISOString(),
        })
      });

      const itemRows = await itemResponse.json();
      const createdItems = Array.isArray(itemRows) ? itemRows : [];
      return okResponse({
        shopping_list: reusableEmptyActiveList,
        items: createdItems,
        missing_count: missing.length,
        reused_active_list: true,
        no_missing_items: false,
      }, 200);
    }
  }

  const listResponse = await restRequest("/rest/v1/kitchen_shopping_lists", {
    method: "POST",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify({
      owner_id: userId,
      status: "active",
      title: recipeTitle.length > 0 ? `${recipeTitle} 장보기` : "AI generated shopping list",
      source_recipe_id: sourceRecipeId,
    })
  });

  if (!listResponse.ok) {
    const details = await listResponse.text();
    return errorResponse(500, "Failed to create shopping list", details);
  }

  const listRows = await listResponse.json();
  if (!Array.isArray(listRows) || listRows.length === 0) {
    return errorResponse(500, "Shopping list creation returned empty response");
  }

  const createdList = listRows[0] as Record<string, unknown>;
  let createdItems: unknown[] = [];

  if (missing.length > 0) {
    const itemPayload = missing.map((item) => ({
      list_id: createdList.id,
      owner_id: userId,
      name: item.original,
      normalized_name: item.normalized,
      quantity: null,
      unit: null,
      is_checked: false,
    }));

    const itemResponse = await restRequest("/rest/v1/kitchen_shopping_items", {
      method: "POST",
      headers: {
        Prefer: "return=representation"
      },
      body: JSON.stringify(itemPayload)
    });

    if (!itemResponse.ok) {
      const details = await itemResponse.text();
      return errorResponse(500, "Failed to create shopping items", details);
    }

    const itemRows = await itemResponse.json();
    createdItems = Array.isArray(itemRows) ? itemRows : [];
  }

  return okResponse({
    shopping_list: createdList,
    items: createdItems,
    missing_count: missing.length,
    no_missing_items: false,
  }, 201);
}

async function patchShoppingItem(req: Request, id: string, userId: string): Promise<Response> {
  const body = await req.json().catch(() => null);
  if (typeof body?.is_checked !== "boolean") {
    return errorResponse(400, "is_checked(boolean) is required");
  }

  const params = new URLSearchParams();
  params.set("id", `eq.${id}`);
  params.set("owner_id", `eq.${userId}`);

  const response = await restRequest(`/rest/v1/kitchen_shopping_items?${params.toString()}`, {
    method: "PATCH",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify({
      is_checked: body.is_checked,
      updated_at: new Date().toISOString(),
    })
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to update shopping item", details);
  }

  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return errorResponse(404, "Shopping item not found", { id });
  }

  return okResponse(rows[0], 200);
}

async function completeShoppingList(id: string, userId: string): Promise<Response> {
  const listParams = new URLSearchParams();
  listParams.set("select", "id,status");
  listParams.set("id", `eq.${id}`);
  listParams.set("owner_id", `eq.${userId}`);
  listParams.set("limit", "1");

  const listResponse = await restRequest(`/rest/v1/kitchen_shopping_lists?${listParams.toString()}`, {
    method: "GET"
  });

  if (!listResponse.ok) {
    const details = await listResponse.text();
    return errorResponse(500, "Failed to load shopping list", details);
  }

  const listRows = await listResponse.json();
  if (!Array.isArray(listRows) || listRows.length === 0) {
    return errorResponse(404, "Shopping list not found", { id });
  }

  const itemParams = new URLSearchParams();
  itemParams.set("select", "id,name,normalized_name,quantity,unit");
  itemParams.set("owner_id", `eq.${userId}`);
  itemParams.set("list_id", `eq.${id}`);
  itemParams.set("is_checked", "eq.true");

  const checkedResponse = await restRequest(`/rest/v1/kitchen_shopping_items?${itemParams.toString()}`, {
    method: "GET"
  });

  if (!checkedResponse.ok) {
    const details = await checkedResponse.text();
    return errorResponse(500, "Failed to load shopping items", details);
  }

  const checkedItems = await checkedResponse.json();
  const checkedRows = Array.isArray(checkedItems) ? checkedItems as Array<Record<string, unknown>> : [];

  for (const item of checkedRows) {
    const normalizedName = String(item.normalized_name ?? "").trim();
    const name = String(item.name ?? "").trim();
    if (normalizedName.length === 0 || name.length === 0) {
      continue;
    }

    const ingredientParams = new URLSearchParams();
    ingredientParams.set("select", "id,quantity");
    ingredientParams.set("owner_id", `eq.${userId}`);
    ingredientParams.set("normalized_name", `eq.${normalizedName}`);
    ingredientParams.set("limit", "1");

    const existingResponse = await restRequest(`/rest/v1/kitchen_ingredients?${ingredientParams.toString()}`, {
      method: "GET"
    });

    if (!existingResponse.ok) {
      continue;
    }

    const existingRows = await existingResponse.json();
    const itemQuantity = typeof item.quantity === "number" ? item.quantity : null;

    if (Array.isArray(existingRows) && existingRows.length > 0) {
      const existing = existingRows[0] as Record<string, unknown>;
      const existingQuantity = typeof existing.quantity === "number" ? existing.quantity : null;
      const mergedQuantity = itemQuantity !== null && existingQuantity !== null
        ? existingQuantity + itemQuantity
        : existingQuantity ?? itemQuantity;

      const updateParams = new URLSearchParams();
      updateParams.set("id", `eq.${String(existing.id)}`);
      updateParams.set("owner_id", `eq.${userId}`);

      await restRequest(`/rest/v1/kitchen_ingredients?${updateParams.toString()}`, {
        method: "PATCH",
        body: JSON.stringify({
          quantity: mergedQuantity,
          unit: typeof item.unit === "string" ? item.unit : null,
          updated_at: new Date().toISOString(),
        })
      });
    } else {
      await restRequest("/rest/v1/kitchen_ingredients", {
        method: "POST",
        body: JSON.stringify({
          owner_id: userId,
          name,
          normalized_name: normalizedName,
          quantity: itemQuantity,
          unit: typeof item.unit === "string" ? item.unit : null,
        })
      });
    }
  }

  const completeParams = new URLSearchParams();
  completeParams.set("id", `eq.${id}`);
  completeParams.set("owner_id", `eq.${userId}`);
  const completeResponse = await restRequest(`/rest/v1/kitchen_shopping_lists?${completeParams.toString()}`, {
    method: "PATCH",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify({
      status: "completed",
      updated_at: new Date().toISOString(),
    })
  });

  if (!completeResponse.ok) {
    const details = await completeResponse.text();
    return errorResponse(500, "Failed to complete shopping list", details);
  }

  const summary = await buildKitchenSummary(userId);
  return okResponse({ completed_list_id: id, summary }, 200);
}

async function resetShoppingList(id: string, userId: string): Promise<Response> {
  const listParams = new URLSearchParams();
  listParams.set("select", "id,status");
  listParams.set("id", `eq.${id}`);
  listParams.set("owner_id", `eq.${userId}`);
  listParams.set("limit", "1");

  const listResponse = await restRequest(`/rest/v1/kitchen_shopping_lists?${listParams.toString()}`, {
    method: "GET"
  });

  if (!listResponse.ok) {
    const details = await listResponse.text();
    return errorResponse(500, "Failed to load shopping list", details);
  }

  const listRows = await listResponse.json();
  if (!Array.isArray(listRows) || listRows.length === 0) {
    return errorResponse(404, "Shopping list not found", { id });
  }

  const itemParams = new URLSearchParams();
  itemParams.set("owner_id", `eq.${userId}`);
  itemParams.set("list_id", `eq.${id}`);
  const resetItemsResponse = await restRequest(`/rest/v1/kitchen_shopping_items?${itemParams.toString()}`, {
    method: "PATCH",
    body: JSON.stringify({
      is_checked: false,
      updated_at: new Date().toISOString(),
    })
  });

  if (!resetItemsResponse.ok) {
    const details = await resetItemsResponse.text();
    return errorResponse(500, "Failed to reset shopping items", details);
  }

  const listUpdateParams = new URLSearchParams();
  listUpdateParams.set("id", `eq.${id}`);
  listUpdateParams.set("owner_id", `eq.${userId}`);
  const listUpdateResponse = await restRequest(`/rest/v1/kitchen_shopping_lists?${listUpdateParams.toString()}`, {
    method: "PATCH",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify({
      status: "active",
      updated_at: new Date().toISOString(),
    })
  });

  if (!listUpdateResponse.ok) {
    const details = await listUpdateResponse.text();
    return errorResponse(500, "Failed to update shopping list status", details);
  }

  const summary = await buildKitchenSummary(userId);
  return okResponse({ reset_list_id: id, summary }, 200);
}

async function archiveOldCompletedShoppingLists(
  userId: string,
  retentionDays: number,
): Promise<Response> {
  if (!Number.isFinite(retentionDays) || retentionDays < 1 || retentionDays > 365) {
    return errorResponse(400, "days must be between 1 and 365", { days: retentionDays });
  }

  const cutoff = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000).toISOString();
  const params = new URLSearchParams();
  params.set("owner_id", `eq.${userId}`);
  params.set("status", "eq.completed");
  params.set("updated_at", `lt.${cutoff}`);

  const response = await restRequest(`/rest/v1/kitchen_shopping_lists?${params.toString()}`, {
    method: "PATCH",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify({
      status: "archived",
      updated_at: new Date().toISOString(),
    })
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to archive old completed shopping lists", details);
  }

  const rows = await response.json();
  const archived = Array.isArray(rows) ? rows.length : 0;
  return okResponse({
    archived_count: archived,
    retention_days: retentionDays,
  }, 200);
}

async function listKitchenCookSessions(url: URL, userId: string): Promise<Response> {
  const { limit, offset, error } = parsePagination(url);
  if (error) {
    return error;
  }

  const params = new URLSearchParams();
  params.set("select", "id,owner_id,recipe_type,recipe_ref_id,recipe_title,consumed_ingredients,missing_ingredients,rating,liked,note,created_at");
  params.set("owner_id", `eq.${userId}`);
  params.set("order", "created_at.desc");
  params.set("limit", String(limit));
  params.set("offset", String(offset));

  const response = await restRequest(`/rest/v1/kitchen_cook_sessions?${params.toString()}`, {
    method: "GET"
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to fetch kitchen cook sessions", details);
  }

  return okResponse(await response.json(), 200);
}

async function completeCook(req: Request, userId: string): Promise<Response> {
  const body = await req.json().catch(() => null);
  const recipeType = typeof body?.recipe_type === "string" ? body.recipe_type.trim() : "";
  const recipeRefId = typeof body?.recipe_id === "string" ? body.recipe_id.trim() : "";
  const recipeTitle = typeof body?.recipe_title === "string" ? body.recipe_title.trim() : "";

  if (recipeType.length === 0 || recipeRefId.length === 0 || recipeTitle.length === 0) {
    return errorResponse(400, "recipe_type, recipe_id, recipe_title are required");
  }

  const payload = {
    owner_id: userId,
    recipe_type: recipeType,
    recipe_ref_id: recipeRefId,
    recipe_title: recipeTitle,
    consumed_ingredients: Array.isArray(body?.consumed_ingredients) ? body.consumed_ingredients : [],
    missing_ingredients: Array.isArray(body?.missing_ingredients) ? body.missing_ingredients : [],
    rating: typeof body?.rating === "number" ? body.rating : null,
    liked: typeof body?.liked === "boolean" ? body.liked : null,
    note: typeof body?.note === "string" ? body.note.trim() || null : null,
  };

  const response = await restRequest("/rest/v1/kitchen_cook_sessions", {
    method: "POST",
    headers: {
      Prefer: "return=representation"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const details = await response.text();
    return errorResponse(500, "Failed to complete cook session", details);
  }

  const rows = await response.json();
  const summary = await buildKitchenSummary(userId);
  return okResponse({
    session: Array.isArray(rows) ? rows[0] : rows,
    summary,
  }, 201);
}

async function handleKitchenRequest(req: Request, url: URL, userId: string): Promise<Response> {
  const view = (url.searchParams.get("view") ?? "").trim().toLowerCase();
  const action = (url.searchParams.get("action") ?? "").trim().toLowerCase();
  const id = (url.searchParams.get("id") ?? "").trim();

  if (req.method === "GET") {
    if (view === "" || view === "summary") {
      return okResponse(await buildKitchenSummary(userId), 200);
    }
    if (view === "ingredients") {
      return await listKitchenIngredients(url, userId);
    }
    if (view === "shopping-lists") {
      return await listKitchenShoppingLists(url, userId);
    }
    if (view === "cook-sessions") {
      return await listKitchenCookSessions(url, userId);
    }
    return errorResponse(400, "Unsupported kitchen GET view", { view });
  }

  if (req.method === "POST") {
    if (view === "ingredients") {
      return await createKitchenIngredient(req, userId);
    }
    if (action === "create-shopping-from-recipe") {
      return await createShoppingFromRecipe(req, userId);
    }
    if (action === "complete-shopping-list") {
      if (id.length === 0) {
        return errorResponse(400, "id query parameter is required for complete-shopping-list");
      }
      return await completeShoppingList(id, userId);
    }
    if (action === "reset-shopping-list") {
      if (id.length === 0) {
        return errorResponse(400, "id query parameter is required for reset-shopping-list");
      }
      return await resetShoppingList(id, userId);
    }
    if (action === "archive-old-completed-shopping-lists") {
      const daysRaw = Number(url.searchParams.get("days") ?? "30");
      const retentionDays = Number.isInteger(daysRaw) ? daysRaw : 30;
      return await archiveOldCompletedShoppingLists(userId, retentionDays);
    }
    if (action === "complete-cook") {
      return await completeCook(req, userId);
    }
    return errorResponse(400, "Unsupported kitchen POST action/view", { action, view });
  }

  if (req.method === "PATCH") {
    if (id.length === 0) {
      return errorResponse(400, "id query parameter is required for kitchen PATCH");
    }
    if (view === "ingredients") {
      return await patchKitchenIngredient(req, id, userId);
    }
    if (view === "shopping-item") {
      return await patchShoppingItem(req, id, userId);
    }
    return errorResponse(400, "Unsupported kitchen PATCH view", { view });
  }

  if (req.method === "DELETE") {
    if (view === "ingredients") {
      if (id.length === 0) {
        return errorResponse(400, "id query parameter is required for ingredient delete");
      }
      return await deleteKitchenIngredient(id, userId);
    }
    return errorResponse(400, "Unsupported kitchen DELETE view", { view });
  }

  return errorResponse(405, "Method not allowed", { method: req.method });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const allowedMethods = new Set(["GET", "POST", "PATCH", "DELETE"]);
    if (!allowedMethods.has(req.method)) {
      return errorResponse(405, "Method not allowed", { method: req.method });
    }

    const url = new URL(req.url);
    const id = getRouteId(url.pathname);
    if (id === "__INVALID_PATH__") {
      return errorResponse(404, "Not found");
    }

    const typeResult = parseType(req.method, url);
    if (typeResult.error || !typeResult.type) {
      return typeResult.error ?? errorResponse(400, "Invalid type");
    }

    const type = typeResult.type;

    if (req.method === "GET") {
      if (type === "kitchen") {
        const auth = await getAuthenticatedUserId(req);
        if (auth.error || !auth.userId) {
          return auth.error ?? errorResponse(401, "Unauthorized");
        }
        return await handleKitchenRequest(req, url, auth.userId);
      }

      if (type === "public") {
        return id ? await getPublicRecipeDetail(id) : await listPublicRecipes(url);
      }

      if (type === "creator" && !hasBearerToken(req)) {
        return creatorAuthRequiredResponse();
      }

      const auth = await getAuthenticatedUserId(req);
      if (auth.error || !auth.userId) {
        return auth.error ?? errorResponse(401, "Unauthorized");
      }

      return id
          ? await getCreatorRecipeDetail(id, auth.userId)
          : await listCreatorRecipes(url, auth.userId);
    }

    if (type === "kitchen") {
      const auth = await getAuthenticatedUserId(req);
      if (auth.error || !auth.userId) {
        return auth.error ?? errorResponse(401, "Unauthorized");
      }
      return await handleKitchenRequest(req, url, auth.userId);
    }

    if (type !== "creator") {
      return errorResponse(400, `${req.method} endpoints require type=creator or type=kitchen`);
    }

    if (!hasBearerToken(req)) {
      return creatorAuthRequiredResponse();
    }

    const auth = await getAuthenticatedUserId(req);
    if (auth.error || !auth.userId) {
      return auth.error ?? errorResponse(401, "Unauthorized");
    }

    if (req.method === "POST") {
      if (id !== null) {
        return errorResponse(400, "POST creator endpoint does not accept /:id");
      }
      return await createCreatorRecipe(req, auth.userId);
    }

    if (req.method === "PATCH") {
      if (!id) {
        return errorResponse(400, "PATCH requires recipe id in path");
      }
      return await patchCreatorRecipe(req, id, auth.userId);
    }

    if (req.method === "DELETE") {
      if (!id) {
        return errorResponse(400, "DELETE requires recipe id in path");
      }
      return await deleteCreatorRecipe(id, auth.userId);
    }

    return errorResponse(405, "Method not allowed", { method: req.method });
  } catch (error) {
    return errorResponse(
      500,
      "Unexpected server error",
      error instanceof Error ? error.message : String(error)
    );
  }
});
