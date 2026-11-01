// Typed port of website/public/app.js: every /api call the purchase and recovery
// pages make, with the same methods, bodies, credentials and error handling.
// Pure helpers (button state, status copy, URL allowlist) live here too so the
// behavior can be tested in Node without a DOM.

export interface Product {
  name: string;
  amount: number;
  currency: string;
  majorVersion: number;
  deviceLimit: number;
  mode: "test" | "live" | string;
  offlineDays: number;
  available: boolean;
}

export type PurchaseStatus =
  | "paid"
  | "pending"
  | "failed"
  | "expired"
  | "revoked"
  | string;

export interface PurchaseResult {
  status: PurchaseStatus;
  licenseKey?: string;
}

export interface CheckoutResult {
  url: string;
}

export interface RecoverResult {
  accepted?: boolean;
  message?: string;
}

export interface RecoverCompleteResult {
  licenseKey: string;
}

export const UNAVAILABLE_MESSAGE =
  "This service is temporarily unavailable. Please try again.";
export const GENERIC_ERROR_MESSAGE = "Something went wrong. Please try again.";

type Fetch = typeof fetch;

/** Same request shape as app.js `api(path, body)`: GET without a body, POST JSON with one. */
export async function api<T>(
  path: string,
  body?: unknown,
  fetchImpl: Fetch = fetch,
): Promise<T> {
  const response = await fetchImpl(path, {
    method: body === undefined ? "GET" : "POST",
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    credentials: "same-origin",
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const result = (await response.json().catch(() => ({}))) as {
    error?: string;
  };
  if (!response.ok) throw new Error(result.error || UNAVAILABLE_MESSAGE);
  return result as T;
}

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : GENERIC_ERROR_MESSAGE;
}

/** GET /api/product, falling back to the static /product.json policy. Throws when both fail. */
export async function loadProduct(fetchImpl: Fetch = fetch): Promise<Product> {
  try {
    return await api<Product>("/api/product", undefined, fetchImpl);
  } catch {
    return api<Product>("/product.json", undefined, fetchImpl);
  }
}

export function formatPrice(product: Pick<Product, "amount" | "currency">): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: product.currency,
  }).format(product.amount / 100);
}

export interface CheckoutButtonState {
  disabled: boolean;
  label: string;
  status: string;
}

export const CHECKOUT_UNAVAILABLE: CheckoutButtonState = {
  disabled: true,
  label: "Checkout unavailable",
  status: "Product details could not be loaded. Please try again later.",
};

export const CHECKOUT_COMING_SOON: CheckoutButtonState = {
  disabled: true,
  label: "Coming soon",
  status: "The commercial release is in preparation. No payment is collected.",
};

/** The candidate only ever enables checkout when the product is available in test mode. */
export function checkoutButtonState(
  product: Pick<Product, "available" | "mode">,
  comingSoon = false,
): CheckoutButtonState {
  if (comingSoon) return CHECKOUT_COMING_SOON;
  const enabled = product.available === true && product.mode === "test";
  return {
    disabled: !enabled,
    label: enabled ? "Try test checkout" : "Test checkout not configured",
    status: enabled
      ? "Test mode only. Use Stripe test payment details. No real payment is collected."
      : "Checkout is waiting for secure payment configuration. Live sales are not enabled.",
  };
}

export const CHECKOUT_DESTINATION_ERROR =
  "Checkout returned an unexpected destination. Please contact support.";

/** Allowlist: only https://checkout.stripe.com may receive the visitor. */
export function checkoutDestination(url: string): URL {
  const parsed = new URL(url);
  if (parsed.protocol !== "https:" || parsed.hostname !== "checkout.stripe.com")
    throw new Error(CHECKOUT_DESTINATION_ERROR);
  return parsed;
}

/** POST /api/checkout {} and return the validated Stripe Checkout URL. */
export async function startCheckout(fetchImpl: Fetch = fetch): Promise<string> {
  const result = await api<CheckoutResult>("/api/checkout", {}, fetchImpl);
  return checkoutDestination(result.url).href;
}

/** GET /api/purchase — the server, not the return URL, decides whether a license exists. */
export function getPurchase(fetchImpl: Fetch = fetch): Promise<PurchaseResult> {
  return api<PurchaseResult>("/api/purchase", undefined, fetchImpl);
}

export const PURCHASE_STATUS_MESSAGES: Record<string, string> = {
  paid: "Payment confirmed by the server. Your license is ready.",
  pending:
    "Payment confirmation is still processing. You can safely use Restore purchase later.",
  failed: "Payment failed. No license has been issued.",
  expired: "This checkout has expired. Please start a new checkout.",
  revoked:
    "This purchase is no longer active. Contact support if you believe this is a mistake.",
};

export const PURCHASE_STATUS_UNKNOWN =
  "Purchase status is unavailable. Please use Restore purchase.";

export function purchaseStatusMessage(status: PurchaseStatus): string {
  return PURCHASE_STATUS_MESSAGES[status] || PURCHASE_STATUS_UNKNOWN;
}

export const PURCHASE_DEFAULT_MESSAGE =
  "Choose test checkout to buy a test license, or restore a previous purchase below.";
export const PURCHASE_CANCELLED_MESSAGE =
  "Checkout was cancelled. No purchase has been confirmed. You can return to pricing whenever you’re ready.";
export const PURCHASE_CHECKING_MESSAGE =
  "Checking server-confirmed purchase status…";

export const PURCHASE_POLL_ATTEMPTS = 8;
export const PURCHASE_POLL_DELAY_MS = 2500;

export type ReturnMode = "offer" | "cancelled" | "verify";

/** Interpret `?status=` on the return URL. Anything other than empty/cancelled means verify with the server. */
export function returnMode(search: string): ReturnMode {
  const status = new URLSearchParams(search).get("status");
  if (!status) return "offer";
  if (status === "cancelled") return "cancelled";
  return "verify";
}

export const NO_LICENSE_ERROR =
  "No license was returned. Please restore your purchase or contact support.";

export function assertLicense(license: unknown): string {
  if (typeof license !== "string" || !license) throw new Error(NO_LICENSE_ERROR);
  return license;
}

/** POST /api/recover {email}. */
export function requestRecovery(
  email: string,
  fetchImpl: Fetch = fetch,
): Promise<RecoverResult> {
  return api<RecoverResult>("/api/recover", { email: email.trim() }, fetchImpl);
}

export const RECOVERY_REQUESTED_MESSAGE =
  "If an eligible purchase matches that address, recovery instructions will be sent. Check your inbox and spam folder.";
export const RECOVERY_DEFAULT_MESSAGE =
  "Recovery email must be configured by the owner before this test service can send instructions.";
export const RECOVERY_VERIFYING_MESSAGE = "Verifying your recovery link…";
export const RECOVERY_RESTORED_MESSAGE =
  "License restored. Save it before leaving this page.";

/** Read `#token=` from a URL fragment (the one-time recovery link). */
export function recoveryToken(hash: string): string | null {
  if (!hash) return null;
  return new URLSearchParams(hash.slice(1)).get("token");
}

/** POST /api/recover/complete {token}. */
export function completeRecovery(
  token: string,
  fetchImpl: Fetch = fetch,
): Promise<RecoverCompleteResult> {
  return api<RecoverCompleteResult>("/api/recover/complete", { token }, fetchImpl);
}

export const DOWNLOAD_UNAVAILABLE_MESSAGE =
  "The download is not available yet. Your license is safe.";
export const DOWNLOAD_FILENAME = "DockGrove.zip";

/** POST /api/download {licenseKey}; resolves to the release archive. */
export async function downloadApp(
  licenseKey: string,
  fetchImpl: Fetch = fetch,
): Promise<Blob> {
  const response = await fetchImpl("/api/download", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "same-origin",
    body: JSON.stringify({ licenseKey }),
  });
  if (!response.ok) {
    const data = (await response.json().catch(() => ({}))) as { error?: string };
    throw new Error(data.error || DOWNLOAD_UNAVAILABLE_MESSAGE);
  }
  return response.blob();
}
