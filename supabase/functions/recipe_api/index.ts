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

  if (type !== "public" && type !== "creator") {
    return {
      error: errorResponse(400, "type must be one of: public, creator")
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
  const params = new URLSearchParams();
  params.set("select", "id,source_id,title,summary,ingredients,steps,calories,image_url,created_at,updated_at");
  params.set("order", "created_at.desc");
  params.set("limit", String(limit));
  params.set("offset", String(offset));

  if (search.length > 0) {
    params.set("title", `ilike.*${search}*`);
  }

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
  if (!Array.isArray(rows) || rows.length === 0) {
    return errorResponse(404, "Public recipe not found", { id });
  }

  return okResponse(rows[0], 200);
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

    if (type !== "creator") {
      return errorResponse(400, `${req.method} endpoints require type=creator`);
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
