"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { getSupabase, isSupabaseConfigured } from "@/lib/supabase";

type Question = {
  id: string;
  seq: number;
  format: "numeric" | "choice";
  body: string;
  memo: string | null;
  choices: string[] | null;
  answer_fields: string[] | null;
  answered: boolean;
  was_correct: boolean | null;
};

type SetData = {
  set_id: string;
  set_date: string;
  started_at: string | null;
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

const MEMO_SAVE_DELAY_MS = 800;

export default function SessionPage() {
  const router = useRouter();
  const [setData, setSetData] = useState<SetData | null>(null);
  const [phase, setPhase] = useState<Phase>({ kind: "loading" });
  const [inputs, setInputs] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [confidence, setConfidence] = useState<boolean | null>(null);
  const [memo, setMemo] = useState("");
  const [resumedFrom, setResumedFrom] = useState<number | null>(null);

  // 1問あたりの所要時間。「問題が実際に画面に見えていた時間」だけを足す。
  // 画面を伏せた・別アプリに移った時間は数えない（考えていた時間ではないため）。
  const timer = useRef<{ acc: number; since: number | null }>({
    acc: 0,
    since: null,
  });
  const startTimer = useCallback(() => {
    timer.current = { acc: 0, since: Date.now() };
  }, []);
  const pauseTimer = useCallback(() => {
    const t = timer.current;
    if (t.since !== null) {
      t.acc += Date.now() - t.since;
      t.since = null;
    }
  }, []);
  const resumeTimer = useCallback(() => {
    const t = timer.current;
    if (t.since === null) t.since = Date.now();
  }, []);
  const readTimer = useCallback(() => {
    const t = timer.current;
    return Math.round(t.acc + (t.since !== null ? Date.now() - t.since : 0));
  }, []);

  const current = useMemo(() => {
    if (!setData) return null;
    if (phase.kind !== "question" && phase.kind !== "result") return null;
    return setData.questions[phase.index];
  }, [setData, phase]);

  // メモは書いたそばから保存する。中断しても消えないようにするため。
  const savedMemo = useRef("");
  const saveMemo = useCallback(async (questionId: string, text: string) => {
    if (text === savedMemo.current) return;
    const previous = savedMemo.current;
    savedMemo.current = text;
    try {
      await getSupabase().rpc("save_memo", {
        p_set_question_id: questionId,
        p_memo: text,
      });
    } catch {
      // メモの保存失敗で学習を止めない。
      // 保存済みの目印を戻しておき、次の入力か送信時にもう一度保存させる。
      savedMemo.current = previous;
    }
  }, []);

  useEffect(() => {
    if (!current || phase.kind === "done") return;
    const id = current.id;
    const t = setTimeout(() => {
      void saveMemo(id, memo);
      current.memo = memo === "" ? null : memo;
    }, MEMO_SAVE_DELAY_MS);
    return () => clearTimeout(t);
  }, [memo, current, phase.kind, saveMemo]);

  // 画面が見えていない間はタイマーを止める
  useEffect(() => {
    function onVisibility() {
      if (document.hidden) pauseTimer();
      else if (phase.kind === "question") resumeTimer();
    }
    document.addEventListener("visibilitychange", onVisibility);
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, [phase.kind, pauseTimer, resumeTimer]);

  const showQuestion = useCallback(
    (set: SetData, index: number) => {
      setInputs({});
      setConfidence(null);
      const q = set.questions[index];
      setMemo(q.memo ?? "");
      savedMemo.current = q.memo ?? "";
      startTimer();
      setPhase({ kind: "question", index });
    },
    [startTimer]
  );

  const completeSet = useCallback(async (setId: string) => {
    const { data } = await getSupabase().rpc("complete_daily_set", {
      p_set_id: setId,
    });
    setPhase({ kind: "done", streak: data?.streak ?? null });
  }, []);

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setPhase({ kind: "error", message: "Supabaseが未設定です。" });
      return;
    }
    getSupabase()
      .rpc("get_or_create_daily_set")
      .then(({ data, error }) => {
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
          return;
        }
        // 途中まで解いていたら、その次の問題から再開する
        if (next > 0) setResumedFrom(next + 1);
        showQuestion(set, next);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
    const elapsedMs = readTimer();
    pauseTimer();
    setBusy(true);
    try {
      await saveMemo(current.id, memo);
      const { data, error } = await getSupabase().rpc("submit_answer", {
        p_set_question_id: current.id,
        p_answer: answer,
        p_elapsed_ms: elapsedMs,
      });
      if (error || !data) {
        setPhase({ kind: "error", message: "解答の送信に失敗しました。" });
        return;
      }
      current.answered = true;
      current.was_correct = data.is_correct;
      setConfidence(null);
      setPhase({ kind: "result", index: phase.index, result: data as Result });
    } finally {
      setBusy(false);
    }
  }

  // 自信申告（正解時のみ）。定着判定は変えず、次回出題間隔だけを補正する。
  // スキップ可能なので、失敗しても学習の流れは止めない。
  async function rateConfidence(confident: boolean) {
    if (!current || confidence !== null) return;
    setConfidence(confident);
    try {
      await getSupabase().rpc("rate_confidence", {
        p_set_question_id: current.id,
        p_confident: confident,
      });
    } catch {
      // 申告の失敗は無視（未申告扱い＝現行挙動のまま）
    }
  }

  function next() {
    if (!setData || phase.kind !== "result") return;
    // 再開の案内は最初の1問だけに出す（次の問題からは今日の続きなので）
    setResumedFrom(null);
    const nextIndex = setData.questions.findIndex((q) => !q.answered);
    if (nextIndex === -1) {
      void completeSet(setData.set_id);
    } else {
      showQuestion(setData, nextIndex);
    }
  }

  // 中断。解答済みの分はサーバに残るので、次に開けば続きから再開できる。
  async function pause() {
    pauseTimer();
    if (current) await saveMemo(current.id, memo);
    router.push("/");
  }

  const total = setData?.questions.length ?? 0;
  const answeredCount = setData?.questions.filter((q) => q.answered).length ?? 0;
  const inProgress = phase.kind === "question" || phase.kind === "result";

  return (
    <main className="flex-1 flex flex-col p-6">
      <header className="flex items-center justify-between pt-4 mb-4">
        <h1 className="font-bold">今日の復習</h1>
        {inProgress ? (
          <button onClick={pause} className="text-sm text-stone-500 underline">
            中断する
          </button>
        ) : (
          <Link href="/" className="text-sm text-stone-500">
            とじる
          </Link>
        )}
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

      {inProgress && current && (
        <div className="flex flex-col gap-5">
          {resumedFrom !== null && (
            <p className="rounded-xl bg-emerald-50 border border-emerald-200 px-4 py-3 text-xs text-emerald-800">
              前回のつづき、{resumedFrom}問目からはじめるよ。
            </p>
          )}

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

          {/* 途中式や気づいたことを書きとめる欄。書いたそばから保存される。 */}
          <div className="flex flex-col gap-1.5">
            <label htmlFor="memo" className="text-xs text-stone-500">
              メモ（途中式・気づいたこと）
            </label>
            <textarea
              id="memo"
              rows={4}
              value={memo}
              onChange={(e) => setMemo(e.target.value)}
              onBlur={() => current && void saveMemo(current.id, memo)}
              maxLength={2000}
              placeholder="計算の途中や、まちがえた理由を書いておこう"
              className="rounded-xl border border-stone-300 bg-white px-3 py-3 text-base leading-relaxed"
            />
          </div>

          {phase.kind === "question" && (
            <>
              <button
                onClick={submit}
                disabled={busy}
                className="rounded-full bg-emerald-600 py-3 text-white font-bold disabled:opacity-50"
              >
                {busy ? "採点中…" : "こたえる"}
              </button>
              <p className="text-xs text-stone-500 text-center">
                ここまでの解答とメモは保存されているよ。
                中断しても、つづきから再開できる。
              </p>
            </>
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

              {phase.result.is_correct && (
                <div className="rounded-2xl border border-stone-200 bg-white p-4">
                  <p className="text-sm font-bold text-center mb-3">
                    明日も解ける自信ある？
                  </p>
                  <div className="grid grid-cols-2 gap-2">
                    <button
                      onClick={() => rateConfidence(true)}
                      disabled={confidence !== null}
                      className={`rounded-xl border px-3 py-3 text-sm font-bold ${
                        confidence === true
                          ? "border-emerald-600 bg-emerald-50 text-emerald-800"
                          : "border-stone-300 disabled:opacity-40"
                      }`}
                    >
                      自信あり
                    </button>
                    <button
                      onClick={() => rateConfidence(false)}
                      disabled={confidence !== null}
                      className={`rounded-xl border px-3 py-3 text-sm font-bold ${
                        confidence === false
                          ? "border-amber-500 bg-amber-50 text-amber-800"
                          : "border-stone-300 disabled:opacity-40"
                      }`}
                    >
                      まだ不安
                    </button>
                  </div>
                  {confidence === false && (
                    <p className="text-xs text-stone-500 text-center mt-3">
                      早めにもう一度出すね。
                    </p>
                  )}
                </div>
              )}

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
