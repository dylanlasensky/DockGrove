import type { Metadata } from "next";

/**
 * Open Graph fields every page shares. Next replaces a parent's `openGraph`
 * whole rather than merging it, so a page that sets its own title and url must
 * spread these back in or lose its description and preview image.
 */
export const sharedOpenGraph = {
  description: "Your apps. Your tools. A little more room to think.",
  type: "website",
  images: ["https://dockgrove.com/assets/DockGrove-wordmark.png"],
} satisfies Metadata["openGraph"];
