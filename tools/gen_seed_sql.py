#!/usr/bin/env python3
"""単元マスタYAMLとテンプレートから Supabase 用シードSQLを生成する。

使い方:
    python3 tools/gen_seed_sql.py > supabase/seed.sql

- units / learning_items: data/curriculum/math-units.yaml から生成
- templates: data/templates/ 配下の T-*.yaml から生成
  ※出題対象になるのは status='approved' のみ（アプリ側で絞る）

生成されるSQLは何度でも実行できる（UPSERT形式）。
既に学習が始まっていても、解答履歴・定着度を壊さずにテンプレートを追加・更新できる。
既にDBで approved にしたテンプレートの status は維持される（YAMLの draft で上書きしない）。
"""

import json
import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:  # pragma: no cover
    raise SystemExit(
        "PyYAML が見つかりません。次を実行してから、もう一度お試しください。\n"
        "    bash tools/setup.sh\n"
        "以後は .venv/bin/python でこのスクリプトを実行してください。\n"
        "（インストールせずに検品したい場合は README のリンク先の検品ページが使えます）"
    )

ROOT = Path(__file__).resolve().parent.parent


def q(s):
    return "'" + str(s).replace("'", "''") + "'"


def main():
    out = []
    out.append("-- 自動生成: python3 tools/gen_seed_sql.py")
    out.append("-- 手で編集しない。元データは data/curriculum/ と data/templates/")
    out.append("--")
    out.append("-- 何度でも実行できる（UPSERT）。学習データは削除しない。")
    out.append("-- DBで approved にしたテンプレートの status は維持される。")
    out.append("begin;")

    master = yaml.safe_load((ROOT / "data/curriculum/math-units.yaml").read_text())
    seq = 0
    for grade in master["grades"]:
        for unit in grade["units"]:
            seq += 1
            out.append(
                f"insert into units (id, grade, domain, name, seq) values "
                f"({q(unit['id'])}, {grade['grade']}, {q(unit['domain'])}, {q(unit['name'])}, {seq}) "
                f"on conflict (id) do update set grade = excluded.grade, "
                f"domain = excluded.domain, name = excluded.name, seq = excluded.seq;"
            )
            for kind, key, prefix in (
                ("knowledge", "knowledge_skills", "K"),
                ("thinking", "thinking_skills", "T"),
            ):
                for i, text in enumerate(unit.get(key, []), start=1):
                    item_id = f"{unit['id']}-{prefix}{i}"
                    out.append(
                        f"insert into learning_items (id, unit_id, kind, seq, text) values "
                        f"({q(item_id)}, {q(unit['id'])}, {q(kind)}, {i}, {q(text)}) "
                        f"on conflict (id) do update set unit_id = excluded.unit_id, "
                        f"kind = excluded.kind, seq = excluded.seq, text = excluded.text;"
                    )

    for path in sorted((ROOT / "data/templates").rglob("T-*.yaml")):
        tpl = yaml.safe_load(path.read_text())
        prefix = "K" if tpl["item_kind"] == "knowledge" else "T"
        item_id = f"{tpl['item']}-{prefix}{tpl['item_index']}"
        # status は on conflict で更新しない。DB側の承認状態（approved）を尊重するため。
        out.append(
            f"insert into templates (id, item_id, format, difficulty, title, spec, status) values "
            f"({q(tpl['id'])}, {q(item_id)}, {q(tpl['format'])}, {tpl['difficulty']}, "
            f"{q(tpl['title'])}, {q(json.dumps(tpl, ensure_ascii=False))}::jsonb, {q(tpl['status'])}) "
            f"on conflict (id) do update set item_id = excluded.item_id, "
            f"format = excluded.format, difficulty = excluded.difficulty, "
            f"title = excluded.title, spec = excluded.spec;"
        )

    out.append("commit;")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
