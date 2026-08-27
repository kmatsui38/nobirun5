-- nobirun5 RPC（サーバロジック）
-- 実装規約により、サーバ処理はすべてPostgres関数（security definer）に置く。
-- 学習日の決定: JST・午前4時境界（機能要件 4.5）

create or replace function nobirun_today() returns date
language sql stable as $$
  select ((now() at time zone 'Asia/Tokyo') - interval '4 hours')::date
$$;

-- ホーム画面用の情報
create or replace function get_home() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_nickname text;
  v_streak int;
  v_done boolean;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select nickname into v_nickname from profiles where user_id = v_user;
  select current into v_streak from streaks where user_id = v_user;
  select (completed_at is not null) into v_done
    from daily_sets where user_id = v_user and set_date = nobirun_today();

  return jsonb_build_object(
    'nickname', coalesce(v_nickname, ''),
    'streak', coalesce(v_streak, 0),
    'today_done', coalesce(v_done, false)
  );
end;
$$;

-- セット完了時のストリーク更新（daily_sets.completed_at の設定と同時に呼ぶ内部関数）
create or replace function complete_daily_set(p_set_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_today date := nobirun_today();
  v_last date;
  v_current int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  update daily_sets set completed_at = now()
   where id = p_set_id and user_id = v_user and completed_at is null;
  if not found then
    return; -- 既に完了済み or 他人のセット
  end if;

  insert into streaks (user_id, current, best, last_completed_date)
  values (v_user, 1, 1, v_today)
  on conflict (user_id) do update set
    current = case
      when streaks.last_completed_date = v_today then streaks.current
      when streaks.last_completed_date = v_today - 1 then streaks.current + 1
      else 1
    end,
    best = greatest(streaks.best, case
      when streaks.last_completed_date = v_today - 1 then streaks.current + 1
      else 1
    end),
    last_completed_date = v_today;
end;
$$;

-- 解答の記録と習熟ボックス更新（機能要件 4.1: 正解でbox+1、不正解でbox=1）
create or replace function submit_answer(
  p_set_question_id uuid,
  p_answer jsonb,
  p_is_correct boolean
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_item text;
  v_new_box int;
  v_interval int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select q.item_id into v_item
    from set_questions q join daily_sets s on s.id = q.set_id
   where q.id = p_set_question_id and s.user_id = v_user;
  if v_item is null then
    raise exception 'question not found';
  end if;

  insert into attempts (set_question_id, user_id, answer, is_correct)
  values (p_set_question_id, v_user, p_answer, p_is_correct);

  select case when p_is_correct then least(coalesce(box, 0) + 1, 5) else 1 end
    into v_new_box
    from mastery where user_id = v_user and item_id = v_item
    union all select case when p_is_correct then 1 else 1 end
    limit 1;

  -- box → 次回出題間隔（日）: 1,2,4,7,14
  v_interval := (array[1, 2, 4, 7, 14])[v_new_box];

  insert into mastery (user_id, item_id, box, due_date, last_result, updated_at)
  values (v_user, v_item, v_new_box, nobirun_today() + v_interval, p_is_correct, now())
  on conflict (user_id, item_id) do update set
    box = v_new_box,
    due_date = nobirun_today() + v_interval,
    last_result = p_is_correct,
    updated_at = now();
end;
$$;

-- 注意: セット生成（get_or_create_daily_set）は問題の実生成（変数の乱択・本文レンダリング）
-- を伴うため、Postgres関数ではなく Supabase Edge Function (TypeScript) で実装する。
-- テンプレートの式評価ロジックをフロントの採点と共有できるためでもある。
-- → supabase/functions/generate-set/ （次のイテレーション）
