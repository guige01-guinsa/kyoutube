import { fetchWithTimeout as fetch } from "../_shared/http.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";
import {
  type BillingDependencies,
  BillingError,
  verifyBilling,
} from "./billing.ts";
export function env(name: string) {
  const value = (Deno.env.get(name) ?? "").trim();
  if (!value) throw new Error("Missing billing configuration");
  return value;
}
export function authClient(authorization: string) {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: authorization }, fetch },
  });
}
type GoogleServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

async function googleAccessToken(): Promise<string> {
  let serviceAccount: GoogleServiceAccount;
  try {
    serviceAccount = JSON.parse(env("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"));
  } catch (_) {
    throw new Error("Invalid Google Play service-account configuration");
  }
  if (!serviceAccount.client_email || !serviceAccount.private_key) {
    throw new Error("Incomplete Google Play service-account configuration");
  }
  const tokenUri = "https://oauth2.googleapis.com/token";
  if (serviceAccount.token_uri && serviceAccount.token_uri !== tokenUri) {
    throw new Error("Unsupported Google token endpoint");
  }
  const privateKey = await importPKCS8(serviceAccount.private_key, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/androidpublisher",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(serviceAccount.client_email)
    .setAudience(tokenUri)
    .setIssuedAt()
    .setExpirationTime("10m")
    .sign(privateKey);
  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const body = await response.json().catch(() => null);
  if (!response.ok || typeof body?.access_token !== "string") {
    throw new Error("Google Play authorization failed");
  }
  return body.access_token;
}

export function billingDependencies(): BillingDependencies {
  const admin = createClient(
    env("SUPABASE_URL"),
    env("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch },
    },
  );
  let accessToken: Promise<string> | undefined;
  const token = () => accessToken ??= googleAccessToken();
  return {
    serial: async () => {
      const { data, error } = await admin.rpc("begin_billing_verification");
      if (error) throw new Error("Billing serial unavailable");
      return Number(data);
    },
    offers: async () => {
      const { data, error } = await admin.from("membership_billing_offers")
        .select("plan_code,product_id,base_plan_id");
      if (error) throw new Error("Billing catalog unavailable");
      return data;
    },
    purchase: async (purchaseToken) => {
      const response = await fetch(
        "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.kyoutube.app/purchases/subscriptionsv2/tokens/" +
          encodeURIComponent(purchaseToken),
        { headers: { Authorization: "Bearer " + await token() } },
      );
      if (!response.ok) {
        throw new BillingError("purchase_verification_failed", 502);
      }
      return await response.json();
    },
    owner: async (hash) => {
      const { data, error } = await admin.from("verified_billing_tokens")
        .select("user_id").eq("token_hash", hash).maybeSingle();
      if (error) throw new Error("Billing owner lookup failed");
      return data?.user_id ?? null;
    },
    acknowledge: async (product, purchaseToken) => {
      const response = await fetch(
        "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.kyoutube.app/purchases/subscriptions/" +
          encodeURIComponent(product) + "/tokens/" +
          encodeURIComponent(purchaseToken) + ":acknowledge",
        {
          method: "POST",
          headers: {
            Authorization: "Bearer " + await token(),
            "Content-Type": "application/json",
          },
          body: "{}",
        },
      );
      if (!response.ok) {
        throw new BillingError("purchase_acknowledgement_failed", 502);
      }
    },
    apply: async (args) => {
      const { data, error } = await admin.rpc(
        "apply_verified_membership",
        args,
      );
      if (error) {
        if (
          [
            "PURCHASE_ACCOUNT_MISMATCH",
            "OTHER_SUBSCRIPTION_ACTIVE",
            "PURCHASE_CHAIN_CONFLICT",
          ].some((code) => error.message.includes(code))
        ) throw new BillingError("purchase_conflict", 409);
        throw new Error("Billing persistence failed");
      }
      return data === true;
    },
  };
}
export function verifyPurchase(token: string, user?: string) {
  return verifyBilling(billingDependencies(), token, user);
}
