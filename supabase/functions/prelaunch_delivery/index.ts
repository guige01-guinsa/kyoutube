import { env, rpc, site } from "../prelaunch_growth/runtime.ts";
import { validEmail } from "../prelaunch_growth/security.ts";
import { deliveryHandler } from "./handler.ts";
import { mail } from "./mail.ts";
Deno.serve(
  deliveryHandler({
    workerSecret: env("GROWTH_WORKER_SECRET"),
    enabled: () =>
      env("GROWTH_DELIVERY_ENABLED") === "true" &&
      env("GROWTH_PRIVACY_READY") === "true" && !!site() &&
      env("GROWTH_TOKEN_KEY").length >= 32 &&
      !!env("GROWTH_RESEND_API_KEY") && validEmail(env("GROWTH_FROM_EMAIL")) &&
      env("GROWTH_SENDER_NOTICE").length > 10,
    rpc,
    send: async (job) => {
      const content = await mail(
        job,
        env("GROWTH_TOKEN_KEY"),
        site()!.href,
        env("GROWTH_SENDER_NOTICE"),
      );
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": "Bearer " + env("GROWTH_RESEND_API_KEY"),
          "Content-Type": "application/json",
          "Idempotency-Key": "prelaunch/" + job.id,
        },
        body: JSON.stringify({
          from: `Recipe Scout <${env("GROWTH_FROM_EMAIL")}>`,
          to: [job.email],
          ...content,
        }),
        signal: AbortSignal.timeout(12000),
      });
      if (!response.ok) throw new Error("Email provider unavailable");
      const result = await response.json();
      if (typeof result.id !== "string" || !result.id) {
        throw new Error("Invalid email response");
      }
    },
  }),
);
