/** Bound JSON API bodies before parsing, including chunked or forged-length input. */
export class RequestBoundaryError extends Error {
  constructor(public status: number, public code: string) {
    super(code);
  }
}

export async function boundedRequest(
  request: Request,
  maxBytes = 512 * 1024,
  timeoutMs = 10000,
): Promise<Request> {
  if (request.url.length > 8192) {
    throw new RequestBoundaryError(414, "uri_too_long");
  }
  const declared = request.headers.get("content-length");
  if (
    declared !== null &&
    (!/^\d+$/.test(declared) || Number(declared) > maxBytes)
  ) {
    void request.body?.cancel().catch(() => {});
    throw new RequestBoundaryError(413, "request_too_large");
  }
  if (!request.body) return request;
  const reader = request.body.getReader();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let cancelOnAbort: (() => void) | undefined;
  const stopped = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new RequestBoundaryError(408, "request_timeout")),
      timeoutMs,
    );
    cancelOnAbort = () =>
      reject(new RequestBoundaryError(408, "request_aborted"));
    if (request.signal.aborted) cancelOnAbort();
    else {request.signal.addEventListener("abort", cancelOnAbort, {
        once: true,
      });}
  });
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await Promise.race([reader.read(), stopped]);
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        throw new RequestBoundaryError(413, "request_too_large");
      }
      chunks.push(value);
    }
    const body = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      body.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return new Request(request, { body });
  } catch (error) {
    void reader.cancel().catch(() => {});
    if (error instanceof RequestBoundaryError) throw error;
    throw new RequestBoundaryError(400, "invalid_request_body");
  } finally {
    clearTimeout(timer);
    if (cancelOnAbort) {
      request.signal.removeEventListener("abort", cancelOnAbort);
    }
    reader.releaseLock();
  }
}

/** Recipes, membership results and signed URLs must not enter shared HTTP caches. */
export function secureResponse(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set("Cache-Control", "no-store");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "no-referrer");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
