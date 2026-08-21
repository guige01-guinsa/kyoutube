import { failure, success } from "./contract.ts";
import type { YoutubeSearchItem } from "./contract.ts";
import {
  type YoutubeSearchLocale,
  YoutubeUpstreamError,
} from "./youtube_client.ts";

export type YoutubeSearchClient = (request: {
  apiKey: string;
  query: string;
  limit: number;
  locale: YoutubeSearchLocale;
}) => Promise<YoutubeSearchItem[]>;

export type YoutubeSearchHandlerDependencies = {
  getEnv: (name: string) => string | undefined;
  searchYoutube: YoutubeSearchClient;
  logFailure?: (code: string, status: number) => void;
};

type LocaleProfile = {
  languageCode: string;
  defaultRegionCode: string;
  allowedRegionCodes: readonly string[];
  cookingQuerySuffix: string;
};

const localeProfiles: Record<string, LocaleProfile> = {
  ko: {
    languageCode: "ko",
    defaultRegionCode: "KR",
    allowedRegionCodes: ["KR"],
    cookingQuerySuffix: "요리 레시피",
  },
  en: {
    languageCode: "en",
    defaultRegionCode: "US",
    allowedRegionCodes: ["US", "GB", "CA", "AU", "SG"],
    cookingQuerySuffix: "cooking recipe",
  },
};

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

const jsonResponse = (body: unknown, status: number) =>
  new Response(
    JSON.stringify(body),
    {
      status,
      headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
    },
  );

const limitOf = (raw: string | null) => {
  const parsed = Number(raw ?? "5");
  return Number.isInteger(parsed) ? Math.max(1, Math.min(10, parsed)) : 5;
};

function localeOf(
  rawLanguage: string | null,
  rawRegion: string | null,
): YoutubeSearchLocale {
  const languageCode = (rawLanguage ?? "ko")
    .trim()
    .toLowerCase()
    .split("-")[0];

  // 출시 초기에는 ko/en만 허용한다.
  // 지원하지 않는 locale은 한국어 기본 profile로 안전하게 fallback한다.
  const profile = localeProfiles[languageCode] ?? localeProfiles.ko;

  const requestedRegion = (rawRegion ?? "")
    .trim()
    .toUpperCase();

  const regionCode = profile.allowedRegionCodes.includes(requestedRegion)
    ? requestedRegion
    : profile.defaultRegionCode;

  return {
    languageCode: profile.languageCode,
    regionCode,
    cookingQuerySuffix: profile.cookingQuerySuffix,
  };
}

export function createYoutubeSearchHandler(
  deps: YoutubeSearchHandlerDependencies,
) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: cors });
    }

    if (request.method !== "GET") {
      return jsonResponse(failure("youtube_http_405", 405), 405);
    }

    const apiKey =
      (deps.getEnv("YOUTUBE_DATA_API_KEY") ?? deps.getEnv("YOUTUBE_API_KEY") ??
        "").trim();

    if (!apiKey) {
      return jsonResponse(failure("youtube_config_missing", 500), 500);
    }

    const url = new URL(request.url);
    const query = (url.searchParams.get("q") ?? "").trim();

    if (query.length < 2 || query.length > 80) {
      return jsonResponse(failure("youtube_input_invalid", 400), 400);
    }

    const locale = localeOf(
      url.searchParams.get("lang"),
      url.searchParams.get("region"),
    );

    try {
      const items = await deps.searchYoutube({
        apiKey,
        query,
        limit: limitOf(url.searchParams.get("limit")),
        locale,
      });

      return jsonResponse(success(items), 200);
    } catch (caught) {
      const error = caught instanceof YoutubeUpstreamError
        ? caught
        : new YoutubeUpstreamError("transport");

      const [code, status] = error.kind === "timeout"
        ? ["youtube_timeout", 504]
        : error.kind === "quota"
        ? ["youtube_quota_exceeded", 429]
        : error.kind === "response"
        ? ["youtube_response_invalid", 502]
        : error.kind === "http"
        ? [`youtube_http_${error.status}`, 502]
        : ["youtube_transport_error", 502];

      deps.logFailure?.(code, status);

      return jsonResponse(failure(code, status), status);
    }
  };
}
