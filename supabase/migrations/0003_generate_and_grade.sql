-- nobirun5 セット生成と採点（アプリの心臓部）
--
-- テンプレート（templates.spec: YAML由来のJSON）から変数を乱択し、
-- 問題を実生成して daily_sets / set_questions に保存する。
-- 採点はサーバ側（submit_answer）で行い、正解・解説は解答後にのみ返す。
--
-- 式の評価について:
--   テンプレートの式（constraints / derived / answers）は運営が検品した信頼データであり、
--   さらに評価前に「変数を数値に置換 → 英字が残っていないことを検査」してから実行するため、
--   任意SQLは実行できない。

-- ===== 正解・解説の秘匿（カラムレベル権限） =====
-- set_questions の correct_answer / explanation はクライアントから直接読めない。
-- （解答後に submit_answer が返す）
revoke select on set_questions from authenticated;
grant select (id, set_id, seq, template_id, item_id, seed, rendered_body, choices)
  on set_questions to authenticated;

-- ===== 内部ヘルパー =====

-- 数値の表示整形（整数は小数点なし、それ以外は末尾ゼロを除去）
create or replace function _fmt_num(v numeric) returns text
language sql immutable as $$
  select case when v = trunc(v) then trunc(v)::bigint::text
              else rtrim(rtrim(round(v, 4)::text, '0'), '.') end
$$;

-- 式中の変数を値に置換し、英字が残らないことを確認してから評価する
create or replace function _subst_vars(p_expr text, p_env jsonb) returns text
language plpgsql immutable as $$
declare
  v_expr text := p_expr;
  v_key text;
begin
  if p_expr !~ '^[0-9a-zA-Z_+\-*/%() .!<>=]+$' then
    raise exception 'expression contains invalid characters: %', p_expr;
  end if;
  for v_key in
    select key from jsonb_object_keys(p_env) as key order by length(key) desc
  loop
    v_expr := regexp_replace(v_expr, '\m' || v_key || '\M',
                             '(' || (p_env ->> v_key) || ')', 'g');
  end loop;
  if v_expr ~ '[a-zA-Z_]' then
    raise exception 'unresolved variable in expression: % -> %', p_expr, v_expr;
  end if;
  return v_expr;
end;
$$;

create or replace function _eval_num(p_expr text, p_env jsonb) returns numeric
language plpgsql as $$
declare
  v numeric;
begin
  execute 'select (' || _subst_vars(p_expr, p_env) || ')::numeric' into v;
  return v;
end;
$$;

create or replace function _eval_bool(p_expr text, p_env jsonb) returns boolean
language plpgsql as $$
declare
  v boolean;
begin
  execute 'select (' || _subst_vars(p_expr, p_env) || ')' into v;
  return v;
end;
$$;

-- テンプレートspecから変数環境（variables + derived）を生成する
create or replace function _instantiate(p_spec jsonb) returns jsonb
language plpgsql as $$
declare
  v_env jsonb;
  v_key text;
  v_def jsonb;
  v_min int;
  v_max int;
  v_val int;
  v_ok boolean;
  v_try int;
  v_pass int;
  v_expr text;
  v_done boolean;
begin
  for v_try in 1..300 loop
    -- 変数の乱択
    v_env := '{}'::jsonb;
    for v_key, v_def in select * from jsonb_each(p_spec -> 'variables') loop
      v_min := (v_def ->> 'min')::int;
      v_max := (v_def ->> 'max')::int;
      loop
        v_val := floor(random() * (v_max - v_min + 1))::int + v_min;
        exit when v_def -> 'exclude' is null
          or not (v_def -> 'exclude') @> to_jsonb(v_val);
      end loop;
      v_env := v_env || jsonb_build_object(v_key, v_val);
    end loop;

    -- 制約チェック
    v_ok := true;
    for v_expr in select jsonb_array_elements_text(coalesce(p_spec -> 'constraints', '[]'::jsonb)) loop
      if not _eval_bool(v_expr, v_env) then
        v_ok := false;
        exit;
      end if;
    end loop;
    exit when v_ok;
  end loop;

  if not v_ok then
    raise exception 'could not satisfy constraints for template';
  end if;

  -- derived の評価（derived同士の依存に備えて最大3パス）
  for v_pass in 1..3 loop
    v_done := true;
    for v_key, v_def in select * from jsonb_each(coalesce(p_spec -> 'derived', '{}'::jsonb)) loop
      if v_env ? v_key then
        continue;
      end if;
      begin
        v_env := v_env || jsonb_build_object(v_key, _eval_num(v_def #>> '{}', v_env));
      exception when others then
        v_done := false;  -- 依存先が未評価。次のパスで再試行
      end;
    end loop;
    exit when v_done;
  end loop;
  if not v_done then
    raise exception 'could not evaluate derived values';
  end if;

  return v_env;
end;
$$;

-- 本文・解説の {変数} を値に置換する
create or replace function _render(p_text text, p_env jsonb) returns text
language plpgsql immutable as $$
declare
  v_text text := p_text;
  v_key text;
  v_val text;
begin
  for v_key in select key from jsonb_object_keys(p_env) as key order by length(key) desc loop
    v_val := case when jsonb_typeof(p_env -> v_key) = 'number'
                  then _fmt_num((p_env ->> v_key)::numeric)
                  else p_env ->> v_key end;
    v_text := replace(v_text, '{' || v_key || '}', v_val);
  end loop;
  return v_text;
end;
$$;

-- ===== セット生成 =====
-- 機能要件 4.2:
--   1問数は7問。①期日到来（box低い順）②新規（後ろの単元から）の優先順で構成。
--   同一テンプレートは1セット1回まで、単元は3つまで。

create or replace function get_or_create_daily_set() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c_set_size constant int := 7;
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

    insert into daily_sets (user_id, set_date) values (v_user, v_today)
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
      'completed', s.completed_at is not null,
      'questions', coalesce(jsonb_agg(
        jsonb_build_object(
          'id', q.id,
          'seq', q.seq,
          'format', t.format,
          'body', q.rendered_body,
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

-- ===== 採点 =====
-- 機能要件 4.1: 正解で box+1（上限5）、不正解で box=1。間隔は 1,2,4,7,14日。

create or replace function submit_answer(p_set_question_id uuid, p_answer jsonb)
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

  insert into attempts (set_question_id, user_id, answer, is_correct)
  values (p_set_question_id, v_user, p_answer, v_correct);

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

-- ===== 苦手マップ =====

create or replace function get_mastery_map() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'unit_id', u.id,
      'grade', u.grade,
      'domain', u.domain,
      'name', u.name,
      'item_count', stats.item_count,
      'touched_count', stats.touched_count,
      'avg_box', stats.avg_box
    ) order by u.seq), '[]'::jsonb)
    from units u
    join lateral (
      select count(*) as item_count,
             count(m.item_id) as touched_count,
             round(avg(coalesce(m.box, 0)), 2) as avg_box
        from learning_items li
        left join mastery m on m.item_id = li.id and m.user_id = v_user
       where li.unit_id = u.id
    ) stats on true
  );
end;
$$;
