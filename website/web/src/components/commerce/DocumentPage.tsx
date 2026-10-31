import type { ReactNode } from "react";
import Link from "next/link";
import SkipLink from "@/components/site/SkipLink";
import PreviewBanner from "@/components/site/PreviewBanner";
import Brand from "@/components/site/Brand";
import { document, link, p } from "./classes";

/** `<main class="section document">` chrome shared by the purchase and recover pages. */
export default function DocumentPage({ children }: { children: ReactNode }) {
  return (
    <>
      <SkipLink />
      <PreviewBanner />
      <main className={document} id="main">
        <Brand />
        {children}
        <p className={p}>
          <Link className={link} href="/">
            ← Back to DockGrove
          </Link>{" "}
          ·{" "}
          <a className={link} href="https://github.com/dylanlasensky/DockGrove/issues">
            Support
          </a>{" "}
          ·{" "}
          <Link className={link} href="/privacy">
            Privacy
          </Link>
        </p>
      </main>
    </>
  );
}
