import type { Metadata } from "next";
import RefinedLanding from "@/components/home/RefinedLanding";

export const metadata: Metadata = {
  title: "DockGrove — Everything within reach.",
  description:
    "A calmer space for your Mac. DockGrove brings apps, useful widgets, AI usage and window controls into one beautifully considered Dock. A commercial release in preparation.",
  alternates: { canonical: "https://dockgrove.com/" },
  openGraph: {
    title: "DockGrove — Everything within reach.",
    description: "Your apps. Your tools. A little more room to think.",
    type: "website",
    url: "https://dockgrove.com/",
    images: ["https://dockgrove.com/assets/DockGrove-wordmark.png"],
  },
};

export default function Home() {
  return <RefinedLanding />;
}
