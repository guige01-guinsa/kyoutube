import { createYoutubeRecipeAssistantHandler } from "./handler.ts";

function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error(`${actual} !== ${expected}`);
}

const source = {
  outputLocale: "en-US",
  recipe: { title: "Banana milk", youtubeUrl: "https://youtu.be/abc123XYZ00" },
  selectedVideo: {
    videoId: "abc123XYZ00",
    youtubeUrl: "https://youtu.be/abc123XYZ00",
    originalTitle: "초간단 Banana milk",
    inferredRecipeTitle: "초간단 Banana milk",
    channelName: "Test kitchen",
    durationSec: 120,
    description:
      "Blend 1 banana with 200 ml milk. Peel the banana. Blend with milk.",
  },
};
const draft = {
  title: "Banana milk",
  summary: "Banana blended with milk.",
  ingredients: [
    { name: "banana", quantity: "1", unit: "piece", status: "confirmed" },
    { name: "milk", quantity: "200", unit: "ml", status: "confirmed" },
  ],
  steps: [
    { instruction: "Peel the banana.", status: "confirmed" },
    { instruction: "Blend with milk.", status: "confirmed" },
  ],
  warnings: [],
};
function request(body: unknown) {
  return new Request("https://local.test/draft", {
    method: "POST",
    headers: {
      Authorization: "Bearer test",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}
function fixture(outputs: unknown[]) {
  let calls = 0;
  let charged: boolean | null = null;
  let prompts = "";
  const handler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    reserveUsage: async () => ({
      id: "test",
      userId: "test",
      planCode: "free",
      recipeModel: "gpt-4o-mini",
    }),
    finishUsage: async (_, succeeded) => {
      charged = succeeded;
    },
    fetchOpenAi: async (_, init) => {
      prompts += String(init?.body);
      const output = outputs[Math.min(calls++, outputs.length - 1)];
      return new Response(
        JSON.stringify({
          choices: [{ message: { content: JSON.stringify(output) } }],
        }),
      );
    },
  });
  return { handler, state: () => ({ calls, charged, prompts }) };
}

Deno.test("legacy English requests normalize Korean promotional title words", async () => {
  const f = fixture([draft]);
  const response = await f.handler(request(source));
  equal(response.status, 200);
  equal(f.state().calls, 1);
  const body = await response.json();
  equal(body.data.references[0].title, "Banana milk");
});

Deno.test("two ingredient two step recipe succeeds without invented filler or repair", async () => {
  const f = fixture([draft]);
  const response = await f.handler(request(source));
  equal(response.status, 200);
  const body = await response.json();
  equal(body.data.ingredientDetails.length, 2);
  equal(body.data.stepDetails.length, 2);
  equal(f.state().calls, 1);
  equal(f.state().charged, true);
});

for (
  const [name, broken] of [
    ["empty summary", { ...draft, summary: "" }],
    ["duplicate ingredients", {
      ...draft,
      ingredients: [
        draft.ingredients[0],
        draft.ingredients[0],
        draft.ingredients[0],
      ],
    }],
    ["duplicate steps", {
      ...draft,
      steps: [draft.steps[0], draft.steps[0], draft.steps[0]],
    }],
  ] as const
) {
  Deno.test(`repairs ${name} before marking a draft successful`, async () => {
    const f = fixture([broken, draft]);
    const response = await f.handler(request(source));
    equal(response.status, 200);
    equal(f.state().calls, 2);
    equal(f.state().charged, true);
    const body = await response.json();
    equal(body.data.summary, draft.summary);
    equal(body.data.ingredientDetails.length, 2);
    equal(body.data.stepDetails.length, 2);
  });
}

Deno.test("persistent incomplete output is not charged or marked successful", async () => {
  const f = fixture([{ ...draft, summary: "" }]);
  const response = await f.handler(request(source));
  equal(response.status, 422);
  equal(f.state().calls, 2);
  equal(f.state().charged, false);
});

Deno.test("mismatched video identity stays rejected with an English error", async () => {
  const f = fixture([draft]);
  const response = await f.handler(
    request({
      ...source,
      selectedVideo: { ...source.selectedVideo, videoId: "other123456" },
    }),
  );
  equal(response.status, 400);
  const body = await response.json();
  equal(body.code, "invalid_selected_video");
  equal(/[가-힣]/.test(body.message), false);
  equal(f.state().calls, 0);
});
