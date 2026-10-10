import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  boundedRequest,
  RequestBoundaryError,
  secureResponse,
} from "./request_boundary.ts";
import { observeHttp } from "./operations.ts";

Deno.test("body boundary preserves UTF-8 JSON and authentication", async () => {
  const json = JSON.stringify({ title: "비빔밥", steps: ["Mix"] });
  const original = new Request("https://test.invalid", {
    method: "POST",
    body: json,
    headers: {
      Authorization: "Bearer test",
      "Content-Type": "application/json",
    },
  });
  const bounded = await boundedRequest(original);
  assertEquals(await bounded.text(), json);
  assertEquals(bounded.headers.get("Authorization"), "Bearer test");
});

Deno.test("oversized body is refused even with absent or forged content length", async () => {
  for (const headers of [new Headers(), new Headers({ "Content-Length": "1" })]) {
    let canceled = false;
    const stream = new ReadableStream<Uint8Array>({
      start(c) {
        c.enqueue(new Uint8Array(9));
      },
      cancel() {
        canceled = true;
      },
    });
    const error = await assertRejects(
      () =>
        boundedRequest(
          new Request("https://test.invalid", {
            method: "POST",
            headers,
            body: stream,
          }),
          8,
        ),
      RequestBoundaryError,
    );
    assertEquals(error.status, 413);
    assertEquals(canceled, true);
  }
});

Deno.test("declared oversize rejects before handler or billed work", async () => {
  let calls = 0;
  const handler = observeHttp("membership", () => {
    calls++;
    return Response.json({});
  }, { record: async () => {}, log: () => {} });
  const response = await handler(
    new Request("https://test.invalid", {
      method: "POST",
      headers: { "Content-Length": "999999999" },
      body: "{}",
    }),
  );
  assertEquals(response.status, 413);
  assertEquals(calls, 0);
  assertEquals((await response.json()).code, "request_too_large");
  assertEquals(response.headers.get("cache-control"), "no-store");
});

Deno.test("slow request stream is canceled by the read deadline", async () => {
  let canceled = false;
  const request = new Request("https://test.invalid", {
    method: "POST",
    body: new ReadableStream({
      cancel() {
        canceled = true;
      },
    }),
  });
  const error = await assertRejects(
    () => boundedRequest(request, 8, 10),
    RequestBoundaryError,
  );
  assertEquals(error.status, 408);
  assertEquals(canceled, true);
});

Deno.test("caller cancellation aborts body processing", async () => {
  const controller = new AbortController();
  const request = new Request("https://test.invalid", {
    method: "POST",
    signal: controller.signal,
    body: new ReadableStream(),
  });
  controller.abort();
  const error = await assertRejects(
    () => boundedRequest(request, 8, 100),
    RequestBoundaryError,
  );
  assertEquals(error.code, "request_aborted");
});

Deno.test("exact size is accepted and oversized URL is rejected", async () => {
  const result = await boundedRequest(
    new Request("https://test.invalid", { method: "POST", body: "12345678" }),
    8,
  );
  assertEquals(await result.text(), "12345678");
  const error = await assertRejects(
    () =>
      boundedRequest(new Request("https://test.invalid/" + "x".repeat(8192))),
    RequestBoundaryError,
  );
  assertEquals(error.status, 414);
});

Deno.test("cache guard retains CORS, status and response body", async () => {
  const response = secureResponse(
    new Response("private", {
      status: 201,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "public, max-age=3600",
      },
    }),
  );
  assertEquals(response.status, 201);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(response.headers.get("X-Content-Type-Options"), "nosniff");
  assertEquals(await response.text(), "private");
});
