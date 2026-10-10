import {
  boundedRequest,
  RequestBoundaryError,
  secureResponse,
} from "../_shared/request_boundary.ts";
import { emailKey, validEmail, verifyClaim } from "./security.ts";
type Deps = {
  origin: string;
  signingKey: string;
  ready: () => Promise<boolean>;
  challenge: (token: string) => Promise<boolean>;
  rpc: (name: string, parameters: Record<string, unknown>) => Promise<unknown>;
};
export function growthHandler(d: Deps) {
  return async (request: Request) => {
    const origin = request.headers.get("origin");
    const allowed = !!d.origin && origin === d.origin;
    const respond = (body: unknown, status = 200) =>
      secureResponse(
        new Response(JSON.stringify(body), {
          status,
          headers: {
            "Content-Type": "application/json",
            "Vary": "Origin",
            ...(allowed
              ? {
                "Access-Control-Allow-Origin": d.origin,
                "Access-Control-Allow-Headers": "content-type",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
              }
              : {}),
          },
        }),
      );
    if (!allowed) return respond({ code: "origin_denied" }, 403);
    if (request.method === "OPTIONS") return respond({});
    try {
      if (request.method === "GET") return respond({ ready: await d.ready() });
      if (request.method !== "POST") {
        return respond({ code: "method_not_allowed" }, 405);
      }
      if (
        !request.headers.get("content-type")?.startsWith("application/json")
      ) return respond({ code: "invalid_request" }, 400);
      const body = await (await boundedRequest(request, 4096)).json();
      if (body?.action === "confirm" || body?.action === "withdraw") {
        if (typeof body.token !== "string") {
          return respond({ code: "invalid_link" }, 400);
        }
        const claim = await verifyClaim(d.signingKey, body.token, body.action);
        if (!claim) return respond({ code: "invalid_link" }, 400);
        const result = await d.rpc(
          body.action === "confirm" ? "growth_confirm" : "growth_withdraw",
          { p_id: claim.u, p_version: claim.v },
        );
        return result === true
          ? respond({
            status: body.action === "confirm" ? "confirmed" : "withdrawn",
          })
          : respond({ code: "invalid_link" }, 400);
      }
      if (!await d.ready()) return respond({ code: "not_ready" }, 503);
      const email = typeof body?.email === "string"
        ? body.email.trim().toLowerCase()
        : "";
      if (
        body?.action !== "join" || !validEmail(email) ||
        body.privacyConsent !== true || body.invitationConsent !== true ||
        body.consentVersion !== "pro-2026-09-v1" ||
        typeof body.newsletter !== "boolean" ||
        !["chef", "owner", "catering", "home"].includes(body.role) ||
        !["costs", "scaling", "purchasing", "video"].includes(body.interest) ||
        !["ko", "en"].includes(body.locale) ||
        typeof body.challenge !== "string" || body.challenge.length > 2048 ||
        typeof body.campaign !== "string" ||
        !/^[a-z0-9_-]{0,48}$/.test(body.campaign) ||
        !["direct", "youtube", "kakao", "partner", "other"].includes(
          body.source,
        )
      ) return respond({ code: "invalid_request" }, 400);
      if (body.website) return respond({ status: "accepted" }, 202); // Honeypot; never persist.
      if (!await d.challenge(body.challenge)) {
        return respond({ code: "challenge_failed" }, 400);
      }
      await d.rpc("growth_register", {
        p_email: email,
        p_email_key: await emailKey(d.signingKey, email),
        p_role: body.role,
        p_interest: body.interest,
        p_locale: body.locale,
        p_newsletter: body.newsletter,
        p_source: body.source,
        p_campaign: body.campaign,
      });
      return respond({ status: "accepted" }, 202); // Same response for new/duplicate/withdrawn addresses.
    } catch (error) {
      if (error instanceof RequestBoundaryError) {
        return respond({ code: error.code }, error.status);
      }
      if (error instanceof SyntaxError) {
        return respond({ code: "invalid_request" }, 400);
      }
      // Never echo database/provider errors, addresses or signed links.
      return respond({ code: "temporarily_unavailable" }, 503);
    }
  };
}
