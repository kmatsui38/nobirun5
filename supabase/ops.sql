-- nobirun5 運用クエリ集
--
-- SupabaseのSQLエディタで、必要な部分だけをコピーして実行する。
-- （被験者2名のMVP期間は、管理画面の代わりにこのクエリ集で運用する）

-- ============================================================
-- 1. 被験者のセットアップ
-- ============================================================

-- 1-1. ユーザー一覧（Authentication → Users で作成したアカウントを確認）
select u.id, u.email, p.nickname, p.grade
  from auth.users u left join profiles p on p.user_id = u.id
 order by u.created_at;

-- 1-2. ニックネームと学年を設定する
-- update profiles set nickname = '○○', grade = 2
--  where user_id = 'ここに 1-1 で確認した id';

-- 1-3. 【重要】既習範囲を設定する
--
-- 設定しない場合、その学年以下の全単元が出題対象になる（＝まだ習っていない単元も出る）。
-- 学校の進度に合わせて、習い終わった単元だけを登録すること。
--
-- 下のリストから「まだ習っていない単元」の行を削除してから実行する。
--
--   M1-A1 正の数と負の数        M2-A1 文字を用いた式
--   M1-A2 文字を用いた式        M2-A2 連立二元一次方程式
--   M1-A3 一元一次方程式        M2-B1 基本的な平面図形の性質
--   M1-B1 平面図形              M2-B2 図形の合同
--   M1-B2 空間図形              M2-C1 一次関数
--   M1-C1 比例、反比例          M2-D1 データの分布（四分位範囲・箱ひげ図）
--   M1-D1 データの分布          M2-D2 不確定な事象の起こりやすさ（確率）
--   M1-D2 不確定な事象の起こりやすさ
--
-- insert into user_scope (user_id, unit_id, learned)
-- select 'ここにユーザーid', unit_id, true
--   from (values
--     ('M1-A1'), ('M1-A2'), ('M1-A3'), ('M1-B1'), ('M1-B2'),
--     ('M1-C1'), ('M1-D1'), ('M1-D2'),
--     ('M2-A1'), ('M2-A2'), ('M2-B1')
--   ) as t(unit_id)
-- on conflict (user_id, unit_id) do update set learned = true;

-- 1-3b. 【そのまま使える版】既習範囲を「中2の1学期まで」に設定する
--
-- 中2の生徒（profiles.grade = 2）全員に一括で適用する。
-- リストにない単元は自動的に未習（learned=false）に設定されるので、
-- 学期が進んだら scope のリストに単元を追加して再実行すればよい。
--
-- 中2の1学期の想定範囲: 中1の全単元 ＋ 式の計算 ＋ 連立方程式
-- （1学期に一次関数まで終わっていれば ('M2-C1') を scope に追加する）

with scope(unit_id) as (
  values ('M1-A1'), ('M1-A2'), ('M1-A3'), ('M1-B1'),
         ('M1-B2'), ('M1-C1'), ('M1-D1'), ('M1-D2'),
         ('M2-A1'), ('M2-A2')
)
insert into user_scope (user_id, unit_id, learned)
select p.user_id, u.id, (u.id in (select unit_id from scope))
  from profiles p cross join units u
 where p.grade = 2
on conflict (user_id, unit_id) do update set learned = excluded.learned;

-- 特定の生徒だけに適用したい場合は、上の where を次に置き換える:
--  where p.user_id = 'ここにユーザーid'

-- 1-4. 設定した既習範囲を確認する
select p.nickname, u.grade, u.id as unit_id, u.name
  from user_scope sc
  join units u on u.id = sc.unit_id
  join profiles p on p.user_id = sc.user_id
 where sc.learned
 order by p.nickname, u.seq;

-- ============================================================
-- 2. 利用状況の確認（毎日の見守り用）
-- ============================================================

-- 2-1. ひと目でわかる進捗サマリ
select p.nickname,
       coalesce(s.current, 0) as 連続日数,
       coalesce(s.best, 0)    as 最高連続,
       (select count(*) from daily_sets d
         where d.user_id = p.user_id and d.completed_at is not null) as 完了セット数,
       (select count(*) from attempts a where a.user_id = p.user_id) as 解答数,
       (select round(100.0 * avg(case when a.is_correct then 1 else 0 end), 1)
          from attempts a where a.user_id = p.user_id) as 正答率,
       s.last_completed_date as 最後にやった日
  from profiles p left join streaks s on s.user_id = p.user_id
 order by p.nickname;

-- 2-2. 日ごとの取り組み（直近14日）
select p.nickname, d.set_date,
       count(a.id) filter (where a.id is not null) as 解答数,
       count(a.id) filter (where a.is_correct)     as 正解数,
       (d.completed_at is not null)                as 完了,
       d.completed_at
  from daily_sets d
  join profiles p on p.user_id = d.user_id
  left join set_questions q on q.set_id = d.id
  left join attempts a on a.set_question_id = q.id
 where d.set_date > current_date - 14
 group by p.nickname, d.set_date, d.completed_at
 order by d.set_date desc, p.nickname;

-- 2-3. 単元ごとの定着度（苦手マップと同じ集計）
select p.nickname, u.grade, u.name as 単元,
       count(m.item_id)              as 学習した事項数,
       round(avg(m.box), 2)          as 平均ボックス,
       count(*) filter (where m.box >= 4) as 定着した事項数
  from mastery m
  join learning_items li on li.id = m.item_id
  join units u on u.id = li.unit_id
  join profiles p on p.user_id = m.user_id
 group by p.nickname, u.grade, u.name, u.seq
 order by p.nickname, u.seq;

-- 2-4. つまずいている事項（box=1 が続いているもの）
select p.nickname, u.name as 単元, li.text as 学習事項, m.box, m.due_date
  from mastery m
  join learning_items li on li.id = m.item_id
  join units u on u.id = li.unit_id
  join profiles p on p.user_id = m.user_id
 where m.box <= 1
 order by p.nickname, u.seq;

-- ============================================================
-- 3. 検証用のデータ抽出
-- ============================================================

-- 3-1. 解答履歴の全件（CSVでダウンロードして分析する）
select p.nickname, d.set_date, q.seq, u.name as 単元, li.text as 学習事項,
       t.title as テンプレート, q.rendered_body as 問題,
       a.answer::text as 解答, q.correct_answer::text as 正解,
       a.is_correct as 正誤, a.confidence as 自信申告, a.answered_at
  from attempts a
  join set_questions q on q.id = a.set_question_id
  join daily_sets d on d.id = q.set_id
  join templates t on t.id = q.template_id
  join learning_items li on li.id = q.item_id
  join units u on u.id = li.unit_id
  join profiles p on p.user_id = a.user_id
 order by p.nickname, a.answered_at;

-- 3-2. 自信申告のキャリブレーション（企画書の副次指標）
--      「自信あり」と答えた事項が、次に出題されたとき正解できたか
with rated as (
  select a.user_id, q.item_id, a.answered_at, a.confidence
    from attempts a join set_questions q on q.id = a.set_question_id
   where a.confidence is not null
),
next_try as (
  select r.user_id, r.confidence,
         (select a2.is_correct
            from attempts a2 join set_questions q2 on q2.id = a2.set_question_id
           where a2.user_id = r.user_id and q2.item_id = r.item_id
             and a2.answered_at > r.answered_at
           order by a2.answered_at limit 1) as next_correct
    from rated r
)
select p.nickname,
       case confidence when 1 then '自信あり' else 'まだ不安' end as 申告,
       count(*) filter (where next_correct is not null) as 次回出題された数,
       round(100.0 * avg(case when next_correct then 1 else 0 end), 1) as 次回正答率
  from next_try n join profiles p on p.user_id = n.user_id
 where next_correct is not null
 group by p.nickname, confidence
 order by p.nickname, confidence desc;

-- ============================================================
-- 4. メンテナンス
-- ============================================================

-- 4-1. 承認済みテンプレートの数（単元ごと）
select u.grade, u.id as unit_id, u.name, count(*) as 承認済み本数
  from templates t
  join learning_items li on li.id = t.item_id
  join units u on u.id = li.unit_id
 where t.status = 'approved'
 group by u.grade, u.id, u.name, u.seq
 order by u.seq;

-- 4-2. テストデータの削除（検証を仕切り直すとき。解答履歴が消えるので注意）
-- delete from daily_sets where user_id = 'ここにユーザーid';
-- delete from mastery     where user_id = 'ここにユーザーid';
-- update streaks set current = 0, best = 0, last_completed_date = null
--  where user_id = 'ここにユーザーid';
