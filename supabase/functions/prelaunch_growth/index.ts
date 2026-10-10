import { growthHandler } from "./handler.ts";
import { challenge, env, ready, rpc, site } from "./runtime.ts";
Deno.serve(
  growthHandler({
    origin: site()?.origin ?? "",
    signingKey: env("GROWTH_TOKEN_KEY"),
    ready,
    challenge,
    rpc,
  }),
);
