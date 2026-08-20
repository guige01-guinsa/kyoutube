import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createYoutubeSearchHandler,
  type YoutubeSearchClient,
} from "./handler.ts";
import { YoutubeUpstreamError } from "./youtube_client.ts";
const req = (q = "pasta", limit?: string) =>
  new Request(
    `http://local/youtube_search?q=${q}${limit ? `&limit=${limit}` : ""}`,
  );
const result = {
  videoId: "abc",
  title: "T",
  channelTitle: "C",
  publishedAt: "2026-01-01T00:00:00Z",
  thumbnailUrl: "https://img",
  youtubeUrl: "https://youtube.test",
  durationSec: null,
};
const handler = (searchYoutube: YoutubeSearchClient, key = "test-key") =>
  createYoutubeSearchHandler({
    getEnv: (name) => name === "YOUTUBE_DATA_API_KEY" ? key : undefined,
    searchYoutube,
  });
Deno.test("missing key and invalid input are safe", async () => {
  assertEquals((await handler(async () => [], "")(req())).status, 500);
  assertEquals((await handler(async () => [])(req("x"))).status, 400);
});
Deno.test("maps canonical response and clamps limit", async () => {
  let receivedLimit = 0;
  const response = await handler(async ({ limit }) => {
    receivedLimit = limit;
    return [result];
  })(req("pasta", "99"));
  assertEquals(response.status, 200);
  assertEquals(receivedLimit, 10);
  assertEquals((await response.json()).status, "ok");
});
Deno.test("JSON responses declare UTF-8 and preserve Korean strings", async () => {
  const korean = { ...result, title: "김치찌개", channelTitle: "요리 채널" };
  const response = await handler(async () => [korean])(req());
  assertEquals(
    response.headers.get("content-type"),
    "application/json; charset=utf-8",
  );
  const body = await response.json();
  assertEquals(body.data.items[0].title, "김치찌개");
  assertEquals(body.data.items[0].channelTitle, "요리 채널");
});
Deno.test("typed failures are safe", async () => {
  assertEquals(
    (await handler(async () => {
      throw new YoutubeUpstreamError("response");
    })(req())).status,
    502,
  );
  assertEquals(
    (await handler(async () => {
      throw new YoutubeUpstreamError("quota", 403);
    })(req())).status,
    429,
  );
});
Deno.test("timeout response and safe error body contain no secret values", async () => {
  const response = await handler(async () => {
    throw new YoutubeUpstreamError("timeout");
  }, "private-key")(req("private-query"));
  const body = await response.text();
  assertEquals(response.status, 504);
  assert(
    !body.includes("private-query") && !body.includes("private-key") &&
      !body.includes("private-url"),
  );
});
