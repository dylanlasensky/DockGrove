import type { Metadata } from "next";
import RefinedLanding from "@/components/home/RefinedLanding";

export const metadata: Metadata = {
  alternates: { canonical: "https://dockgrove.com/" },
};

export default function Home() {
  return <RefinedLanding />;
}
