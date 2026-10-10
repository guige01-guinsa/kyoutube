import {
  boundedRequest,
  RequestBoundaryError,
  secureResponse,
} from "./request_boundary.ts";
export type OpsSource =
  | "ai_recipe_assistant"
  | "ai_youtube_recipe_assistant"
  | "recipe_api"
  | "youtube_search"
  | "membership"
  | "youtube_recipe_context"
  | "delete-account";
export type OpsEvent = {
  kind: "request";
  source: OpsSource;
  outcome: "succeeded" | "failed" | "rejected";
  code: string;
  http_status: number;
  duration_ms: number;
};
type Handler = (request: Request) => Response | Promise<Response>;

export function classifyResponse(
  status: number,
  code: unknown,
): Pick<OpsEvent, "code" | "outcome"> {
  // Only categorical, constant strings leave the function. No upstream messages.
  if (status < 400) return { code: "ok", outcome: "succeeded" };
  const key = typeof code === "string" ? code : "";
  if (
    [
      "ai_quota_daily",
      "ai_quota_weekly",
      "ai_quota_monthly",
      "ai_request_in_flight",
      "ai_rate_limited",
    ].includes(key)
  ) {
    return { code: "quota", outcome: "rejected" };
  }
  if (key === "ai_draft_incomplete" || key === "ai_suggestion_invalid") {
    return { code: "incomplete_draft", outcome: "failed" };
  }
  if (
    [
      "ai_not_configured",
      "youtube_config_missing",
      "server_configuration_error",
    ].includes(key)
  ) return { code: "configuration", outcome: "failed" };
  if (status === 401 || status === 403) {
    return { code: "unauthorized", outcome: "rejected" };
  }
  if (status === 408 || status === 504) {
    return { code: "timeout", outcome: "failed" };
  }
  if (status === 429 || status === 502 || status === 503) {
    return { code: "upstream", outcome: "failed" };
  }
  return status >= 500
    ? { code: "http_error", outcome: "failed" }
    : { code: "invalid_request", outcome: "rejected" };
}

async function persistEvent(event: OpsEvent): Promise<void> {
  const url = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const key = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  if (!url || !key) throw new Error("ops_configuration_missing");
  const result = await fetch(`${url}/rest/v1/ops_events`, {
    method: "POST",
    signal: AbortSignal.timeout(2000),
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify(event),
  });
  await result.body?.cancel();
  if (!result.ok) throw new Error("ops_persistence_failed");
}

/** Observe completed requests without changing the response or trusting payloads.
 * Platform crashes before invocation and unavailable telemetry transport are not
 * in these counts. Safe structured logs remain the fallback when storage fails.
 */
export function observeHttp(source: OpsSource, handler: Handler, options: {
  record?: (event: OpsEvent) => Promise<void>;
  log?: (event: Record<string, unknown>) => void;
  now?: () => number;
} = {}): Handler {
  const record = options.record ?? persistEvent;
  const log = options.log ?? ((event) => console.log(JSON.stringify(event)));
  const now = options.now ?? (() => performance.now());
  return async (request) => {
    if (request.method === "OPTIONS") {
      return secureResponse(await handler(request));
    }
    const started = now();
    let response: Response;
    let exception = false;
    try {
      response = await handler(await boundedRequest(request));
    } catch (error) {
      exception = !(error instanceof RequestBoundaryError);
      response = new Response(
        JSON.stringify({
          status: "error",
          code: error instanceof RequestBoundaryError
            ? error.code
            : "internal_error",
        }),
        {
          status: error instanceof RequestBoundaryError ? error.status : 500,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        },
      );
    }
    const duration = Math.min(
      3600000,
      Math.max(0, Math.round(now() - started)),
    );
    let code: unknown;
    if (response.status >= 400) {
      const body = await response.clone().json().catch(() => null);
      code = body?.code ?? body?.errorCode;
    }
    const event: OpsEvent = {
      kind: "request",
      source,
      ...classifyResponse(response.status, code),
      ...(exception ? { code: "exception" } : {}),
      http_status: response.status,
      duration_ms: duration,
    };
    const work = (async () => {
      try {
        log({ event: "ops_request", ...event });
        await record(event);
      } catch (_) {
        // Never log credentials, URLs, request contents, exception messages or traces.
        try {
          log({ event: "ops_delivery_failed", source });
        } catch (_) { /* observer cannot fail requests */ }
      }
    })();
    const runtime = (globalThis as unknown as {
      EdgeRuntime?: { waitUntil(p: Promise<unknown>): void };
    }).EdgeRuntime;
    if (runtime) runtime.waitUntil(work);
    else await work;
    return secureResponse(response);
  };
}
