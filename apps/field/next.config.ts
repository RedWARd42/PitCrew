import type { NextConfig } from "next";
import path from "node:path";
import { existsSync } from "node:fs";
const workspaceRoot = path.resolve(__dirname, "../..");
const envPath = path.join(workspaceRoot, ".env");
if (existsSync(envPath)) process.loadEnvFile(envPath);
const config: NextConfig = {
  // Keep a demo server and a verification build from overwriting each other's artifacts.
  distDir: process.env.NEXT_DIST_DIR ?? ".next",
  outputFileTracingRoot: workspaceRoot,
  devIndicators: false,
  experimental: { externalDir: true },
};
export default config;
