import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import { fetchWithTimeout } from "../_shared/http.ts";
import { CoupangError, createCoupangClient } from "./client.ts";
import { createHandler } from "./handler.ts";
const env = (key: string) => Deno.env.get(key) ?? "";
Deno.serve(createHandler({
  reserve: async (authorization, action) => {
    if (!env("SUPABASE_URL") || !env("SUPABASE_ANON_KEY")) {
      throw new CoupangError("service_unavailable", 503);
    }
    const client = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
      global: {
        fetch: fetchWithTimeout,
        headers: { Authorization: authorization },
      },
    });
    const { data: { user }, error: authError } = await client.auth.getUser();
    if (authError || !user || user.is_anonymous) {
      throw new CoupangError("unauthorized", 401);
    }
    const { data, error } = await client.rpc("admin_consume_coupang_api", {
      p_action: action,
    });
    if (error) {
      if (error.message.includes("ADMIN_MFA_REQUIRED")) {
        throw new CoupangError("admin_mfa_required", 403);
      }
      if (error.message.includes("ADMIN_REQUIRED")) {
        throw new CoupangError("admin_required", 403);
      }
      throw new CoupangError("service_unavailable", 503);
    }
    if (data !== true) throw new CoupangError("rate_limited", 429);
  },
  client: () => {
    const access = env("COUPANG_PARTNERS_ACCESS_KEY");
    const secret = env("COUPANG_PARTNERS_SECRET_KEY");
    if (!access || !secret) throw new CoupangError("not_configured", 503);
    return createCoupangClient(access, secret);
  },
}));
