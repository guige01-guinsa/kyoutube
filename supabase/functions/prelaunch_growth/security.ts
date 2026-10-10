const bytes = new TextEncoder();
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
function encode(value: Uint8Array) {
  return btoa(String.fromCharCode(...value)).replaceAll("+", "-").replaceAll(
    "/",
    "_",
  ).replaceAll("=", "");
}
function decode(value: string) {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("Invalid token");
  return Uint8Array.from(
    atob(value.replaceAll("-", "+").replaceAll("_", "/")),
    (c) => c.charCodeAt(0),
  );
}
async function key(secret: string) {
  if (secret.length < 32) throw new Error("Missing signing configuration");
  return await crypto.subtle.importKey(
    "raw",
    bytes.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}
export async function emailKey(secret: string, email: string) {
  const data = await crypto.subtle.sign(
    "HMAC",
    await key(secret),
    bytes.encode("email:" + email),
  );
  return [...new Uint8Array(data)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
export type Claim = {
  u: string;
  v: string;
  p: "confirm" | "withdraw";
  e: number;
};
export async function signClaim(secret: string, claim: Claim) {
  const payload = encode(bytes.encode(JSON.stringify(claim)));
  return payload + "." +
    encode(
      new Uint8Array(
        await crypto.subtle.sign(
          "HMAC",
          await key(secret),
          bytes.encode(payload),
        ),
      ),
    );
}
export async function verifyClaim(
  secret: string,
  token: string,
  purpose: Claim["p"],
  now = Date.now(),
): Promise<Claim | null> {
  try {
    if (token.length > 768) return null;
    const parts = token.split(".");
    if (
      parts.length !== 2 ||
      !await crypto.subtle.verify(
        "HMAC",
        await key(secret),
        decode(parts[1]),
        bytes.encode(parts[0]),
      )
    ) return null;
    const c = JSON.parse(new TextDecoder().decode(decode(parts[0])));
    return uuid.test(c.u) && uuid.test(c.v) && c.p === purpose &&
        Number.isSafeInteger(c.e) && c.e > now / 1000
      ? c
      : null;
  } catch {
    return null;
  }
}
export async function equalSecret(actual: string, expected: string) {
  if (expected.length < 32) return false;
  const a = new Uint8Array(
    await crypto.subtle.digest("SHA-256", bytes.encode(actual)),
  );
  const b = new Uint8Array(
    await crypto.subtle.digest("SHA-256", bytes.encode(expected)),
  );
  return a.reduce((difference, value, i) => difference | (value ^ b[i]), 0) ===
    0;
}
export function validEmail(value: unknown): value is string {
  return typeof value === "string" && value.length <= 254 &&
    /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/
      .test(value);
}
