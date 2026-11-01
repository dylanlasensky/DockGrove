import Link from "next/link";
import Brand from "./Brand";

const linkClass =
  "inline-flex min-h-11 items-center no-underline hover:underline";

/** The home page `<footer>` (index.html), styled per home.css. */
export default function SiteFooter() {
  return (
    <footer className="flex flex-wrap items-center gap-[25px] px-[max(6vw,24px)] py-[45px] text-[0.75rem] text-[#59625c] max-[700px]:gap-[18px] max-[700px]:px-6 max-[700px]:py-[35px]">
      <Brand href="#top" className="text-[1rem] text-[#282c28]" />
      <span className="max-[700px]:text-[0.625rem]">Thoughtfully at hand.</span>
      <div className="ml-auto flex flex-wrap gap-[25px] max-[700px]:ml-0 max-[700px]:w-full">
        <Link className={linkClass} href="/privacy">
          Privacy
        </Link>
        <a className={linkClass} href="https://github.com/dylanlasensky/DockGrove/issues">
          Feedback
        </a>
        <Link className={linkClass} href="/terms">
          Proposed terms
        </Link>
      </div>
      <small className="w-full border-t border-[var(--line)] pt-[25px] text-[0.625rem] text-[#59625c] max-[700px]:leading-[1.6]">
        © 2026 DockGrove. An independent project. Nine pixel-art companions, now at home in your
        Dock. Not affiliated with Apple or CoolDock.
      </small>
    </footer>
  );
}
