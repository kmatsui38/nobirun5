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
   **テンプレートを追加したときは、その都度これを再実行する。**
   このSQLは何度でも実行でき、解答履歴・定着度・承認状態を壊さない（UPSERT形式）。
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

## デプロイ（Vercel）

MVPは Vercel にgit連携でデプロイする。手順は次のとおり。

1. **デプロイ元のブランチを決める**
   本番は `main` から配信する。作業ブランチの内容を main にマージしておく。
2. **Vercel でプロジェクトを作成**
   [vercel.com](https://vercel.com) にGitHubアカウントでログイン →
   「Add New… → Project」→ `kmatsui38/nobirun5` を Import。
3. **Root Directory に `web` を指定する**（必須）
   リポジトリ直下ではなく `web` がフロントのルート。Import画面の
   「Root Directory」の Edit から `web` を選ぶ。
   ここが未設定だと、ビルド成果物が見つからず全ページが 404（`Code: NOT_FOUND`）になる。

   ビルド方法と配信ディレクトリは `web/vercel.json` で明示している
   （`npm run build` を実行し、静的エクスポートの出力先 `out/` を配信する）。
   Vercel の Framework Preset や Output Directory を手動で上書きしないこと。
4. **環境変数を2つ設定する**（Environment Variables）
   Supabase の Project Settings → API からコピーする。
   `NEXT_PUBLIC_*` はビルド時に埋め込まれるため、**デプロイ前に設定すること**。

   | Name | Value |
   |---|---|
   | `NEXT_PUBLIC_SUPABASE_URL` | `https://xxxxx.supabase.co` |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `eyJ...`（anon public キー） |

   ※ `service_role` キーは絶対に設定しない（ブラウザに露出し、RLSを迂回されるため）。
5. **Deploy** を押す。`https://<プロジェクト名>.vercel.app` が発行される。
6. **スマホで開いて動作確認**し、ホーム画面に追加してもらう
   （iOS: 共有 → ホーム画面に追加 / Android: メニュー → ホーム画面に追加）。

以後は main への push で自動的に再デプロイされる。

### 1日の問題数を変えたいとき

既定は**5問**（機能要件4.2により3〜5問の範囲で調整する）。
`supabase/ops.sql` の 4-3 にある次の1文を実行するだけで変えられる。

```sql
create or replace function nobirun_set_size() returns int
language sql stable as $$ select 4 $$;   -- 3〜5 で調整
```

変更は「その日のセットがまだ生成されていないユーザー」から効く。
すでに今日の分が生成済みなら、今日の問題数は変わらない。

### 1日の問題数が既定より少ないとき

出題数は「候補となる学習事項 × 承認済みテンプレート」で決まる。少ない場合は次を確認する。

```sql
-- 承認済みテンプレートの本数（103本あるはず）
select status, count(*) from templates group by status;
```

4本しかない場合は、最新の `supabase/seed.sql` を実行してから
`update templates set status = 'approved';` で承認する。
（テンプレートを103本に増やした後、seed.sql の再実行を忘れると起きる）

### 全ページが404になるとき

- `Code: NOT_FOUND` … デプロイは存在するが配信するファイルが無い状態。
  **Root Directory が `web` になっているか**を Project Settings → Build and Deployment で確認する。
  設定を変えただけでは再ビルドされないので、Deployments → 最新 → ⋯ → **Redeploy** を実行する。
- `Code: DEPLOYMENT_NOT_FOUND` … そのデプロイ自体が存在しない（URLが古い）。
  Project のトップに出ている本番ドメインを開き直す。
- Build Logs に `Detected Next.js version` や `Build Completed` が出ているかも確認する。

### anonキーを公開してよい理由

anon キーはブラウザに露出する前提の公開鍵で、権限は Row Level Security で制限している。
ローカルPostgreSQLで `authenticated` ロールになりきって検証した結果:

- 問題テンプレート（正解の式を含む）は読めない
- 出題中の問題の正解・解説カラムは読めない
- 他人のプロフィール・解答履歴・定着度は読めない
- どのテーブルにも直接書き込めない（更新0行、挿入はRLS違反で拒否）

学習データの書き込みはすべて security definer の RPC 経由に限定している。

### 商用化時（S3 + CloudFront）

`npm run build` の `out/` を S3 に同期し CloudFront で配信する
（[技術スタック選定](../docs/requirements/03_技術スタック選定.md) 4.6 参照）。

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
