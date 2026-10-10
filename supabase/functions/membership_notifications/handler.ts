import { BillingError } from "../membership/billing.ts";
import {
  boundedRequest,
  RequestBoundaryError,
} from "../_shared/request_boundary.ts";
export function notificationsHandler(
  deps: {
    authenticate: (jwt: string) => Promise<void>;
    verify: (token: string) => Promise<unknown>;
  },
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return new Response(null, { status: 405 });
    const auth = request.headers.get("authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return new Response(null, { status: 401 });
    try {
      await deps.authenticate(auth.substring(7));
    } catch {
      return new Response(null, { status: 401 });
    }
    try {
      const text = await (await boundedRequest(request, 32768)).text();
      let body;
      let notification;
      try {
        body = JSON.parse(text);
        notification = JSON.parse(atob(body.message.data));
      } catch {
        return new Response(null, { status: 400 });
      }
      if (notification.packageName !== "com.kyoutube.app") {
        return new Response(null, { status: 403 });
      }
      if (notification.testNotification) {
        return new Response(null, { status: 204 });
      }
      const token = notification.subscriptionNotification?.purchaseToken ??
        notification.voidedPurchaseNotification?.purchaseToken;
      if (typeof token !== "string") return new Response(null, { status: 400 });
      // Notifications are signals only. Always fetch the current Google state.
      await deps.verify(token);
      return new Response(null, { status: 204 });
    } catch (e) {
      if (e instanceof RequestBoundaryError) {
        return new Response(null, { status: 413 });
      }
      if (e instanceof BillingError && e.code === "purchase_pending") {
        return new Response(null, { status: 204 });
      }
      console.error("billing_notification_failed", {
        errorType: e instanceof Error ? e.name : "unknown",
      });
      return new Response(null, { status: 503 });
    }
  };
}
