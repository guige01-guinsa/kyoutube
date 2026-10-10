import { recipeApiHandler } from "./handler.ts";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

const endpoint =
  "https://edge.example.invalid/functions/v1/recipe_api?type=kitchen";
const key = "66000000-0000-4000-8000-000000000001";

Deno.test("shopping list preserves manual specifications and recipe item compatibility", async () => {
  const owner = "66000000-0000-4000-8000-000000000010";
  const list = "66000000-0000-4000-8000-000000000011";
  await withBackend(async (input) => {
    const url = new URL(String(input));
    if (url.pathname === "/auth/v1/user") return Response.json({id: owner, is_anonymous: false});
    if (url.pathname === "/rest/v1/ops_events") return new Response(null, {status: 204});
    if (url.pathname === "/rest/v1/kitchen_shopping_lists") {
      assert(url.searchParams.get("owner_id") === `eq.${owner}`, "Owner filter required");
      return Response.json([{id: list, owner_id: owner, status: "active", title: "Manual ingredients", source_recipe_id: null}]);
    }
    assert(url.pathname === "/rest/v1/kitchen_shopping_items", "Unexpected backend call");
    assert(url.searchParams.get("select")?.includes("purchase_specification"), "Specification is queried");
    assert(url.searchParams.get("owner_id") === `eq.${owner}`, "Items remain owner scoped");
    return Response.json([
      {id: "manual",list_id:list,name:"soy sauce",ingredient_text:"soy sauce 2 bottles",purchase_specification:"1L per bottle",quantity:2,unit:"bottle",status:"pending",review_status:"confirmed",is_checked:false,revision:0,updated_at:"2026-09-30T00:00:00Z"},
      {id: "recipe",list_id:list,name:"carrot",ingredient_text:"carrot 500g",quantity:500,unit:"g",status:"pending",review_status:"confirmed",is_checked:false,revision:0,updated_at:"2026-09-30T00:00:00Z"},
    ]);
  }, async () => {
    const response = await recipeApiHandler(new Request(`${endpoint}&view=shopping-lists`, {headers:{Authorization:"Bearer test-user-token"}}));
    assert(response.status === 200, "List read succeeds");
    const json = await response.json();
    const rows = json.data[0].items;
    assert(rows[0].purchase_specification === "1L per bottle" && rows[0].quantity === 2 && rows[0].unit === "bottle", "Exact package is preserved");
    assert(rows[1].purchase_specification === "", "Older recipe items remain compatible");
  });
});

Deno.test("browser preflight permits idempotent kitchen writes without authentication", async () => {
  for (
    const action of [
      "create-shopping-from-recipe",
      "complete-shopping-list",
      "cleanup-kitchen-workspace",
    ]
  ) {
    const requested = [
      "authorization",
      "apikey",
      "content-type",
      "idempotency-key",
    ];
    const response = await recipeApiHandler(
      new Request(`${endpoint}&action=${action}`, {
        method: "OPTIONS",
        headers: {
          Origin: "https://recipe-scout-workspace.web.app",
          "Access-Control-Request-Method": "POST",
          "Access-Control-Request-Headers": requested.join(","),
        },
      }),
    );
    const allowed = (response.headers.get("Access-Control-Allow-Headers") ?? "")
      .toLowerCase().split(",").map((header) => header.trim());
    assert(
      response.status === 200,
      "Browser preflight must not require sign-in",
    );
    assert(
      requested.every((header) => allowed.includes(header)),
      "Browser blocks a required kitchen write header",
    );
    assert(!allowed.includes("*"), "Keep an explicit request header allowlist");
    assert(
      response.headers.get("Access-Control-Allow-Origin") === "*",
      "Existing origins remain supported",
    );
    assert(
      response.headers.get("Access-Control-Allow-Methods")?.split(",").includes(
        "POST",
      ),
      "POST is permitted",
    );
    await response.body?.cancel();
  }
});

async function withBackend(
  backend: typeof fetch,
  run: () => Promise<void>,
) {
  const values = {
    SUPABASE_URL: "https://backend.example.invalid",
    SUPABASE_ANON_KEY: "test-public-key",
    SUPABASE_SERVICE_ROLE_KEY: "test-service-key",
  };
  const previous = new Map(
    Object.keys(values).map((name) => [name, Deno.env.get(name)]),
  );
  const originalFetch = globalThis.fetch;
  try {
    for (const [name, value] of Object.entries(values)) {
      Deno.env.set(name, value);
    }
    globalThis.fetch = backend;
    await run();
  } finally {
    globalThis.fetch = originalFetch;
    for (const [name, value] of previous) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

Deno.test("allowing browser headers does not authorize missing, invalid or anonymous sessions", async () => {
  let mode = "invalid";
  await withBackend(async (input) => {
    const path = new URL(String(input)).pathname;
    if (path === "/rest/v1/ops_events") {
      return new Response(null, { status: 204 });
    }
    assert(
      path === "/auth/v1/user",
      "Unauthorized request reached application data",
    );
    return mode === "anonymous"
      ? Response.json({ id: "anonymous-user", is_anonymous: true })
      : Response.json({ error: "invalid session" }, { status: 401 });
  }, async () => {
    for (mode of ["missing", "invalid", "anonymous"]) {
      const response = await recipeApiHandler(
        new Request(`${endpoint}&action=create-shopping-from-recipe`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Idempotency-Key": key,
            ...(mode === "missing"
              ? {}
              : { Authorization: "Bearer test-user-token" }),
          },
          body: "{}",
        }),
      );
      assert(
        response.status === 401,
        "Browser header support must preserve user authentication",
      );
      await response.body?.cancel();
    }
  });
});

Deno.test("five purchase items keep exact amounts and the same request key on retry", async () => {
  const items = [
    { name: "두부", ingredient_text: "두부 1/2 개", quantity: 200, unit: "g" },
    { name: "양파", ingredient_text: "양파 1/2 개", quantity: 6, unit: "ea" },
    { name: "대파", ingredient_text: "대파 1/2 개", quantity: 5, unit: "ea" },
    {
      name: "애호박",
      ingredient_text: "애호박 1/2 개",
      quantity: 6,
      unit: "ea",
    },
    {
      name: "표고버섯",
      ingredient_text: "표고버섯 1 개",
      quantity: null,
      unit: null,
    },
  ];
  const listId = "66000000-0000-4000-8000-000000000002";
  let calls = 0;
  await withBackend(async (input, init) => {
    const path = new URL(String(input)).pathname;
    if (path === "/auth/v1/user") return Response.json({ id: "test-user" });
    if (path === "/rest/v1/ops_events") {
      return new Response(null, { status: 204 });
    }
    assert(
      new Headers(init?.headers).get("Authorization") ===
        "Bearer test-user-token",
      "Kitchen writes must retain the caller's user session",
    );
    const body = JSON.parse(String(init?.body));
    if (path === "/rest/v1/rpc/create_kitchen_shopping_list") {
      assert(body.p_idempotency_key === key, "Retry key was lost");
      assert(
        JSON.stringify(body.p_items) === JSON.stringify(items),
        "Purchase amounts or cooking text changed",
      );
      calls++;
      return Response.json([{
        list_id: listId,
        status: "active",
        created: calls === 1,
        replayed: calls > 1,
        idempotency_key: key,
      }]);
    }
    assert(
      path === "/rest/v1/kitchen_shopping_lists" && init?.method === "PATCH",
      "Unexpected application write",
    );
    assert(body.title === "강된장", "Recipe title was lost");
    return Response.json([{ id: listId, title: body.title }]);
  }, async () => {
    for (let attempt = 0; attempt < 2; attempt++) {
      const response = await recipeApiHandler(
        new Request(`${endpoint}&action=create-shopping-from-recipe`, {
          method: "POST",
          headers: {
            Authorization: "Bearer test-user-token",
            "Content-Type": "application/json",
            "Idempotency-Key": key,
          },
          body: JSON.stringify({
            source_recipe_id: "user:test-recipe",
            recipe_title: "강된장",
            items,
          }),
        }),
      );
      assert(
        response.status === (attempt === 0 ? 201 : 200),
        "Create/replay HTTP contract failed",
      );
      const result = await response.json();
      assert(
        result.data.list_id === listId && result.data.idempotency_key === key,
        "Retry returned a different list",
      );
      assert(result.data.replayed === (attempt > 0), "Replay state changed");
    }
    assert(calls === 2, "Both attempts must use the idempotent RPC");
  });
});
