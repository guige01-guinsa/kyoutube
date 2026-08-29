export type SelectedVideo = {
  videoId: string;
  youtubeUrl: string;
  originalTitle: string;
  inferredRecipeTitle: string;
  channelName: string;
  description: string;
};

type YoutubeRecipeInput = {
  title: string;
  youtubeUrl: string;
};

type YoutubeEnrichmentRequest = {
  recipe: YoutubeRecipeInput;
  selectedVideo: SelectedVideo;
};

type HandlerOptions = {
  getEnv: (name: string) => string | undefined;
  fetchOpenAi?: typeof fetch;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function text(value: unknown, maxLength: number): string {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function textList(
  value: unknown,
  maxItems: number,
  maxLength: number,
): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => text(item, maxLength))
    .filter(Boolean)
    .slice(0, maxItems);
}

export function extractYoutubeVideoId(rawUrl: string): string | null {
  let url: URL;
  try {
    url = new URL(rawUrl.trim());
  } catch (_) {
    return null;
  }

  const host = url.hostname.toLowerCase();
  let videoId: string | null = null;
  if (host === "youtu.be" || host.endsWith(".youtu.be")) {
    videoId = url.pathname.split("/").filter(Boolean)[0] ?? null;
  } else if (host === "youtube.com" || host.endsWith(".youtube.com")) {
    if (url.pathname === "/watch") {
      videoId = url.searchParams.get("v");
    } else {
      const parts = url.pathname.split("/").filter(Boolean);
      if (parts.length >= 2 && ["shorts", "embed", "live"].includes(parts[0])) {
        videoId = parts[1];
      }
    }
  }

  return videoId && /^[A-Za-z0-9_-]{6,30}$/.test(videoId) ? videoId : null;
}

function normalizeRequest(value: unknown): YoutubeEnrichmentRequest | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;

  const forbiddenKeys = [
    "references",
    "referenceRecipeIds",
    "referenceRecipeId",
    "publicRecipeIds",
    "publicRecipeId",
  ];
  if (forbiddenKeys.some((key) => key in body)) return null;
  if (
    Object.keys(body).some((key) => !["recipe", "selectedVideo"].includes(key))
  ) {
    return null;
  }

  if (
    !body.recipe || typeof body.recipe !== "object" ||
    Array.isArray(body.recipe)
  ) {
    return null;
  }
  if (
    !body.selectedVideo || typeof body.selectedVideo !== "object" ||
    Array.isArray(body.selectedVideo)
  ) {
    return null;
  }

  const recipeSource = body.recipe as Record<string, unknown>;
  const selectedSource = body.selectedVideo as Record<string, unknown>;
  if (
    Object.keys(recipeSource).some((key) =>
      !["title", "youtubeUrl"].includes(key)
    )
  ) return null;
  const selectedKeys = [
    "videoId",
    "youtubeUrl",
    "originalTitle",
    "inferredRecipeTitle",
    "channelName",
    "description",
  ];
  if (Object.keys(selectedSource).some((key) => !selectedKeys.includes(key))) {
    return null;
  }
  const recipe = {
    title: text(recipeSource.title, 120),
    youtubeUrl: text(recipeSource.youtubeUrl, 500),
  };
  const selectedVideo = {
    videoId: text(selectedSource.videoId, 30),
    youtubeUrl: text(selectedSource.youtubeUrl, 500),
    originalTitle: text(selectedSource.originalTitle, 200),
    inferredRecipeTitle: text(selectedSource.inferredRecipeTitle, 40),
    channelName: text(selectedSource.channelName, 160),
    description: text(selectedSource.description, 6000),
  };

  if (
    !recipe.title || !recipe.youtubeUrl ||
    Object.values(selectedVideo).some((item) => !item)
  ) return null;
  if ([...selectedVideo.inferredRecipeTitle].length > 10) return null;
  if (
    /(초간단|대박|역대급|무조건|강력추천|필수시청|레전드|황금레시피)/.test(
      selectedVideo.inferredRecipeTitle,
    )
  ) return null;

  const recipeVideoId = extractYoutubeVideoId(recipe.youtubeUrl);
  const selectedUrlVideoId = extractYoutubeVideoId(selectedVideo.youtubeUrl);
  if (
    !recipeVideoId || !selectedUrlVideoId ||
    recipeVideoId !== selectedUrlVideoId ||
    selectedVideo.videoId !== selectedUrlVideoId
  ) {
    return null;
  }

  return { recipe, selectedVideo };
}

function parseModelOutput(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const source = value as Record<string, unknown>;
  const summary = text(source.summary, 240);
  const ingredients = textList(source.ingredients, 60, 160);
  const steps = textList(source.steps, 40, 500);
  if (!summary || ingredients.length === 0 || steps.length === 0) return null;
  return {
    summary,
    ingredients,
    steps,
    tips: text(source.tips, 500) || null,
    warnings: textList(source.warnings, 10, 240),
  };
}

function prompt(input: YoutubeEnrichmentRequest): string {
  return `
당신은 한국어 레시피 편집 보조 AI입니다.
오직 사용자가 선택한 한 개의 YouTube 영상 정보와 설명만 사용하세요.
공공 레시피, 다른 영상, 외부 자료, 자막 또는 댓글을 사용하지 마세요.
설명에 없는 계량, 시간, 비율을 사실처럼 만들지 말고 warnings에 영상 확인 필요를 표시하세요.
결과는 자동 저장되지 않는 사용자 검토용 초안입니다.
반드시 아래 JSON 객체만 반환하세요.
{"summary":"240자 이하","ingredients":["재료"],"steps":["단계"],"tips":null,"warnings":["주의"]}

현재 레시피: ${JSON.stringify(input.recipe)}
선택된 영상: ${JSON.stringify(input.selectedVideo)}
  `.trim();
}

export function createYoutubeRecipeAssistantHandler(options: HandlerOptions) {
  const fetchOpenAi = options.fetchOpenAi ?? fetch;

  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (request.method !== "POST") {
      return jsonResponse({
        status: "error",
        code: "method_not_allowed",
        message: "POST 요청만 지원합니다.",
      }, 405);
    }
    const authorization = (request.headers.get("Authorization") ?? "").trim();
    if (!authorization.startsWith("Bearer ")) {
      return jsonResponse({
        status: "error",
        code: "unauthorized",
        message: "로그인이 필요합니다.",
      }, 401);
    }

    const input = normalizeRequest(await request.json().catch(() => null));
    if (!input) {
      return jsonResponse({
        status: "error",
        code: "invalid_selected_video",
        message: "선택한 YouTube 영상 정보가 올바르지 않습니다.",
      }, 400);
    }

    const apiKey = (options.getEnv("OPENAI_API_KEY") ?? "").trim();
    const model = (options.getEnv("OPENAI_RECIPE_MODEL") ?? "gpt-4o-mini")
      .trim();
    if (!apiKey) {
      return jsonResponse({
        status: "error",
        code: "ai_not_configured",
        message: "AI 기능이 아직 설정되지 않았습니다.",
      }, 503);
    }

    try {
      const upstream = await fetchOpenAi(
        "https://api.openai.com/v1/chat/completions",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${apiKey}`,
          },
          body: JSON.stringify({
            model,
            temperature: 0.2,
            response_format: { type: "json_object" },
            messages: [
              {
                role: "system",
                content:
                  "Create safe Korean recipe drafts from exactly one selected YouTube video description.",
              },
              { role: "user", content: prompt(input) },
            ],
          }),
        },
      );
      if (!upstream.ok) {
        return jsonResponse({
          status: "error",
          code: "ai_upstream_error",
          message: "AI 레시피 보강을 지금 처리할 수 없습니다.",
        }, 502);
      }
      const payload = await upstream.json().catch(() => null);
      const raw = payload?.choices?.[0]?.message?.content;
      const result = typeof raw === "string"
        ? parseModelOutput(JSON.parse(raw))
        : null;
      if (!result) {
        return jsonResponse({
          status: "error",
          code: "ai_response_invalid",
          message: "AI 응답 형식이 올바르지 않습니다.",
        }, 502);
      }
      return jsonResponse({
        status: "ok",
        data: {
          ...result,
          references: [{
            type: "youtube_description",
            title: input.selectedVideo.inferredRecipeTitle,
            channelName: input.selectedVideo.channelName,
            youtubeUrl: input.selectedVideo.youtubeUrl,
          }],
        },
      });
    } catch (_) {
      return jsonResponse({
        status: "error",
        code: "ai_request_failed",
        message: "AI 레시피 보강 중 오류가 발생했습니다.",
      }, 502);
    }
  };
}
