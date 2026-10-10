import { secureResponse } from "../_shared/request_boundary.ts";
import { equalSecret } from "../prelaunch_growth/security.ts";
import { type Job } from "./mail.ts";
type Deps = {
  workerSecret: string;
  enabled: () => boolean;
  rpc: (name: string, args?: Record<string, unknown>) => Promise<unknown>;
  send: (job: Job) => Promise<void>;
};
export function deliveryHandler(d: Deps) {
  return async (request: Request) => {
    const respond = (body: unknown, status = 200) =>
      secureResponse(Response.json(body, { status }));
    if (request.method !== "POST") {
      return respond({ code: "method_not_allowed" }, 405);
    }
    if (
      !await equalSecret(
        request.headers.get("authorization") ?? "",
        "Bearer " + d.workerSecret,
      ) || d.workerSecret.length < 32
    ) return respond({ code: "unauthorized" }, 401);
    try {
      await d.rpc("growth_maintain");
      if (!d.enabled()) return respond({ status: "paused" });
      const job = await d.rpc("growth_claim_job") as Job | null;
      if (!job) return respond({ status: "idle" });
      if (
        await d.rpc("growth_job_deliverable", {
          p_id: job.id,
          p_lease: job.lease_id,
        }) !== true
      ) return respond({ status: "cancelled" });
      try {
        await d.send(job);
      } catch {
        await d.rpc("growth_finish_job", {
          p_id: job.id,
          p_lease: job.lease_id,
          p_sent: false,
          p_code: "provider",
        });
        return respond({ status: "retry_queued" }, 503);
      }
      // If the final write fails, lease retry uses the same provider idempotency key.
      await d.rpc("growth_finish_job", {
        p_id: job.id,
        p_lease: job.lease_id,
        p_sent: true,
        p_code: "unknown",
      });
      return respond({ status: "provider_accepted" });
    } catch {
      return respond({ code: "temporarily_unavailable" }, 503);
    }
  };
}
