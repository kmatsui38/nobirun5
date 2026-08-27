"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getSupabase, isSupabaseConfigured } from "@/lib/supabase";

type UnitStat = {
  unit_id: string;
  grade: number;
  domain: string;
  name: string;
  learned: boolean;
  item_count: number;
  touched_count: number;
  avg_box: number;
};

// 既習単元の定着度（avg_box 0〜5）に応じた色。
// 未習単元は色をつけず、これから習うことが分かる見た目にする。
function tileClass(u: UnitStat): string {
  if (!u.learned) return "bg-stone-50 text-stone-400 border border-dashed border-stone-300";
  if (u.touched_count === 0) return "bg-stone-100 text-stone-500";
  if (u.avg_box < 1.5) return "bg-red-100 text-red-800";
  if (u.avg_box < 3) return "bg-amber-100 text-amber-800";
  if (u.avg_box < 4.5) return "bg-lime-100 text-lime-800";
  return "bg-emerald-200 text-emerald-900";
}

function tileLabel(u: UnitStat): string {
  if (!u.learned) return "まだ習っていない";
  if (u.touched_count === 0) return "これから出題";
  return `定着度 ${u.avg_box.toFixed(1)} / 5`;
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

  const learnedCount = stats?.filter((s) => s.learned).length ?? 0;
  const grades = [1, 2, 3];

  return (
    <main className="flex-1 flex flex-col p-6">
      <header className="flex items-center justify-between pt-4 mb-2">
        <h1 className="font-bold">苦手マップ</h1>
        <Link href="/" className="text-sm text-stone-500">
          もどる
        </Link>
      </header>

      {stats && (
        <p className="text-xs text-stone-500 mb-5">
          習った単元 {learnedCount} / 全 {stats.length} 単元
        </p>
      )}

      {error && <p className="text-sm text-red-600">{error}</p>}
      {!stats && !error && <p className="text-sm text-stone-500">読み込み中…</p>}

      {stats && (
        <div className="flex flex-col gap-6 pb-8">
          {grades.map((g) => {
            const units = stats.filter((s) => s.grade === g);
            // まだ習っておらず、出題もされていない学年は表示しない
            // （中2の生徒に中3の未習単元だけを並べても情報にならないため）
            if (!units.some((u) => u.learned || u.touched_count > 0)) return null;
            // 習った単元を先に並べる
            const sorted = [...units].sort(
              (a, b) => Number(b.learned) - Number(a.learned)
            );
            return (
              <section key={g}>
                <h2 className="text-sm font-bold text-stone-500 mb-2">中{g}</h2>
                <div className="grid grid-cols-2 gap-2">
                  {sorted.map((u) => (
                    <div
                      key={u.unit_id}
                      className={`rounded-xl p-3 ${tileClass(u)}`}
                    >
                      <p className="text-xs font-bold leading-snug">{u.name}</p>
                      <p className="text-[11px] mt-1">{tileLabel(u)}</p>
                    </div>
                  ))}
                </div>
              </section>
            );
          })}

          <div className="rounded-xl border border-stone-200 bg-white p-4">
            <p className="text-xs font-bold text-stone-500 mb-2">見かた</p>
            <ul className="text-[11px] text-stone-600 flex flex-col gap-1.5">
              <li className="flex items-center gap-2">
                <span className="inline-block w-4 h-4 rounded bg-red-100 border border-red-200" />
                苦手（もう一度やろう）
              </li>
              <li className="flex items-center gap-2">
                <span className="inline-block w-4 h-4 rounded bg-amber-100 border border-amber-200" />
                あと少しで定着
              </li>
              <li className="flex items-center gap-2">
                <span className="inline-block w-4 h-4 rounded bg-emerald-200 border border-emerald-300" />
                定着した
              </li>
              <li className="flex items-center gap-2">
                <span className="inline-block w-4 h-4 rounded bg-stone-100 border border-stone-200" />
                習ったけど、まだ出題されていない
              </li>
              <li className="flex items-center gap-2">
                <span className="inline-block w-4 h-4 rounded bg-stone-50 border border-dashed border-stone-300" />
                まだ習っていない（出題されない）
              </li>
            </ul>
          </div>
        </div>
      )}
    </main>
  );
}
