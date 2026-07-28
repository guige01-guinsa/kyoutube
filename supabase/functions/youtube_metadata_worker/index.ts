import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-worker-secret",
  "Access-Control-Allow-Methods": "POST,OPTIONS"
};

const JSON_HEADERS = {
  "Content-Type": "application/json",
  ...CORS_HEADERS
};

function okResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify({ status: "ok", data }), {
    status,
    headers: JSON_HEADERS
  });
}

function errorResponse(status: number, message: string, details: unknown = null): Response {
  return new Response(JSON.stringify({ status: "error", message, details }), {
    status,
    headers: JSON_HEADERS
  });
}

function getEnv(name: string): string {
  return Deno.env.get(name) ?? "";
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
      Authorization: `Bearer ${token}`,
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

function extractVideoId(url: string): string | null {
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.toLowerCase();

    if (host.includes("youtu.be")) {
      const id = parsed.pathname.replaceAll("/", "").trim();
      return id.length > 0 ? id : null;
    }

    if (host.includes("youtube.com")) {
      const byQuery = parsed.searchParams.get("v")?.trim() ?? "";
      if (byQuery.length > 0) {
        return byQuery;
      }

      const parts = parsed.pathname.split("/").filter((value) => value.length > 0);
      const shortsIndex = parts.findIndex((value) => value === "shorts");
      if (shortsIndex >= 0 && parts.length > shortsIndex + 1) {
        return parts[shortsIndex + 1];
      }
    }
  } catch (_) {
    return null;
  }

  return null;
}

async function fetchYoutubeMetadata(youtubeUrl: string): Promise<Record<string, unknown>> {
  const oembedUrl = `https://www.youtube.com/oembed?url=${encodeURIComponent(youtubeUrl)}&format=json`;
  const response = await fetch(oembedUrl, {
    signal: AbortSignal.timeout(12000)
  });

  if (!response.ok) {
    throw new Error(`oEmbed request failed: ${response.status}`);
  }

  const payload = await response.json();
  return typeof payload === "object" && payload ? payload as Record<string, unknown> : {};
}

async function upsertYoutubeMetadata(params: {
  recipeCreatorId: string;
  youtubeUrl: string;
  status: "ok" | "error";
  payload: Record<string, unknown>;
  errorMessage?: string;
}): Promise<void> {
  const videoId = extractVideoId(params.youtubeUrl);

  const body = {
    recipe_creator_id: params.recipeCreatorId,
    youtube_url: params.youtubeUrl,
    youtube_video_id: videoId,
    title: typeof params.payload.title === "string" ? params.payload.title : null,
    channel_name: typeof params.payload.author_name === "string" ? params.payload.author_name : null,
    author_url: typeof params.payload.author_url === "string" ? params.payload.author_url : null,
    thumbnail_url: typeof params.payload.thumbnail_url === "string" ? params.payload.thumbnail_url : null,
    provider_name: typeof params.payload.provider_name === "string" ? params.payload.provider_name : null,
    fetched_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    last_status: params.status,
    last_error: params.errorMessage ?? null,
    raw: params.payload,
  };

  const response = await restRequest("/rest/v1/recipe_youtube_metadata?on_conflict=recipe_creator_id", {
    method: "POST",
    headers: {
      Prefer: "resolution=merge-duplicates,return=minimal"
    },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    const details = await response.text().catch(() => "");
    throw new Error(`Failed to upsert metadata: ${details}`);
  }
}

async function fetchCreatorRecipe(recipeId: string, userId: string): Promise<Record<string, unknown> | null> {
  const params = new URLSearchParams();
  params.set("select", "id,author_id,youtube_url");
  params.set("id", `eq.${recipeId}`);
  params.set("author_id", `eq.${userId}`);
  params.set("limit", "1");

  const response = await restRequest(`/rest/v1/recipes_creator?${params.toString()}`, { method: "GET" });
  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Failed to fetch creator recipe: ${details}`);
  }

  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return null;
  }

  return rows[0] as Record<string, unknown>;
}

async function listPendingCreatorRecipes(limit: number): Promise<Array<Record<string, unknown>>> {
  const params = new URLSearchParams();
  params.set("select", "id,author_id,youtube_url");
  params.set("youtube_url", "not.is.null");
  params.set("order", "updated_at.desc");
  params.set("limit", String(limit));

  const response = await restRequest(`/rest/v1/recipes_creator?${params.toString()}`, {
    method: "GET"
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Failed to list pending creator recipes: ${details}`);
  }

  const rows = await response.json();
  return Array.isArray(rows) ? rows as Array<Record<string, unknown>> : [];
}

function requireWorkerSecret(req: Request): { ok: boolean; error?: Response } {
  const expected = getEnv("YOUTUBE_WORKER_SECRET").trim();
  if (expected.length === 0) {
    return {
      ok: false,
      error: errorResponse(500, "YOUTUBE_WORKER_SECRET is not configured")
    };
  }

  const actual = (req.headers.get("x-worker-secret") ?? "").trim();
  if (actual !== expected) {
    return {
      ok: false,
      error: errorResponse(401, "Invalid worker secret")
    };
  }

  return { ok: true };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return errorResponse(405, "Method not allowed");
  }

  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return errorResponse(400, "Request body must be valid JSON object");
  }

  const action = typeof body.action === "string" ? body.action.trim().toLowerCase() : "sync_one";

  if (action === "sync_one") {
    const userId = await getAuthenticatedUserId(req);
    if (!userId) {
      return errorResponse(401, "Authorization Bearer token is required");
    }

    const recipeId = typeof body.recipe_id === "string" ? body.recipe_id.trim() : "";
    if (recipeId.length === 0) {
      return errorResponse(400, "recipe_id is required for sync_one");
    }

    const recipe = await fetchCreatorRecipe(recipeId, userId);
    if (!recipe) {
      return errorResponse(404, "Creator recipe not found");
    }

    const youtubeUrl = String(recipe.youtube_url ?? "").trim();
    if (youtubeUrl.length === 0) {
      return errorResponse(400, "youtube_url is empty on target recipe");
    }

    try {
      const metadata = await fetchYoutubeMetadata(youtubeUrl);
      await upsertYoutubeMetadata({
        recipeCreatorId: String(recipe.id),
        youtubeUrl,
        status: "ok",
        payload: metadata,
      });

      return okResponse({
        synced: 1,
        failed: 0,
        recipe_id: String(recipe.id),
        youtube_video_id: extractVideoId(youtubeUrl),
      });
    } catch (error) {
      const message = String(error);
      await upsertYoutubeMetadata({
        recipeCreatorId: String(recipe.id),
        youtubeUrl,
        status: "error",
        payload: {},
        errorMessage: message,
      });
      return errorResponse(502, "Failed to fetch youtube metadata", message);
    }
  }

  if (action === "sync_pending") {
    const secret = requireWorkerSecret(req);
    if (!secret.ok) {
      return secret.error as Response;
    }

    const rawLimit = Number((body as Record<string, unknown>).limit ?? 20);
    const limit = Number.isFinite(rawLimit)
      ? Math.max(1, Math.min(100, Math.trunc(rawLimit)))
      : 20;

    const rows = await listPendingCreatorRecipes(limit);

    let synced = 0;
    let failed = 0;

    for (const row of rows) {
      const recipeCreatorId = String(row.id ?? "").trim();
      const youtubeUrl = String(row.youtube_url ?? "").trim();
      if (recipeCreatorId.length === 0 || youtubeUrl.length === 0) {
        continue;
      }

      try {
        const metadata = await fetchYoutubeMetadata(youtubeUrl);
        await upsertYoutubeMetadata({
          recipeCreatorId,
          youtubeUrl,
          status: "ok",
          payload: metadata,
        });
        synced += 1;
      } catch (error) {
        failed += 1;
        await upsertYoutubeMetadata({
          recipeCreatorId,
          youtubeUrl,
          status: "error",
          payload: {},
          errorMessage: String(error),
        });
      }
    }

    return okResponse({
      requested_limit: limit,
      scanned: rows.length,
      synced,
      failed,
    });
  }

  return errorResponse(400, "action must be one of: sync_one, sync_pending");
});
