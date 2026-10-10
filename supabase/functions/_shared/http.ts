/** Bounds both response headers and body consumption; never retries writes. */
export function fetchWithTimeout(
  input: string | URL | Request,
  init: RequestInit = {},
  timeoutMs = 15000,
): Promise<Response> {
  const upstreamSignal = init.signal ??
    (input instanceof Request ? input.signal : undefined);
  const timeout = AbortSignal.timeout(timeoutMs);
  const signal = upstreamSignal
    ? AbortSignal.any([upstreamSignal, timeout])
    : timeout;
  return globalThis.fetch(input, { ...init, signal });
}

export class AccessError extends Error {
  constructor(public status: number) {
    super("authentication_unavailable");
  }
}

/** An anon API key is a valid gateway JWT, but is not a signed-in user. */
export async function authenticatedUser(request: Request): Promise<string> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) throw new AccessError(401);
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !key) throw new AccessError(503);
  let result: Response;
  try {
    result = await fetchWithTimeout(`${url}/auth/v1/user`, {
      headers: { apikey: key, Authorization: authorization },
    });
  } catch (_) {
    throw new AccessError(503);
  }
  if (!result.ok) {
    await result.body?.cancel();
    throw new AccessError(
      result.status >= 500 || result.status === 429 ? 503 : 401,
    );
  }
  const user = await result.json().catch(() => null);
  if (typeof user?.id !== "string" || !user.id || user.is_anonymous === true) {
    throw new AccessError(401);
  }
  return user.id;
}
