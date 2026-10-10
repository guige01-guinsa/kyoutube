import { createRemoteJWKSet } from "npm:jose@5.9.6";
import { pushAuthenticator } from "./auth.ts";
import { observeHttp } from "../_shared/operations.ts";
import { env, verifyPurchase } from "../membership/runtime.ts";
import { notificationsHandler } from "./handler.ts";
const keys = createRemoteJWKSet(
  new URL("https://www.googleapis.com/oauth2/v3/certs"),
);
Deno.serve(observeHttp(
  "membership",
  notificationsHandler({
    authenticate: async (token) => {
      await pushAuthenticator(
        env("GOOGLE_PLAY_RTDN_AUDIENCE"),
        env("GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT_EMAIL"),
        keys,
      )(token);
    },
    verify: verifyPurchase,
  }),
));
