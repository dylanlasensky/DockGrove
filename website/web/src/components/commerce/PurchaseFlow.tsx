"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import {
  assertLicense,
  CHECKOUT_UNAVAILABLE,
  checkoutButtonState,
  errorMessage,
  formatPrice,
  getPurchase,
  loadProduct,
  PURCHASE_CANCELLED_MESSAGE,
  PURCHASE_CHECKING_MESSAGE,
  PURCHASE_DEFAULT_MESSAGE,
  PURCHASE_POLL_ATTEMPTS,
  PURCHASE_POLL_DELAY_MS,
  purchaseStatusMessage,
  returnMode,
  startCheckout,
  type CheckoutButtonState,
  type Product,
} from "@/lib/commerce";
import Link from "next/link";
import LicensePanel from "./LicensePanel";
import { cardButton, fine, formCard, full, h2, link, p, statusMessage } from "./classes";

const INITIAL_BUTTON: CheckoutButtonState = {
  disabled: true,
  label: "Checking test checkout…",
  status: "No live payments are being accepted.",
};

// The return URL's query string: `null` while server-rendering / hydrating.
const noSubscribe = () => () => {};
const getSearch = () => window.location.search;
const getServerSearch = () => null;

/** Port of the purchase.html `.form-card` and app.js purchase behavior. */
export default function PurchaseFlow({ comingSoon = false }: { comingSoon?: boolean }) {
  const search = useSyncExternalStore(noSubscribe, getSearch, getServerSearch);
  const mode = search === null ? null : returnMode(search);
  const [price, setPrice] = useState("—");
  const [checkout, setCheckout] = useState<CheckoutButtonState>(INITIAL_BUTTON);
  const [verifyStatus, setVerifyStatus] = useState<string | null>(null);
  const [license, setLicense] = useState("");

  const purchaseStatus =
    mode === "offer"
      ? PURCHASE_DEFAULT_MESSAGE
      : mode === "cancelled"
        ? PURCHASE_CANCELLED_MESSAGE
        : (verifyStatus ?? PURCHASE_CHECKING_MESSAGE);

  // loadProduct(): price from /api/product (falling back to /product.json), gate the button.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      let product: Product;
      try {
        product = await loadProduct();
      } catch {
        if (cancelled) return;
        setPrice("Price unavailable");
        setCheckout(CHECKOUT_UNAVAILABLE);
        return;
      }
      if (cancelled) return;
      setPrice(formatPrice(product));
      setCheckout(checkoutButtonState(product, comingSoon));
    })().catch((error) => {
      if (!cancelled) setCheckout((s) => ({ ...s, status: errorMessage(error) }));
    });
    return () => {
      cancelled = true;
    };
  }, [comingSoon]);

  // ?status=<anything but cancelled>: ask the server, polling while payment is pending.
  useEffect(() => {
    if (mode !== "verify") return;
    let cancelled = false;
    let attempts = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    async function checkPurchase() {
      try {
        const result = await getPurchase();
        if (cancelled) return;
        if (result.status === "paid") {
          setLicense(assertLicense(result.licenseKey));
          setVerifyStatus(purchaseStatusMessage("paid"));
          return;
        }
        setVerifyStatus(purchaseStatusMessage(result.status));
        if (result.status === "pending" && ++attempts < PURCHASE_POLL_ATTEMPTS)
          timer = setTimeout(checkPurchase, PURCHASE_POLL_DELAY_MS);
      } catch (error) {
        if (!cancelled) setVerifyStatus(errorMessage(error));
      }
    }
    checkPurchase();
    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, [mode]);

  async function onCheckout() {
    if (comingSoon) return;
    setCheckout((s) => ({ ...s, disabled: true, status: "Opening secure test checkout…" }));
    try {
      window.location.assign(await startCheckout());
    } catch (error) {
      setCheckout((s) => ({ ...s, disabled: false, status: errorMessage(error) }));
    }
  }

  return (
    <div className={formCard}>
      {mode !== "verify" && (
        <section id="purchase-offer">
          <h2 className={h2}>
            DockGrove <span data-price>{price}</span>
          </h2>
          <p className={p}>
            One-time purchase for major version 1, maintenance updates, all nine
            companions and three personal Macs.
          </p>
          <button
            className={`${cardButton} ${full}`}
            id="checkout-button"
            disabled={checkout.disabled}
            onClick={onCheckout}
            data-coming-soon={comingSoon ? "true" : undefined}
          >
            {checkout.label}
          </button>
          <p className={fine} id="checkout-status" role="status">
            {checkout.status}
          </p>
          <p className={fine}>
            <Link className={link} href="/terms">
              Proposed purchase terms
            </Link>{" "}
            · Test mode only.
          </p>
        </section>
      )}
      <p id="purchase-status" className={statusMessage} role="status">
        {purchaseStatus}
      </p>
      {license && <LicensePanel license={license} />}
      <p className={p}>
        <Link className={link} href="/recover">
          Restore a previous purchase
        </Link>
      </p>
      <p className={p}>
        <Link className={link} href="/#pricing">
          Return to pricing
        </Link>
      </p>
    </div>
  );
}
