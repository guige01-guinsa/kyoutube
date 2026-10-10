import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import { fetchWithTimeout } from "../_shared/http.ts";
import { validEmail } from "./security.ts";
export const env = (name: string) => Deno.env.get(name)?.trim() ?? "";
export function site() {
  try {
    const url = new URL(env("GROWTH_SITE_URL"));
    return url.protocol === "https:" && !url.username && !url.password &&
        !url.search && !url.hash
      ? url
      : null;
  } catch {
    return null;
  }
}
export function admin() {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: fetchWithTimeout },
  });
}
export async function rpc(
  name: string,
  parameters: Record<string, unknown> = {},
) {
  const { data, error } = await admin().rpc(name, parameters);
  if (error) throw new Error("Growth storage unavailable");
  return data;
}
export async function ready() {
  if (
    !site() || env("GROWTH_TOKEN_KEY").length < 32 ||
    !env("GROWTH_TURNSTILE_SECRET") ||
    !env("GROWTH_RESEND_API_KEY") || !validEmail(env("GROWTH_FROM_EMAIL")) ||
    env("GROWTH_WORKER_SECRET").length < 32 ||
    env("GROWTH_SENDER_NOTICE").length <= 10 ||
    env("GROWTH_DELIVERY_ENABLED") !== "true" ||
    env("GROWTH_PRIVACY_READY") !== "true"
  ) return false;
  const { data, error } = await admin().from("growth_controls").select(
    "intake_enabled,delivery_enabled",
  ).eq("id", true).single();
  return !error && data?.intake_enabled === true &&
    data?.delivery_enabled === true;
}
export async function challenge(token: string) {
  const res = await fetch(
    "https://challenges.cloudflare.com/turnstile/v0/siteverify",
    {
      method: "POST",
      body: new URLSearchParams({
        secret: env("GROWTH_TURNSTILE_SECRET"),
        response: token,
      }),
      signal: AbortSignal.timeout(10000),
    },
  );
  if (!res.ok) return false;
  const data = await res.json();
  return data.success === true && data.hostname === site()?.hostname &&
    data.action === "prelaunch";
}
