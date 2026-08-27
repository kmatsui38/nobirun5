"use client";

import Link from "next/link";

// 今日の復習セッション画面（S3）
// 次のイテレーションで実装: RPC get_or_create_daily_set → 1問ずつ出題 →
// 解答 → RPC submit_answer（採点・習熟ボックス更新）→ 解説表示 → 次へ
export default function SessionPage() {
  return (
    <main className="flex-1 flex flex-col p-6">
      <header className="flex items-center justify-between pt-4 mb-6">
        <h1 className="font-bold">今日の復習</h1>
        <Link href="/" className="text-sm text-stone-500">
          とじる
        </Link>
      </header>
      <div className="flex-1 grid place-items-center">
        <p className="text-sm text-stone-500">
          出題機能は次のイテレーションで実装します。
        </p>
      </div>
    </main>
  );
}
