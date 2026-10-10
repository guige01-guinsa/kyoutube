import {
  createYoutubeRecipeAssistantHandler,
  extractRecipeDescription,
} from "./handler.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (actual !== expected) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
}

const validBody = {
  recipe: { title: "김치찌개", youtubeUrl: "https://youtu.be/abc123XYZ00" },
  selectedVideo: {
    videoId: "abc123XYZ00",
    youtubeUrl: "https://www.youtube.com/watch?v=abc123XYZ00",
    originalTitle: "집에서 만드는 맛있는 김치찌개",
    inferredRecipeTitle: "김치찌개",
    channelName: "요리 채널",
    description: "김치와 돼지고기를 이용한 조리 설명",
    durationSec: 179,
  },
};

const successFetch: typeof fetch = () =>
  Promise.resolve(
    new Response(
      JSON.stringify({
        choices: [{
          message: {
            content: JSON.stringify({
              title: "김치찌개",
              summary: "영상 설명 기반 초안",
              ingredients: [
                {
                  name: "김치",
                  quantity: "300",
                  unit: "g",
                  status: "confirmed",
                },
                {
                  name: "돼지고기",
                  quantity: "200",
                  unit: "g",
                  status: "confirmed",
                },
                {
                  name: "대파",
                  quantity: null,
                  unit: null,
                  status: "inferred",
                },
              ],
              steps: [
                {
                  instruction: "김치와 돼지고기를 손질한다",
                  status: "confirmed",
                },
                { instruction: "냄비에서 재료를 볶는다", status: "inferred" },
                { instruction: "물을 넣고 충분히 끓인다", status: "confirmed" },
              ],
              tips: null,
              warnings: ["영상 확인 필요"],
            }),
          },
        }],
      }),
      { status: 200 },
    ),
  );

const handler = createYoutubeRecipeAssistantHandler({
  getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
  fetchOpenAi: successFetch,
});

Deno.test("Spanish draft and repair both send Spanish system instructions", async () => {
  const systems: string[] = [];
  const run = createYoutubeRecipeAssistantHandler({
    getEnv: () => "test",
    fetchOpenAi: (_url, init) => {
      const payload = JSON.parse(String(init?.body));
      systems.push(payload.messages[0].content);
      return Promise.resolve(Response.json({choices:[{message:{content: JSON.stringify({
        title: "Sopa", summary: "Sopa de verduras", ingredients:[{name:"tomate",quantity:null,unit:null,status:"unverified"}],
        steps:[{instruction:"Cocinar",status:"unverified"}], tips:null,warnings:[],
      })}}]}));
    },
  });
  const res = await run(request({...validBody, outputLocale: "es-419"}));
  assertEquals(res.status, 422);
  assertEquals(systems.length, 2);
  for (const system of systems) {
    assertEquals(system.includes("Latin American Spanish"), true);
    assertEquals(system.includes("Korean"), false);
  }
  assertEquals((await res.json()).message.includes("borrador"), true);
});

function request(body: unknown) {
  return new Request("http://local/ai_youtube_recipe_assistant", {
    method: "POST",
    headers: {
      Authorization: "Bearer test",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

Deno.test("accepts a selectedVideo-only request", async () => {
  const response = await handler(request(validBody));
  assertEquals(response.status, 200);
  assertEquals((await response.json()).status, "ok");
});

Deno.test("removes advertising lines but keeps measured recipe evidence", () => {
  const cleaned = extractRecipeDescription(`
[재료]
김치 300g
유료 광고 포함: 구매 링크 https://shop.example/item
협찬 고춧가루 1큰술
대파 1대
  `);
  assertEquals(cleaned.recipeEvidence.includes("구매 링크"), false);
  assertEquals(cleaned.recipeEvidence.includes("김치 300g"), true);
  assertEquals(cleaned.recipeEvidence.includes("협찬"), false);
  assertEquals(cleaned.recipeEvidence.includes("고춧가루 1큰술"), true);
  assertEquals(cleaned.removedLineCount, 2);
});

Deno.test("removes English promotions and keeps English recipe evidence", () => {
  const cleaned = extractRecipeDescription(`
Ingredients
2 cups all-purpose flour
Paid partnership: shop now https://shop.example/item
Use my code DINNER20 for a discount
1 tbsp olive oil
Directions
Mix the flour and oil.
  `);
  assertEquals(cleaned.recipeEvidence.includes("Paid partnership"), false);
  assertEquals(cleaned.recipeEvidence.includes("DINNER20"), false);
  assertEquals(
    cleaned.recipeEvidence.includes("2 cups all-purpose flour"),
    true,
  );
  assertEquals(cleaned.recipeEvidence.includes("1 tbsp olive oil"), true);
  assertEquals(cleaned.removedLineCount, 2);
});

Deno.test("accepts a user-pasted transcript for the selected video", async () => {
  const response = await handler(request({
    ...validBody,
    selectedVideo: {
      ...validBody.selectedVideo,
      transcript: "김치를 썰고 돼지고기를 볶은 뒤 물을 넣고 끓입니다.",
      recipeNameHint: "돼지고기 김치찌개",
      ingredientHints: "김치, 돼지고기, 두부, 대파",
    },
  }));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.status, "ok");
  assertEquals(body.data.references[0].type, "user_transcript");
});

Deno.test("accepts a legacy request without durationSec", async () => {
  const legacyVideo = { ...validBody.selectedVideo } as Record<string, unknown>;
  delete legacyVideo.durationSec;
  const response = await handler(request({
    ...validBody,
    selectedVideo: legacyVideo,
  }));
  assertEquals(response.status, 200);
});

Deno.test("rejects public recipe references", async () => {
  const response = await handler(request({ ...validBody, references: [] }));
  assertEquals(response.status, 400);
});

Deno.test("rejects public recipe IDs inside the recipe payload", async () => {
  const response = await handler(request({
    ...validBody,
    recipe: { ...validBody.recipe, publicRecipeId: "public-1" },
  }));
  assertEquals(response.status, 400);
});

Deno.test("rejects mismatched YouTube videoId and URL", async () => {
  const response = await handler(request({
    ...validBody,
    selectedVideo: { ...validBody.selectedVideo, videoId: "different99" },
  }));
  assertEquals(response.status, 400);
});

Deno.test("rejects a recipe URL for a different selected video", async () => {
  const response = await handler(request({
    ...validBody,
    recipe: { ...validBody.recipe, youtubeUrl: "https://youtu.be/other123456" },
  }));
  assertEquals(response.status, 400);
});

Deno.test("enforces inferred title length of at most 10 characters", async () => {
  const response = await handler(request({
    ...validBody,
    selectedVideo: {
      ...validBody.selectedVideo,
      inferredRecipeTitle: "아주맛있는특별김치찌개",
    },
  }));
  assertEquals(response.status, 400);
});

Deno.test("rejects unsupported output locales", async () => {
  const response = await handler(request({
    ...validBody,
    outputLocale: "fr-FR",
  }));
  assertEquals(response.status, 400);
});

Deno.test("accepts Latin American Spanish output", async () => {
  const spanishHandler=createYoutubeRecipeAssistantHandler({
    getEnv:()=>"test",fetchOpenAi:()=>Promise.resolve(Response.json({choices:[{message:{content:JSON.stringify({
      title:"Sopa de kimchi",summary:"Sopa casera con kimchi y cerdo.",
      ingredients:["kimchi 300 g","cerdo 200 g"],steps:["Corta el kimchi y el cerdo.","Hierve los ingredientes en la olla."],warnings:[],
    })}}]})),
  });
  const response = await spanishHandler(request({
    ...validBody,
    outputLocale: "es-419",
    selectedVideo: {
      ...validBody.selectedVideo,
      inferredRecipeTitle: "Sopa de kimchi casera",
    },
  }));
  assertEquals(response.status, 200);
});

Deno.test("creates a structured US English draft for an English request", async () => {
  const upstreamBodies: Record<string, unknown>[] = [];
  const englishHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    fetchOpenAi: (_input, init) => {
      upstreamBodies.push(JSON.parse(String(init?.body)));
      return Promise.resolve(
        new Response(JSON.stringify({
          choices: [{
            message: {
              content: JSON.stringify({
                title: "One Pot Chicken Alfredo",
                summary: "A creamy weeknight pasta based on the video.",
                servings: 4,
                ingredients: [
                  {
                    name: "chicken breast",
                    quantity: "1",
                    unit: "lb",
                    status: "confirmed",
                  },
                  {
                    name: "fettuccine",
                    quantity: "12",
                    unit: "oz",
                    status: "confirmed",
                  },
                  {
                    name: "heavy cream",
                    quantity: "2",
                    unit: "cups",
                    status: "confirmed",
                  },
                ],
                steps: [
                  {
                    instruction: "Slice and season the chicken.",
                    status: "confirmed",
                  },
                  {
                    instruction: "Cook the chicken until browned.",
                    durationMinutes: 8,
                    status: "confirmed",
                  },
                  {
                    instruction: "Simmer the pasta in the cream sauce.",
                    status: "confirmed",
                  },
                ],
                tips: "Reserve a little pasta water for the sauce.",
                warnings: [],
              }),
            },
          }],
        })),
      );
    },
  });

  const response = await englishHandler(request({
    outputLocale: "en-US",
    recipe: {
      title: "One Pot Chicken Alfredo",
      youtubeUrl: "https://youtu.be/abc123XYZ00",
    },
    selectedVideo: {
      ...validBody.selectedVideo,
      originalTitle: "Easy One Pot Chicken Alfredo Dinner",
      inferredRecipeTitle: "One Pot Chicken Alfredo",
      channelName: "Home Kitchen",
      description:
        "Ingredients\n1 lb chicken breast\n12 oz fettuccine\n2 cups heavy cream\nDirections\nSlice the chicken. Brown it. Simmer the pasta in the sauce.",
    },
  }));
  const body = await response.json();
  const messages = upstreamBodies[0]?.messages as Array<Record<string, string>>;

  assertEquals(response.status, 200);
  assertEquals(body.data.title, "One Pot Chicken Alfredo");
  assertEquals(body.data.ingredients[0], "chicken breast 1 lb");
  assertEquals(
    body.data.steps[1],
    "Cook the chicken until browned. (about 8 min)",
  );
  assertEquals(messages[0]?.content.includes("US English"), true);
  assertEquals(messages[1]?.content.includes("outputLocale"), false);
  assertEquals(messages[1]?.content.includes("natural US English"), true);
});

Deno.test("accepts normal cooking videos and rejects videos over 60 minutes", async () => {
  const accepted = await handler(request({
    ...validBody,
    selectedVideo: { ...validBody.selectedVideo, durationSec: 1800 },
  }));
  assertEquals(accepted.status, 200);

  const response = await handler(request({
    ...validBody,
    selectedVideo: { ...validBody.selectedVideo, durationSec: 3601 },
  }));
  assertEquals(response.status, 400);
});

Deno.test("uses GPT-5.4 Mini with low reasoning by default", async () => {
  const upstreamBodies: Record<string, unknown>[] = [];
  const modelHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    fetchOpenAi: (_input, init) => {
      upstreamBodies.push(JSON.parse(String(init?.body)));
      return successFetch(_input, init);
    },
  });

  const response = await modelHandler(request(validBody));
  const upstreamBody = upstreamBodies[0];
  assertEquals(response.status, 200);
  assertEquals(upstreamBody?.["model"], "gpt-5.4-mini");
  assertEquals(upstreamBody?.["reasoning_effort"], "low");
  assertEquals(upstreamBody?.["max_completion_tokens"], 4000);
  assertEquals("temperature" in (upstreamBody ?? {}), false);
});

Deno.test("uses the server membership plan model and finalizes successful usage", async () => {
  const upstreamBodies: Record<string, unknown>[] = [];
  const finalizations: Array<Record<string, unknown>> = [];
  const membershipHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    reserveUsage: () =>
      Promise.resolve({
        id: "reservation-1",
        userId: "user-1",
        planCode: "free",
        recipeModel: "gpt-4o-mini",
      }),
    finishUsage: (reservation, succeeded, model) => {
      finalizations.push({ reservation, succeeded, model });
      return Promise.resolve();
    },
    fetchOpenAi: (_input, init) => {
      upstreamBodies.push(JSON.parse(String(init?.body)));
      return successFetch(_input, init);
    },
  });

  const response = await membershipHandler(request(validBody));
  assertEquals(response.status, 200);
  assertEquals(upstreamBodies[0]?.model, "gpt-4o-mini");
  assertEquals(finalizations.length, 1);
  assertEquals(finalizations[0]?.succeeded, true);
  assertEquals(finalizations[0]?.model, "gpt-4o-mini");
});

Deno.test("does not charge and records a draft missing ingredient measures", async () => {
  const finalizations: Array<Record<string, unknown>> = [];
  const incompleteDrafts: Array<Record<string, unknown>> = [];
  const incompleteHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    reserveUsage: () =>
      Promise.resolve({
        id: "reservation-incomplete",
        userId: "user-1",
        planCode: "free",
        recipeModel: "gpt-4o-mini",
      }),
    finishUsage: (reservation, succeeded) => {
      finalizations.push({ reservation, succeeded });
      return Promise.resolve();
    },
    saveIncompleteDraft: (details) => {
      incompleteDrafts.push(details);
      return Promise.resolve();
    },
    fetchOpenAi: () =>
      Promise.resolve(
        new Response(JSON.stringify({
          choices: [{
            message: {
              content: JSON.stringify({
                title: "김치찌개",
                summary: "계량이 부족한 초안",
                ingredients: [{
                  name: "김치",
                  quantity: null,
                  unit: null,
                  status: "unverified",
                }],
                steps: [{ instruction: "끓인다", status: "confirmed" }],
              }),
            },
          }],
        })),
      ),
  });

  const response = await incompleteHandler(request(validBody));
  const body = await response.json();
  assertEquals(response.status, 422);
  assertEquals(body.code, "ai_draft_incomplete");
  assertEquals(incompleteDrafts.length, 1);
  assertEquals(finalizations[0]?.succeeded, false);
});

Deno.test("returns a membership quota error before calling OpenAI", async () => {
  let upstreamCalls = 0;
  const quotaHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    reserveUsage: () =>
      Promise.reject({
        code: "ai_quota_monthly",
        status: 429,
        message: "이번 달에 사용할 수 있는 AI 초안 횟수를 모두 사용했습니다.",
      }),
    fetchOpenAi: (_input, init) => {
      upstreamCalls += 1;
      return successFetch(_input, init);
    },
  });

  const response = await quotaHandler(request(validBody));
  const body = await response.json();
  assertEquals(response.status, 429);
  assertEquals(body.code, "ai_quota_monthly");
  assertEquals(upstreamCalls, 0);
});

Deno.test("falls back to gpt-4o-mini when GPT-5.4 Mini access is denied", async () => {
  const upstreamBodies: Record<string, unknown>[] = [];
  const events: Array<Record<string, unknown>> = [];
  const fallbackHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    fetchOpenAi: (_input, init) => {
      upstreamBodies.push(JSON.parse(String(init?.body)));
      if (upstreamBodies.length === 1) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              error: {
                code: "model_not_allowed",
                type: "invalid_request_error",
              },
            }),
            {
              status: 403,
              headers: { "x-request-id": "req-primary" },
            },
          ),
        );
      }
      return successFetch(_input, init);
    },
    logError: (event) => events.push(event),
  });

  const response = await fallbackHandler(request(validBody));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.status, "ok");
  assertEquals(upstreamBodies.length, 2);
  assertEquals(upstreamBodies[0]?.["model"], "gpt-5.4-mini");
  assertEquals(upstreamBodies[0]?.["reasoning_effort"], "low");
  assertEquals(upstreamBodies[1]?.["model"], "gpt-4o-mini");
  assertEquals(upstreamBodies[1]?.["temperature"], 0.2);
  assertEquals("reasoning_effort" in upstreamBodies[1], false);
  assertEquals(events[1]?.event, "openai_recipe_model_fallback");
  assertEquals(events[1]?.primaryModel, "gpt-5.4-mini");
  assertEquals(events[1]?.fallbackModel, "gpt-4o-mini");
  assertEquals("apiKey" in events[1], false);
});

Deno.test("reports a model access error when fallback is also denied", async () => {
  const deniedHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => {
      if (name === "OPENAI_API_KEY") return "test-key";
      if (name === "OPENAI_RECIPE_FALLBACK_MODEL") return "gpt-5.4-mini";
      return undefined;
    },
    fetchOpenAi: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            error: {
              code: "model_not_allowed",
              type: "invalid_request_error",
            },
          }),
          { status: 403 },
        ),
      ),
    logError: () => {},
  });

  const response = await deniedHandler(request(validBody));
  const body = await response.json();
  assertEquals(response.status, 502);
  assertEquals(body.code, "ai_upstream_model_access_error");
  assertEquals(body.message, "AI 모델 접근 권한을 확인해야 합니다.");
});

Deno.test("ignores recipe models outside the approved two-model set", async () => {
  const upstreamBodies: Record<string, unknown>[] = [];
  const restrictedHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => {
      if (name === "OPENAI_API_KEY") return "test-key";
      if (name === "OPENAI_RECIPE_MODEL") return "gpt-5.6-terra";
      if (name === "OPENAI_RECIPE_FALLBACK_MODEL") return "gpt-5.6-sol";
      return undefined;
    },
    fetchOpenAi: (_input, init) => {
      upstreamBodies.push(JSON.parse(String(init?.body)));
      return successFetch(_input, init);
    },
  });

  const response = await restrictedHandler(request(validBody));
  assertEquals(response.status, 200);
  assertEquals(upstreamBodies[0]?.["model"], "gpt-5.4-mini");
});

Deno.test("returns structured ingredient evidence and cooking times", async () => {
  const structuredHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    fetchOpenAi: () =>
      Promise.resolve(
        new Response(JSON.stringify({
          choices: [{
            message: {
              content: JSON.stringify({
                title: "크림수프",
                summary: "영상 근거 초안",
                servings: 2,
                prepTimeMinutes: 5,
                cookTimeMinutes: 15,
                ingredients: [
                  {
                    name: "우유",
                    quantity: "300",
                    unit: "ml",
                    preparation: null,
                    status: "confirmed",
                  },
                  {
                    name: "양파",
                    quantity: "1/2",
                    unit: "개",
                    status: "confirmed",
                  },
                  {
                    name: "버터",
                    quantity: "10",
                    unit: "g",
                    status: "confirmed",
                  },
                ],
                steps: [
                  {
                    instruction: "우유를 넣고 끓인다",
                    durationMinutes: 5,
                    ingredientNames: ["우유"],
                    status: "confirmed",
                  },
                  { instruction: "양파를 버터에 볶는다", status: "confirmed" },
                  {
                    instruction: "재료를 섞어 부드럽게 끓인다",
                    status: "confirmed",
                  },
                ],
                tips: null,
                warnings: [],
              }),
            },
          }],
        })),
      ),
  });

  const response = await structuredHandler(request(validBody));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.servings, 2);
  assertEquals(body.data.ingredients[0], "우유 300 ml");
  assertEquals(body.data.steps[0], "우유를 넣고 끓인다 (약 5분)");
  assertEquals(body.data.ingredientDetails[0].status, "confirmed");
});

Deno.test("normalizes promotional inferred titles without rejecting the video", async () => {
  const response = await handler(request({
    ...validBody,
    selectedVideo: {
      ...validBody.selectedVideo,
      inferredRecipeTitle: "초간단김치찌개",
    },
  }));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.data.references[0].title, "김치찌개");
});

Deno.test("cleans promotional text from the model recipe title", async () => {
  const promotionalTitleFetch: typeof fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          choices: [{
            message: {
              content: JSON.stringify({
                title: "[대박] 무조건 구독! 초간단 김치찌개 레시피",
                summary: "영상 설명 기반 초안",
                ingredients: [
                  {
                    name: "김치",
                    quantity: "300",
                    unit: "g",
                    status: "confirmed",
                  },
                  {
                    name: "돼지고기",
                    quantity: "200",
                    unit: "g",
                    status: "confirmed",
                  },
                  {
                    name: "대파",
                    quantity: "1",
                    unit: "대",
                    status: "confirmed",
                  },
                ],
                steps: [
                  { instruction: "재료를 손질한다", status: "confirmed" },
                  {
                    instruction: "김치와 돼지고기를 볶는다",
                    status: "confirmed",
                  },
                  { instruction: "물을 넣고 끓인다", status: "confirmed" },
                ],
                tips: null,
                warnings: [],
              }),
            },
          }],
        }),
        { status: 200 },
      ),
    );
  const titleHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    fetchOpenAi: promotionalTitleFetch,
  });

  const response = await titleHandler(request(validBody));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.title, "김치찌개");
});

for (const ingredientStatus of ['confirmed','unverified']) Deno.test(`only confirmed ingredients can complete a draft without measures (${ingredientStatus})`, async () => {
  const finalizations: Array<Record<string, unknown>> = [];
  const thresholdHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    reserveUsage: () =>
      Promise.resolve({
        id: "reservation-threshold",
        userId: "user-1",
        planCode: "free",
        recipeModel: "gpt-4o-mini",
      }),
    finishUsage: (reservation, succeeded) => {
      finalizations.push({ reservation, succeeded });
      return Promise.resolve();
    },
    fetchOpenAi: () =>
      Promise.resolve(
        new Response(JSON.stringify({
          choices: [{
            message: {
              content: JSON.stringify({
                title: "채소볶음",
                summary: "계량 없이도 편집 가능한 초안",
                ingredients: [
                  {
                    name: "양파",
                    quantity: null,
                    unit: null,
                    status: ingredientStatus,
                  },
                  {
                    name: "당근",
                    quantity: null,
                    unit: null,
                    status: ingredientStatus,
                  },
                  {
                    name: "대파",
                    quantity: null,
                    unit: null,
                    status: ingredientStatus,
                  },
                ],
                steps: [
                  { instruction: "채소를 씻는다", status: "confirmed" },
                  { instruction: "먹기 좋게 썬다", status: "confirmed" },
                  { instruction: "팬에서 볶는다", status: "confirmed" },
                ],
                warnings: [],
              }),
            },
          }],
        })),
      ),
  });

  const response = await thresholdHandler(request(validBody));
  const body = await response.json();
  const accepted=ingredientStatus==='confirmed';
  assertEquals(response.status, accepted?200:422);
  assertEquals(body.status, accepted?'ok':'error');
  assertEquals(finalizations[0]?.succeeded, accepted);
  if(accepted)assertEquals(body.data.warnings.length > 0, true);
  else assertEquals(body.code,'ai_draft_incomplete');
});

Deno.test("reports and safely logs OpenAI quota errors", async () => {
  const events: Array<Record<string, unknown>> = [];
  const quotaHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    fetchOpenAi: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            error: { code: "insufficient_quota", type: "insufficient_quota" },
          }),
          {
            status: 429,
            headers: { "x-request-id": "req-test" },
          },
        ),
      ),
    logError: (event) => events.push(event),
  });

  const response = await quotaHandler(request(validBody));
  const body = await response.json();
  assertEquals(response.status, 502);
  assertEquals(body.code, "ai_upstream_quota_exceeded");
  assertEquals(
    body.message,
    "AI API 사용 한도 또는 결제 설정을 확인해야 합니다.",
  );
  assertEquals(events[0].status, 429);
  assertEquals(events[0].code, "insufficient_quota");
  assertEquals(events[0].requestId, "req-test");
  assertEquals("apiKey" in events[0], false);
});

Deno.test("distinguishes OpenAI authentication errors", async () => {
  let requestCount = 0;
  const authHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    fetchOpenAi: () => {
      requestCount += 1;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            error: { code: "invalid_api_key", type: "invalid_request_error" },
          }),
          { status: 401 },
        ),
      );
    },
    logError: () => {},
  });

  const response = await authHandler(request(validBody));
  const body = await response.json();
  assertEquals(response.status, 502);
  assertEquals(body.code, "ai_upstream_auth_error");
  assertEquals(body.message, "AI API 인증 설정을 확인해야 합니다.");
  assertEquals(requestCount, 1);
});
