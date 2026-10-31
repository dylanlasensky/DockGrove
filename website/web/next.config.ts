import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Static files in `out/`; `/api/*` is served by the separate Worker backend.
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
