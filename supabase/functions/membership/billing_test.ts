import {
  type BillingDependencies,
  BillingError,
  type PlayPurchase,
  resolvePurchase,
  verifyBilling,
} from "./billing.ts";
import { billingHandler } from "./handler.ts";
import { notificationsHandler } from "../membership_notifications/handler.ts";
const user = "66000000-0000-4000-8000-000000000001";
const offers = [{
  plan_code: "plus_monthly",
  product_id: "recipe_scout_plus",
  base_plan_id: "monthly",
}, {
  plan_code: "business_annual",
  product_id: "recipe_scout_business",
  base_plan_id: "annual",
}];
const eq = (a: unknown, b: unknown) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error(`Expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
  }
};
const purchase = (state = "SUBSCRIPTION_STATE_ACTIVE"): PlayPurchase => ({
  subscriptionState: state,
  startTime: "2026-01-01T00:00:00Z",
  acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
  externalAccountIdentifiers: { obfuscatedExternalAccountId: user },
  lineItems: [{
    productId: "recipe_scout_plus",
    offerDetails: { basePlanId: "monthly" },
    expiryTime: "2099-01-01T00:00:00Z",
    latestSuccessfulOrderId: "GPA.fixture",
    autoRenewingPlan: { autoRenewEnabled: true },
  }],
});
for (
  const [state, status, entitled] of [
    ["ACTIVE", "active", true],
    ["IN_GRACE_PERIOD", "grace_period", true],
    ["CANCELED", "canceled", true],
    ["ON_HOLD", "paused", false],
    ["PAUSED", "paused", false],
    ["EXPIRED", "expired", false],
  ] as const
) {
  Deno.test(`Play state ${state} resolves ${status}`, () => {
    const r = resolvePurchase(purchase("SUBSCRIPTION_STATE_" + state), offers);
    eq([r.status, r.entitled], [status, entitled]);
  });
}
Deno.test("expired active response does not grant access", () => {
  const p = purchase();
  p.lineItems![0].expiryTime = "2020-01-01T00:00:00Z";
  eq(resolvePurchase(p, offers).entitled, false);
});
Deno.test("auto renewal comes from Play plan, not ACTIVE state", () => {
  const p = purchase();
  p.lineItems![0].autoRenewingPlan!.autoRenewEnabled = false;
  eq(resolvePurchase(p, offers).autoRenews, false);
});
Deno.test("deferred replacement retains owned tier despite future item expiry", () => {
  const p = purchase();
  p.lineItems![0].deferredItemReplacement = {
    productId: "recipe_scout_business",
  };
  p.lineItems!.push({
    productId: "recipe_scout_business",
    offerDetails: { basePlanId: "annual" },
    expiryTime: "2100-01-01T00:00:00Z",
  });
  eq(resolvePurchase(p, offers).offer.plan_code, "plus_monthly");
});
Deno.test("deferred first renewal grants new tier with old expired line retained", () => {
  const p = purchase();
  p.lineItems![0].expiryTime = "2020-01-01T00:00:00Z";
  p.lineItems!.push({
    productId: "recipe_scout_business",
    offerDetails: { basePlanId: "annual" },
    expiryTime: "2099-01-01T00:00:00Z",
    latestSuccessfulOrderId: "GPA.fixture-new",
  });
  eq(resolvePurchase(p, offers).offer.plan_code, "business_annual");
});
for (
  const change of [
    "unknown_base",
    "ambiguous",
    "unknown_state",
    "pending",
    "missing_account",
    "future_start",
  ]
) {
  Deno.test(`invalid provider response rejected: ${change}`, () => {
    const p = purchase();
    if (change === "unknown_base") {
      p.lineItems![0].offerDetails = { basePlanId: "unknown" };
    }
    if (change === "ambiguous") p.lineItems!.push({ ...p.lineItems![0] });
    if (change === "unknown_state") {
      p.subscriptionState = "NEW_UNSUPPORTED_STATE";
    }
    if (change === "pending") {
      p.subscriptionState = "SUBSCRIPTION_STATE_PENDING";
    }
    if (change === "missing_account") delete p.externalAccountIdentifiers;
    if (change === "future_start") p.startTime = "2100-01-01T00:00:00Z";
    try {
      resolvePurchase(p, offers);
      throw new Error("not rejected");
    } catch (e) {
      if (!(e instanceof BillingError)) throw e;
    }
  });
}
function fixture() {
  const calls: string[] = [];
  const values: Record<string, unknown>[] = [];
  const d: BillingDependencies = {
    owner: async () => null,
    serial: async () => {
      calls.push("serial");
      return 1;
    },
    purchase: async () => {
      calls.push("lookup");
      return purchase();
    },
    offers: async () => offers,
    apply: async (v) => {
      calls.push("apply");
      values.push(v);
      return true;
    },
    acknowledge: async () => {
      calls.push("ack");
    },
  };
  return { d, calls, values };
}
Deno.test("verification binds account and persists before acknowledgement", async () => {
  const f = fixture();
  await verifyBilling(f.d, "fixture-purchase-token-long", user);
  eq(f.calls, ["serial", "lookup", "apply", "ack"]);
  eq(f.values[0].p_user_id, user);
  eq(String(f.values[0].p_token_hash).length, 64);
});
Deno.test("Play subscriptions-center resubscription binds expired account and token", async () => {
  const f = fixture();
  const p = purchase();
  delete p.externalAccountIdentifiers;
  p.outOfAppPurchaseContext = {
    expiredExternalAccountIdentifiers: { obfuscatedExternalAccountId: user },
    expiredPurchaseToken: "expired-purchase-token-fixture",
  };
  f.d.purchase = async () => p;
  await verifyBilling(f.d, "new-purchase-token-fixture", user);
  eq(f.values[0].p_user_id, user);
  eq(String(f.values[0].p_linked_hash).length, 64);
});
Deno.test("post-ack renewal without context uses persisted token owner", async () => {
  const f = fixture();
  const p = purchase();
  delete p.externalAccountIdentifiers;
  f.d.purchase = async () => p;
  f.d.owner = async () => user;
  await verifyBilling(f.d, "new-purchase-token-fixture", user);
  eq(f.values[0].p_user_id, user);
});
Deno.test("caller ID alone never claims an unbound out-of-app token", async () => {
  const f = fixture();
  const p = purchase();
  delete p.externalAccountIdentifiers;
  f.d.purchase = async () => p;
  try {
    await verifyBilling(f.d, "new-purchase-token-fixture", user);
    throw new Error("claimed");
  } catch (e) {
    if (!(e instanceof BillingError) || e.code !== "purchase_account_missing") {
      throw e;
    }
  }
  eq(f.values.length, 0);
});
Deno.test("other account cannot persist or acknowledge", async () => {
  const f = fixture();
  try {
    await verifyBilling(f.d, "fixture-purchase-token-long", "another-user");
    throw new Error("allowed");
  } catch (e) {
    if (!(e instanceof BillingError) || e.status !== 403) throw e;
  }
  eq(f.calls, ["serial", "lookup"]);
});
Deno.test("persistence failure does not acknowledge", async () => {
  const f = fixture();
  f.d.apply = async () => {
    throw new Error("database unavailable");
  };
  try {
    await verifyBilling(f.d, "fixture-purchase-token-long", user);
  } catch { /* expected */ }
  eq(f.calls.includes("ack"), false);
});
Deno.test("acknowledgement failure retries persistence and acknowledgement", async () => {
  const f = fixture();
  let n = 0;
  f.d.acknowledge = async () => {
    if (++n === 1) throw new Error("timeout");
  };
  try {
    await verifyBilling(f.d, "fixture-purchase-token-long", user);
  } catch { /* expected */ }
  await verifyBilling(f.d, "fixture-purchase-token-long", user);
  eq(n, 2);
  eq(f.values.length, 2);
});
Deno.test("superseded verification does not acknowledge or report current purchase", async () => {
  const f = fixture();
  f.d.apply = async () => false;
  eq(
    (await verifyBilling(f.d, "fixture-purchase-token-long", user))
      .currentPurchase,
    false,
  );
  eq(f.calls.includes("ack"), false);
});
Deno.test("HTTP billing rejects no-auth, anonymous, invalid JSON and unknown action", async () => {
  const handler = billingHandler({
    user: async (a) => a === "Bearer signed" ? user : null,
    status: async () => ({ plan_code: "free" }),
    verify: async () => {
      throw new Error("unexpected");
    },
  });
  const req = (body: string, auth = "Bearer signed") =>
    new Request("https://local.test", {
      method: "POST",
      headers: { authorization: auth },
      body,
    });
  eq((await handler(req("{}", ""))).status, 401);
  eq((await handler(req("{}", "Bearer guest"))).status, 401);
  eq((await handler(req("broken"))).status, 400);
  eq((await handler(req("{}"))).status, 400);
  eq((await handler(req('{"action":"status"}'))).status, 200);
});
const notificationRequest = (body: unknown, auth = "Bearer signed") =>
  new Request("https://local.test", {
    method: "POST",
    headers: { authorization: auth },
    body: JSON.stringify({
      message: { messageId: "fixture", data: btoa(JSON.stringify(body)) },
    }),
  });
Deno.test("RTDN requires verified identity and matching package", async () => {
  let calls = 0;
  const handler = notificationsHandler({
    authenticate: async (jwt) => {
      if (jwt !== "signed") throw new Error("invalid");
    },
    verify: async () => calls++,
  });
  eq((await handler(notificationRequest({}, "Bearer fake"))).status, 401);
  eq(
    (await handler(notificationRequest({ packageName: "other" }))).status,
    403,
  );
  eq(calls, 0);
});
Deno.test("duplicate and reverse RTDN signals always refresh current provider state", async () => {
  let calls = 0;
  const handler = notificationsHandler({
    authenticate: async () => {},
    verify: async () => calls++,
  });
  for (const time of ["200", "100", "100"]) {
    eq(
      (await handler(
        notificationRequest({
          packageName: "com.kyoutube.app",
          eventTimeMillis: time,
          subscriptionNotification: {
            purchaseToken: "fixture-purchase-token-long",
          },
        }),
      )).status,
      204,
    );
  }
  eq(calls, 3);
});
Deno.test("RTDN persistence failures return retryable status", async () => {
  const handler = notificationsHandler({
    authenticate: async () => {},
    verify: async () => {
      throw new Error("database down");
    },
  });
  eq(
    (await handler(
      notificationRequest({
        packageName: "com.kyoutube.app",
        subscriptionNotification: {
          purchaseToken: "fixture-purchase-token-long",
        },
      }),
    )).status,
    503,
  );
});
