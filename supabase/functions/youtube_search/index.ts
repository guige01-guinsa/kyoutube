import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

import { createYoutubeSearchHandler } from "./handler.ts";
import { searchYoutube } from "./youtube_client.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

const handler = createYoutubeSearchHandler({
  getEnv: (name) => Deno.env.get(name),
  searchYoutube,
  logFailure: (code, status) =>
    console.error("youtube_search_failed", { code, status }),
});

async function authorizeAndConsumeRateLimit(
  request: Request,
): Promise<Response | null> {
  const authorization = request.headers.get("Authorization");

  if (authorization == null || !authorization.startsWith("Bearer ")) {
    return jsonResponse(
      {
        status: "error",
        errorCode: "youtube_auth_required",
        httpStatus: 401,
      },
      401,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("youtube_search_server_config_missing");

    return jsonResponse(
      {
        status: "error",
        errorCode: "youtube_config_missing",
        httpStatus: 500,
      },
      500,
    );
  }

  try {
    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
      global: {
        headers: {
          Authorization: authorization,
        },
      },
    });

    const {
      data: { user },
      error: userError,
    } = await authClient.auth.getUser();

    if (userError != null || user == null || user.is_anonymous == true) {
      return jsonResponse(
        {
          status: "error",
          errorCode: "youtube_auth_required",
          httpStatus: 401,
        },
        401,
      );
    }

    const {
      data: allowed,
      error: rateLimitError,
    } = await authClient.rpc("consume_youtube_search_rate_limit");

    if (rateLimitError != null) {
      console.error("youtube_search_rate_limit_check_failed", {
        code: rateLimitError.code,
        message: rateLimitError.message,
      });

      return jsonResponse(
        {
          status: "error",
          errorCode: "youtube_rate_limit_unavailable",
          httpStatus: 503,
        },
        503,
      );
    }

    if (allowed != true) {
      return jsonResponse(
        {
          status: "error",
          errorCode: "youtube_rate_limited",
          httpStatus: 429,
        },
        429,
      );
    }

    return null;
  } catch (error) {
    console.error("youtube_search_auth_check_failed", {
      message: error instanceof Error ? error.message : "unknown_error",
    });

    return jsonResponse(
      {
        status: "error",
        errorCode: "youtube_auth_unavailable",
        httpStatus: 503,
      },
      503,
    );
  }
}

serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return handler(request);
  }

  // 잘못된 HTTP method는 handler가 405 응답을 반환한다.
  if (request.method !== "GET") {
    return handler(request);
  }

  // 잘못된 검색어는 quota를 소비하지 않고 handler가 400 응답을 반환한다.
  const url = new URL(request.url);
  const query = (url.searchParams.get("q") ?? "").trim();

  if (query.length < 2 || query.length > 80) {
    return handler(request);
  }

  const authFailure = await authorizeAndConsumeRateLimit(request);

  if (authFailure != null) {
    return authFailure;
  }

  return handler(request);
});
