"use client";

import Link from "next/link";

// 苦手マップ画面（S5）
// 次のイテレーションで実装: RPC get_mastery_map → 単元×定着度ヒートマップ表示
export default function MapPage() {
  return (
    <main className="flex-1 flex flex-col p-6">
      <header className="flex items-center justify-between pt-4 mb-6">
        <h1 className="font-bold">苦手マップ</h1>
        <Link href="/" className="text-sm text-stone-500">
          もどる
        </Link>
      </header>
      <div className="flex-1 grid place-items-center">
        <p className="text-sm text-stone-500">
          苦手マップは次のイテレーションで実装します。
        </p>
      </div>
    </main>
  );
}
