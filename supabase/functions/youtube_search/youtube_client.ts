import type { YoutubeSearchItem } from "./contract.ts";

export class YoutubeUpstreamError extends Error {
  constructor(
    readonly kind: "timeout" | "quota" | "http" | "transport" | "response",
    readonly status?: number,
    readonly retryAfterMs?: number,
  ) {
    super(kind);
  }
}
export type FetchLike = (
  input: string,
  init?: RequestInit,
) => Promise<Response>;
export type Sleep = (milliseconds: number) => Promise<void>;
export type TimeoutSignalFactory = (milliseconds: number) => AbortSignal;
const timeoutMs = 12000;
const asRecord = (v: unknown): Record<string, unknown> | null =>
  v !== null && typeof v === "object" && !Array.isArray(v)
    ? v as Record<string, unknown>
    : null;
const text = (v: unknown): string | null =>
  typeof v === "string" && v.trim() ? v.trim() : null;

async function request(
  fetcher: FetchLike,
  url: URL,
  sleep: Sleep,
  timeoutSignal: TimeoutSignalFactory,
): Promise<unknown> {
  for (let attempt = 0; attempt < 2; attempt++) {
    let response: Response;
    try {
      response = await fetcher(url.toString(), {
        signal: timeoutSignal(timeoutMs),
      });
    } catch (e) {
      if (e instanceof DOMException && e.name === "TimeoutError") {
        throw new YoutubeUpstreamError("timeout");
      }
      throw new YoutubeUpstreamError("transport");
    }
    if (response.ok) {
      try {
        return await response.json();
      } catch (_) {
        throw new YoutubeUpstreamError("response");
      }
    }
    if (response.status === 403) throw new YoutubeUpstreamError("quota", 403);
    const retryable = response.status === 429 || response.status >= 500;
    if (retryable && attempt === 0) {
      const seconds = Number(response.headers.get("retry-after"));
      if (Number.isFinite(seconds) && seconds > 0) {
        await sleep(Math.min(seconds * 1000, 2000));
      }
      continue;
    }
    throw new YoutubeUpstreamError(
      response.status === 429 ? "quota" : "http",
      response.status,
    );
  }
  throw new YoutubeUpstreamError("transport");
}
export async function searchYoutube({
  apiKey,
  query,
  limit,
  fetcher = fetch,
  sleep = (milliseconds: number) =>
    new Promise<void>((resolve) => setTimeout(resolve, milliseconds)),
  timeoutSignal = AbortSignal.timeout,
}: {
  apiKey: string;
  query: string;
  limit: number;
  fetcher?: FetchLike;
  sleep?: Sleep;
  timeoutSignal?: TimeoutSignalFactory;
}): Promise<YoutubeSearchItem[]> {
  const url = new URL("https://www.googleapis.com/youtube/v3/search");
  for (
    const [k, v] of Object.entries({
      part: "snippet",
      type: "video",
      q: query,
      maxResults: String(limit),
      key: apiKey,
    })
  ) url.searchParams.set(k, v);
  const payload = asRecord(await request(fetcher, url, sleep, timeoutSignal));
  if (!payload || !Array.isArray(payload.items)) {
    throw new YoutubeUpstreamError("response");
  }
  return payload.items.map((raw): YoutubeSearchItem => {
    const item = asRecord(raw);
    const id = asRecord(item?.id);
    const snippet = asRecord(item?.snippet);
    const thumbnails = asRecord(snippet?.thumbnails);
    const thumbnail = asRecord(thumbnails?.high) ??
      asRecord(thumbnails?.medium) ?? asRecord(thumbnails?.default);
    const videoId = text(id?.videoId),
      title = text(snippet?.title),
      channelTitle = text(snippet?.channelTitle),
      publishedAt = text(snippet?.publishedAt),
      thumbnailUrl = text(thumbnail?.url);
    if (!videoId || !title || !channelTitle || !publishedAt || !thumbnailUrl) {
      throw new YoutubeUpstreamError("response");
    }
    return {
      videoId,
      title,
      channelTitle,
      publishedAt,
      thumbnailUrl,
      youtubeUrl: `https://www.youtube.com/watch?v=${
        encodeURIComponent(videoId)
      }`,
      durationSec: null,
    };
  });
}
