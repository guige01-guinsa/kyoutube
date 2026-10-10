import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import { fetchWithTimeout } from "../_shared/http.ts";
import { createMarketingDraftHandler } from "./handler.ts";

function client(authorization: string) {
  return createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: fetchWithTimeout, headers: { Authorization: authorization } },
  });
}
async function rpc(auth: string, name: string, params?: Record<string, unknown>) {
  const { data, error } = await client(auth).rpc(name, params);
  if (error) throw new Error(error.message.includes("MARKETING_RATE_LIMIT") ? "MARKETING_RATE_LIMIT" : "database_unavailable");
  return data;
}
Deno.serve(createMarketingDraftHandler({
  getEnv: key => Deno.env.get(key),
  authorize: async auth => {
    const c = client(auth);
    const { data: { user }, error } = await c.auth.getUser();
    if (error || !user || user.is_anonymous) return false;
    const gate = await c.rpc("admin_assert_integration_access");
    return !gate.error && gate.data === true;
  },
  begin: (auth, id, topic) => rpc(auth, "admin_begin_marketing_draft", { p_id: id, p_topic: topic }),
  complete: async (auth, id, draft) => { await rpc(auth, "admin_complete_marketing_draft", { p_id: id, p_draft: draft }); },
  getCampaign: async (auth, id) => {
    const result = await rpc(auth, "admin_marketing_overview");
    return result.campaigns.find((c: { id: string }) => c.id === id) ?? null;
  },
}));
