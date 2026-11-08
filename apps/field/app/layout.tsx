import type { Metadata, Viewport } from "next";
import "./globals.css";
import "./workspace.css";
import "./task-flow.css";
import "./decision-room.css";
import "./refinement.css";
import "./investigation.css";
import "./fleet.css";
import "./operations.css";
export const metadata: Metadata = {
  title: "PitCrew · Sector operations",
  description:
    "Sector agents investigate signals, dispatch qualified technicians, and carry the evidence through every handoff.",
  manifest: "/manifest.webmanifest",
  icons: {
    icon: { url: "/icon.svg", type: "image/svg+xml" },
    shortcut: "/icon.svg",
  },
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "PitCrew",
  },
};
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#080809",
};
export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
