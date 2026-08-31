"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getSupabase, isSupabaseConfigured } from "@/lib/supabase";

type HomeState =
  | { kind: "loading" }
  | { kind: "unconfigured" }
  | { kind: "signed_out" }
  | {
      kind: "ready";
      nickname: string;
      streak: number;
      todayDone: boolean;
      // 途中で中断したときに「つづきから」を出すための進捗
      answered: number;
      total: number;
    };

export default function HomePage() {
  const [state, setState] = useState<HomeState>({ kind: "loading" });

  async function signOut() {
    if (!window.confirm("ログアウトします。よろしいですか？")) return;
    try {
      await getSupabase().auth.signOut();
    } catch {
      // 通信に失敗してもローカルのセッションは破棄されるので画面は進める
    }
    setState({ kind: "signed_out" });
  }

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setState({ kind: "unconfigured" });
      return;
    }
    const supabase = getSupabase();
    supabase.auth.getSession().then(async ({ data }) => {
      if (!data.session) {
        setState({ kind: "signed_out" });
        return;
      }
      // ホーム表示に必要な情報を取得（プロフィール・ストリーク・今日の完了状態）
      const { data: home, error } = await supabase.rpc("get_home");
      if (error || !home) {
        setState({
          kind: "ready",
          nickname: "",
          streak: 0,
          todayDone: false,
          answered: 0,
          total: 0,
        });
        return;
      }
      setState({
        kind: "ready",
        nickname: home.nickname ?? "",
        streak: home.streak ?? 0,
        todayDone: home.today_done ?? false,
        answered: home.today_answered ?? 0,
        total: home.today_total ?? 0,
      });
    });
  }, []);

  if (state.kind === "loading") {
    return <main className="flex-1 grid place-items-center">読み込み中…</main>;
  }

  if (state.kind === "unconfigured") {
    return (
      <main className="flex-1 grid place-items-center p-6">
        <div className="rounded-lg border border-amber-300 bg-amber-50 p-4 text-sm">
          <p className="font-bold mb-1">セットアップが必要です</p>
          <p>
            web/.env.local に NEXT_PUBLIC_SUPABASE_URL と
            NEXT_PUBLIC_SUPABASE_ANON_KEY を設定してください。
          </p>
        </div>
      </main>
    );
  }

  if (state.kind === "signed_out") {
    return (
      <main className="flex-1 grid place-items-center p-6">
        <div className="text-center">
          <h1 className="text-2xl font-bold mb-2">nobirun5</h1>
          <p className="text-sm text-stone-600 mb-6">
            毎日コツコツ、苦手を克服しよう
          </p>
          <Link
            href="/login/"
            className="inline-block rounded-full bg-emerald-600 px-8 py-3 text-white font-bold"
          >
            ログイン
          </Link>
        </div>
      </main>
    );
  }

  // 今日のセットを途中まで解いて中断している状態
  const inProgress =
    !state.todayDone && state.answered > 0 && state.answered < state.total;

  return (
    <main className="flex-1 flex flex-col p-6 gap-6">
      <header className="pt-4">
        <h1 className="text-xl font-bold">
          {state.nickname ? `${state.nickname}さん、` : ""}こんにちは
        </h1>
      </header>

      <section className="rounded-2xl bg-white border border-stone-200 p-6 text-center">
        <p className="text-sm text-stone-500 mb-1">連続記録</p>
        <p className="text-4xl font-bold tabular-nums">
          {state.streak}
          <span className="text-base font-normal ml-1">日</span>
        </p>
      </section>

      <section className="flex-1 grid place-items-center">
        {state.todayDone ? (
          <div className="text-center">
            <p className="text-lg font-bold text-emerald-700 mb-2">
              今日の復習は完了！
            </p>
            <p className="text-sm text-stone-600">また明日、続けよう。</p>
          </div>
        ) : (
          <div className="text-center flex flex-col gap-3">
            <Link
              href="/session/"
              className="rounded-full bg-emerald-600 px-10 py-4 text-white text-lg font-bold shadow"
            >
              {inProgress ? "つづきから再開する" : "今日の復習をはじめる"}
            </Link>
            {inProgress && (
              <p className="text-sm text-stone-600">
                {state.answered} / {state.total} 問おわってるよ
              </p>
            )}
          </div>
        )}
      </section>

      <nav className="pb-6 flex items-center justify-between">
        <Link href="/map/" className="text-sm text-emerald-700 underline">
          苦手マップを見る
        </Link>
        <button
          onClick={signOut}
          className="text-sm text-stone-500 underline"
        >
          ログアウト
        </button>
      </nav>
    </main>
  );
}
