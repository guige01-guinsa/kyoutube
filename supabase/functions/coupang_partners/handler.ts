import { CoupangError, productUrl } from "./client.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export function createHandler(deps: {
  reserve: (authorization: string, action: string) => Promise<void>;
  client: () => {
    search: (keyword: string) => Promise<unknown>;
    deeplink: (url: string) => Promise<string>;
  };
}) {
  const reply = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: {
        ...cors,
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    });
  return async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") {
      return reply({ error: "method_not_allowed" }, 405);
    }
    const auth = req.headers.get("authorization") ?? "";
    if (!/^Bearer\s+\S+$/i.test(auth)) {
      return reply({ error: "unauthorized" }, 401);
    }
    try {
      // Bound body size even for chunked requests.
      const reader = req.body?.getReader();
      if (!reader) return reply({ error: "invalid_input" }, 400);
      const chunks: Uint8Array[] = [];
      let bytes = 0;
      while (true) {
        const part = await reader.read();
        if (part.done) break;
        bytes += part.value.length;
        if (bytes > 8192) {
          await reader.cancel();
          return reply({ error: "invalid_input" }, 413);
        }
        chunks.push(part.value);
      }
      const buffer = new Uint8Array(bytes);
      let offset = 0;
      for (const part of chunks) {
        buffer.set(part, offset);
        offset += part.length;
      }
      let input;
      try {
        input = JSON.parse(new TextDecoder().decode(buffer));
      } catch {
        return reply({ error: "invalid_input" }, 400);
      }
      const action = input?.action;
      const keyword = typeof input?.keyword === "string"
        ? input.keyword.trim()
        : "";
      if (
        action !== "search" && action !== "deeplink" ||
        action === "search" &&
          (!keyword || keyword.length > 80 ||
            /[\x00-\x1f\x7f]/.test(keyword)) ||
        action === "deeplink" && !productUrl(input?.url)
      ) return reply({ error: "invalid_input" }, 400);
      await deps.reserve(auth, action);
      const client = deps.client();
      return action === "search"
        ? reply({ items: await client.search(keyword) })
        : reply({ link: await client.deeplink(input.url) });
    } catch (error) {
      const safe = error instanceof CoupangError
        ? error
        : new CoupangError("service_unavailable", 503);
      return reply({ error: safe.code }, safe.status);
    }
  };
}
