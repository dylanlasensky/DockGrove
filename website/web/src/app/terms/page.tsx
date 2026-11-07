import Link from "next/link";
import type { Metadata } from "next";
import { sharedOpenGraph } from "@/lib/metadata";
import Brand from "@/components/site/Brand";
import PreviewBanner from "@/components/site/PreviewBanner";
import SkipLink from "@/components/site/SkipLink";

export const metadata: Metadata = {
  title: "Proposed purchase terms",
  description:
    "Draft DockGrove purchase terms for owner review, including direct purchases and the terms that would apply to a copy bought on the App Store. Sales are not open.",
  alternates: { canonical: "/terms" },
  openGraph: {
    ...sharedOpenGraph,
    title: "Proposed purchase terms — DockGrove",
    description:
      "Draft purchase terms for DockGrove, for direct and App Store purchases. Sales are not open.",
    url: "/terms",
  },
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
          Updated November 6, 2026.
        </p>
        <h2>Proposed offer</h2>
        <p>
          US $9.99 once for DockGrove major version 1, its maintenance updates and all nine included
          companions. The proposed allowance is three personal Macs. No subscription is included,
          and future major-version upgrades are not automatically included.
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
        <h2>If you buy on the App Store</h2>
        <p>
          DockGrove is not on the App Store, and no App Store submission is part of this release
          candidate. This section is drafted in case that changes. It would apply only to a copy
          obtained from the App Store.
        </p>
        <p>
          App Store apps are licensed either under Apple’s{" "}
          <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">
            Licensed Application End User License Agreement
          </a>{" "}
          or under a custom agreement from the developer. The App Store listing would show which one
          applies. If it is Apple’s standard agreement, that agreement governs your App Store copy.
          If it is a custom agreement, the terms below apply to your App Store copy, and they take
          priority over anything different elsewhere on this page. “The developer” means the
          developer of DockGrove.
        </p>
        <ul className="my-4 list-disc space-y-3 pl-5 text-[var(--muted)]">
          <li>
            <strong>Who the agreement is with.</strong> This agreement is between you and the
            developer only, not Apple. The developer, not Apple, is solely responsible for DockGrove
            and its content. These terms do not set usage rules that conflict with the Apple Media
            Services Terms and Conditions.
          </li>
          <li>
            <strong>License.</strong> You receive a non-transferable license to use DockGrove on any
            Apple-branded products you own or control, as the Usage Rules in the Apple Media
            Services Terms and Conditions permit. Other accounts associated with the purchaser may
            also access, acquire and use it through Family Sharing, volume purchasing or Legacy
            Contacts.
          </li>
          <li>
            <strong>Maintenance and support.</strong> The developer is solely responsible for any
            maintenance and support described in these terms or required by applicable law. Apple
            has no obligation whatsoever to provide maintenance or support for DockGrove.
          </li>
          <li>
            <strong>Warranty.</strong> The developer is solely responsible for any product
            warranties, express or implied by law, to the extent they are not effectively
            disclaimed. If DockGrove fails to conform to an applicable warranty, you may notify
            Apple, and Apple will refund the purchase price to you. To the maximum extent permitted
            by applicable law, Apple has no other warranty obligation for DockGrove. Any other
            claims, losses, liabilities, damages, costs or expenses caused by a failure to conform
            to a warranty are the developer’s sole responsibility.
          </li>
          <li>
            <strong>Refunds.</strong> App Store purchases are refunded through Apple, not the
            developer. You can ask for one at{" "}
            <a href="https://reportaproblem.apple.com/">reportaproblem.apple.com</a>, and Apple
            decides the request under its own terms.
          </li>
          <li>
            <strong>Product claims.</strong> The developer, not Apple, is responsible for addressing
            any claims by you or a third party relating to DockGrove or your possession or use of
            it. These include product liability claims, claims that DockGrove fails to conform to
            any applicable legal or regulatory requirement, and claims under consumer protection or
            similar laws. These terms do not limit the developer’s liability to you beyond what
            applicable law permits.
          </li>
          <li>
            <strong>Intellectual property claims.</strong> If a third party claims that DockGrove, or
            your possession and use of it, infringes their intellectual property rights, the
            developer, not Apple, is solely responsible for investigating, defending, settling and
            discharging that claim.
          </li>
          <li>
            <strong>Legal compliance.</strong> You represent and warrant that you are not located in
            a region subject to a U.S. Government embargo or designated by the U.S. Government as a
            “terrorist supporting” region, and that you are not listed on any U.S. Government list
            of prohibited or restricted parties.
          </li>
          <li>
            <strong>Third-party terms.</strong> You must comply with applicable third-party terms
            when you use DockGrove, including the terms of any service or provider account you
            connect to a widget.
          </li>
          <li>
            <strong>Third-party beneficiary.</strong> You and the developer acknowledge and agree
            that Apple and Apple’s subsidiaries are third-party beneficiaries of this agreement.
            Once you accept these terms, Apple has the right, and is deemed to have accepted the
            right, to enforce them against you as a third-party beneficiary.
          </li>
          <li>
            <strong>Questions, complaints and claims.</strong> These go to the developer, not Apple.
            The developer’s name, address, telephone number and email address will be published here
            before any App Store sale. They are not listed yet because the seller’s identity has not
            been approved.
          </li>
        </ul>
        <h2>Direct purchases</h2>
        <p>
          A copy bought directly through this website stays under the other proposed terms on this
          page, not the App Store section above. Apple is not a party to a direct purchase and does
          not handle its refunds or support. The three-Mac allowance, activation, offline period,
          deactivation and purchase recovery described here apply to direct purchases.
        </p>
        <h2>Before sales open</h2>
        <p>
          The owner must approve the commercial license boundary, seller identity, refund and
          support policy, applicable taxes, retention policy, and these customer terms. An App Store
          release would also need the owner to choose Apple’s standard agreement or a custom one,
          and to publish the developer’s contact details. Apple signing and notarization are handled
          separately. No refund promise, tax registration, or
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
