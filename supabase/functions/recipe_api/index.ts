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

function buildCookRcpApiUrl(start: number, end: number): string {
  const apiBaseUrl = getEnv("FOOD_API_BASE_URL").trim();
  const apiKey = getEnv("FOOD_API_KEY").trim();
  const apiUrlTemplate = getEnv("FOOD_API_URL_TEMPLATE").trim();

  if (apiBaseUrl.length === 0 || apiKey.length === 0) {
    throw new Error("FOOD_API_BASE_URL or FOOD_API_KEY is missing");
  }

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
    .split(/[\n,]/g)
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

function mapPublicApiRecord(record: Record<string, unknown>): PublicRecipeRow | null {
  const sourceId = String(record.RCP_SEQ ?? record.id ?? "").trim();
  const title = String(record.RCP_NM ?? record.RCP_NM_KO ?? record.title ?? "").trim();
  if (sourceId.length === 0 || title.length === 0) {
    return null;
  }

  const summary = String(record.HASH_TAG ?? record.RCP_PAT2 ?? record.summary ?? "").trim();
  const ingredients = splitIngredients(String(record.RCP_PARTS_DTLS ?? record.ingredients ?? ""));
  const steps = pickSteps(record);
  const caloriesRaw = String(record.INFO_ENG ?? record.calories ?? "").trim();
  const calories = caloriesRaw.length > 0 ? Number(caloriesRaw) : null;
  const imageUrl = String(record.ATT_FILE_NO_MAIN ?? record.image_url ?? "").trim();
  const now = new Date().toISOString();

  return {
    id: sourceId,
    source_id: sourceId,
    title,
    summary: summary.length > 0 ? summary : null,
    ingredients,
    steps,
    calories: Number.isFinite(calories) ? calories : null,
    image_url: imageUrl.length > 0 ? imageUrl : null,
    created_at: now,
    updated_at: now,
  };
}

async function fetchCookRcpRows(start: number, end: number): Promise<PublicRecipeRow[]> {
  const timeoutMsRaw = Number(getEnv("FOOD_API_TIMEOUT_MS") || "12000");
  const timeoutMs = Number.isFinite(timeoutMsRaw)
    ? Math.max(3000, Math.min(timeoutMsRaw, 30000))
    : 12000;

  const response = await fetch(buildCookRcpApiUrl(start, end), {
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) {
    throw new Error(`COOKRCP01 request failed: ${response.status}`);
  }

  const payload = await response.json();
  const rows = Array.isArray(payload?.COOKRCP01?.row)
    ? payload.COOKRCP01.row
    : (Array.isArray(payload?.row) ? payload.row : []);

  if (!Array.isArray(rows)) {
    return [];
  }

  return rows
    .map((item: Record<string, unknown>) => mapPublicApiRecord(item))
    .filter((item: PublicRecipeRow | null): item is PublicRecipeRow => item !== null);
}

async function fetchPublicRecipeBySourceId(sourceId: string): Promise<PublicRecipeRow | null> {
  const pageSize = 300;
  const maxPages = 40;

  for (let page = 0; page < maxPages; page += 1) {
    const start = page * pageSize + 1;
    const end = start + pageSize - 1;
    const rows = await fetchCookRcpRows(start, end);

    if (rows.length === 0) {
      break;
    }

    const match = rows.find((row) => row.source_id === sourceId);
    if (match) {
      return match;
    }

    if (rows.length < pageSize) {
      break;
    }
  }

  return null;
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
    .trim()
    .toLowerCase()
    .split(/[\s,]+/)
    .map((token) => token.trim())
    .filter((token) => token.length > 0)
    .slice(0, 8);
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
  };
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
  return [token, ...extras.map((item) => item.toLowerCase())];
}

function matchesKeywordSearch(row: PublicRecipeRow, tokens: string[]): boolean {
  if (tokens.length === 0) {
    return true;
  }

  const text = buildSearchText(row);
  return tokens.every((token) => text.all.includes(token));
}

function scoreAiSearch(row: PublicRecipeRow, tokens: string[]): number {
  if (tokens.length === 0) {
    return 0;
  }

  const text = buildSearchText(row);
  let score = 0;
  let matchedGroups = 0;

  for (const token of tokens) {
    const candidates = expandAiToken(token);
    let matched = false;

    for (const word of candidates) {
      if (text.title.includes(word)) {
        score += 4;
        matched = true;
      }
      if (text.summary.includes(word)) {
        score += 3;
        matched = true;
      }
      if (text.ingredients.includes(word)) {
        score += 3;
        matched = true;
      }
      if (text.steps.includes(word)) {
        score += 2;
        matched = true;
      }
    }

    if (matched) {
      matchedGroups += 1;
    }
  }

  if (matchedGroups == 0) {
    return 0;
  }

  return score + matchedGroups;
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
  const searchMode = parseSearchMode(url);
  const tokens = tokenizeSearch(search);
  const effectiveLimit = tokens.length === 0 ? limit : Math.min(limit, 5);

  if (tokens.length === 0) {
    const params = new URLSearchParams();
    params.set("select", "id,source_id,title,summary,ingredients,steps,calories,image_url,created_at,updated_at");
    params.set("order", "created_at.desc");
    params.set("limit", String(effectiveLimit));
    params.set("offset", String(offset));

    const response = await restRequest(`/rest/v1/recipes_public?${params.toString()}`, {
      method: "GET"
    });

    if (!response.ok) {
      const details = await response.text();
      return errorResponse(500, "Failed to fetch public recipes", details);
    }

    const data = await response.json();
    return okResponse(data, 200);
  }

  const externalRows: PublicRecipeRow[] = [];
  const pageSize = 300;
  const maxPages = 40;

  try {
    for (let page = 0; page < maxPages; page += 1) {
      const start = page * pageSize + 1;
      const end = start + pageSize - 1;
      const rows = await fetchCookRcpRows(start, end);

      if (rows.length === 0) {
        break;
      }

      externalRows.push(...rows);

      if (rows.length < pageSize) {
        break;
      }
    }
  } catch (error) {
    return errorResponse(502, "Failed to fetch COOKRCP01 recipes", String(error));
  }

  if (searchMode === "keyword") {
    const matched = externalRows.filter((row) => matchesKeywordSearch(row, tokens));
    return okResponse(matched.slice(offset, offset + effectiveLimit), 200);
  }

  const ranked = externalRows
    .map((row) => ({
      row,
      score: scoreAiSearch(row, tokens),
    }))
    .filter((item) => item.score > 0)
    .sort((a, b) => {
      if (a.score == b.score) {
        return String(b.row.created_at).localeCompare(String(a.row.created_at));
      }
      return b.score - a.score;
    })
    .map((item) => item.row);

  return okResponse(ranked.slice(offset, offset + effectiveLimit), 200);
}

async function getPublicRecipeDetail(id: string): Promise<Response> {
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
    return okResponse(rows[0], 200);
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
    return okResponse(sourceRows[0], 200);
  }

  try {
    const external = await fetchPublicRecipeBySourceId(id);
    if (external) {
      return okResponse(external, 200);
    }
  } catch (error) {
    return errorResponse(502, "Failed to fetch COOKRCP01 recipe detail", String(error));
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
  itemParams.set("order", "created_at.asc");

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

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const managedShoppingItemFields = new Set(["id", "list_id", "owner_id", "normalized_name", "status", "is_checked", "completed_at", "inventory_change_count"]);

function idempotencyKey(req: Request): string | null {
  const key = (req.headers.get("Idempotency-Key") ?? "").trim();
  return uuidPattern.test(key) ? key : null;
}

async function userRpc(req: Request, rpcName: string, body: Record<string, unknown>): Promise<Response> {
  const token = getBearerToken(req);
  if (!token) return errorResponse(401, "Authorization Bearer token is required");
  const { supabaseUrl, anonKey } = getSupabaseConfig();
  return fetch(`${supabaseUrl}/rest/v1/rpc/${rpcName}`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function shoppingRpcError(response: Response): Response {
  if (response.status === 401 || response.status === 403) return errorResponse(401, "Unauthorized");
  if (response.status === 404) return errorResponse(404, "Shopping list not found");
  return errorResponse(422, "Shopping request was rejected", { code: "shopping_request_rejected" });
}

async function createShoppingFromRecipe(req: Request, _userId: string): Promise<Response> {
  const body = await req.json().catch(() => null) as Record<string, unknown> | null;
  const key = idempotencyKey(req);
  if (!key) return errorResponse(400, "A valid Idempotency-Key header is required", { code: "invalid_idempotency_key" });
  const sourceRecipeId = typeof body?.source_recipe_id === "string" ? body.source_recipe_id.trim() : "";
  if (!Array.isArray(body?.items)) {
    return errorResponse(422, "Structured ingredient review is required", { code: "ingredient_review_required" });
  }
  if (sourceRecipeId.length === 0 || !/^(public|creator|user):.+/.test(sourceRecipeId)) {
    return errorResponse(400, "source_recipe_id is required");
  }
  const items = body.items;
  const names = new Set<string>();
  for (const item of items) {
    if (!item || typeof item !== "object" || Array.isArray(item)) return errorResponse(422, "Structured ingredient review is required", { code: "ingredient_review_required" });
    const value = item as Record<string, unknown>;
    if (Object.keys(value).some((field) => managedShoppingItemFields.has(field))) return errorResponse(400, "Server-managed shopping fields are not accepted");
    const name = typeof value.name === "string" ? value.name.trim() : "";
    const text = typeof value.ingredient_text === "string" ? value.ingredient_text : "";
    if (!name || !text.trim() || name.length > 200 || text.length > 500 || (value.quantity !== null && value.quantity !== undefined && (typeof value.quantity !== "number" || !Number.isFinite(value.quantity) || value.quantity <= 0)) || (value.unit !== null && value.unit !== undefined && (typeof value.unit !== "string" || !value.unit.trim() || value.unit.trim().length > 32))) return errorResponse(422, "Structured ingredient review is required", { code: "ingredient_review_required" });
    const canonical = name.toLowerCase();
    if (names.has(canonical)) return errorResponse(422, "Duplicate canonical ingredient names require review", { code: "ingredient_review_required" });
    names.add(canonical);
  }
  const rpc = await userRpc(req, "create_kitchen_shopping_list", { p_source_recipe_id: sourceRecipeId, p_items: items, p_idempotency_key: key });
  if (!rpc.ok) return shoppingRpcError(rpc);
  const rows: unknown = await rpc.json().catch(() => null);
  if (!Array.isArray(rows) || rows.length !== 1 || !rows[0] || typeof rows[0] !== "object" || Array.isArray(rows[0])) {
    return errorResponse(500, "Shopping create response shape was invalid");
  }
  const result = rows[0] as Record<string, unknown>;
  const listId = typeof result.list_id === "string" ? result.list_id.trim() : "";
  const status = typeof result.status === "string" ? result.status : "";
  const created = result.created;
  const replayed = result.replayed;
  const responseIdempotencyKey = typeof result.idempotency_key === "string" ? result.idempotency_key.trim() : "";
  if (!listId || status !== "active" || typeof created !== "boolean" || typeof replayed !== "boolean" || !responseIdempotencyKey || responseIdempotencyKey !== key) {
    return errorResponse(500, "Shopping create result was invalid");
  }
  return okResponse({ list_id: listId, status, created, replayed, idempotency_key: responseIdempotencyKey }, created ? 201 : 200);
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

async function completeShoppingList(req: Request, id: string, _userId: string): Promise<Response> {
  const key = idempotencyKey(req);
  if (!key) return errorResponse(400, "A valid Idempotency-Key header is required", { code: "invalid_idempotency_key" });
  if (!uuidPattern.test(id)) return errorResponse(400, "Shopping list id must be a UUID");
  const rpc = await userRpc(req, "complete_kitchen_shopping_list", { p_list_id: id, p_idempotency_key: key });
  if (!rpc.ok) return shoppingRpcError(rpc);
  const rows = await rpc.json();
  const result = Array.isArray(rows) ? rows[0] : rows;
  return okResponse({ shopping_list: result }, 200);
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
      return await completeShoppingList(req, id, userId);
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

      const auth = await getAuthenticatedUserId(req);
      if (auth.error || !auth.userId) {
        return auth.error ?? errorResponse(401, "Unauthorized");
      }

      return id
          ? await getCreatorRecipeDetail(id, auth.userId)
          : await listCreatorRecipes(url, auth.userId);
    }

    const auth = await getAuthenticatedUserId(req);
    if (auth.error || !auth.userId) {
      return auth.error ?? errorResponse(401, "Unauthorized");
    }

    if (type === "kitchen") {
      return await handleKitchenRequest(req, url, auth.userId);
    }

    if (type !== "creator") {
      return errorResponse(400, `${req.method} endpoints require type=creator or type=kitchen`);
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
