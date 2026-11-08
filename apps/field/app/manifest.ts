import type { MetadataRoute } from "next";
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "PitCrew",
    short_name: "PitCrew",
    description: "Sector teams. Prepared field work. Continuous context.",
    start_url: "/",
    display: "standalone",
    background_color: "#080809",
    theme_color: "#080809",
    icons: [
      { src: "/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" },
    ],
  };
}
