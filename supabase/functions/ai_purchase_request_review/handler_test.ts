import { classificationInput, parseClassification } from "./classification.ts";
import {
  parseInput,
  parseReview,
  reviewBody,
  ReviewError,
  reviewHandler,
  type Usage,
} from "./handler.ts";
function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const input = {
  language: "ko",
  currency: "KRW",
  lines: [{
    id: "a",
    name: "Carrot",
    spec: "1kg bag",
    unit: "bag",
    quantity: 2,
    price: null,
  }],
};
const result = {
  summary: "Check the quote.",
  checks: ["Confirm pack size."],
  suggestions: [{
    line_id: "a",
    name: "Carrots",
    spec: "1kg bag",
    reason: "Clearer wording.",
  }],
};
const output = (data: unknown = result, status = "completed") => ({
  status,
  usage: { input_tokens: 400, output_tokens: 100 },
  output: [{
    type: "message",
    content: [{ type: "output_text", text: JSON.stringify(data) }],
  }],
});
function setup(
  options: {
    output?: unknown;
    quota?: boolean;
    key?: boolean;
    failFetch?: boolean;
    failFinish?: boolean;
  } = {},
) {
  let calls = 0, reservations = 0;
  const finishes: { succeeded: boolean; usage: Usage }[] = [];
  let sent: Record<string, unknown> = {};
  const handler = reviewHandler({
    key: () => options.key === false ? undefined : "test-key",
    reserve: async () => {
      reservations++;
      if (options.quota) throw new ReviewError("ai_quota_daily", 429);
      return { id: "r", recipeModel: "gpt-4o-mini" };
    },
    finish: async (_, succeeded, usage) => {
      finishes.push({ succeeded, usage });
      if (options.failFinish) throw new Error("private detail");
    },
    fetch: ((_url: unknown, init: RequestInit) => {
      calls++;
      sent = JSON.parse(String(init.body));
      if (options.failFetch) throw new Error("private upstream detail");
      return Promise.resolve(Response.json(options.output ?? output()));
    }) as typeof fetch,
  });
  const request = (body: unknown = input, auth = "Bearer fake") =>
    handler(
      new Request("https://local.test", {
        method: "POST",
        headers: { authorization: auth },
        body: JSON.stringify(body),
      }),
    );
  return {
    request,
    handler,
    finishes,
    get calls() {
      return calls;
    },
    get reservations() {
      return reservations;
    },
    get sent() {
      return sent;
    },
  };
}
Deno.test("success uses restricted schema, no storage, no tools, one call and usage", async () => {
  const x = setup();
  const response = await x.request();
  assert(response.status === 200);
  assert((await response.json()).suggestions[0].line_id === "a");
  assert(x.calls === 1 && x.reservations === 1 && x.finishes.length === 1);
  assert(x.finishes[0].succeeded && x.finishes[0].usage.output === 100);
  assert(
    x.sent.store === false && x.sent.max_output_tokens === 3000 &&
      !("tools" in x.sent),
  );
  assert(response.headers.get("cache-control") === "no-store");
});
Deno.test("invalid auth, extra private fields, oversized body and too many items never reserve", async () => {
  const x = setup();
  assert((await x.request(input, "")).status === 401);
  assert((await x.request({ ...input, address: "private" })).status === 400);
  assert(
    (await x.request({
      ...input,
      lines: Array.from(
        { length: 21 },
        (_, i) => ({ ...input.lines[0], id: String(i) }),
      ),
    })).status === 400,
  );
  assert(
    (await x.request({ ...input, extra: "x".repeat(33000) })).status === 413,
  );
  assert(
    (await x.request({ ...input, lines: [input.lines[0], input.lines[0]] }))
      .status === 400,
  );
  assert(
    (await x.request({
      ...input,
      lines: [{ ...input.lines[0], quantity: -2 }],
    })).status === 400,
  );
  assert(x.calls === 0 && x.reservations === 0);
});
Deno.test("quota and missing key stop before any paid call", async () => {
  for (const options of [{ quota: true }, { key: false }]) {
    const x = setup(options);
    assert((await x.request()).status >= 400);
    assert(x.calls === 0);
  }
});
Deno.test("incomplete response records paid tokens, never retries", async () => {
  const x = setup({ output: output(result, "incomplete") });
  assert((await x.request()).status === 502);
  assert(x.calls === 1);
  assert(
    x.finishes.length === 1 && !x.finishes[0].succeeded &&
      x.finishes[0].usage.input === 400,
  );
});
Deno.test("reject foreign IDs, duplicate suggestions and injected price changes", async () => {
  for (
    const suggestions of [[{ ...result.suggestions[0], line_id: "foreign" }], [
      result.suggestions[0],
      result.suggestions[0],
    ], [{ ...result.suggestions[0], price: 1 }]]
  ) {
    const x = setup({ output: output({ ...result, suggestions }) });
    assert((await x.request()).status === 502);
    assert(!x.finishes[0].succeeded);
  }
});
Deno.test("refusals, malformed JSON and invalid text are not usable drafts", () => {
  const parsed = parseInput(input);
  for (
    const response of [output({ ...result, checks: ["x".repeat(301)] }), {
      status: "completed",
      output: [{ content: [{ type: "refusal" }] }],
    }, {
      status: "completed",
      output: [{ content: [{ type: "output_text", text: "{" }] }],
    }]
  ) {
    let rejected = false;
    try {
      parseReview(response, parsed);
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});
Deno.test("unknown price is accepted without inventing a number", () => {
  const parsed = parseInput(input);
  assert(parsed.lines[0].price === null);
  const body = reviewBody(parsed, "gpt-5.4-mini");
  assert("reasoning" in body && body.reasoning.effort === "low");
  assert(body.model === "gpt-5.4-mini");
});
Deno.test("provider or accounting failures return generic errors and preserve original workflow", async () => {
  for (const options of [{ failFetch: true }, { failFinish: true }]) {
    const x = setup(options);
    const response = await x.request();
    assert(response.status === 503);
    assert(!(await response.text()).includes("private"));
    assert(x.calls === 1);
  }
});
Deno.test("method and preflight do not consume usage", async () => {
  const x = setup();
  assert((await x.handler(new Request("https://local.test"))).status === 405);
  assert(
    (await x.handler(new Request("https://local.test", { method: "OPTIONS" })))
      .status === 200,
  );
  assert(x.reservations === 0);
});

Deno.test("exclude changed packaging facts but keep useful review checks", () => {
  const korean = parseInput({
    language: "ko",
    currency: "KRW",
    lines: [{
      id: "a",
      name: "양파",
      spec: "2kg망",
      unit: "망",
      quantity: 3,
      price: null,
    }],
  });
  const draft = parseReview(
    output({
      ...result,
      suggestions: [{
        line_id: "a",
        name: "양파",
        spec: "2kg 봉지",
        reason: "Uniform units",
      }],
    }),
    korean,
  );
  assert((draft.suggestions as unknown[]).length === 0);
  assert((draft.checks as string[]).some((s) => s.includes("제외")));
});
Deno.test("exclude changed quantities and measured units, accept unchanged facts with clearer spacing", () => {
  for (const spec of ["2kg bag", "1g bag", "1.5kg bag"]) {
    const draft = parseReview(
      output({ ...result, suggestions: [{ ...result.suggestions[0], spec }] }),
      parseInput(input),
    );
    assert((draft.suggestions as unknown[]).length === 0);
  }
  const draft = parseReview(
    output({
      ...result,
      suggestions: [{ ...result.suggestions[0], spec: "1 kg bag" }],
    }),
    parseInput(input),
  );
  assert((draft.suggestions as unknown[]).length === 1);
});

Deno.test("unchanged suggestions are omitted without a false safety warning", () => {
  const draft = parseReview(
    output({
      ...result,
      suggestions: [{ ...result.suggestions[0], name: "Carrot" }],
    }),
    parseInput(input),
  );
  assert((draft.suggestions as unknown[]).length === 0);
  assert((draft.checks as string[]).length === 1);
});

Deno.test("classification validates identities, coverage and category allowlist", () => {
  const items = classificationInput({
    task: "categorize",
    items: [{ id: "0", name: "손질 대파" }],
  });
  const valid = { categories: [{ id: "0", category: "produce" }] };
  assert(
    JSON.stringify(parseClassification(output(valid), items)) ===
      JSON.stringify(valid),
  );
  for (
    const bad of [
      { categories: [] },
      { categories: [{ id: "9", category: "produce" }] },
      { categories: [{ id: "0", category: "invented" }] },
      { categories: [{ id: "0", category: "produce", quantity: 10 }] },
    ]
  ) {
    let rejected = false;
    try {
      parseClassification(output(bad), items);
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});
Deno.test("classification shares authentication quota and usage accounting", async () => {
  const input = { task: "categorize", items: [{ id: "0", name: "손질 대파" }] };
  const s = setup({
    output: output({ categories: [{ id: "0", category: "produce" }] }),
  });
  assert((await s.request(input)).status === 200);
  assert(s.calls === 1 && s.finishes[0].succeeded);
  const quota = setup({ quota: true });
  assert((await quota.request(input)).status === 429 && quota.calls === 0);
  const unauth = setup();
  assert(
    (await unauth.request(input, "")).status === 401 && unauth.calls === 0,
  );
});
Deno.test("classification rejects excess data before a paid request", async () => {
  for (
    const body of [
      { task: "categorize", items: [{ id: "0", name: "대파", quantity: 10 }] },
      {
        task: "categorize",
        items: Array.from(
          { length: 21 },
          (_, i) => ({ id: String(i), name: "대파" }),
        ),
      },
      {
        task: "categorize",
        items: [{ id: "0", name: "대파" }, { id: "0", name: "무" }],
      },
    ]
  ) {
    const s = setup();
    assert((await s.request(body)).status === 400 && s.calls === 0);
  }
});
Deno.test("invalid AI classifications fail closed and still account for tokens", async () => {
  const s = setup({
    output: output({ categories: [{ id: "0", category: "bad" }] }),
  });
  const response = await s.request({
    task: "categorize",
    items: [{ id: "0", name: "대파" }],
  });
  assert(
    response.status === 502 && !s.finishes[0].succeeded &&
      s.finishes[0].usage.input === 400,
  );
});

Deno.test("AI ingredient matches only reference distinct existing IDs", () => {
  const items = classificationInput({
    task: "categorize",
    items: [{ id: "0", name: "대파" }, { id: "1", name: "손질 대파" }],
  });
  const categories = [{ id: "0", category: "produce" }, {
    id: "1",
    category: "produce",
  }];
  const valid = { categories, matches: [["0", "1"]] };
  assert(
    JSON.stringify(parseClassification(output(valid), items)) ===
      JSON.stringify(valid),
  );
  for (
    const matches of [[["0", "9"]], [["0", "0"]], [["0"]], [["0", "1"], [
      "0",
      "1",
    ]]]
  ) {
    let rejected = false;
    try {
      parseClassification(output({ categories, matches }), items);
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});
