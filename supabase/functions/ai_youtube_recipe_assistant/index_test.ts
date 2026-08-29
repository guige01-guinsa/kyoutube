import { createYoutubeRecipeAssistantHandler } from "./handler.ts";

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
              ingredients: ["김치"],
              steps: ["끓인다"],
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

Deno.test("rejects a selected video longer than 180 seconds", async () => {
  const response = await handler(request({
    ...validBody,
    selectedVideo: { ...validBody.selectedVideo, durationSec: 181 },
  }));
  assertEquals(response.status, 400);
});

Deno.test("rejects promotional inferred titles", async () => {
  const response = await handler(request({
    ...validBody,
    selectedVideo: {
      ...validBody.selectedVideo,
      inferredRecipeTitle: "초간단김치찌개",
    },
  }));
  assertEquals(response.status, 400);
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
                ingredients: ["김치"],
                steps: ["끓인다"],
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

Deno.test("reports and safely logs OpenAI quota errors", async () => {
  const events: Array<Record<string, unknown>> = [];
  const quotaHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    fetchOpenAi: () => Promise.resolve(new Response(JSON.stringify({
      error: { code: "insufficient_quota", type: "insufficient_quota" },
    }), {
      status: 429,
      headers: { "x-request-id": "req-test" },
    })),
    logError: (event) => events.push(event),
  });

  const response = await quotaHandler(request(validBody));
  const body = await response.json();
  assertEquals(response.status, 502);
  assertEquals(body.code, "ai_upstream_quota_exceeded");
  assertEquals(body.message, "AI API 사용 한도 또는 결제 설정을 확인해야 합니다.");
  assertEquals(events[0].status, 429);
  assertEquals(events[0].code, "insufficient_quota");
  assertEquals(events[0].requestId, "req-test");
  assertEquals("apiKey" in events[0], false);
});

Deno.test("distinguishes OpenAI authentication errors", async () => {
  const authHandler = createYoutubeRecipeAssistantHandler({
    getEnv: (name) => name === "OPENAI_API_KEY" ? "test-key" : undefined,
    fetchOpenAi: () => Promise.resolve(new Response(JSON.stringify({
      error: { code: "invalid_api_key", type: "invalid_request_error" },
    }), { status: 401 })),
    logError: () => {},
  });

  const response = await authHandler(request(validBody));
  const body = await response.json();
  assertEquals(response.status, 502);
  assertEquals(body.code, "ai_upstream_auth_error");
  assertEquals(body.message, "AI API 인증 설정을 확인해야 합니다.");
});
