"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getSupabase, isSupabaseConfigured } from "@/lib/supabase";

type UnitStat = {
  unit_id: string;
  grade: number;
  domain: string;
  name: string;
  item_count: number;
  touched_count: number;
  avg_box: number;
};

// 定着度（avg_box 0〜5）に応じた色。0=未着手(グレー)、低=赤系、高=緑系
function boxColor(stat: UnitStat): string {
  if (stat.touched_count === 0) return "bg-stone-100 text-stone-400";
  if (stat.avg_box < 1.5) return "bg-red-100 text-red-800";
  if (stat.avg_box < 3) return "bg-amber-100 text-amber-800";
  if (stat.avg_box < 4.5) return "bg-lime-100 text-lime-800";
  return "bg-emerald-200 text-emerald-900";
}

export default function MapPage() {
  const [stats, setStats] = useState<UnitStat[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setError("Supabaseが未設定です。");
      return;
    }
    getSupabase()
      .rpc("get_mastery_map")
      .then(({ data, error }) => {
        if (error || !data) {
          setError("苦手マップの取得に失敗しました。");
          return;
        }
        setStats(data as UnitStat[]);
      });
  }, []);

  const grades = [1, 2, 3];

  return (
    <main className="flex-1 flex flex-col p-6">
      <header className="flex items-center justify-between pt-4 mb-6">
        <h1 className="font-bold">苦手マップ</h1>
        <Link href="/" className="text-sm text-stone-500">
          もどる
        </Link>
      </header>

      {error && <p className="text-sm text-red-600">{error}</p>}
      {!stats && !error && <p className="text-sm text-stone-500">読み込み中…</p>}

      {stats && (
        <div className="flex flex-col gap-6 pb-8">
          {grades.map((g) => {
            const units = stats.filter((s) => s.grade === g);
            if (units.length === 0) return null;
            return (
              <section key={g}>
                <h2 className="text-sm font-bold text-stone-500 mb-2">
                  中{g}
                </h2>
                <div className="grid grid-cols-2 gap-2">
                  {units.map((u) => (
                    <div
                      key={u.unit_id}
                      className={`rounded-xl p-3 ${boxColor(u)}`}
                    >
                      <p className="text-xs font-bold leading-snug">{u.name}</p>
                      <p className="text-[11px] mt-1">
                        {u.touched_count === 0
                          ? "未学習"
                          : `定着度 ${u.avg_box.toFixed(1)} / 5`}
                      </p>
                    </div>
                  ))}
                </div>
              </section>
            );
          })}
          <div className="text-[11px] text-stone-500 flex gap-3 flex-wrap">
            <span>■ グレー: 未学習</span>
            <span className="text-red-700">■ 赤: 苦手</span>
            <span className="text-amber-700">■ 黄: 定着中</span>
            <span className="text-emerald-700">■ 緑: 定着</span>
          </div>
        </div>
      )}
    </main>
  );
}
