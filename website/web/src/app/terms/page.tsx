import Link from "next/link";
import type { Metadata } from "next";
import Brand from "@/components/site/Brand";
import PreviewBanner from "@/components/site/PreviewBanner";
import SkipLink from "@/components/site/SkipLink";

export const metadata: Metadata = {
  title: "Proposed purchase terms",
};

/** Port of website/public/terms.html. */
export default function TermsPage() {
  return (
    <>
      <SkipLink />
      <PreviewBanner />
      <main className="section document" id="main">
        <Brand />
        <h1>A clear little agreement.</h1>
        <p>
          <strong>Draft for owner review. These terms are not approved for live sales.</strong>{" "}
          This release candidate uses Stripe test mode only and does not accept real payments.
        </p>
        <h2>Proposed offer</h2>
        <p>
          US $9.99 once for DockGrove major version 1, its maintenance updates. The proposed
          allowance is three personal Macs. No subscription is included, and future major-version
          upgrades are not automatically included.
        </p>
        <h2>Activation and offline use</h2>
        <p>
          Initial activation requires an internet connection. A valid signed activation is cached
          for up to 30 days of offline use, with online refresh required afterward. A successful
          refresh renews that period. Refunds (including partial refunds), disputes or revoked
          purchases can suspend future activation or refresh pending owner review. Revocation
          cannot instantly invalidate an already cached offline entitlement. Restoring Apple’s Dock
          and quitting DockGrove remain available even when a license is invalid or the service is
          unavailable.
        </p>
        <p>
          Deactivate a Mac before reusing its slot on another one. Purchase recovery requires access
          to the checkout email address and a configured recovery service. Service interruptions do
          not erase local app data.
        </p>
        <h2>Compatibility and permissions</h2>
        <p>
          macOS 14 or newer is required. Some widgets need additional provider accounts or macOS
          permissions. Native Liquid Glass requires a supported macOS release; older systems use a
          native material fallback. DockGrove does not implement every feature of Apple’s system
          Dock.
        </p>
        <h2>Legacy software and notices</h2>
        <p>
          Previously distributed DockGrove 0.8 code was licensed under MIT. Existing copies keep
          those permissions. Required MIT and third-party notices must be preserved in derived
          material. These proposed commercial terms do not retroactively change rights in old
          releases.
        </p>
        <h2>Before sales open</h2>
        <p>
          The owner must approve the commercial license boundary, seller identity, refund and
          support policy, applicable taxes, retention policy, and these customer terms. Apple
          signing and notarization are handled separately. No refund promise, tax registration, or
          legal approval is asserted by this draft.
        </p>
        <p className="support-link">
          <Link href="/">← Back to DockGrove</Link> ·{" "}
          <a href="https://github.com/dylanlasensky/DockGrove/issues">Support</a> ·{" "}
          <Link href="/privacy">Privacy</Link>
        </p>
      </main>
    </>
  );
}
