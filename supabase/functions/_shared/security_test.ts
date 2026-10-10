import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { AccessError, authenticatedUser, fetchWithTimeout } from "./http.ts";
import { recipeApiHandler } from "../recipe_api/handler.ts";
import { youtubeContextHandler } from "../youtube_recipe_context/handler.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const otherId = "22222222-2222-4222-8222-222222222222";
async function isolated(work: () => Promise<void>) {
  const original = globalThis.fetch;
  const values = {
    SUPABASE_URL: "https://unit.invalid",
    SUPABASE_ANON_KEY: "unit-anon",
    SUPABASE_SERVICE_ROLE_KEY: "unit-service",
    YOUTUBE_DATA_API_KEY: "unit-youtube",
  };
  const previous = new Map(
    Object.keys(values).map((k) => [k, Deno.env.get(k)]),
  );
  for (const [key, value] of Object.entries(values)) Deno.env.set(key, value);
  try {
    await work();
  } finally {
    globalThis.fetch = original;
    for (const [key, value] of previous) {
      value === undefined ? Deno.env.delete(key) : Deno.env.set(key, value);
    }
  }
}
function request(
  path: string,
  method = "GET",
  body?: unknown,
  token = "unit-user",
) {
  return new Request("https://unit.invalid/functions/v1/" + path, {
    method,
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
Deno.test("metadata rejects anon and anonymous users before any billed YouTube call", () =>
  isolated(async () => {
    for (
      const auth of [
        new Response("{}", { status: 401 }),
        Response.json({ id: userId, is_anonymous: true }),
      ]
    ) {
      let billed = 0;
      globalThis.fetch = ((input: string | URL | Request) => {
        const url = String(input);
        if (url.includes("/auth/v1/user")) return Promise.resolve(auth);
        if (url.includes("googleapis")) billed++;
        return Promise.resolve(new Response(null, { status: 204 }));
      }) as typeof fetch;
      const result = await youtubeContextHandler(
        request("youtube_recipe_context", "POST", {
          youtubeUrl: "https://www.youtube.com/watch?v=6QQ67F8y2b8",
        }, "unit-anon"),
      );
      assertEquals(result.status, 401);
      assertEquals(billed, 0);
    }
  }));
Deno.test("metadata authenticated user receives matching video metadata", () =>
  isolated(async () => {
    globalThis.fetch = ((input: string | URL | Request) => {
      const url = String(input);
      if (url.includes("/auth/v1/user")) {
        return Promise.resolve(Response.json({ id: userId }));
      }
      if (url.includes("googleapis")) {
        return Promise.resolve(
          Response.json({
            items: [{
              id: "6QQ67F8y2b8",
              snippet: {
                title: "Bibimbap",
                description: "Cook rice",
                channelTitle: "Chef",
              },
              contentDetails: { duration: "PT3M" },
            }],
          }),
        );
      }
      return Promise.resolve(new Response(null, { status: 204 }));
    }) as typeof fetch;
    const result = await youtubeContextHandler(
      request("youtube_recipe_context", "POST", {
        youtubeUrl: "https://www.youtube.com/watch?v=6QQ67F8y2b8",
      }),
    );
    assertEquals(result.status, 200);
    assertEquals((await result.text()).includes("Bibimbap"), true);
  }));
Deno.test("authentication outage is unavailable, not a valid user or expired login", () =>
  isolated(async () => {
    globalThis.fetch = (() =>
      Promise.resolve(new Response(null, { status: 503 }))) as typeof fetch;
    const error = await assertRejects(() =>
      authenticatedUser(request("test")), AccessError);
    assertEquals(error.status, 503);
  }));
Deno.test("bounded transport aborts a hung call and preserves caller cancellation", () =>
  isolated(async () => {
    let calls = 0;
    globalThis.fetch = ((_input: unknown, init: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        calls++;
        const signal = init.signal!;
        if (signal.aborted) {
          reject(signal.reason);
        } else {signal.addEventListener("abort", () =>
            reject(signal.reason), {
            once: true,
          });}
      })) as typeof fetch;
    await assertRejects(() =>
      fetchWithTimeout("https://unit.invalid", {}, 10)
    );
    const controller = new AbortController();
    controller.abort();
    await assertRejects(() =>
      fetchWithTimeout(
        "https://unit.invalid",
        { signal: controller.signal },
        100,
      )
    );
    assertEquals(calls, 2); // No automatic duplicate write/retry.
  }));
Deno.test("creator saves are private and upstream database detail never reaches clients", () =>
  isolated(async () => {
    let fail = false;
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(String(input));
      if (url.pathname.includes("/auth/v1/user")) {
        return Promise.resolve(Response.json({ id: userId }));
      }
      if (url.pathname.endsWith("/profiles")) {
        return Promise.resolve(Response.json([{ id: userId }]));
      }
      if (url.pathname.endsWith("/ops_events")) {
        return Promise.resolve(new Response(null, { status: 204 }));
      }
      if (fail) {
        return Promise.resolve(
          new Response("private_row_data internal_sql_detail", { status: 500 }),
        );
      }
      if (init?.method === "POST") {
        const payload = JSON.parse(String(init.body));
        assertEquals(payload.is_published, false);
        assertEquals(payload.author_id, userId);
        return Promise.resolve(Response.json([{ id: otherId, ...payload }]));
      }
      assertEquals(url.searchParams.get("author_id"), "eq." + userId);
      return Promise.resolve(Response.json([]));
    }) as typeof fetch;
    const created = await recipeApiHandler(
      request("recipe_api?type=creator", "POST", {
        title: "Private",
        is_published: true,
        ingredients: ["Rice"],
        steps: ["Cook"],
      }),
    );
    assertEquals(created.status, 201);
    const missing = await recipeApiHandler(
      request("recipe_api/" + otherId + "?type=creator"),
    );
    assertEquals(missing.status, 404);
    const invalid = await recipeApiHandler(
      request("recipe_api?type=creator", "POST", {
        title: "x".repeat(121),
        ingredients: [],
        steps: [],
      }),
    );
    assertEquals(invalid.status, 400);
    fail = true;
    const failed = await recipeApiHandler(request("recipe_api?type=creator"));
    assertEquals(failed.status, 500);
    const body = await failed.json();
    assertEquals(body.details, null);
    assertEquals(JSON.stringify(body).includes("private_row_data"), false);
  }));
Deno.test("creator mutation cannot alter another owner", () =>
  isolated(async () => {
    let writes = 0;
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      if (url.includes("/auth/v1/user")) {
        return Promise.resolve(Response.json({ id: userId }));
      }
      if (url.includes("/ops_events")) {
        return Promise.resolve(new Response(null, { status: 204 }));
      }
      if (init?.method === "PATCH" || init?.method === "DELETE") writes++;
      return Promise.resolve(
        Response.json([{ id: otherId, author_id: otherId }]),
      );
    }) as typeof fetch;
    for (const method of ["PATCH", "DELETE"]) {
      const result = await recipeApiHandler(
        request(
          "recipe_api/" + otherId + "?type=creator",
          method,
          method === "PATCH"
            ? { title: "No", ingredients: [], steps: [] }
            : undefined,
        ),
      );
      assertEquals(result.status, 403);
    }
    assertEquals(writes, 0);
  }));
