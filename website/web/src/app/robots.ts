import type {MetadataRoute} from "next";

export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  return {rules: {userAgent: "*", allow: "/", disallow: ["/purchase", "/recover"]}, sitemap: "https://dockgrove.com/sitemap.xml"};
}
