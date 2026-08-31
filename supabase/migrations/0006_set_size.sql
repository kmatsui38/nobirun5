-- nobirun5 1日の出題数を「設定値」にして 7問 → 5問 に変更する
--
-- 経緯: 被験者に7問は多かったため、機能要件4.2の想定範囲を3〜5問に見直した。
--
-- 出題数は nobirun_set_size() で持つ。数を変えたいときは
-- get_or_create_daily_set を貼り直さず、次の1文だけを実行すればよい。
--
--   create or replace function nobirun_set_size() returns int
--   language sql stable as $x$ select 3 $x$;   -- 3〜5 の範囲で調整する
--
-- 変更は「その日のセットがまだ生成されていないユーザー」から順に効く。
-- すでに生成済みの当日セットの問題数は変わらない（履歴を壊さないため）。

create or replace function nobirun_set_size() returns int
language sql stable as $$ select 5 $$;

comment on function nobirun_set_size() is
  '1日の出題数。機能要件4.2により3〜5問の範囲で調整する。';

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
