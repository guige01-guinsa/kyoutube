import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type YoutubeSearchItem = {
  videoId: string;
  title: string;
  channelTitle: string;
  publishedAt: string;
  thumbnailUrl: string;
  youtubeUrl: string;
  durationSec: number | null;
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET,OPTIONS",
};

const JSON_HEADERS = {
  "Content-Type": "application/json",
  ...CORS_HEADERS,
};

function okResponse(data: unknown, status = 200): Response {
  return new Response(
    JSON.stringify({
      status: "ok",
      data,
    }),
    {
      status,
      headers: JSON_HEADERS,
    },
  );
}

function errorResponse(
  status: number,
  errorCode: string,
  message: string,
  details: unknown = null,
): Response {
  return new Response(
    JSON.stringify({
      status: "error",
      errorCode,
      message,
      details,
    }),
    {
      status,
      headers: JSON_HEADERS,
    },
  );
}

function getEnv(name: string): string {
  return Deno.env.get(name) ?? "";
}

function getYoutubeApiKey(): string {
  return (getEnv("YOUTUBE_DATA_API_KEY") || getEnv("YOUTUBE_API_KEY")).trim();
}

function parseLimit(value: string | null): number {
  const parsed = Number(value ?? "5");
  if (!Number.isFinite(parsed)) {
    return 5;
  }

  const normalized = Math.trunc(parsed);
  if (normalized < 1) {
    return 1;
  }
  if (normalized > 10) {
    return 10;
  }
  return normalized;
}

function parseQuery(raw: string | null): string {
  const normalized = (raw ?? "").trim();
  if (normalized.length > 80) {
    return normalized.slice(0, 80);
  }
  return normalized;
}

function parseDurationSeconds(raw: string | undefined): number | null {
  if (!raw || !raw.startsWith("PT")) {
    return null;
  }

  const hours = /([0-9]+)H/.exec(raw);
  const minutes = /([0-9]+)M/.exec(raw);
  const seconds = /([0-9]+)S/.exec(raw);

  const h = hours ? Number(hours[1]) : 0;
  const m = minutes ? Number(minutes[1]) : 0;
  const s = seconds ? Number(seconds[1]) : 0;

  if (!Number.isFinite(h) || !Number.isFinite(m) || !Number.isFinite(s)) {
    return null;
  }

  return h * 3600 + m * 60 + s;
}

async function fetchYoutubeSearch(params: {
  apiKey: string;
  query: string;
  limit: number;
  hl: string;
  regionCode: string;
}): Promise<YoutubeSearchItem[]> {
  const searchUrl = new URL("https://www.googleapis.com/youtube/v3/search");
  searchUrl.searchParams.set("part", "snippet");
  searchUrl.searchParams.set("type", "video");
  searchUrl.searchParams.set("q", params.query);
  searchUrl.searchParams.set("maxResults", String(params.limit));
  searchUrl.searchParams.set("key", params.apiKey);
  searchUrl.searchParams.set("hl", params.hl);
  searchUrl.searchParams.set("regionCode", params.regionCode);

  const searchResponse = await fetch(searchUrl.toString(), {
    signal: AbortSignal.timeout(10000),
  });

  if (!searchResponse.ok) {
    const text = await searchResponse.text().catch(() => "");
    if (searchResponse.status === 403 || searchResponse.status === 429) {
      throw new Error(`quota_exceeded:${text}`);
    }
    throw new Error(`upstream_error:${searchResponse.status}:${text}`);
  }

  const searchPayload = await searchResponse.json();
  const rows = Array.isArray(searchPayload?.items)
    ? searchPayload.items
    : [];

  const videoIds = rows
    .map((item: Record<string, unknown>) => {
      const id = item.id as Record<string, unknown> | undefined;
      return String(id?.videoId ?? "").trim();
    })
    .filter((id: string) => id.length > 0);

  const durationById = new Map<string, number | null>();
  if (videoIds.length > 0) {
    const detailsUrl = new URL("https://www.googleapis.com/youtube/v3/videos");
    detailsUrl.searchParams.set("part", "contentDetails");
    detailsUrl.searchParams.set("id", videoIds.join(","));
    detailsUrl.searchParams.set("key", params.apiKey);

    const detailsResponse = await fetch(detailsUrl.toString(), {
      signal: AbortSignal.timeout(10000),
    });

    if (detailsResponse.ok) {
      const detailsPayload = await detailsResponse.json();
      const detailRows = Array.isArray(detailsPayload?.items)
        ? detailsPayload.items
        : [];

      for (const row of detailRows) {
        const item = row as Record<string, unknown>;
        const id = String(item.id ?? "").trim();
        const details = item.contentDetails as Record<string, unknown> | undefined;
        const duration = parseDurationSeconds(
          details?.duration ? String(details.duration) : undefined,
        );

        if (id.length > 0) {
          durationById.set(id, duration);
        }
      }
    }
  }

  return rows
    .map((item: Record<string, unknown>) => {
      const idPart = item.id as Record<string, unknown> | undefined;
      const snippet = item.snippet as Record<string, unknown> | undefined;

      const videoId = String(idPart?.videoId ?? "").trim();
      const title = String(snippet?.title ?? "").trim();
      const channelTitle = String(snippet?.channelTitle ?? "").trim();
      const publishedAt = String(snippet?.publishedAt ?? "").trim();
      const thumbnails = snippet?.thumbnails as Record<string, unknown> | undefined;
      const highThumb = thumbnails?.high as Record<string, unknown> | undefined;
      const mediumThumb = thumbnails?.medium as Record<string, unknown> | undefined;
      const defaultThumb = thumbnails?.default as Record<string, unknown> | undefined;
      const thumbnailUrl =
        String(highThumb?.url ?? "").trim() ||
        String(mediumThumb?.url ?? "").trim() ||
        String(defaultThumb?.url ?? "").trim();

      if (!videoId || !title) {
        return null;
      }

      return {
        videoId,
        title,
        channelTitle,
        publishedAt,
        thumbnailUrl,
        youtubeUrl: `https://www.youtube.com/watch?v=${videoId}`,
        durationSec: durationById.has(videoId) ? (durationById.get(videoId) ?? null) : null,
      } satisfies YoutubeSearchItem;
    })
    .filter((item: YoutubeSearchItem | null): item is YoutubeSearchItem => item !== null);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "GET") {
    return errorResponse(405, "method_not_allowed", "Use GET for youtube_search");
  }

  const apiKey = getYoutubeApiKey();
  if (apiKey.length === 0) {
    return errorResponse(500, "misconfigured", "YOUTUBE_DATA_API_KEY is not configured");
  }

  const url = new URL(req.url);
  const query = parseQuery(url.searchParams.get("q"));
  if (query.length < 1) {
    return errorResponse(400, "invalid_query", "q is required");
  }

  const limit = parseLimit(url.searchParams.get("limit"));
  const hl = (url.searchParams.get("hl") ?? "ko").trim() || "ko";
  const regionCode = (url.searchParams.get("regionCode") ?? "KR").trim() || "KR";

  try {
    const items = await fetchYoutubeSearch({
      apiKey,
      query,
      limit,
      hl,
      regionCode,
    });

    return okResponse({
      query,
      total: items.length,
      items,
    });
  } catch (error) {
    const message = String(error);

    if (message.includes("quota_exceeded:")) {
      return errorResponse(429, "quota_exceeded", "YouTube API quota exceeded");
    }

    if (message.includes("upstream_error:")) {
      return errorResponse(502, "upstream_error", "YouTube API error", message);
    }

    if (message.toLowerCase().includes("timeout")) {
      return errorResponse(504, "upstream_timeout", "YouTube API timeout");
    }

    return errorResponse(500, "internal_error", "Failed to search YouTube", message);
  }
});
