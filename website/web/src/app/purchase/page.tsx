import type { Metadata } from "next";
import DocumentPage from "@/components/commerce/DocumentPage";
import PurchaseFlow from "@/components/commerce/PurchaseFlow";
import { fine, h1 } from "@/components/commerce/classes";

export const metadata: Metadata = {
  title: { absolute: "Your purchase — DockGrove" },
};

export default function PurchasePage() {
  return (
    <DocumentPage>
      <h1 className={h1}>Your next little upgrade.</h1>
      <PurchaseFlow />
      <p className={fine}>
        The return page alone is not proof of payment. A license appears only
        after the server verifies Stripe’s payment record.
      </p>
    </DocumentPage>
  );
}
