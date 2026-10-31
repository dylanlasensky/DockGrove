import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Page not found",
};

/** Port of website/public/404.html. */
export default function NotFound() {
  return (
    <main className="section document">
      <Link className="brand" href="/">
        DockGrove
      </Link>
      <h1>A little off course.</h1>
      <p>That page is not here. Your Dock is a little closer to home.</p>
      <Link className="button" href="/">
        Back to DockGrove
      </Link>
    </main>
  );
}
