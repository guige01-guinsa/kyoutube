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
const maxCookingDurationSec = 180;
const searchCandidateMinimum = 12;
const searchCandidateMaximum = 25;

const asRecord = (value: unknown): Record<string, unknown> | null =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;

const text = (value: unknown): string | null =>
  typeof value === "string" && value.trim() ? value.trim() : null;

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
    } catch (error) {
      if (error instanceof DOMException && error.name === "TimeoutError") {
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

    if (response.status === 403) {
      throw new YoutubeUpstreamError("quota", 403);
    }

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

function durationSeconds(value: string | null): number | null {
  if (value == null) {
    return null;
  }

  const match = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(value);

  if (match == null) {
    return null;
  }

  const hours = Number(match[1] ?? "0");
  const minutes = Number(match[2] ?? "0");
  const seconds = Number(match[3] ?? "0");

  if (
    !Number.isFinite(hours) ||
    !Number.isFinite(minutes) ||
    !Number.isFinite(seconds)
  ) {
    return null;
  }

  return (hours * 3600) + (minutes * 60) + seconds;
}

type SearchCandidate = {
  videoId: string;
  title: string;
  channelTitle: string;
  publishedAt: string;
  thumbnailUrl: string;
};

function candidateLimit(limit: number): number {
  return Math.min(
    Math.max(limit * 3, searchCandidateMinimum),
    searchCandidateMaximum,
  );
}

function cookingRecipeQuery(query: string): string {
  return `${query} 요리 레시피`;
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
  const searchUrl = new URL(
    "https://www.googleapis.com/youtube/v3/search",
  );

  for (
    const [key, value] of Object.entries({
      part: "snippet",
      type: "video",
      q: cookingRecipeQuery(query),
      maxResults: String(candidateLimit(limit)),
      videoCategoryId: "26",
      videoDuration: "short",
      relevanceLanguage: "ko",
      regionCode: "KR",
      key: apiKey,
    })
  ) {
    searchUrl.searchParams.set(key, value);
  }

  const searchPayload = asRecord(
    await request(fetcher, searchUrl, sleep, timeoutSignal),
  );

  if (!searchPayload || !Array.isArray(searchPayload.items)) {
    throw new YoutubeUpstreamError("response");
  }

  const candidates = searchPayload.items.map((raw): SearchCandidate => {
    const item = asRecord(raw);
    const id = asRecord(item?.id);
    const snippet = asRecord(item?.snippet);
    const thumbnails = asRecord(snippet?.thumbnails);

    const thumbnail = asRecord(thumbnails?.high) ??
      asRecord(thumbnails?.medium) ??
      asRecord(thumbnails?.default);

    const videoId = text(id?.videoId);
    const title = text(snippet?.title);
    const channelTitle = text(snippet?.channelTitle);
    const publishedAt = text(snippet?.publishedAt);
    const thumbnailUrl = text(thumbnail?.url);

    if (!videoId || !title || !channelTitle || !publishedAt || !thumbnailUrl) {
      throw new YoutubeUpstreamError("response");
    }

    return {
      videoId,
      title,
      channelTitle,
      publishedAt,
      thumbnailUrl,
    };
  });

  if (candidates.length === 0) {
    return [];
  }

  const detailsUrl = new URL(
    "https://www.googleapis.com/youtube/v3/videos",
  );

  for (
    const [key, value] of Object.entries({
      part: "contentDetails",
      id: candidates.map((candidate) => candidate.videoId).join(","),
      key: apiKey,
    })
  ) {
    detailsUrl.searchParams.set(key, value);
  }

  const detailsPayload = asRecord(
    await request(fetcher, detailsUrl, sleep, timeoutSignal),
  );

  if (!detailsPayload || !Array.isArray(detailsPayload.items)) {
    throw new YoutubeUpstreamError("response");
  }

  const durationByVideoId = new Map<string, number>();

  for (const raw of detailsPayload.items) {
    const item = asRecord(raw);
    const videoId = text(item?.id);
    const contentDetails = asRecord(item?.contentDetails);

    const seconds = durationSeconds(text(contentDetails?.duration));

    if (
      videoId != null &&
      seconds != null &&
      seconds <= maxCookingDurationSec
    ) {
      durationByVideoId.set(videoId, seconds);
    }
  }

  return candidates
    .filter((candidate) => durationByVideoId.has(candidate.videoId))
    .slice(0, limit)
    .map((candidate): YoutubeSearchItem => ({
      videoId: candidate.videoId,
      title: candidate.title,
      channelTitle: candidate.channelTitle,
      publishedAt: candidate.publishedAt,
      thumbnailUrl: candidate.thumbnailUrl,
      youtubeUrl: `https://www.youtube.com/watch?v=${
        encodeURIComponent(candidate.videoId)
      }`,
      durationSec: durationByVideoId.get(candidate.videoId) ?? null,
    }));
}
