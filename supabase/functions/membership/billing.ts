export type BillingOffer = {
  plan_code: string;
  product_id: string;
  base_plan_id: string;
};
type Item = {
  productId?: string;
  expiryTime?: string;
  latestSuccessfulOrderId?: string;
  offerDetails?: { basePlanId?: string };
  autoRenewingPlan?: { autoRenewEnabled?: boolean };
  deferredItemReplacement?: { productId?: string };
};
export type PlayPurchase = {
  subscriptionState?: string;
  startTime?: string;
  lineItems?: Item[];
  acknowledgementState?: string;
  linkedPurchaseToken?: string;
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
  outOfAppPurchaseContext?: {
    expiredExternalAccountIdentifiers?: {
      obfuscatedExternalAccountId?: string;
    };
    expiredPurchaseToken?: string;
  };
};
export class BillingError extends Error {
  constructor(public code: string, public status = 409) {
    super(code);
  }
}
export function resolvePurchase(
  p: PlayPurchase,
  offers: BillingOffer[],
  now = Date.now(),
) {
  const userId = p.externalAccountIdentifiers?.obfuscatedExternalAccountId ??
    p.outOfAppPurchaseContext?.expiredExternalAccountIdentifiers
      ?.obfuscatedExternalAccountId;
  if (!userId || !/^[a-f0-9-]{36}$/i.test(userId)) {
    throw new BillingError("purchase_account_missing", 403);
  }
  if (
    p.subscriptionState === "SUBSCRIPTION_STATE_PENDING" ||
    p.subscriptionState === "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED"
  ) {
    throw new BillingError("purchase_pending");
  }
  const items = (p.lineItems ?? []).filter((i) =>
    i.expiryTime && Number.isFinite(Date.parse(i.expiryTime))
  );
  // A deferred replacement can include a future, not-yet-owned item. Never grant
  // that future tier merely because it has the latest expiry or matches UI input.
  const owned = items.filter((i) =>
    !!i.latestSuccessfulOrderId || !!i.deferredItemReplacement
  );
  const entitledItems = owned.length ? owned : items.length === 1 ? items : [];
  const live = entitledItems.filter((i) => Date.parse(i.expiryTime!) > now);
  // After deferred renewal Play retains the old, expired line alongside the new
  // current line. On complete expiry only the last expired line identifies plan.
  const lastExpiry = Math.max(
    ...entitledItems.map((i) => Date.parse(i.expiryTime!)),
  );
  const candidates = live.length
    ? live
    : entitledItems.filter((i) => Date.parse(i.expiryTime!) === lastExpiry);
  if (candidates.length !== 1) {
    throw new BillingError("ambiguous_purchase_items", 502);
  }
  const item = candidates[0];
  const offer = offers.find((o) =>
    o.product_id === item.productId &&
    o.base_plan_id === item.offerDetails?.basePlanId
  );
  if (!offer) throw new BillingError("unknown_billing_offer", 403);
  const started = Date.parse(p.startTime ?? "");
  const expiry = Date.parse(item.expiryTime!);
  if (!Number.isFinite(started) || started > now) {
    throw new BillingError("invalid_purchase_period", 502);
  }
  const statuses: Record<string, string> = {
    SUBSCRIPTION_STATE_ACTIVE: "active",
    SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace_period",
    SUBSCRIPTION_STATE_CANCELED: "canceled",
    SUBSCRIPTION_STATE_PAUSED: "paused",
    SUBSCRIPTION_STATE_ON_HOLD: "paused",
    SUBSCRIPTION_STATE_EXPIRED: "expired",
  };
  const status = statuses[p.subscriptionState ?? ""];
  if (!status) throw new BillingError("unknown_subscription_state", 502);
  return {
    userId,
    offer,
    status,
    startedAt: new Date(started).toISOString(),
    validUntil: new Date(expiry).toISOString(),
    autoRenews: status !== "canceled" &&
      item.autoRenewingPlan?.autoRenewEnabled === true,
    entitled: expiry > now &&
      ["active", "grace_period", "canceled"].includes(status),
    needsAcknowledgement:
      p.acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING",
  };
}
export async function tokenHash(token: string) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)),
    ),
  )
    .map((v) => v.toString(16).padStart(2, "0")).join("");
}
export type BillingDependencies = {
  owner: (hash: string) => Promise<string | null>;
  serial: () => Promise<number>;
  offers: () => Promise<BillingOffer[]>;
  purchase: (token: string) => Promise<PlayPurchase>;
  acknowledge: (product: string, token: string) => Promise<void>;
  apply: (args: Record<string, unknown>) => Promise<boolean>;
};
export async function verifyBilling(
  d: BillingDependencies,
  token: string,
  expectedUser?: string,
) {
  if (token.length < 20 || token.length > 4096) {
    throw new BillingError("invalid_purchase", 400);
  }
  // Reserve before the provider lookup. Older concurrent responses cannot replace
  // a newer successfully applied response; RTDN event time is never authoritative.
  const serial = await d.serial();
  const purchase = await d.purchase(token);
  const hash = await tokenHash(token);
  const linked = purchase.linkedPurchaseToken ??
    purchase.outOfAppPurchaseContext?.expiredPurchaseToken;
  const linkedHash = linked ? await tokenHash(linked) : null;
  // Play removes outOfAppPurchaseContext after acknowledgement. Subsequent
  // renewals must use the server-owned token binding, never the caller's user ID.
  if (
    !purchase.externalAccountIdentifiers?.obfuscatedExternalAccountId &&
    !purchase.outOfAppPurchaseContext?.expiredExternalAccountIdentifiers
      ?.obfuscatedExternalAccountId
  ) {
    const owner = await d.owner(hash) ??
      (linkedHash ? await d.owner(linkedHash) : null);
    if (owner) {
      purchase.externalAccountIdentifiers = {
        obfuscatedExternalAccountId: owner,
      };
    }
  }
  const resolved = resolvePurchase(purchase, await d.offers());
  if (expectedUser && resolved.userId !== expectedUser) {
    throw new BillingError("purchase_account_mismatch", 403);
  }
  const applied = await d.apply({
    p_user_id: resolved.userId,
    p_token: token,
    p_token_hash: hash,
    p_linked_hash: linkedHash,
    p_serial: serial,
    p_plan_code: resolved.offer.plan_code,
    p_product_id: resolved.offer.product_id,
    p_base_plan_id: resolved.offer.base_plan_id,
    p_status: resolved.status,
    p_started_at: resolved.startedAt,
    p_valid_until: resolved.validUntil,
    p_auto_renews: resolved.autoRenews,
  });
  // Grant + event are transactional. A failed acknowledgement is retried, even if
  // the same entitlement was already persisted. Never acknowledge before binding.
  if (applied && resolved.entitled && resolved.needsAcknowledgement) {
    await d.acknowledge(resolved.offer.product_id, token);
  }
  return { ...resolved, currentPurchase: applied };
}
