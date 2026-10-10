const base = "https://api-gateway.coupang.com";
const path = "/v2/providers/affiliate_open_api/apis/openapi";

export class CoupangError extends Error {
  constructor(public code: string, public status = 502) {
    super(code);
  }
}

export function productUrl(value: unknown): value is string {
  if (
    typeof value !== "string" || value.length > 2048 ||
    /[\s\\\x00-\x1f\x7f]/.test(value)
  ) return false;
  // Only canonical product pages are accepted. Never fetch a supplied URL.
  return /^https:\/\/www\.coupang\.com\/vp\/products\/[0-9]+(?:\?[^#]+)?$/.test(
    value,
  );
}

export function shortUrl(value: unknown): value is string {
  return typeof value === "string" && value.length <= 2048 &&
    /^https:\/\/link\.coupang\.com\/a\/[A-Za-z0-9]+$/.test(value);
}

/** Only expose an image that Coupang returned from its own CDN. */
export function productImage(value: unknown): value is string {
  if (
    typeof value !== "string" || value.length > 2048 ||
    /[\s\\\x00-\x1f\x7f]/.test(value)
  ) return false;
  const normalized = value.replace(/^http:\/\//, "https://");
  return /^https:\/\/[a-z0-9.-]*coupangcdn\.com\/.+$/i.test(normalized);
}

export async function authorization(
  method: string,
  url: URL,
  access: string,
  secret: string,
  now = new Date(),
) {
  const date = now.toISOString().slice(2, 19).replace(/[-:]/g, "") + "Z";
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(date + method + url.pathname + url.search.slice(1)),
  );
  const hex = Array.from(
    new Uint8Array(signature),
    (v) => v.toString(16).padStart(2, "0"),
  ).join("");
  return `CEA algorithm=HmacSHA256, access-key=${access}, signed-date=${date}, signature=${hex}`;
}

export function createCoupangClient(
  access: string,
  secret: string,
  fetcher: typeof fetch = fetch,
) {
  async function call(
    method: string,
    suffix: string,
    query = "",
    body?: unknown,
  ) {
    const url = new URL(base + path + suffix + (query ? "?" + query : ""));
    try {
      const response = await fetcher(url, {
        method,
        redirect: "error",
        signal: AbortSignal.timeout(12000),
        headers: {
          Authorization: await authorization(method, url, access, secret),
          "Content-Type": "application/json",
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new CoupangError(
          response.status === 429
            ? "upstream_rate_limited"
            : response.status === 401 || response.status === 403
            ? "coupang_access_denied"
            : "upstream_unavailable",
          response.status === 429 ? 429 : 502,
        );
      }
      const payload = await response.json();
      if (payload?.rCode !== "0") {
        throw new CoupangError("coupang_request_rejected");
      }
      return payload.data;
    } catch (error) {
      if (error instanceof CoupangError) throw error;
      throw new CoupangError(
        error instanceof DOMException && error.name === "TimeoutError"
          ? "upstream_timeout"
          : "upstream_unavailable",
      );
    }
  }
  return {
    async search(keyword: string) {
      const data = await call(
        "GET",
        "/products/search",
        `keyword=${encodeURIComponent(keyword)}&limit=10`,
      );
      if (!data || !Array.isArray(data.productData)) {
        throw new CoupangError("upstream_invalid");
      }
      return data.productData.slice(0, 10).map(
        (row: Record<string, unknown>) => {
          const id = String(row.productId ?? "");
          if (
            !/^[0-9]+$/.test(id) || typeof row.productName !== "string" ||
            !row.productName.trim() || row.productName.length > 300
          ) {
            throw new CoupangError("upstream_invalid");
          }
          // Canonical URL is used only as deeplink input; tracking is issued by Coupang.
          const image = typeof row.productImage === "string"
            ? row.productImage.replace(/^http:\/\//, "https://")
            : "";
          return {
            productId: id,
            title: row.productName,
            productUrl: `https://www.coupang.com/vp/products/${id}`,
            price: typeof row.productPrice === "number" &&
                Number.isFinite(row.productPrice) && row.productPrice >= 0
              ? row.productPrice
              : null,
            // A photo is optional: malformed or off-domain URLs are never
            // sent to the app for rendering.
            imageUrl: productImage(image) ? image : null,
          };
        },
      );
    },
    async deeplink(url: string) {
      if (!productUrl(url)) throw new CoupangError("invalid_input", 400);
      const data = await call("POST", "/deeplink", "", { coupangUrls: [url] });
      if (
        !Array.isArray(data) || data.length !== 1 ||
        data[0].originalUrl !== url || !shortUrl(data[0].shortenUrl)
      ) {
        throw new CoupangError("upstream_invalid");
      }
      return data[0].shortenUrl as string;
    },
  };
}
