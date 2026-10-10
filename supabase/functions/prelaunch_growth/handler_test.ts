import { growthHandler } from "./handler.ts";
import { emailKey, signClaim, verifyClaim } from "./security.ts";
import { deliveryHandler } from "../prelaunch_delivery/handler.ts";
import { type Job, mail } from "../prelaunch_delivery/mail.ts";
import {
  attribution,
  calculateCost,
  channelUrl,
  cleanShareUrl,
} from "../../../playstore-site/prelaunch-domain.js";
const eq = (actual: unknown, expected: unknown) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
};
const secret = "local-test-secret-only-1234567890abcdef";
const id = "11111111-1111-4111-8111-111111111111";
const version = "22222222-2222-4222-8222-222222222222";
const valid = {
  action: "join",
  email: " Chef@example.test ",
  role: "chef",
  interest: "costs",
  locale: "ko",
  privacyConsent: true,
  invitationConsent: true,
  newsletter: false,
  consentVersion: "pro-2026-09-v1",
  challenge: "verified-test-token",
  source: "youtube",
  campaign: "chef-cost",
  website: "",
};
function setup(overrides: Record<string, unknown> = {}) {
  const calls: Array<{ name: string; parameters: Record<string, unknown> }> =
    [];
  const handler = growthHandler({
    origin: "https://example.test",
    signingKey: secret,
    ready: () => Promise.resolve(true),
    challenge: () => Promise.resolve(true),
    rpc: (name, parameters) => {
      calls.push({ name, parameters });
      return Promise.resolve(true);
    },
    ...overrides,
  });
  const run = (body: unknown = valid, origin = "https://example.test") =>
    handler(
      new Request("https://api.example.test/growth", {
        method: "POST",
        headers: { "Origin": origin, "Content-Type": "application/json" },
        body: JSON.stringify(body),
      }),
    );
  return { calls, handler, run };
}
Deno.test("intake normalizes address and persists only the declared consent and attribution", async () => {
  const s = setup();
  const r = await s.run();
  eq(r.status, 202);
  eq(await r.json(), { status: "accepted" });
  eq(s.calls[0].name, "growth_register");
  eq(s.calls[0].parameters.p_email, "chef@example.test");
  eq(s.calls[0].parameters.p_newsletter, false);
  eq(s.calls[0].parameters.p_source, "youtube");
  eq(String(s.calls[0].parameters.p_email_key).length, 64);
  eq(r.headers.get("cache-control"), "no-store");
  eq(r.headers.get("access-control-allow-origin"), "https://example.test");
});
Deno.test("wrong origin, missing consent, invalid addresses and failed CAPTCHA cannot create a lead", async () => {
  const s = setup();
  eq((await s.run(valid, "https://example.test.evil")).status, 403);
  for (
    const body of [
      { ...valid, privacyConsent: false },
      { ...valid, invitationConsent: false },
      { ...valid, email: "a\nb@example.test" },
      { ...valid, newsletter: "true" },
      { ...valid, campaign: "<script>" },
      { ...valid, role: "admin" },
    ]
  ) eq((await s.run(body)).status, 400);
  eq(s.calls.length, 0);
  const blocked = setup({ challenge: () => Promise.resolve(false) });
  eq((await blocked.run()).status, 400);
  eq(blocked.calls.length, 0);
});
Deno.test("paused, oversized and honeypot submissions do not store addresses", async () => {
  const paused = setup({ ready: () => Promise.resolve(false) });
  eq((await paused.run()).status, 503);
  eq(paused.calls.length, 0);
  const s = setup();
  eq((await s.run({ ...valid, website: "spam" })).status, 202);
  eq((await s.run({ padding: "x".repeat(5000) })).status, 413);
  eq(s.calls.length, 0);
});
Deno.test("backend failures never leak SQL or email details to the caller", async () => {
  const s = setup({
    rpc: () => {
      throw new Error("sensitive SQL chef@example.test");
    },
  });
  const r = await s.run();
  eq(r.status, 503);
  eq(await r.json(), { code: "temporarily_unavailable" });
});
Deno.test("signed confirmation rejects purpose substitution, expiry, tampering and a changed key", async () => {
  const claim = {
    u: id,
    v: version,
    p: "confirm" as const,
    e: Math.floor(Date.now() / 1000) + 60,
  };
  const token = await signClaim(secret, claim);
  eq(await verifyClaim(secret, token, "confirm"), claim);
  eq(await verifyClaim(secret, token, "withdraw"), null);
  eq(await verifyClaim(secret, token, "confirm", (claim.e + 1) * 1000), null);
  eq(await verifyClaim(secret + "changed", token, "confirm"), null);
  eq(await verifyClaim(secret, token + "x", "confirm"), null);
  eq(
    await emailKey(secret, "chef@example.test") ===
      await emailKey(secret, "other@example.test"),
    false,
  );
});
Deno.test("email scanner GET never confirms; withdrawal works while intake is paused", async () => {
  const s = setup({ ready: () => Promise.resolve(false) });
  await s.handler(
    new Request("https://api.example.test/growth?confirm=anything", {
      headers: { Origin: "https://example.test" },
    }),
  );
  eq(s.calls.length, 0);
  const token = await signClaim(secret, {
    u: id,
    v: version,
    p: "withdraw",
    e: Math.floor(Date.now() / 1000) + 60,
  });
  const r = await s.run({ action: "withdraw", token });
  eq(r.status, 200);
  eq(s.calls[0], {
    name: "growth_withdraw",
    parameters: { p_id: id, p_version: version },
  });
});
const job: Job = {
  id,
  lease_id: version,
  lead_id: id,
  version,
  email: "chef@example.test",
  kind: "welcome",
  locale: "ko",
  created_at: "2026-09-14T00:00:00Z",
  expires_at: "2027-03-13T00:00:00Z",
  newsletter: false,
};
Deno.test("scheduled worker requires its separate secret and remains paused by default", async () => {
  const calls: string[] = [];
  const h = deliveryHandler({
    workerSecret: secret,
    enabled: () => false,
    rpc: (name) => {
      calls.push(name);
      return Promise.resolve(null);
    },
    send: () => {
      throw new Error("Must not send");
    },
  });
  eq(
    (await h(new Request("https://api.test", { method: "POST" }))).status,
    401,
  );
  eq(calls, []);
  const r = await h(
    new Request("https://api.test", {
      method: "POST",
      headers: { authorization: "Bearer " + secret },
    }),
  );
  eq(await r.json(), { status: "paused" });
  eq(calls, ["growth_maintain"]);
});
Deno.test("withdrawal after claim cancels delivery before contacting provider", async () => {
  let sent = false;
  const h = deliveryHandler({
    workerSecret: secret,
    enabled: () => true,
    rpc: (name) => Promise.resolve(name === "growth_claim_job" ? job : false),
    send: () => {
      sent = true;
      return Promise.resolve();
    },
  });
  const r = await h(
    new Request("https://api.test", {
      method: "POST",
      headers: { authorization: "Bearer " + secret },
    }),
  );
  eq(await r.json(), { status: "cancelled" });
  eq(sent, false);
});
Deno.test("provider errors queue a bounded retry; success acknowledges the matching lease", async () => {
  for (const fail of [true, false]) {
    const results: unknown[] = [];
    const h = deliveryHandler({
      workerSecret: secret,
      enabled: () => true,
      rpc: (name, args) => {
        if (name === "growth_finish_job") results.push(args);
        return Promise.resolve(name === "growth_claim_job" ? job : true);
      },
      send: () =>
        fail
          ? Promise.reject(new Error("private provider detail"))
          : Promise.resolve(),
    });
    const r = await h(
      new Request("https://api.test", {
        method: "POST",
        headers: { authorization: "Bearer " + secret },
      }),
    );
    eq(r.status, fail ? 503 : 200);
    eq(results, [{
      p_id: id,
      p_lease: version,
      p_sent: !fail,
      p_code: fail ? "provider" : "unknown",
    }]);
  }
});
Deno.test("mail retries are identical, links hide email, and optional promotional tips require consent", async () => {
  const a = await mail(
    job,
    secret,
    "https://example.test/",
    "Recipe Scout, test operator address",
  );
  eq(
    a,
    await mail(
      job,
      secret,
      "https://example.test/",
      "Recipe Scout, test operator address",
    ),
  );
  eq(a.text.includes(job.email), false);
  eq(a.text.includes("#withdraw="), true);
  let rejected = false;
  try {
    await mail(
      { ...job, kind: "tip" },
      secret,
      "https://example.test/",
      "Sender",
    );
  } catch {
    rejected = true;
  }
  eq(rejected, true);
  const tip = await mail(
    { ...job, kind: "tip", newsletter: true },
    secret,
    "https://example.test/",
    "Sender",
  );
  eq(tip.subject.startsWith("(광고)"), true);
});
Deno.test("worksheet accounts for yield and adds markup without treating it as margin", () => {
  eq(
    calculateCost({
      ingredients: 20000,
      yieldPercent: 80,
      extra: 5000,
      portions: 10,
      markup: 50,
    }),
    { total: 30000, unit: 3000, price: 4500 },
  );
  for (const yieldPercent of [0, 101, NaN]) {
    eq(
      calculateCost({
        ingredients: 20000,
        yieldPercent,
        extra: 0,
        portions: 10,
        markup: 50,
      }),
      null,
    );
  }
  eq(
    calculateCost({
      ingredients: 10000,
      yieldPercent: 100,
      extra: 0,
      portions: 1,
      markup: 100,
    })?.price,
    20000,
  );
});
Deno.test("shared URLs discard email tokens and untrusted channel/campaign input", () => {
  eq(
    cleanShareUrl(
      "https://example.test/?email=secret&lang=ko#withdraw=sensitive",
      "en",
    ),
    "https://example.test/?utm_source=partner&utm_campaign=chef-share&lang=en",
  );
  eq(attribution("?utm_source=youtube&utm_campaign=chef-cost"), {
    source: "youtube",
    campaign: "chef-cost",
  });
  eq(attribution("?utm_source=evil&utm_campaign=%3Cscript%3E"), {
    source: "other",
    campaign: "",
  });
  eq(channelUrl("javascript:alert(1)", "kakao"), null);
  eq(channelUrl("https://pf.kakao.com.evil/test", "kakao"), null);
  eq(
    channelUrl("https://pf.kakao.com/example", "kakao"),
    "https://pf.kakao.com/example",
  );
});
