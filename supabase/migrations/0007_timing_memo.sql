-- nobirun5 学習時間の計測・中断と再開・メモ
--
-- 1. 時間の計測
--    daily_sets.started_at   … そのセットを最初に開いた時刻（＝開始時間）
--    daily_sets.completed_at … 既存（＝終了時間）
--    attempts.elapsed_ms     … その問題を画面に出してから解答するまでの時間
--
--    1問あたりの時間を answered_at の差分で求めると、中断した休憩時間まで
--    「考えていた時間」に混ざる。そのためクライアントで「問題が実際に画面に
--    見えていた時間」を計測して送る（画面を伏せている間は加算しない）。
--    計測は参考値なので、異常値は丸めるだけにして解答自体は失敗させない。
--
-- 2. 中断と再開
--    解答は1問ずつサーバに保存されるので、途中でやめても再開できる。
--    再開位置を画面に出せるよう get_home に進捗（何問中何問）を追加する。
--
-- 3. メモ
--    set_questions.memo … 生徒がその問題を解くときに書いたメモ。
--    解答前に書くものなので attempts ではなく set_questions に持ち、
--    中断してもメモが消えないよう save_memo で随時保存する。

-- ===== 1. 列の追加 =====

alter table daily_sets   add column if not exists started_at timestamptz;
alter table attempts     add column if not exists elapsed_ms int
  check (elapsed_ms is null or elapsed_ms between 0 and 3600000);
alter table set_questions add column if not exists memo text
  check (memo is null or char_length(memo) <= 2000);

-- 既存セットの開始時刻は、最初の解答時刻で埋める（それ以前は分からないため）
update daily_sets s
   set started_at = sub.first_answered
  from (
    select q.set_id, min(a.answered_at) as first_answered
      from set_questions q join attempts a on a.set_question_id = q.id
     group by q.set_id
  ) sub
 where sub.set_id = s.id and s.started_at is null;

-- ===== 2. セット生成（開始時刻を記録し、メモを返す） =====

create or replace function get_or_create_daily_set() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c_set_size constant int := nobirun_set_size();  -- 0006: 設定値から取得
  c_max_units constant int := 3;
  v_user uuid := auth.uid();
  v_today date := nobirun_today();
  v_set_id uuid;
  v_grade int;
  v_item record;
  v_tpl record;
  v_env jsonb;
  v_body text;
  v_expl text;
  v_correct jsonb;
  v_choices jsonb;
  v_case text;
  v_key text;
  v_expr jsonb;
  v_seq int := 0;
  v_units text[] := '{}';
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select id into v_set_id from daily_sets
   where user_id = v_user and set_date = v_today;

  if v_set_id is null then
    select grade into v_grade from profiles where user_id = v_user;

    -- 0007: 開始時刻（このセットを最初に開いた時刻）を記録する
    insert into daily_sets (user_id, set_date, started_at)
    values (v_user, v_today, now())
    returning id into v_set_id;

    for v_item in
      with learned_units as (
        -- 既習範囲: user_scopeにlearned=trueがあればそれ、なければ自学年以下の全単元
        select u.id, u.seq from units u
         where exists (select 1 from user_scope sc
                        where sc.user_id = v_user and sc.learned)
           and exists (select 1 from user_scope sc
                        where sc.user_id = v_user and sc.unit_id = u.id and sc.learned)
        union all
        select u.id, u.seq from units u
         where not exists (select 1 from user_scope sc
                            where sc.user_id = v_user and sc.learned)
           and u.grade <= v_grade
      ),
      candidates as (
        -- ① 期日到来の復習（boxが低い＝苦手な順）
        select li.id, li.unit_id, 1 as bucket,
               m.box as o1, lu.seq as o2, li.seq as o3
          from mastery m
          join learning_items li on li.id = m.item_id
          join learned_units lu on lu.id = li.unit_id
         where m.user_id = v_user and m.box > 0 and m.due_date <= v_today
        union all
        -- ② 未出題の新規（最近習った=後ろの単元から。知識技能を先に）
        select li.id, li.unit_id, 2 as bucket,
               case li.kind when 'knowledge' then 0 else 1 end as o1,
               -lu.seq as o2, li.seq as o3
          from learning_items li
          join learned_units lu on lu.id = li.unit_id
         where not exists (select 1 from mastery m
                            where m.user_id = v_user and m.item_id = li.id and m.box > 0)
      )
      select c.id, c.unit_id from candidates c
       where exists (select 1 from templates t
                      where t.item_id = c.id and t.status = 'approved')
       order by c.bucket, c.o1, c.o2, c.o3
    loop
      exit when v_seq >= c_set_size;
      -- 単元数の上限
      if not (v_item.unit_id = any (v_units)) then
        if array_length(v_units, 1) >= c_max_units then
          continue;
        end if;
        v_units := v_units || v_item.unit_id;
      end if;
      -- 同一テンプレートは1セット1回まで
      select t.id, t.spec, t.format into v_tpl
        from templates t
       where t.item_id = v_item.id and t.status = 'approved'
         and t.id not in (select template_id from set_questions where set_id = v_set_id)
       order by random() limit 1;
      if v_tpl.id is null then
        continue;
      end if;

      v_env := _instantiate(v_tpl.spec);

      if v_tpl.spec ? 'case_var' then
        v_case := v_env ->> (v_tpl.spec ->> 'case_var');
        v_body := _render(v_tpl.spec -> 'body_by_case' ->> v_case, v_env);
        v_correct := jsonb_build_object('correct', v_tpl.spec -> 'correct_by_case' ->> v_case);
        select jsonb_agg(x.v order by random()) into v_choices
          from (
            select (v_tpl.spec -> 'correct_by_case' ->> v_case) as v
            union all
            select jsonb_array_elements_text(v_tpl.spec -> 'distractors_by_case' -> v_case)
          ) x;
      elsif v_tpl.format = 'choice' then
        v_body := _render(v_tpl.spec ->> 'body', v_env);
        v_correct := jsonb_build_object('correct', v_tpl.spec ->> 'correct');
        select jsonb_agg(x.v order by random()) into v_choices
          from (
            select (v_tpl.spec ->> 'correct') as v
            union all
            select jsonb_array_elements_text(v_tpl.spec -> 'distractors')
          ) x;
      else
        v_body := _render(v_tpl.spec ->> 'body', v_env);
        v_correct := '{}'::jsonb;
        for v_key, v_expr in select * from jsonb_each(v_tpl.spec -> 'answers') loop
          v_correct := v_correct
            || jsonb_build_object(v_key, _eval_num(v_expr #>> '{}', v_env));
        end loop;
        v_choices := null;
      end if;

      v_expl := _render(v_tpl.spec ->> 'explanation', v_env);
      v_seq := v_seq + 1;

      insert into set_questions
        (set_id, seq, template_id, item_id, seed, rendered_body,
         correct_answer, choices, explanation)
      values
        (v_set_id, v_seq, v_tpl.id, v_item.id,
         floor(random() * 1e9)::int, v_body, v_correct, v_choices, v_expl);
    end loop;

    -- 1問も作れなかった場合はセットを取り消す
    if v_seq = 0 then
      delete from daily_sets where id = v_set_id;
      return jsonb_build_object('error', 'no_questions');
    end if;
  end if;

  -- セット内容を返す（正解・解説は含めない。解答済みの問題には結果を付ける）
  return (
    select jsonb_build_object(
      'set_id', s.id,
      'set_date', s.set_date,
      'started_at', s.started_at,
      'completed', s.completed_at is not null,
      'questions', coalesce(jsonb_agg(
        jsonb_build_object(
          'id', q.id,
          'seq', q.seq,
          'format', t.format,
          'body', q.rendered_body,
          'memo', q.memo,
          'choices', q.choices,
          'answer_fields', case when t.format = 'numeric'
                                then (select jsonb_agg(k) from jsonb_object_keys(q.correct_answer) as k)
                                else null end,
          'answered', a.id is not null,
          'was_correct', a.is_correct
        ) order by q.seq
      ), '[]'::jsonb)
    )
    from daily_sets s
    join set_questions q on q.set_id = s.id
    join templates t on t.id = q.template_id
    left join lateral (
      select id, is_correct from attempts
       where set_question_id = q.id and user_id = v_user
       order by answered_at limit 1
    ) a on true
    where s.id = v_set_id
    group by s.id
  );
end;
$$;

-- ===== 3. 採点（所要時間を受け取る） =====
-- 引数が増えるので旧シグネチャを消す。残すと2引数の呼び出しが曖昧になるため。
drop function if exists submit_answer(uuid, jsonb);

create or replace function submit_answer(
  p_set_question_id uuid,
  p_answer jsonb,
  p_elapsed_ms int default null   -- 0007: その問題を画面に出してから解答するまでの時間
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_q record;
  v_correct boolean;
  v_key text;
  v_box int;
  v_interval int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select q.id, q.item_id, q.correct_answer, q.explanation, t.format
    into v_q
    from set_questions q
    join daily_sets s on s.id = q.set_id
    join templates t on t.id = q.template_id
   where q.id = p_set_question_id and s.user_id = v_user;
  if v_q.id is null then
    raise exception 'question not found';
  end if;

  -- 再解答は不可（最初の解答のみ記録）
  if exists (select 1 from attempts
              where set_question_id = p_set_question_id and user_id = v_user) then
    raise exception 'already answered';
  end if;

  if v_q.format = 'choice' then
    v_correct := (p_answer ->> 'choice') = (v_q.correct_answer ->> 'correct');
  else
    v_correct := true;
    for v_key in select jsonb_object_keys(v_q.correct_answer) loop
      begin
        if (p_answer ->> v_key) is null
           or (p_answer ->> v_key)::numeric <> (v_q.correct_answer ->> v_key)::numeric then
          v_correct := false;
        end if;
      exception when others then
        v_correct := false;  -- 数値として解釈できない入力
      end;
    end loop;
  end if;

  -- 計測値は参考値なので、異常値は丸めるだけにして解答自体は絶対に失敗させない
  insert into attempts (set_question_id, user_id, answer, is_correct, elapsed_ms)
  values (p_set_question_id, v_user, p_answer, v_correct,
          case when p_elapsed_ms is null then null
               else least(greatest(p_elapsed_ms, 0), 3600000) end);

  select box into v_box from mastery
   where user_id = v_user and item_id = v_q.item_id;
  v_box := case when v_correct then least(coalesce(v_box, 0) + 1, 5) else 1 end;
  v_interval := (array[1, 2, 4, 7, 14])[v_box];

  insert into mastery (user_id, item_id, box, due_date, last_result, updated_at)
  values (v_user, v_q.item_id, v_box, nobirun_today() + v_interval, v_correct, now())
  on conflict (user_id, item_id) do update set
    box = excluded.box,
    due_date = excluded.due_date,
    last_result = excluded.last_result,
    updated_at = excluded.updated_at;

  return jsonb_build_object(
    'is_correct', v_correct,
    'correct_answer', v_q.correct_answer,
    'explanation', v_q.explanation
  );
end;
$$;

-- ===== 4. メモの保存 =====
-- 解答前・解答後どちらでも書き直せる。空文字はnullとして扱う（未記入と同じ）。

create or replace function save_memo(p_set_question_id uuid, p_memo text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  update set_questions q
     -- 空白だけなら未記入に戻す。ただし中身があるときは字下げを保つため trim しない
     set memo = case when btrim(coalesce(p_memo, '')) = '' then null
                     else left(p_memo, 2000) end
    from daily_sets s
   where q.id = p_set_question_id
     and s.id = q.set_id
     and s.user_id = v_user;

  if not found then
    raise exception 'question not found';
  end if;
end;
$$;

-- ===== 5. ホーム（再開のための進捗を返す） =====

create or replace function get_home() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_nickname text;
  v_streak int;
  v_set record;
  v_total int := 0;
  v_answered int := 0;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select nickname into v_nickname from profiles where user_id = v_user;
  select current into v_streak from streaks where user_id = v_user;

  select id, completed_at into v_set
    from daily_sets where user_id = v_user and set_date = nobirun_today();

  if v_set.id is not null then
    select count(*) into v_total
      from set_questions where set_id = v_set.id;
    select count(distinct q.id) into v_answered
      from set_questions q join attempts a on a.set_question_id = q.id
     where q.set_id = v_set.id and a.user_id = v_user;
  end if;

  return jsonb_build_object(
    'nickname', coalesce(v_nickname, ''),
    'streak', coalesce(v_streak, 0),
    'today_done', (v_set.completed_at is not null),
    -- 0007: 途中まで進んでいるときに「つづきから」を出すための進捗
    'today_total', v_total,
    'today_answered', v_answered
  );
end;
$$;
