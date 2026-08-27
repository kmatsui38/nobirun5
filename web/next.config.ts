import type { NextConfig } from "next";

// 実装規約（docs/requirements/03_技術スタック選定.md 4.6）:
// フロントは完全静的（SPA）。output:'export' を維持し、
// APIルート・Server Actions・SSR・ミドルウェアは使用しない。
// これにより Vercel → S3+CloudFront の移行がアップロード先の変更だけで済む。
const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
};

export default nextConfig;
