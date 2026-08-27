"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { getSupabase, isSupabaseConfigured } from "@/lib/supabase";

type Question = {
  id: string;
  seq: number;
  format: "numeric" | "choice";
  body: string;
  choices: string[] | null;
  answer_fields: string[] | null;
  answered: boolean;
  was_correct: boolean | null;
};

type SetData = {
  set_id: string;
  set_date: string;
  completed: boolean;
  questions: Question[];
};

type Result = {
  is_correct: boolean;
  correct_answer: Record<string, unknown>;
  explanation: string;
};

type Phase =
  | { kind: "loading" }
  | { kind: "error"; message: string }
  | { kind: "question"; index: number }
  | { kind: "result"; index: number; result: Result }
  | { kind: "done"; streak: number | null };

export default function SessionPage() {
  const [setData, setSetData] = useState<SetData | null>(null);
  const [phase, setPhase] = useState<Phase>({ kind: "loading" });
  const [inputs, setInputs] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setPhase({ kind: "error", message: "Supabaseが未設定です。" });
      return;
    }
    const supabase = getSupabase();
    supabase.rpc("get_or_create_daily_set").then(({ data, error }) => {
      if (error || !data) {
        setPhase({ kind: "error", message: "セットの取得に失敗しました。" });
        return;
      }
      if (data.error === "no_questions") {
        setPhase({
          kind: "error",
          message: "出題できる問題がありません（テンプレート未承認の可能性）。",
        });
        return;
      }
      const set = data as SetData;
      setSetData(set);
      if (set.completed) {
        setPhase({ kind: "done", streak: null });
        return;
      }
      const next = set.questions.findIndex((q) => !q.answered);
      if (next === -1) {
        void completeSet(set.set_id);
      } else {
        setPhase({ kind: "question", index: next });
      }
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const current = useMemo(() => {
    if (!setData) return null;
    if (phase.kind !== "question" && phase.kind !== "result") return null;
    return setData.questions[phase.index];
  }, [setData, phase]);

  async function completeSet(setId: string) {
    const supabase = getSupabase();
    const { data } = await supabase.rpc("complete_daily_set", {
      p_set_id: setId,
    });
    setPhase({ kind: "done", streak: data?.streak ?? null });
  }

  async function submit() {
    if (!setData || !current || phase.kind !== "question" || busy) return;
    const answer: Record<string, string> = {};
    if (current.format === "choice") {
      if (!inputs["choice"]) return;
      answer["choice"] = inputs["choice"];
    } else {
      for (const f of current.answer_fields ?? []) {
        if (!inputs[f]?.trim()) return;
        answer[f] = inputs[f].trim();
      }
    }
    setBusy(true);
    try {
      const supabase = getSupabase();
      const { data, error } = await supabase.rpc("submit_answer", {
        p_set_question_id: current.id,
        p_answer: answer,
      });
      if (error || !data) {
        setPhase({ kind: "error", message: "解答の送信に失敗しました。" });
        return;
      }
      current.answered = true;
      current.was_correct = data.is_correct;
      setPhase({ kind: "result", index: phase.index, result: data as Result });
    } finally {
      setBusy(false);
    }
  }

  function next() {
    if (!setData || phase.kind !== "result") return;
    setInputs({});
    const nextIndex = setData.questions.findIndex((q) => !q.answered);
    if (nextIndex === -1) {
      void completeSet(setData.set_id);
    } else {
      setPhase({ kind: "question", index: nextIndex });
    }
  }

  const total = setData?.questions.length ?? 0;
  const answeredCount = setData?.questions.filter((q) => q.answered).length ?? 0;

  return (
    <main className="flex-1 flex flex-col p-6">
      <header className="flex items-center justify-between pt-4 mb-4">
        <h1 className="font-bold">今日の復習</h1>
        <Link href="/" className="text-sm text-stone-500">
          とじる
        </Link>
      </header>

      {total > 0 && phase.kind !== "done" && (
        <div className="h-2 rounded-full bg-stone-200 mb-6">
          <div
            className="h-2 rounded-full bg-emerald-500 transition-all"
            style={{ width: `${(answeredCount / total) * 100}%` }}
          />
        </div>
      )}

      {phase.kind === "loading" && (
        <div className="flex-1 grid place-items-center text-stone-500">
          問題を準備中…
        </div>
      )}

      {phase.kind === "error" && (
        <div className="flex-1 grid place-items-center">
          <p className="text-sm text-red-600">{phase.message}</p>
        </div>
      )}

      {(phase.kind === "question" || phase.kind === "result") && current && (
        <div className="flex flex-col gap-5">
          <p className="text-xs text-stone-500">
            {answeredCount + (phase.kind === "result" ? 0 : 1)} / {total} 問目
          </p>
          <div className="rounded-2xl bg-white border border-stone-200 p-5 whitespace-pre-wrap leading-relaxed">
            {current.body}
          </div>

          {current.format === "choice" && (
            <div className="grid gap-2">
              {(current.choices ?? []).map((c) => (
                <button
                  key={c}
                  disabled={phase.kind === "result"}
                  onClick={() => setInputs({ choice: c })}
                  className={`rounded-xl border px-4 py-3 text-left ${
                    inputs["choice"] === c
                      ? "border-emerald-600 bg-emerald-50"
                      : "border-stone-300 bg-white"
                  }`}
                >
                  {c}
                </button>
              ))}
            </div>
          )}

          {current.format === "numeric" && (
            <div className="grid gap-3">
              {(current.answer_fields ?? []).map((f) => (
                <label key={f} className="flex items-center gap-3 text-sm">
                  <span className="min-w-16 font-medium">{f}</span>
                  <input
                    type="text"
                    inputMode="numeric"
                    pattern="-?[0-9]*"
                    disabled={phase.kind === "result"}
                    value={inputs[f] ?? ""}
                    onChange={(e) =>
                      setInputs((prev) => ({ ...prev, [f]: e.target.value }))
                    }
                    className="flex-1 rounded-lg border border-stone-300 px-3 py-3 text-base"
                  />
                </label>
              ))}
            </div>
          )}

          {phase.kind === "question" && (
            <button
              onClick={submit}
              disabled={busy}
              className="rounded-full bg-emerald-600 py-3 text-white font-bold disabled:opacity-50"
            >
              {busy ? "採点中…" : "こたえる"}
            </button>
          )}

          {phase.kind === "result" && (
            <div className="flex flex-col gap-4">
              <p
                className={`text-xl font-bold text-center ${
                  phase.result.is_correct ? "text-emerald-600" : "text-red-500"
                }`}
              >
                {phase.result.is_correct ? "正解！" : "ざんねん…"}
              </p>
              {!phase.result.is_correct && (
                <p className="text-sm text-center text-stone-600">
                  正解:{" "}
                  {current.format === "choice"
                    ? String(phase.result.correct_answer["correct"])
                    : Object.entries(phase.result.correct_answer)
                        .map(([k, v]) => `${k} = ${v}`)
                        .join(", ")}
                </p>
              )}
              <div className="rounded-2xl bg-stone-100 p-4 text-sm whitespace-pre-wrap leading-relaxed">
                {phase.result.explanation}
              </div>
              <button
                onClick={next}
                className="rounded-full bg-emerald-600 py-3 text-white font-bold"
              >
                つぎへ
              </button>
            </div>
          )}
        </div>
      )}

      {phase.kind === "done" && (
        <div className="flex-1 grid place-items-center">
          <div className="text-center flex flex-col gap-4">
            <p className="text-2xl font-bold text-emerald-700">
              今日の復習はおしまい！
            </p>
            {phase.streak !== null && (
              <p className="text-stone-600">
                連続 <span className="text-3xl font-bold">{phase.streak}</span> 日
              </p>
            )}
            <div className="flex flex-col gap-2 mt-4">
              <Link
                href="/map/"
                className="rounded-full bg-emerald-600 px-8 py-3 text-white font-bold"
              >
                苦手マップを見る
              </Link>
              <Link href="/" className="text-sm text-stone-500 underline">
                ホームへもどる
              </Link>
            </div>
          </div>
        </div>
      )}
    </main>
  );
}
