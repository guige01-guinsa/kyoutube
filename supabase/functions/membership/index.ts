import { observeHttp } from "../_shared/operations.ts";
import { billingHandler } from "./handler.ts";
import { authClient, verifyPurchase } from "./runtime.ts";
Deno.serve(observeHttp(
  "membership",
  billingHandler({
    user: async (auth) => {
      const { data: { user }, error } = await authClient(auth).auth.getUser();
      return error || user?.is_anonymous ? null : user?.id ?? null;
    },
    status: async (auth) => {
      const { data, error } = await authClient(auth).rpc("get_my_membership");
      if (error) throw new Error("Membership unavailable");
      return Array.isArray(data) ? data[0] : data;
    },
    verify: verifyPurchase,
  }),
));
