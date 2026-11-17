import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Pin react-dom as a runtime external so documents/renderHtml.ts uses the app's own react-dom/server.
  serverExternalPackages: ["react-dom"],
  /* config options here */
};

export default nextConfig;
