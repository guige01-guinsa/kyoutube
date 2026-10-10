import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { searchYoutube } from "./youtube_client.ts";

const neverTimeout = () => new AbortController().signal;

const searchPayload = {
  items: [
    {
      id: { videoId: "short-video" },
      snippet: {
        title: "김치찌개 3분 레시피",
        channelTitle: "요리 채널",
        publishedAt: "2026-01-01T00:00:00Z",
        thumbnails: { high: { url: "https://thumbnail.test/short" } },
      },
    },
    {
      id: { videoId: "long-video" },
      snippet: {
        title: "김치찌개 긴 레시피",
        channelTitle: "요리 채널",
        publishedAt: "2026-01-01T00:00:00Z",
        thumbnails: { high: { url: "https://thumbnail.test/long" } },
      },
    },
    {
      id: { videoId: "missing-duration" },
      snippet: {
        title: "시간 정보 없는 레시피",
        channelTitle: "요리 채널",
        publishedAt: "2026-01-01T00:00:00Z",
        thumbnails: { high: { url: "https://thumbnail.test/missing" } },
      },
    },
    {
      id: { videoId: "advertisement-video" },
      snippet: {
        title: "김치찌개 먹방 광고",
        channelTitle: "광고 채널",
        description: "협찬 상품 리뷰",
        publishedAt: "2026-01-01T00:00:00Z",
        thumbnails: { high: { url: "https://thumbnail.test/ad" } },
      },
    },
  ],
};

const detailsPayload = {
  items: [
    {
      id: "short-video",
      contentDetails: { duration: "PT2M59S" },
    },
    {
      id: "long-video",
      contentDetails: { duration: "PT3M1S" },
    },
    {
      id: "advertisement-video",
      contentDetails: { duration: "PT30S" },
    },
  ],
};

Deno.test("429 and 5xx retry once, while other 4xx do not retry", async () => {
  for (const status of [429, 500, 400]) {
    let calls = 0;

    await assertRejects(
      () =>
        searchYoutube({
          apiKey: "test-key",
          query: "test-query",
          limit: 5,
          fetcher: async () => {
            calls++;
            return new Response("private-body", { status });
          },
          sleep: async () => {},
          timeoutSignal: neverTimeout,
        }),
    );

    assertEquals(calls, status === 400 ? 1 : 2);
  }
});

Deno.test("returns embeddable cooking candidates at or under 60 minutes", async () => {
  const requestedUrls: URL[] = [];

  const items = await searchYoutube({
    apiKey: "test-key",
    query: "김치찌개",
    limit: 5,
    fetcher: async (input) => {
      const url = new URL(input);
      requestedUrls.push(url);

      if (url.pathname.endsWith("/search")) {
        return Response.json(searchPayload);
      }

      if (url.pathname.endsWith("/videos")) {
        return Response.json(detailsPayload);
      }

      return new Response("unexpected request", { status: 500 });
    },
    sleep: async () => {},
    timeoutSignal: neverTimeout,
  });

  assertEquals(requestedUrls.length, 2);

  const searchUrl = requestedUrls[0];
  assertEquals(searchUrl.searchParams.get("q"), "김치찌개 요리 레시피");
  assertEquals(searchUrl.searchParams.get("type"), "video");
  assertEquals(searchUrl.searchParams.get("videoCategoryId"), null);
  assertEquals(searchUrl.searchParams.get("videoDuration"), null);
  assertEquals(searchUrl.searchParams.get("videoEmbeddable"), "true");
  assertEquals(searchUrl.searchParams.get("safeSearch"), "moderate");
  assertEquals(searchUrl.searchParams.get("relevanceLanguage"), "ko");
  assertEquals(searchUrl.searchParams.get("regionCode"), "KR");
  assertEquals(searchUrl.searchParams.get("maxResults"), "20");

  const detailsUrl = requestedUrls[1];
  assertEquals(detailsUrl.searchParams.get("part"), "contentDetails");
  assertEquals(
    detailsUrl.searchParams.get("id"),
    "short-video,long-video,missing-duration,advertisement-video",
  );

  assertEquals(items.length, 2);
  assertEquals(items[0].videoId, "short-video");
  assertEquals(items[0].durationSec, 179);
  assertEquals(items[1].videoId, "long-video");
  assertEquals(items[1].durationSec, 181);
});

Deno.test("returns an empty list when every candidate exceeds 60 minutes", async () => {
  const items = await searchYoutube({
    apiKey: "test-key",
    query: "파스타",
    limit: 5,
    fetcher: async (input) => {
      const url = new URL(input);

      if (url.pathname.endsWith("/search")) {
        return Response.json(searchPayload);
      }

      return Response.json({
        items: [
          {
            id: "short-video",
            contentDetails: { duration: "PT1H1S" },
          },
          {
            id: "long-video",
            contentDetails: { duration: "PT2H" },
          },
        ],
      });
    },
    sleep: async () => {},
    timeoutSignal: neverTimeout,
  });

  assertEquals(items, []);
});
