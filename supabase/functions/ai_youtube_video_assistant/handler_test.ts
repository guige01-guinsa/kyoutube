import {
  createVideoAssistantHandler,
  validateVideoEvidence,
  videoDuration,
} from "./handler.ts";
const eq = (a: unknown, b: unknown) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error(`Expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
  }
};
const body = {
  outputLocale: "en-US",
  recipe: { title: "Tofu soup", youtubeUrl: "https://youtu.be/abc123XYZ00" },
  selectedVideo: {
    videoId: "abc123XYZ00",
    youtubeUrl: "https://youtu.be/abc123XYZ00",
    originalTitle: "Tofu soup",
    inferredRecipeTitle: "Tofu soup",
    channelName: "Chef",
    description: "UNTRUSTED_CLIENT",
    durationSec: 1,
  },
};
const draft = {
  title: "Tofu soup",
  summary: "Cook tofu and onion.",
  servings: 4,
  ingredients: [{
    name: "Tofu",
    quantity: "300",
    unit: "g",
    status: "confirmed",
    evidence: { timestampSeconds: 12, quote: "300 g tofu" },
  }, { name: "Onion", quantity: "2", unit: "ea", status: "confirmed" }],
  steps: [{
    instruction: "Cut tofu",
    status: "confirmed",
    evidence: { timestampSeconds: 20, quote: "Cut tofu into cubes" },
  }, {
    instruction: "Add onion and cook",
    durationMinutes: 50,
    status: "confirmed",
  }],
};
function setup(
  o: {
    plan?: string;
    quota?: boolean;
    duration?: string;
    privacy?: string;
    live?: string;
    blocked?: boolean;
    timeout?: boolean;
    startFailure?: boolean;
    key?: boolean;
    result?: unknown;
  } = {},
) {
  const calls: string[] = [],
    finishes: unknown[][] = [],
    bodies: unknown[] = [];
  let started = 0;
  const handler = createVideoAssistantHandler({
    getEnv: (n) =>
      n === "VIDEO_ANALYSIS_ENABLED"
        ? "true"
        : o.key === false
        ? undefined
        : "fake-test-key",
    reserve: async () => {
      if (o.quota) throw { code: "video_quota_monthly", status: 429 };
      return {
        id: "r",
        userId: "u",
        planCode: o.plan ?? "business_monthly",
        recipeModel: "gpt-5.4-mini",
      };
    },
    start: async () => {
      if (o.startFailure) throw { code: "membership_unavailable", status: 503 };
      started++;
    },
    finish: async (...args) => {
      finishes.push(args);
    },
    fetch: async (url, init) => {
      const u = String(url);
      calls.push(u);
      if (u.startsWith("https://www.googleapis.com/youtube/v3/videos")) {
        return Response.json({
          items: [{
            id: "abc123XYZ00",
            status: { privacyStatus: o.privacy ?? "public" },
            snippet: {
              title: "Canonical title",
              channelTitle: "Canonical chef",
              description: "Source",
              liveBroadcastContent: o.live ?? "none",
            },
            contentDetails: { duration: o.duration ?? "PT10M" },
          }],
        });
      }
      if (
        !u.startsWith(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent",
        )
      ) throw new Error("Unexpected destination");
      bodies.push(JSON.parse(String(init?.body)));
      if (o.timeout) throw new DOMException("timeout", "TimeoutError");
      return Response.json({
        candidates: [{
          finishReason: o.blocked ? "SAFETY" : "STOP",
          content: { parts: [{ text: JSON.stringify(o.result ?? draft) }] },
        }],
        usageMetadata: {
          promptTokenCount: 1000,
          candidatesTokenCount: 100,
          thoughtsTokenCount: 50,
          promptTokensDetails: [{ modality: "VIDEO", tokenCount: 900 }, {
            modality: "AUDIO",
            tokenCount: 100,
          }],
        },
      });
    },
  });
  return {
    run: (b: unknown = body, auth = true) =>
      handler(
        new Request("https://local/video", {
          method: "POST",
          headers: auth ? { authorization: "Bearer test" } : {},
          body: JSON.stringify(b),
        }),
      ),
    calls,
    finishes,
    bodies,
    started: () => started,
  };
}
Deno.test("video extraction uses canonical video and retains unknown evidence flags", async () => {
  const s = setup();
  const res = await s.run();
  eq(res.status, 200);
  const data = (await res.json()).data;
  eq(data.servings, null);
  eq(data.ingredientDetails[1].quantity, null);
  eq(data.ingredientDetails[1].status, "unverified");
  eq(data.stepDetails[1].durationMinutes, null);
  eq(data.ingredients[1].startsWith("[Check video]"), true);
  eq(s.finishes[0][1], true);
  eq(s.finishes[0][3], 1000);
  eq(s.finishes[0][4], 150);
  const config = (s.bodies[0] as {
    generationConfig: {
      responseJsonSchema: { type: string; required: string[] };
      thinkingConfig: unknown;
      maxOutputTokens: number;
    };
  }).generationConfig;
  eq(config.responseJsonSchema.type, "object");
  eq(config.responseJsonSchema.required.includes("ingredients"), true);
  eq(config.thinkingConfig, { thinkingLevel: "low" });
  eq(config.maxOutputTokens, 8192);
  const text = JSON.stringify(s.bodies);
  eq(text.includes("UNTRUSTED_CLIENT"), false);
  eq(text.includes("https://www.youtube.com/watch?v=abc123XYZ00"), true);
  eq(s.started(), 1);
});

Deno.test("Spanish video analysis sends Spanish instructions and localized errors", async () => {
  const s = setup();
  const res = await s.run({...body, outputLocale: "es-419"});
  eq(res.status, 200);
  const payload = JSON.stringify(s.bodies);
  eq(payload.includes("Latin American Spanish"), true);
  eq(payload.includes("Korean"), false);
  const unavailable = setup({key:false});
  const failure = await unavailable.run({...body, outputLocale:"es-419"});
  eq(failure.status,503);
  eq((await failure.json()).message.includes("configurado"),true);
});
Deno.test("Korean video draft labels uncertainty in Korean", async () => {
  const s = setup({
    result: { ...draft, title: "두부국", summary: "두부와 양파를 끓입니다." },
  });
  const res = await s.run({
    ...body,
    outputLocale: "ko-KR",
    selectedVideo: { ...body.selectedVideo, inferredRecipeTitle: "두부국" },
  });
  eq(res.status, 200);
  eq((await res.json()).data.ingredients[1].startsWith("[확인 필요]"), true);
});
for (const plan of ["free", "paid_annual", "paid_monthly"]) {
  Deno.test(`${plan} cannot cause any upstream video request`, async () => {
    const s = setup({ plan });
    const r = await s.run();
    eq(r.status, 403);
    eq(s.calls.length, 0);
    eq(s.finishes[0][1], false);
  });
}
for (const plan of ['plus_monthly','plus_annual','business_monthly','business_annual']) {
  Deno.test(`${plan} can use a server-authorized video reservation`, async () => {
    const s = setup({ plan });
    eq((await s.run()).status,200);
    eq(s.started(),1);
  });
}
Deno.test("no authentication and forged request fields rejected before reservation", async () => {
  const s = setup();
  eq((await s.run(body, false)).status, 401);
  eq((await s.run({ ...body, planCode: "paid_monthly" })).status, 400);
  eq(s.calls.length, 0);
  eq(s.finishes.length, 0);
});
Deno.test("monthly quota stops network before provider charges", async () => {
  const s = setup({ quota: true });
  eq((await s.run()).status, 429);
  eq(s.calls.length, 0);
});
for (
  const o of [{ duration: "PT20M1S" }, { privacy: "unlisted" }, {
    live: "live",
  }, { duration: "bad" }]
) {
  Deno.test(`server metadata rejects ${JSON.stringify(o)}`, async () => {
    const s = setup(o);
    eq((await s.run()).status, 400);
    eq(s.calls.length, 1);
    eq(s.started(), 0);
    eq(s.finishes[0][1], false);
  });
}
Deno.test("failed durable usage start prevents provider request", async () => {
  const s = setup({ startFailure: true });
  eq((await s.run()).status, 503);
  eq(s.calls.length, 1);
});
Deno.test("missing configuration does not fall back or charge analysis", async () => {
  const s = setup({ key: false });
  eq((await s.run()).status, 503);
  eq(s.calls.length, 0);
  eq(s.started(), 0);
});
for (
  const o of [{ blocked: true }, { result: {} }, {
    result: { ...draft, ingredients: [] },
  }]
) {
  Deno.test(`invalid/incomplete output cannot create successful draft ${JSON.stringify(o)}`, async () => {
    const s = setup(o);
    eq((await s.run()).status, 422);
    eq(s.finishes[0][1], false);
    eq(s.calls.length, 2);
  });
}
Deno.test("provider timeout is bounded, counted and never retried automatically", async () => {
  const s = setup({ timeout: true });
  eq((await s.run()).status, 504);
  eq(s.calls.length, 2);
  eq(s.started(), 1);
  eq(s.finishes[0][1], false);
});
Deno.test("bad timestamps cannot confirm measurements; duration boundaries", () => {
  const d = validateVideoEvidence({
    ...draft,
    ingredients: [{
      name: "Tofu",
      quantity: "10",
      unit: "kg",
      status: "confirmed",
      evidence: { timestampSeconds: 999, quote: "10kg" },
    }],
  }, 60)!;
  eq(
    (d.ingredients as { status: string; quantity: unknown }[])[0].status,
    "unverified",
  );
  eq((d.ingredients as { quantity: unknown }[])[0].quantity, null);
  eq(videoDuration("PT20M"), 1200);
  eq(videoDuration("PT20M1S"), null);
  eq(videoDuration("PT0S"), null);
});
