import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "nobirun5",
  description: "毎日コツコツ復習して苦手を克服する学習アプリ",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ja">
      <body className="min-h-dvh bg-stone-50 text-stone-800 antialiased">
        <div className="mx-auto max-w-md min-h-dvh flex flex-col">{children}</div>
      </body>
    </html>
  );
}
