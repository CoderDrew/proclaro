import type { NextConfig } from "next";

const chromiumBin = "./node_modules/@sparticuz/chromium/bin/**";

const nextConfig: NextConfig = {
  // Pin react-dom as a runtime external so documents/renderHtml.ts uses the app's own react-dom/server.
  // @sparticuz/chromium ships its browser as files under bin/; it must stay external so those files are traced.
  serverExternalPackages: ["react-dom", "@sparticuz/chromium"],
  // The serverless browser (67 MB) is read at runtime, so tracing misses it. Ship it only with the routes that render
  // PDFs. Keys are globs, so the bracketed segments are escaped.
  outputFileTracingIncludes: {
    "/api/bids/\\[bidId\\]/form": [chromiumBin],
    "/api/solicitations/\\[id\\]/blank-form": [chromiumBin],
    "/api/solicitations/\\[id\\]/preview": [chromiumBin],
    "/office/solicitations/\\[id\\]": [chromiumBin],
    "/office/solicitations/\\[id\\]/addenda/\\[addendumId\\]": [chromiumBin],
  },
};

export default nextConfig;
