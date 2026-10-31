import type { Metadata } from "next";
import DocumentPage from "@/components/commerce/DocumentPage";
import RecoveryFlow from "@/components/commerce/RecoveryFlow";
import { fine, h1, p } from "@/components/commerce/classes";

export const metadata: Metadata = {
  title: { absolute: "Restore purchase — DockGrove" },
};

export default function RecoverPage() {
  return (
    <DocumentPage>
      <h1 className={h1}>Back to your space.</h1>
      <p className={p}>
        Recover your test license using the email address from checkout. No new
        purchase is needed.
      </p>
      <RecoveryFlow />
      <p className={fine}>
        Recovery links expire after 15 minutes and can be used once. If you no
        longer have access to your purchase email, contact support without
        sharing your license or payment details in a public issue.
      </p>
    </DocumentPage>
  );
}
