-- 自信申告（「明日も解ける自信ある?」）
--
-- 方針（docs/requirements/01_MVP機能要件.md 4.1）:
--   自信は定着判定の主決定因ではなく、出題間隔の補正因子。
--   box更新は正誤ベースのまま変えず、「まだ不安」のときだけ次回間隔を1段短くする。
--   未申告なら現行挙動と同一（申告はスキップ可能）。

alter table attempts add column if not exists confidence smallint
  check (confidence in (0, 1));  -- null=未申告 / 1=自信あり / 0=まだ不安

create or replace function rate_confidence(
  p_set_question_id uuid,
  p_confident boolean
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_attempt record;
  v_box int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select a.id, a.is_correct, a.confidence, q.item_id
    into v_attempt
    from attempts a
    join set_questions q on q.id = a.set_question_id
   where a.set_question_id = p_set_question_id and a.user_id = v_user
   order by a.answered_at desc limit 1;

  if v_attempt.id is null then
    raise exception 'attempt not found';
  end if;
  if not v_attempt.is_correct then
    raise exception 'confidence is only asked for correct answers';
  end if;
  if v_attempt.confidence is not null then
    raise exception 'confidence already rated';
  end if;

  update attempts set confidence = case when p_confident then 1 else 0 end
   where id = v_attempt.id;

  -- 「まだ不安」→ 次回出題間隔を1段短縮（boxは変えない）
  if not p_confident then
    select box into v_box from mastery
     where user_id = v_user and item_id = v_attempt.item_id;
    if v_box is not null and v_box between 1 and 5 then
      update mastery
         set due_date = nobirun_today() + (array[1, 1, 2, 4, 7])[v_box]
       where user_id = v_user and item_id = v_attempt.item_id;
    end if;
  end if;
end;
$$;
