import {
  addQualityWarnings,
  draftQualityIssues,
  normalizeRequest,
  parseModelOutput,
} from "../ai_youtube_recipe_assistant/handler.ts";
import type { AiUsageReservation } from "../_shared/membership.ts";
import {
  boundedRequest,
  RequestBoundaryError,
  secureResponse,
} from "../_shared/request_boundary.ts";

import { MODEL, videoGenerationBody } from "./request.ts";
import { localizedMessage, type OutputLocale } from "../_shared/output_locale.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};
const response = (body: unknown, status = 200) =>
  secureResponse(new Response(JSON.stringify(body), { status, headers }));
type Options = {
  getEnv: (name: string) => string | undefined;
  fetch?: typeof fetch;
  reserve: (authorization: string) => Promise<AiUsageReservation>;
  start: (reservation: AiUsageReservation, seconds: number) => Promise<void>;
  finish: (
    reservation: AiUsageReservation,
    succeeded: boolean,
    model: string,
    input: number,
    output: number,
    metadata: Record<string, unknown>,
  ) => Promise<void>;
};
class VideoError extends Error {
  constructor(readonly code: string, readonly status: number) {
    super(code);
  }
}
const messages: Record<string, [string, string]> = {
  video_membership_required: [
    "영상 분석은 플러스 또는 비즈니스 구독이 필요합니다.",
    "Video analysis requires Plus or Business.",
  ],
  video_quota_monthly: [
    "이번 달 요금제의 영상 분석 횟수를 모두 사용했습니다.",
    "You have reached your plan’s monthly video analysis limit.",
  ],
  video_not_available: [
    "20분 이내의 공개된 일반 YouTube 영상만 분석할 수 있습니다.",
    "Choose a public, non-live YouTube video up to 20 minutes long.",
  ],
  ai_not_configured: [
    "영상 분석 기능을 준비 중입니다. 기존 자동 초안을 이용해 주세요.",
    "Video analysis is not configured yet. Use the standard automatic draft.",
  ],
  invalid_request: [
    "영상 정보를 다시 선택해 주세요.",
    "Select the video again.",
  ],
  ai_draft_incomplete: [
    "영상에서 충분한 조리 정보를 확인하지 못했습니다. 설명·자막으로 다시 만들 수 있습니다.",
    "Not enough cooking evidence was found. Try the description or captions.",
  ],
  ai_request_failed: [
    "영상 분석을 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.",
    "Video analysis could not finish. Please try again later.",
  ],
  ai_request_timeout: [
    "영상 분석 시간이 초과되었습니다. 잠시 후 사용 내역을 확인해 주세요.",
    "Video analysis timed out. Check your usage shortly.",
  ],
  unauthorized: ["로그인이 필요합니다.", "Please sign in."],
};
const spanishMessages: Record<string, string> = {
  video_membership_required: "El análisis de video requiere Plus o Business.",
  video_quota_monthly: "Alcanzaste el límite mensual de análisis de video de tu plan.",
  video_not_available: "Elige un video público de YouTube, que no sea en vivo, de hasta 20 minutos.",
  ai_not_configured: "El análisis de video aún no está configurado. Usa el borrador automático estándar.",
  invalid_request: "Selecciona el video de nuevo.",
  ai_draft_incomplete: "No se encontró suficiente información de cocina. Prueba con la descripción o los subtítulos.",
  ai_request_failed: "No se pudo completar el análisis de video. Inténtalo más tarde.",
  ai_request_timeout: "El análisis de video agotó el tiempo de espera. Revisa tu uso en un momento.",
  unauthorized: "Inicia sesión.",
};
export function videoDuration(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const m = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(value);
  if (!m) return null;
  const n = Number(m[1] || 0) * 3600 + Number(m[2] || 0) * 60 +
    Number(m[3] || 0);
  return n > 0 && n <= 1200 ? n : null;
}

// All quantities/times require explicit evidence. Unknown fields stay null.
export function validateVideoEvidence(
  raw: unknown,
  seconds: number,
): Record<string, unknown> | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const d = structuredClone(raw) as Record<string, unknown>;
  if (!Array.isArray(d.ingredients) || !Array.isArray(d.steps)) return null;
  const evidenced = (v: unknown) => {
    if (!v || typeof v !== "object" || Array.isArray(v)) return false;
    const e = v as Record<string, unknown>;
    return typeof e.timestampSeconds === "number" &&
      Number.isFinite(e.timestampSeconds) && e.timestampSeconds >= 0 &&
      e.timestampSeconds < seconds && typeof e.quote === "string" &&
      e.quote.trim().length >= 2 && e.quote.length <= 400;
  };
  d.ingredients = d.ingredients.slice(0, 60).map((rawItem: unknown) => {
    const item =
      rawItem && typeof rawItem === "object" && !Array.isArray(rawItem)
        ? rawItem as Record<string, unknown>
        : { name: typeof rawItem === "string" ? rawItem : "" };
    const confirmed = item.status === "confirmed" && evidenced(item.evidence);
    return {
      ...item,
      quantity: confirmed ? item.quantity : null,
      unit: confirmed ? item.unit : null,
      status: confirmed ? "confirmed" : "unverified",
    };
  });
  d.steps = d.steps.slice(0, 40).map((rawItem: unknown) => {
    const item =
      rawItem && typeof rawItem === "object" && !Array.isArray(rawItem)
        ? rawItem as Record<string, unknown>
        : { instruction: typeof rawItem === "string" ? rawItem : "" };
    const confirmed = item.status === "confirmed" && evidenced(item.evidence);
    return {
      ...item,
      durationMinutes: confirmed ? item.durationMinutes : null,
      status: confirmed ? "confirmed" : "unverified",
    };
  });
  for (const field of ["servings", "prepTimeMinutes", "cookTimeMinutes"]) {
    if (
      !evidenced(
        (d.fieldEvidence as Record<string, unknown> | undefined)?.[field],
      )
    ) d[field] = null;
  }
  return d;
}

export function createVideoAssistantHandler(options: Options) {
  const transport = options.fetch ?? fetch;
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return response({});
    if (request.method !== "POST") {
      return response({ status: "error", code: "method_not_allowed" }, 405);
    }
    let locale: OutputLocale = "ko-KR";
    let reservation: AiUsageReservation | null = null,
      succeeded = false,
      inputTokens = 0,
      outputTokens = 0;
    let metadata: Record<string, unknown> = {
      provider: "gemini",
      usageKnown: false,
    };
    try {
      const authorization = request.headers.get("authorization") ?? "";
      if (!/^Bearer\s+\S+$/i.test(authorization)) {
        throw new VideoError("unauthorized", 401);
      }
      const bounded = await boundedRequest(request, 64 * 1024);
      const body = await bounded.json().catch(() => null);
      locale = body?.outputLocale === "es-419" ? "es-419"
        : body?.outputLocale === "en-US" ? "en-US" : "ko-KR";
      const input = normalizeRequest(body);
      if (!input) throw new VideoError("invalid_request", 400);
      // Authorization/quota is mandatory, never inferred from client plan flags.
      reservation = await options.reserve(authorization);
      if (!["plus_monthly","plus_annual","business_monthly","business_annual"].includes(reservation.planCode)) {
        throw new VideoError("video_membership_required", 403);
      }
      const key = (options.getEnv("GEMINI_API_KEY") ?? "").trim();
      const youtubeKey = (options.getEnv("YOUTUBE_DATA_API_KEY") ?? "").trim();
      if (
        !key || !youtubeKey ||
        options.getEnv("VIDEO_ANALYSIS_ENABLED") !== "true"
      ) throw new VideoError("ai_not_configured", 503);
      const url = new URL("https://www.googleapis.com/youtube/v3/videos");
      url.search = new URLSearchParams({
        part: "snippet,contentDetails,status",
        id: input.selectedVideo.videoId,
      }).toString();
      const videoResponse = await transport(url, {
        headers: { "X-Goog-Api-Key": youtubeKey },
        signal: AbortSignal.timeout(12000),
      });
      if (!videoResponse.ok) throw new VideoError("ai_request_failed", 502);
      const video = (await videoResponse.json())?.items?.[0];
      const seconds = videoDuration(video?.contentDetails?.duration);
      if (
        video?.id !== input.selectedVideo.videoId ||
        video?.status?.privacyStatus !== "public" ||
        video?.snippet?.liveBroadcastContent !== "none" || !seconds
      ) throw new VideoError("video_not_available", 400);
      const canonical =
        `https://www.youtube.com/watch?v=${input.selectedVideo.videoId}`;
      // Use server metadata, not forged descriptions, durations, or user hints.
      input.selectedVideo = {
        ...input.selectedVideo,
        originalTitle: String(video.snippet.title).slice(0, 200),
        channelName: String(video.snippet.channelTitle).slice(0, 160),
        youtubeUrl: canonical,
        description: String(video.snippet.description ?? "").slice(0, 10000),
        transcript: null,
        recipeNameHint: null,
        ingredientHints: null,
        durationSec: seconds,
      };
      await options.start(reservation, seconds);
      const upstream = await transport(
        `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": key,
          },
          signal: AbortSignal.timeout(90000),
          body: JSON.stringify(videoGenerationBody(canonical, input.outputLocale)),
        },
      );
      if (!upstream.ok) throw new VideoError("ai_request_failed", 502);
      const payload = await upstream.json();
      const usage = payload.usageMetadata;
      const tokens = (n: unknown) =>
        typeof n === "number" && Number.isSafeInteger(n) && n >= 0 ? n : 0;
      inputTokens = tokens(usage?.promptTokenCount);
      outputTokens = tokens(usage?.candidatesTokenCount) +
        tokens(usage?.thoughtsTokenCount);
      metadata = {
        provider: "gemini",
        usageKnown: Boolean(usage),
        promptTokenCount: inputTokens,
        candidatesTokenCount: tokens(usage?.candidatesTokenCount),
        thoughtsTokenCount: tokens(usage?.thoughtsTokenCount),
        promptTokensDetails: Array.isArray(usage?.promptTokensDetails)
          ? usage.promptTokensDetails.map((
            d: { modality?: unknown; tokenCount?: unknown },
          ) => ({
            modality: String(d.modality ?? "").slice(0, 20),
            tokenCount: tokens(d.tokenCount),
          }))
          : [],
      };
      const candidate = payload.candidates?.[0];
      if (candidate?.finishReason !== "STOP") {
        throw new VideoError("ai_draft_incomplete", 422);
      }
      const content = candidate.content?.parts?.filter((
        p: { thought?: boolean; text?: string },
      ) => !p.thought && typeof p.text === "string").map((
        p: { text: string },
      ) => p.text).join("") ?? "";
      let raw: unknown;
      try {
        raw = JSON.parse(content);
      } catch {
        throw new VideoError("ai_draft_incomplete", 422);
      }
      const evidence = validateVideoEvidence(raw, seconds);
      const result = evidence ? parseModelOutput(evidence, input) : null;
      if (!result || draftQualityIssues(result).length) {
        throw new VideoError("ai_draft_incomplete", 422);
      }
      addQualityWarnings(result, input.outputLocale);
      result.warnings.push(
        localizedMessage(locale,
          "AI 영상 분석에서 놓친 내용이 있을 수 있습니다. 분량·불 세기·조리 시간은 원본 영상과 확인해 주세요.",
          "AI video analysis can miss details. Verify quantities, heat and cooking times against the original video.",
          "La IA puede pasar por alto detalles del video. Verifica las cantidades, el fuego y los tiempos de cocción con el video original."),
      );
      succeeded = true;
      return response({
        status: "ok",
        data: {
          ...result,
          references: [{
            type: "youtube_video_analysis",
            title: result.title,
            channelName: input.selectedVideo.channelName,
            youtubeUrl: canonical,
          }],
        },
      });
    } catch (error) {
      const e = error as { code?: string; status?: number; name?: string };
      const code = e instanceof RequestBoundaryError
        ? e.code
        : e.name === "TimeoutError"
        ? "ai_request_timeout"
        : e.code ?? "ai_request_failed";
      const status = e instanceof RequestBoundaryError
        ? e.status
        : e.name === "TimeoutError"
        ? 504
        : e.status ?? 502;
      return response({
        status: "error",
        code,
        message: locale === "es-419"
          ? (spanishMessages[code] ?? spanishMessages.ai_request_failed)
          : (messages[code] ?? messages.ai_request_failed)[locale === "en-US" ? 1 : 0],
      }, status);
    } finally {
      if (reservation) {
        await options.finish(
          reservation,
          succeeded,
          MODEL,
          inputTokens,
          outputTokens,
          metadata,
        ).catch(() =>
          console.error(
            JSON.stringify({ event: "video_usage_finalization_failed" }),
          )
        );
      }
    }
  };
}
