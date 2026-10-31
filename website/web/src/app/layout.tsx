import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://dockgrove.com"),
  title: {
    default: "DockGrove — Thoughtfully at hand.",
    template: "%s — DockGrove",
  },
  description:
    "A calmer space for your Mac. DockGrove brings apps, useful widgets, AI usage and window controls into one beautifully considered Dock. A commercial release in preparation.",
  icons: { icon: [{ url: "/assets/DockGrove-icon.png", type: "image/png" }] },
  openGraph: {
    title: "DockGrove — Find your flow.",
    description: "Your apps. Your tools. A little more room to think.",
    type: "website",
    url: "https://dockgrove.com/",
    images: ["https://dockgrove.com/assets/DockGrove-wordmark.png"],
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#111214",
  colorScheme: "light dark",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
