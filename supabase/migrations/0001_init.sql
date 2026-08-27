-- nobirun5 初期スキーマ
-- 前提: docs/requirements/01_MVP機能要件.md のデータ設計
-- 認証は Supabase Auth (auth.users) を利用し、profiles で拡張する

-- ===== マスタ =====

create table units (
  id text primary key,              -- 例: M1-A1（math-units.yaml 準拠）
  grade int not null check (grade in (1, 2, 3)),
  domain text not null check (domain in ('A', 'B', 'C', 'D')),
  name text not null,
  seq int not null                  -- 表示順
);

create table learning_items (
  id text primary key,              -- 例: M1-A1-K2（K=knowledge / T=thinking + 事項番号）
  unit_id text not null references units (id),
  kind text not null check (kind in ('knowledge', 'thinking')),
  seq int not null,                 -- 単元内の事項番号（1始まり）
  text text not null                -- 指導要領の事項（原文）
);

create table templates (
  id text primary key,              -- 例: T-M1-A1-001
  item_id text not null references learning_items (id),
  format text not null check (format in ('numeric', 'choice')),
  difficulty int not null check (difficulty between 1 and 3),
  title text not null,
  spec jsonb not null,              -- テンプレートYAMLの全文（variables/constraints/body等）
  status text not null default 'draft'
    check (status in ('draft', 'ai_reviewed', 'approved'))
);

-- ===== ユーザー =====

create table profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null default '',
  grade int not null default 2 check (grade in (1, 2, 3)),
  created_at timestamptz not null default now()
);

create table user_scope (           -- 既習範囲
  user_id uuid not null references profiles (user_id) on delete cascade,
  unit_id text not null references units (id),
  learned boolean not null default false,
  primary key (user_id, unit_id)
);

create table mastery (              -- 事項ごとの定着度（習熟ボックス0-5）
  user_id uuid not null references profiles (user_id) on delete cascade,
  item_id text not null references learning_items (id),
  box int not null default 0 check (box between 0 and 5),
  due_date date,                    -- 次回出題日（box=0はnull）
  last_result boolean,
  updated_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

create table streaks (
  user_id uuid primary key references profiles (user_id) on delete cascade,
  current int not null default 0,
  best int not null default 0,
  last_completed_date date
);

-- ===== 出題・解答 =====

create table daily_sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (user_id) on delete cascade,
  set_date date not null,           -- 学習日（JST・午前4時境界で決定した日付）
  completed_at timestamptz,
  unique (user_id, set_date)
);

create table set_questions (
  id uuid primary key default gen_random_uuid(),
  set_id uuid not null references daily_sets (id) on delete cascade,
  seq int not null,
  template_id text not null references templates (id),
  item_id text not null references learning_items (id),
  seed int not null,                -- 変数確定用の乱数種（テンプレ+seedで問題を完全再現できる）
  rendered_body text not null,      -- 出題時の本文スナップショット
  correct_answer jsonb not null,    -- 正解（numeric: {フィールド:値}, choice: {correct:文字列}）
  choices jsonb,                    -- choiceのみ: 表示順の選択肢配列
  explanation text not null,        -- 解説スナップショット
  unique (set_id, seq)
);

create table attempts (
  id uuid primary key default gen_random_uuid(),
  set_question_id uuid not null references set_questions (id) on delete cascade,
  user_id uuid not null references profiles (user_id) on delete cascade,
  answer jsonb not null,
  is_correct boolean not null,
  answered_at timestamptz not null default now()
);

-- ===== Row Level Security =====
-- マスタは全認証ユーザーが読み取り可。ユーザーデータは本人のみ。
-- 書き込みはRPC（security definer関数）経由のみとし、直接insert/updateは許可しない。

alter table units enable row level security;
alter table learning_items enable row level security;
alter table templates enable row level security;
alter table profiles enable row level security;
alter table user_scope enable row level security;
alter table mastery enable row level security;
alter table streaks enable row level security;
alter table daily_sets enable row level security;
alter table set_questions enable row level security;
alter table attempts enable row level security;

create policy "units_read" on units for select to authenticated using (true);
create policy "items_read" on learning_items for select to authenticated using (true);
-- templates は正解生成式を含むため、クライアントからは読ませない（RPC経由のみ）

create policy "profiles_own" on profiles for select to authenticated
  using (user_id = auth.uid());
create policy "scope_own" on user_scope for select to authenticated
  using (user_id = auth.uid());
create policy "mastery_own" on mastery for select to authenticated
  using (user_id = auth.uid());
create policy "streaks_own" on streaks for select to authenticated
  using (user_id = auth.uid());
create policy "sets_own" on daily_sets for select to authenticated
  using (user_id = auth.uid());
create policy "set_questions_own" on set_questions for select to authenticated
  using (exists (select 1 from daily_sets s
                 where s.id = set_id and s.user_id = auth.uid()));
create policy "attempts_own" on attempts for select to authenticated
  using (user_id = auth.uid());

-- ===== インデックス =====

create index mastery_due_idx on mastery (user_id, due_date);
create index attempts_user_idx on attempts (user_id, answered_at);
create index templates_item_idx on templates (item_id) where status = 'approved';
