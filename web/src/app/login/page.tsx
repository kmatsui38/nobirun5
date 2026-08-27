"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabase } from "@/lib/supabase";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const supabase = getSupabase();
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });
      if (error) {
        setError("IDまたはパスワードが違います。");
        return;
      }
      router.push("/");
    } catch {
      setError("ログインに失敗しました。設定を確認してください。");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="flex-1 grid place-items-center p-6">
      <form onSubmit={onSubmit} className="w-full max-w-sm flex flex-col gap-4">
        <h1 className="text-xl font-bold text-center mb-2">ログイン</h1>
        <label className="flex flex-col gap-1 text-sm">
          ID（メールアドレス）
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            autoComplete="username"
            className="rounded-lg border border-stone-300 px-3 py-3 text-base"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          パスワード
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            autoComplete="current-password"
            className="rounded-lg border border-stone-300 px-3 py-3 text-base"
          />
        </label>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button
          type="submit"
          disabled={busy}
          className="rounded-full bg-emerald-600 py-3 text-white font-bold disabled:opacity-50"
        >
          {busy ? "ログイン中…" : "ログイン"}
        </button>
      </form>
    </main>
  );
}
