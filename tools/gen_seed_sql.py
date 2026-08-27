#!/usr/bin/env python3
"""単元マスタYAMLとテンプレートから Supabase 用シードSQLを生成する。

使い方:
    python3 tools/gen_seed_sql.py > supabase/seed.sql

- units / learning_items: data/curriculum/math-units.yaml から生成
- templates: data/templates/ 配下の T-*.yaml から生成（statusはYAMLの値を保持）
  ※出題対象になるのは status='approved' のみ（アプリ側で絞る）
"""

import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent


def q(s):
    return "'" + str(s).replace("'", "''") + "'"


def main():
    out = []
    out.append("-- 自動生成: python3 tools/gen_seed_sql.py")
    out.append("-- 手で編集しない。元データは data/curriculum/ と data/templates/")
    out.append("begin;")
    out.append("delete from templates; delete from learning_items; delete from units;")

    master = yaml.safe_load((ROOT / "data/curriculum/math-units.yaml").read_text())
    seq = 0
    for grade in master["grades"]:
        for unit in grade["units"]:
            seq += 1
            out.append(
                f"insert into units (id, grade, domain, name, seq) values "
                f"({q(unit['id'])}, {grade['grade']}, {q(unit['domain'])}, {q(unit['name'])}, {seq});"
            )
            for kind, key, prefix in (
                ("knowledge", "knowledge_skills", "K"),
                ("thinking", "thinking_skills", "T"),
            ):
                for i, text in enumerate(unit.get(key, []), start=1):
                    item_id = f"{unit['id']}-{prefix}{i}"
                    out.append(
                        f"insert into learning_items (id, unit_id, kind, seq, text) values "
                        f"({q(item_id)}, {q(unit['id'])}, {q(kind)}, {i}, {q(text)});"
                    )

    for path in sorted((ROOT / "data/templates").rglob("T-*.yaml")):
        tpl = yaml.safe_load(path.read_text())
        prefix = "K" if tpl["item_kind"] == "knowledge" else "T"
        item_id = f"{tpl['item']}-{prefix}{tpl['item_index']}"
        out.append(
            f"insert into templates (id, item_id, format, difficulty, title, spec, status) values "
            f"({q(tpl['id'])}, {q(item_id)}, {q(tpl['format'])}, {tpl['difficulty']}, "
            f"{q(tpl['title'])}, {q(json.dumps(tpl, ensure_ascii=False))}::jsonb, {q(tpl['status'])});"
        )

    out.append("commit;")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
