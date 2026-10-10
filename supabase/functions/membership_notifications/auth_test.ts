import {
  createLocalJWKSet,
  exportJWK,
  generateKeyPair,
  SignJWT,
} from "npm:jose@5.9.6";
import { pushAuthenticator } from "./auth.ts";
Deno.test("OIDC checks signature, issuer, audience, expiry and verified service identity", async () => {
  const pair = await generateKeyPair("RS256");
  const other = await generateKeyPair("RS256");
  const jwk = await exportJWK(pair.publicKey);
  jwk.kid = "fixture";
  const authenticate = pushAuthenticator(
    "https://local.test/push",
    "push@example.invalid",
    createLocalJWKSet({ keys: [jwk] }),
  );
  for (
    const variant of [
      "valid",
      "wrong_aud",
      "wrong_iss",
      "wrong_email",
      "unverified",
      "expired",
      "wrong_signature",
      "missing_exp",
    ]
  ) {
    let jwt = new SignJWT({
      email: variant === "wrong_email"
        ? "other@example.invalid"
        : "push@example.invalid",
      email_verified: variant !== "unverified",
    })
      .setProtectedHeader({ alg: "RS256", kid: "fixture" }).setSubject(
        "fixture-sub",
      )
      .setIssuer(
        variant === "wrong_iss" ? "untrusted" : "https://accounts.google.com",
      )
      .setAudience(
        variant === "wrong_aud" ? "wrong" : "https://local.test/push",
      ).setIssuedAt();
    if (variant !== "missing_exp") {
      jwt = jwt.setExpirationTime(
        variant === "expired" ? Math.floor(Date.now() / 1000) - 100 : "5m",
      );
    }
    const token = await jwt.sign(
      variant === "wrong_signature" ? other.privateKey : pair.privateKey,
    );
    let passed = false;
    try {
      await authenticate(token);
      passed = true;
    } catch { /* rejected */ }
    if (passed !== (variant === "valid")) {
      throw new Error("Unexpected OIDC result: " + variant);
    }
  }
});
