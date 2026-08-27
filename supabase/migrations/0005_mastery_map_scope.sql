-- 苦手マップに「既習かどうか」を含める
--
-- 既習範囲の判定は get_or_create_daily_set と同じ規則にそろえる:
--   user_scope に learned=true の行が1件でもあればそれを既習範囲とする。
--   1件もなければ、プロフィールの学年以下の全単元を既習とみなす。

create or replace function get_mastery_map() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_grade int;
  v_has_scope boolean;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select grade into v_grade from profiles where user_id = v_user;
  select exists (select 1 from user_scope
                  where user_id = v_user and learned) into v_has_scope;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'unit_id', u.id,
      'grade', u.grade,
      'domain', u.domain,
      'name', u.name,
      'learned', case when v_has_scope
                      then exists (select 1 from user_scope sc
                                    where sc.user_id = v_user
                                      and sc.unit_id = u.id and sc.learned)
                      else u.grade <= coalesce(v_grade, 3) end,
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
