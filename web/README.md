# nobirun5 web

nobirun5 のフロントエンド（Next.js 静的SPA）。

## 実装規約（必読）

[docs/requirements/03_技術スタック選定.md](../docs/requirements/03_技術スタック選定.md) 4.6 のとおり:

- `output: 'export'`（静的エクスポート）を維持する
- **Next.jsのサーバ機能を使わない**: APIルート・Server Actions・SSR・ミドルウェア禁止
- サーバロジックは Supabase（RPC / Edge Functions）に置く

この規約により、Vercel → S3+CloudFront の移行はアップロード先の変更だけで済む。

## セットアップ

1. [Supabase](https://supabase.com) でプロジェクトを作成
2. SQLエディタで `../supabase/migrations/*.sql` を番号順に実行
3. `python3 ../tools/gen_seed_sql.py > ../supabase/seed.sql` を生成してSQLエディタで実行
4. Authentication → Users から被験者のアカウント（メール+パスワード）を作成
5. `.env.example` をコピーして `.env.local` を作り、Project Settings → API の値を設定

```bash
npm install
npm run dev      # http://localhost:3000
npm run build    # 静的エクスポート（out/ に生成）
```

## デプロイ

- MVP: Vercel にgit連携でデプロイ（環境変数を設定）
- 商用化時: `npm run build` の `out/` を S3 に同期し CloudFront で配信

## 画面

| パス | 画面 | 状態 |
|---|---|---|
| `/` | ホーム（S2）: ストリーク・今日の復習への導線 | 骨組み実装済み |
| `/login` | ログイン（S1） | 実装済み |
| `/session` | 復習セッション（S3/S4） | プレースホルダ |
| `/map` | 苦手マップ（S5） | プレースホルダ |
