/**
 * Typed port of the product/checkout logic in the original app.js that the home
 * #download section uses: load `/api/product` (falling back to `/product.json`),
 * format the price, and derive the checkout button state.
 */

export interface Product {
  name: string;
  amount: number;
  currency: string;
  majorVersion: number;
  deviceLimit: number;
  mode: string;
  offlineDays: number;
  available: boolean;
}

/** Fallback copy shown while product.json has not loaded yet (matches the static HTML). */
export const DEFAULT_PRICE = "$9.99";
export const DEFAULT_DEVICES = "3";

export const COMING_SOON_LABEL = "Coming soon";
export const COMING_SOON_STATUS =
  "The commercial release is in preparation. No payment is collected.";

export const UNAVAILABLE_PRICE = "Price unavailable";
export const UNAVAILABLE_LABEL = "Checkout unavailable";
export const UNAVAILABLE_STATUS =
  "Product details could not be loaded. Please try again later.";

export const GENERIC_ERROR = "Something went wrong. Please try again.";
export const SERVICE_ERROR = "This service is temporarily unavailable. Please try again.";

/** `api()` from app.js: same-origin JSON fetch that throws the server's `error` message. */
export async function api<T>(path: string, body?: unknown): Promise<T> {
  const response = await fetch(path, {
    method: body === undefined ? "GET" : "POST",
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    credentials: "same-origin",
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const result: unknown = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message =
      typeof result === "object" && result !== null && "error" in result
        ? (result as { error?: unknown }).error
        : undefined;
    throw new Error(typeof message === "string" && message ? message : SERVICE_ERROR);
  }
  return result as T;
}

/** `/api/product`, then `/product.json`; rejects when neither loads. */
export async function fetchProduct(): Promise<Product> {
  try {
    return await api<Product>("/api/product");
  } catch {
    return await api<Product>("/product.json");
  }
}

export function formatPrice(product: Pick<Product, "amount" | "currency">): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: product.currency,
  }).format(product.amount / 100);
}

export interface CheckoutState {
  disabled: boolean;
  label: string;
  status: string;
}

/**
 * Button copy for a loaded product. `comingSoon` mirrors `data-coming-soon="true"`
 * on the marketing CTA, which always keeps checkout disabled.
 */
export function checkoutState(product: Product, comingSoon: boolean): CheckoutState {
  if (comingSoon) {
    return { disabled: true, label: COMING_SOON_LABEL, status: COMING_SOON_STATUS };
  }
  const enabled = product.available === true && product.mode === "test";
  return {
    disabled: !enabled,
    label: enabled ? "Try test checkout" : "Test checkout not configured",
    status: enabled
      ? "Test mode only. Use Stripe test payment details. No real payment is collected."
      : "Checkout is waiting for secure payment configuration. Live sales are not enabled.",
  };
}

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : GENERIC_ERROR;
}

/** Starts a Stripe test checkout; resolves to the validated destination. */
export async function startCheckout(): Promise<string> {
  const result = await api<{ url?: string }>("/api/checkout", {});
  const url = new URL(String(result.url));
  if (url.protocol !== "https:" || url.hostname !== "checkout.stripe.com") {
    throw new Error("Checkout returned an unexpected destination. Please contact support.");
  }
  return url.href;
}
