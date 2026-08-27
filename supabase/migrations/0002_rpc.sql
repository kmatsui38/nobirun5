-- nobirun5 RPC 基盤（プロフィール自動作成・ホーム・セット完了）
-- 実装規約により、サーバ処理はすべてPostgres関数（security definer）に置く。
-- 学習日の決定: JST・午前4時境界（機能要件 4.5）

-- 旧定義が残っている場合の掃除（返り値型の変更に備える）
drop function if exists complete_daily_set(uuid);
drop function if exists submit_answer(uuid, jsonb, boolean);

create or replace function nobirun_today() returns date
language sql stable as $$
  select ((now() at time zone 'Asia/Tokyo') - interval '4 hours')::date
$$;

-- ユーザー作成時に profiles / streaks を自動作成
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (user_id) values (new.id) on conflict do nothing;
  insert into streaks (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

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

-- セット完了（全問解答済みのときのみ）とストリーク更新
create or replace function complete_daily_set(p_set_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_today date := nobirun_today();
  v_total int;
  v_answered int;
  v_streak int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select count(*) into v_total
    from set_questions q join daily_sets s on s.id = q.set_id
   where s.id = p_set_id and s.user_id = v_user;
  select count(distinct q.id) into v_answered
    from set_questions q
    join attempts a on a.set_question_id = q.id
   where q.set_id = p_set_id and a.user_id = v_user;

  if v_total = 0 or v_answered < v_total then
    return jsonb_build_object('completed', false, 'answered', v_answered, 'total', v_total);
  end if;

  update daily_sets set completed_at = now()
   where id = p_set_id and user_id = v_user and completed_at is null;

  insert into streaks (user_id, current, best, last_completed_date)
  values (v_user, 1, 1, v_today)
  on conflict (user_id) do update set
    current = case
      when streaks.last_completed_date = v_today then streaks.current
      when streaks.last_completed_date = v_today - 1 then streaks.current + 1
      else 1
    end,
    best = greatest(streaks.best, case
      when streaks.last_completed_date = v_today then streaks.current
      when streaks.last_completed_date = v_today - 1 then streaks.current + 1
      else 1
    end),
    last_completed_date = v_today;

  select current into v_streak from streaks where user_id = v_user;
  return jsonb_build_object('completed', true, 'streak', v_streak);
end;
$$;
