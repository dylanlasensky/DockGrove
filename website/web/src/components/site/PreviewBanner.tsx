import { COMMERCE_ENVIRONMENT } from "@/lib/commerce";

/** The release-candidate notice shown above the purchase, recover, terms and privacy pages. */
export default function PreviewBanner() {
  return (
    <div className="bg-[var(--soft)] px-[18px] py-2 text-center text-[0.75rem] tracking-[0.04em] text-[var(--muted)]">
      {COMMERCE_ENVIRONMENT === "production" ? "DockGrove · Purchase and license support" : "1.0 release candidate · Test mode only · Live sales are not enabled"}
    </div>
  );
}
