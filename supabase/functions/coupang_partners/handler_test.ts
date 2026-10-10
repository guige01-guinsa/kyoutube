import { createHmac } from "node:crypto";
import {
  authorization,
  CoupangError,
  createCoupangClient,
  productUrl,
} from "./client.ts";
import { createHandler } from "./handler.ts";
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
const request = (body: unknown, token = "Bearer test") =>
  new Request("https://local.test", {
    method: "POST",
    headers: { Authorization: token },
    body: JSON.stringify(body),
  });

Deno.test("HMAC signs UTC date, method, path and exact encoded query without question mark", async () => {
  const url = new URL(
    "https://api-gateway.coupang.com/path?keyword=%EA%B0%84%EC%9E%A5&limit=10",
  );
  const signature = createHmac("sha256", "fixture-secret").update(
    "260926T010203ZGET/pathkeyword=%EA%B0%84%EC%9E%A5&limit=10",
  ).digest("hex");
  equal(
    await authorization(
      "GET",
      url,
      "fixture-access",
      "fixture-secret",
      new Date("2026-09-26T01:02:03Z"),
    ),
    `CEA algorithm=HmacSHA256, access-key=fixture-access, signed-date=260926T010203Z, signature=${signature}`,
  );
});

Deno.test("product URLs reject credentials, spoof hosts, redirects, short URLs and controls", () => {
  equal(
    productUrl(
      "https://www.coupang.com/vp/products/12?itemId=34&vendorItemId=56",
    ),
    true,
  );
  for (
    const url of [
      "http://www.coupang.com/vp/products/12",
      "https://www.coupang.com.evil/vp/products/12",
      "https://www.coupang.com@evil/vp/products/12",
      "https://www.coupang.com:443/vp/products/12",
      "https://link.coupang.com/a/abc",
      "https://www.coupang.com/np/search?q=rice",
      "https://www.coupang.com/vp/products/12\n",
      "https://www.coupang.com/vp/products/12#redirect",
    ]
  ) equal(productUrl(url), false);
});

Deno.test("search encodes Korean keyword, bounds results and exposes only selected safe product image fields", async () => {
  const client = createCoupangClient(
    "fixture",
    "fixture",
    (async (url, init) => {
      const value = new URL(String(url));
      equal(value.searchParams.get("keyword"), "간장 & 소금");
      equal(value.searchParams.get("limit"), "10");
      equal(init?.redirect, "error");
      equal(
        value.pathname,
        "/v2/providers/affiliate_open_api/apis/openapi/products/search",
      );
      return Response.json({
        rCode: "0",
        data: {
          productData: [{
            productId: 123,
            productName: "간장",
            productPrice: 1000,
            productImage: "http://image8.coupangcdn.com/image/product/image.jpg",
            productUrl: "not copied",
          }],
        },
      });
    }) as typeof fetch,
  );
  equal(await client.search("간장 & 소금"), [{
    productId: "123",
    title: "간장",
    productUrl: "https://www.coupang.com/vp/products/123",
    price: 1000,
    imageUrl: "https://image8.coupangcdn.com/image/product/image.jpg",
  }]);
});

Deno.test("deeplink preserves issued URL and original option parameters", async () => {
  const originalUrl =
    "https://www.coupang.com/vp/products/123?itemId=4&vendorItemId=5";
  const client = createCoupangClient(
    "fixture",
    "fixture",
    (async (_url, init) => {
      equal(JSON.parse(String(init?.body)), { coupangUrls: [originalUrl] });
      equal(init?.method, "POST");
      return Response.json({
        rCode: "0",
        data: [{
          originalUrl,
          shortenUrl: "https://link.coupang.com/a/Issued123",
        }],
      });
    }) as typeof fetch,
  );
  equal(
    await client.deeplink(originalUrl),
    "https://link.coupang.com/a/Issued123",
  );
});

Deno.test("malformed and non-success upstream responses cannot create usable links", async () => {
  const originalUrl = "https://www.coupang.com/vp/products/123";
  for (
    const body of [{ rCode: "ERROR", rMessage: "private upstream detail" }, {
      rCode: "0",
      data: [{
        originalUrl: originalUrl + "4",
        shortenUrl: "https://link.coupang.com/a/A",
      }],
    }, {
      rCode: "0",
      data: [{ originalUrl, shortenUrl: "https://evil.test/a/A" }],
    }]
  ) {
    const client = createCoupangClient(
      "fixture",
      "fixture",
      (async () => Response.json(body)) as typeof fetch,
    );
    let failed = false;
    try {
      await client.deeplink(originalUrl);
    } catch (error) {
      failed = error instanceof CoupangError;
    }
    equal(failed, true);
  }
});

Deno.test("authentication, invalid input and admin/MFA/quota denial never call Coupang", async () => {
  let reserved = 0, calls = 0;
  const handler = createHandler({
    reserve: async () => {
      reserved++;
      throw new CoupangError("admin_mfa_required", 403);
    },
    client: () => {
      calls++;
      throw new Error("must not run");
    },
  });
  equal(
    (await handler(request({ action: "search", keyword: "rice" }, ""))).status,
    401,
  );
  equal(
    (await handler(request({ action: "search", keyword: "" }))).status,
    400,
  );
  equal(
    (await handler(request({ action: "deeplink", url: "https://evil.test" })))
      .status,
    400,
  );
  equal(reserved, 0);
  equal(
    (await handler(request({ action: "search", keyword: "rice" }))).status,
    403,
  );
  equal(reserved, 1);
  equal(calls, 0);
  for (const status of [401, 403, 429, 503]) {
    const blocked = createHandler({
      reserve: async () => {
        throw new CoupangError("blocked", status);
      },
      client: () => {
        calls++;
        throw new Error("must not run");
      },
    });
    equal(
      (await blocked(request({ action: "search", keyword: "rice" }))).status,
      status,
    );
  }
  equal(calls, 0);
});

Deno.test("handler returns results, handles CORS and never echoes raw exceptions", async () => {
  const handler = createHandler({
    reserve: async () => {},
    client: () => ({
      search: async (keyword) => [{ title: keyword }],
      deeplink: async () => "https://link.coupang.com/a/A",
    }),
  });
  equal(
    await (await handler(request({ action: "search", keyword: " rice " })))
      .json(),
    { items: [{ title: "rice" }] },
  );
  equal(
    (await handler(new Request("https://local.test", { method: "OPTIONS" })))
      .status,
    200,
  );
  equal((await handler(new Request("https://local.test"))).status, 405);
  equal(
    (await handler(request({ action: "search", keyword: "x".repeat(9000) })))
      .status,
    413,
  );
  const failure = createHandler({
    reserve: async () => {
      throw new Error("SECRET");
    },
    client: () => {
      throw new Error("SECRET");
    },
  });
  equal(
    await (await failure(request({ action: "search", keyword: "rice" })))
      .json(),
    { error: "service_unavailable" },
  );
});
