import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { searchYoutube } from "./youtube_client.ts";

const payload = {
  items: [{
    id: { videoId: "video-id" },
    snippet: {
      title: "title",
      channelTitle: "channel",
      publishedAt: "2026-01-01T00:00:00Z",
      thumbnails: { high: { url: "https://thumbnail.test" } },
    },
  }],
};

const neverTimeout = () => new AbortController().signal;

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

Deno.test("maps a canonical upstream response without network access", async () => {
  const items = await searchYoutube({
    apiKey: "test-key",
    query: "test-query",
    limit: 5,
    fetcher: async () => Response.json(payload),
    sleep: async () => {},
    timeoutSignal: neverTimeout,
  });
  assertEquals(items[0].durationSec, null);
  assertEquals(items[0].videoId, "video-id");
});
