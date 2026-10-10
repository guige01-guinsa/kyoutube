import { classifyResponse, observeHttp, type OpsEvent } from "./operations.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error("Unexpected observation");
  }
}

Deno.test("classifies quota separately from actual AI and upstream failures", () => {
  equal(classifyResponse(429, "ai_quota_daily"), {
    code: "quota",
    outcome: "rejected",
  });
  equal(classifyResponse(422, "ai_draft_incomplete"), {
    code: "incomplete_draft",
    outcome: "failed",
  });
  equal(classifyResponse(429, "provider_busy"), {
    code: "upstream",
    outcome: "failed",
  });
  equal(classifyResponse(401, "secret"), {
    code: "unauthorized",
    outcome: "rejected",
  });
  equal(classifyResponse(504, null), { code: "timeout", outcome: "failed" });
  equal(classifyResponse(400, "user recipe"), {
    code: "invalid_request",
    outcome: "rejected",
  });
});

Deno.test("preserves response while excluding request and error content from observations", async () => {
  const events: OpsEvent[] = [], logs: Record<string, unknown>[] = [];
  let tick = 0;
  const body = JSON.stringify({
    code: "private recipe",
    message: "private email",
  });
  const handler = observeHttp(
    "ai_recipe_assistant",
    () => new Response(body, { status: 502 }),
    {
      record: async (event) => {
        events.push(event);
      },
      log: (event) => {
        logs.push(event);
      },
      now: () => (tick += 50),
    },
  );
  const response = await handler(
    new Request("https://example.test/private-url", {
      headers: { Authorization: "private bearer" },
    }),
  );
  equal(await response.text(), body);
  equal(response.status, 502);
  equal(events[0], {
    kind: "request",
    source: "ai_recipe_assistant",
    code: "upstream",
    outcome: "failed",
    http_status: 502,
    duration_ms: 50,
  });
  equal(JSON.stringify(logs).includes("private"), false);
});

Deno.test("telemetry failure cannot fail a successful product request", async () => {
  const logs: Record<string, unknown>[] = [];
  const response = await observeHttp("recipe_api", () => new Response("ok"), {
    record: async () => {
      throw new Error("secret credential");
    },
    log: (e) => {
      logs.push(e);
    },
  })(new Request("https://example.test"));
  equal(response.status, 200);
  equal(await response.text(), "ok");
  equal(logs[1], { event: "ops_delivery_failed", source: "recipe_api" });
  equal(JSON.stringify(logs).includes("secret"), false);
});

Deno.test("uncaught exception produces a safe 500 and categorized failure", async () => {
  let event: OpsEvent | undefined;
  const response = await observeHttp("membership", () => {
    throw new Error("secret");
  }, {
    record: async (e) => {
      event = e;
    },
    log: () => {},
  })(new Request("https://example.test"));
  equal(response.status, 500);
  equal(event?.code, "exception");
  equal(event?.outcome, "failed");
  equal((await response.text()).includes("secret"), false);
});

Deno.test("CORS preflight does not count as a request", async () => {
  let count = 0;
  const response = await observeHttp(
    "youtube_search",
    () => new Response(null, { status: 204 }),
    {
      record: async () => {
        count++;
      },
      log: () => {},
    },
  )(new Request("https://example.test", { method: "OPTIONS" }));
  equal(response.status, 204);
  equal(count, 0);
});
