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
3. `supabase/seed.sql`（リポジトリ同梱・自動生成済み）をSQLエディタで実行
4. サンプルテンプレートを検品のうえ承認: `update templates set status = 'approved' where id in (...);`
   （検品フローの「人の検品」に相当。実際に数問解いて確認してから承認する）
5. Authentication → Users から被験者のアカウント（メール+パスワード）を作成
   （profiles / streaks はトリガで自動作成）
6. **`../supabase/ops.sql` の「1. 被験者のセットアップ」を実行**
   ニックネーム・学年の設定と、**既習範囲の登録**を行う。
   既習範囲を登録しないと、まだ習っていない単元まで出題されるので必ず設定すること。
7. `.env.example` をコピーして `.env.local` を作り、Project Settings → API の値を設定

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
| `/` | ホーム（S2）: ストリーク・今日の復習への導線・ログアウト | 実装済み |
| `/login` | ログイン（S1） | 実装済み |
| `/session` | 復習セッション（S3/S4）: 出題→採点→解説→完了 | 実装済み |
| `/map` | 苦手マップ（S5）: 単元×定着度ヒートマップ（既習/未習を区別） | 実装済み |

## 運用

被験者の進捗確認・解答履歴の抽出・検証用の集計は `../supabase/ops.sql` にまとめてある。
SupabaseのSQLエディタで必要な部分をコピーして実行する。

## 動作確認済みのバックエンド

マイグレーション・RPCはローカルPostgreSQL 16でE2Eテスト済み:
セット生成（優先順位・単元上限・テンプレート重複禁止）、採点（numeric/choice）、
再解答拒否、未完了時の完了拒否、ストリーク更新、苦手マップ集計。
