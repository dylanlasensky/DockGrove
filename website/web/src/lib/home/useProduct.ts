"use client";

import { useEffect, useState } from "react";
import {
  CHECKOUT_COMING_SOON,
  CHECKOUT_UNAVAILABLE,
  checkoutButtonState,
  errorMessage,
  formatPrice,
  loadProduct,
  startCheckout,
} from "@/lib/commerce";

/** Fallback copy shown while product.json has not loaded yet (matches the static HTML). */
const DEFAULT_PRICE = "$9.99";
const DEFAULT_DEVICES = "3";
const UNAVAILABLE_PRICE = "Price unavailable";

export interface ProductView {
  price: string;
  devices: string;
  buttonDisabled: boolean;
  buttonLabel: string;
  status: string;
  /** Click handler for the checkout button (no-op while coming soon). */
  checkout: () => void;
}

/**
 * React port of `loadProduct()` + the `#checkout-button` handler from app.js.
 * Renders the static copy first (so the prerendered HTML matches the original), then
 * swaps in the live product details once they load.
 */
export function useProduct(comingSoon: boolean): ProductView {
  const [price, setPrice] = useState(DEFAULT_PRICE);
  const [devices, setDevices] = useState(DEFAULT_DEVICES);
  const [button, setButton] = useState(CHECKOUT_COMING_SOON);

  useEffect(() => {
    let cancelled = false;
    loadProduct()
      .then((product) => {
        if (cancelled) return;
        setPrice(formatPrice(product));
        setDevices(String(product.deviceLimit));
        setButton(checkoutButtonState(product, comingSoon));
      })
      .catch(() => {
        if (cancelled) return;
        setPrice(UNAVAILABLE_PRICE);
        setButton(CHECKOUT_UNAVAILABLE);
      });
    return () => {
      cancelled = true;
    };
  }, [comingSoon]);

  const checkout = () => {
    if (comingSoon) return;
    setButton((b) => ({ ...b, disabled: true, status: "Opening secure test checkout…" }));
    startCheckout()
      .then((href) => window.location.assign(href))
      .catch((error: unknown) =>
        setButton((b) => ({ ...b, disabled: false, status: errorMessage(error) })),
      );
  };

  return {
    price,
    devices,
    buttonDisabled: button.disabled,
    buttonLabel: button.label,
    status: button.status,
    checkout,
  };
}
