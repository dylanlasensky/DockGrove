import type {MetadataRoute} from "next";

export const dynamic = "force-static";

/** Public pages only: purchase and recover are transactional and stay out of search. */
export default function sitemap(): MetadataRoute.Sitemap {
  return ["", "/privacy", "/terms"].map(path => ({url: `https://dockgrove.com${path || "/"}`, changeFrequency: "monthly", priority: path ? 0.3 : 1}));
}
