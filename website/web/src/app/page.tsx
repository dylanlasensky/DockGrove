import type { Metadata } from "next";
import SkipLink from "@/components/site/SkipLink";
import SiteFooter from "@/components/site/SiteFooter";
import SiteHeader from "@/components/home/SiteHeader";
import Hero from "@/components/home/Hero";
import Experience from "@/components/home/Experience";
import Intelligence from "@/components/home/Intelligence";
import Widgets from "@/components/home/Widgets";
import Workspace from "@/components/home/Workspace";
import Personalize from "@/components/home/Personalize";
import Companions from "@/components/home/Companions";
import PrivacySection from "@/components/home/PrivacySection";
import Questions from "@/components/home/Questions";
import Download from "@/components/home/Download";

export const metadata: Metadata = {
  title: "DockGrove — Thoughtfully at hand.",
  description:
    "A calmer space for your Mac. DockGrove brings apps, useful widgets, AI usage and window controls into one beautifully considered Dock. A commercial release in preparation.",
  alternates: { canonical: "https://dockgrove.com/" },
  openGraph: {
    title: "DockGrove — Find your flow.",
    description: "Your apps. Your tools. A little more room to think.",
    type: "website",
    url: "https://dockgrove.com/",
    images: ["https://dockgrove.com/assets/DockGrove-wordmark.png"],
  },
};

export default function Home() {
  return (
    <div className="home-theme flex-1">
      <SkipLink />
      <SiteHeader />
      <main id="main">
        <Hero />
        <Experience />
        <Intelligence />
        <Widgets />
        <Workspace />
        <Personalize />
        <Companions />
        <PrivacySection />
        <Questions />
        <Download />
      </main>
      <SiteFooter />
    </div>
  );
}
