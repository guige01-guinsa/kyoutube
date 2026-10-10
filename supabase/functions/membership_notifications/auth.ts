import { jwtVerify, type JWTVerifyGetKey } from "npm:jose@5.9.6";
export function pushAuthenticator(
  audience: string,
  email: string,
  keys: JWTVerifyGetKey,
) {
  if (!audience || !email) throw new Error("Missing push configuration");
  return async (token: string) => {
    const { payload } = await jwtVerify(token, keys, {
      algorithms: ["RS256"],
      issuer: ["https://accounts.google.com", "accounts.google.com"],
      audience,
      requiredClaims: ["exp", "iat", "sub", "email", "email_verified"],
      maxTokenAge: "1h",
      clockTolerance: 10,
    });
    if (payload.email !== email || payload.email_verified !== true) {
      throw new Error("Invalid push identity");
    }
  };
}
