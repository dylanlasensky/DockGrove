"use client";

import { useEffect, useState } from "react";
import {
  COMING_SOON_LABEL,
  COMING_SOON_STATUS,
  DEFAULT_DEVICES,
  DEFAULT_PRICE,
  UNAVAILABLE_LABEL,
  UNAVAILABLE_PRICE,
  UNAVAILABLE_STATUS,
  checkoutState,
  errorMessage,
  fetchProduct,
  formatPrice,
  startCheckout,
} from "./product";

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
  const [button, setButton] = useState({
    disabled: true,
    label: COMING_SOON_LABEL,
    status: COMING_SOON_STATUS,
  });

  useEffect(() => {
    let cancelled = false;
    fetchProduct()
      .then((product) => {
        if (cancelled) return;
        setPrice(formatPrice(product));
        setDevices(String(product.deviceLimit));
        setButton(checkoutState(product, comingSoon));
      })
      .catch(() => {
        if (cancelled) return;
        setPrice(UNAVAILABLE_PRICE);
        setButton({ disabled: true, label: UNAVAILABLE_LABEL, status: UNAVAILABLE_STATUS });
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
