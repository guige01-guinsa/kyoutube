import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function extractVideoId(rawUrl: string): string | null {
  let uri: URL;

  try {
    uri = new URL(rawUrl.trim());
  } catch (_) {
    return null;
  }

  const host = uri.hostname.toLowerCase();

  if (host === "youtu.be" || host.endsWith(".youtu.be")) {
    const parts = uri.pathname.split("/").filter(Boolean);
    return parts.length === 0 ? null : parts[0];
  }

  const isYoutube =
    host === "youtube.com" || host.endsWith(".youtube.com");

  if (!isYoutube) {
    return null;
  }

  if (uri.pathname === "/watch") {
    return uri.searchParams.get("v");
  }

  const parts = uri.pathname.split("/").filter(Boolean);

  if (parts.length >= 2 && ["shorts", "embed", "live"].includes(parts[0])) {
    return parts[1];
  }

  return null;
}
function text(value: unknown, maxLength: number): string {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return response(
      {
        status: "error",
        message: "POST 요청만 사용할 수 있습니다.",
      },
      405,
    );
  }

  const authorization = request.headers.get("Authorization") ?? "";

  if (!authorization.startsWith("Bearer ")) {
    return response(
      {
        status: "error",
        message: "로그인이 필요합니다.",
      },
      401,
    );
  }

  const body = await request.json().catch(() => null);
  const youtubeUrl =
    body && typeof body === "object"
      ? text((body as Record<string, unknown>).youtubeUrl, 500)
      : "";

  const videoId = extractVideoId(youtubeUrl);

  if (!videoId || !/^[A-Za-z0-9_-]{6,30}$/.test(videoId)) {
    return response(
      {
        status: "error",
        message: "유효한 YouTube 영상 링크가 필요합니다.",
      },
      400,
    );
  }

  const apiKey = (Deno.env.get("YOUTUBE_DATA_API_KEY") ?? "").trim();

  if (!apiKey) {
    return response(
      {
        status: "error",
        message: "YouTube API 설정이 없습니다.",
      },
      503,
    );
  }

  const url = new URL("https://www.googleapis.com/youtube/v3/videos");
  url.searchParams.set("part", "snippet");
  url.searchParams.set("id", videoId);
  url.searchParams.set("key", apiKey);

  try {
    const upstream = await fetch(url, {
      signal: AbortSignal.timeout(12000),
    });

    if (upstream.status === 403 || upstream.status === 429) {
      return response(
        {
          status: "error",
          message: "YouTube API 사용량 제한에 도달했습니다.",
        },
        429,
      );
    }

    if (!upstream.ok) {
      return response(
        {
          status: "error",
          message: "YouTube 영상 정보를 불러오지 못했습니다.",
        },
        502,
      );
    }

    const payload = await upstream.json();
    const item = Array.isArray(payload?.items) ? payload.items[0] : null;
    const snippet = item?.snippet;

    if (!snippet) {
      return response(
        {
          status: "error",
          message: "YouTube 영상 정보를 찾지 못했습니다.",
        },
        404,
      );
    }

    return response({
      status: "ok",
      data: {
        videoId,
        title: text(snippet.title, 200),
        channelTitle: text(snippet.channelTitle, 160),
        description: text(snippet.description, 6000),
        youtubeUrl: `https://www.youtube.com/watch?v=${encodeURIComponent(videoId)}`,
        sourceType: "youtube_description",
      },
    });
  } catch (_) {
    return response(
      {
        status: "error",
        message: "YouTube 영상 설명란을 불러오지 못했습니다.",
      },
      502,
    );
  }
});