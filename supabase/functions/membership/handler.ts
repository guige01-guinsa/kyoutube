import { BillingError } from "./billing.ts";
import {
  boundedRequest,
  RequestBoundaryError,
} from "../_shared/request_boundary.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};
export function billingHandler(
  deps: {
    user: (auth: string) => Promise<string | null>;
    status: (auth: string) => Promise<unknown>;
    verify: (token: string, user: string) => Promise<unknown>;
  },
) {
  return async (request: Request): Promise<Response> => {
    const reply = (body: unknown, status = 200) =>
      new Response(JSON.stringify(body), { status, headers });
    if (request.method === "OPTIONS") return reply({});
    if (request.method !== "POST") {
      return reply({ code: "method_not_allowed" }, 405);
    }
    const auth = request.headers.get("authorization") ?? "";
    if (!auth.startsWith("Bearer ")) {
      return reply({ code: "unauthorized" }, 401);
    }
    try {
      const user = await deps.user(auth);
      if (!user) return reply({ code: "unauthorized" }, 401);
      const text = await (await boundedRequest(request, 8192)).text();
      let body;
      try {
        body = JSON.parse(text);
      } catch {
        return reply({ code: "invalid_json" }, 400);
      }
      let verification;
      if (body?.action === "verify_google_play") {
        if (typeof body.purchaseToken !== "string") {
          return reply({ code: "invalid_purchase" }, 400);
        }
        verification = await deps.verify(body.purchaseToken, user);
      } else if (body?.action !== "status") {
        return reply({ code: "invalid_action" }, 400);
      }
      return reply({
        status: "ok",
        data: await deps.status(auth),
        verification,
      });
    } catch (e) {
      if (e instanceof RequestBoundaryError) {
        return reply({ code: "request_too_large" }, 413);
      }
      if (e instanceof BillingError) {
        return reply({
          status: "error",
          code: e.code,
          message:
            "구독을 확인하지 못했습니다. 잠시 후 구독 복원을 눌러 주세요.",
        }, e.status);
      }
      console.error("membership_request_failed", {
        errorType: e instanceof Error ? e.name : "unknown",
      });
      return reply({
        status: "error",
        code: "membership_unavailable",
        message: "회원 정보를 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.",
      }, 503);
    }
  };
}
