export type SelectedVideo = {
  videoId: string;
  youtubeUrl: string;
  originalTitle: string;
  inferredRecipeTitle: string;
  channelName: string;
  description: string;
  durationSec: number | null;
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
    "durationSec",
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
    durationSec: typeof selectedSource.durationSec === "number"
      ? selectedSource.durationSec
      : null,
  };

  if (
    !recipe.title || !recipe.youtubeUrl || !selectedVideo.videoId ||
    !selectedVideo.youtubeUrl || !selectedVideo.originalTitle ||
    !selectedVideo.inferredRecipeTitle || !selectedVideo.channelName
  ) return null;
  if ([...selectedVideo.inferredRecipeTitle].length > 10) return null;
  if (
    selectedVideo.durationSec != null &&
    (!Number.isInteger(selectedVideo.durationSec) ||
      selectedVideo.durationSec < 1 || selectedVideo.durationSec > 180)
  ) return null;
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

function cleanRecipeTitle(value: unknown, fallback: string): string {
  const cleaned = text(value, 80)
    .replace(/[\[\(【].*?[\]\)】]/g, " ")
    .replace(
      /(초간단|대박|역대급|무조건|강력추천|필수시청|레전드|황금레시피|구독|좋아요|알림설정|만드는|만들기|레시피)/g,
      " ",
    )
    .replace(/[^가-힣A-Za-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  const normalized = cleaned || fallback.trim();
  return [...normalized].slice(0, 20).join("").trim();
}

function parseModelOutput(value: unknown, input: YoutubeEnrichmentRequest) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const source = value as Record<string, unknown>;
  const title = cleanRecipeTitle(
    source.title,
    input.selectedVideo.inferredRecipeTitle,
  );
  const summary = text(source.summary, 240);
  const ingredients = textList(source.ingredients, 60, 160);
  const steps = textList(source.steps, 40, 500);
  if (!title || !summary || ingredients.length === 0 || steps.length === 0) {
    return null;
  }
  return {
    title,
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
영상 제목·설명·채널·길이에서 확인 가능한 제목, 요약, 재료, 계량, 조리 순서, 시간, 팁을 최대한 채우세요.
제목은 음식명 중심으로 20자 이내로 추론하고 광고, 감탄, 홍보, 채널명, 특수문자를 제외하세요.
설명에 없는 계량, 시간, 비율을 사실처럼 만들지 말고 해당 항목은 warnings에 영상 확인 필요를 표시하세요.
재료나 조리 순서를 확인할 수 없으면 빈 배열 대신 "영상에서 확인 필요"라는 편집용 항목을 넣으세요.
결과는 자동 저장되지 않는 사용자 검토용 초안입니다.
반드시 아래 JSON 객체만 반환하세요.
{"title":"레시피 제목","summary":"240자 이하","ingredients":["재료와 계량"],"steps":["단계와 확인 가능한 시간"],"tips":"팁 또는 null","warnings":["사용자가 영상에서 확인할 항목"]}

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
        ? parseModelOutput(JSON.parse(raw), input)
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
