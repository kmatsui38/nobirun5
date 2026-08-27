#!/usr/bin/env python3
"""テンプレートから実際の問題例を出力する（検品フロー④「人の検品」の補助）。

使い方:
    python3 tools/preview_templates.py                     # 全テンプレート、各2問
    python3 tools/preview_templates.py M2-C1               # 単元を指定
    python3 tools/preview_templates.py M2-C1 --samples 3   # 出す問題数を指定
"""

import argparse
import random
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent))
from validate_templates import instantiate, render, safe_eval, fmt  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("filter", nargs="?", default="",
                    help="単元IDやテンプレートIDの一部（例: M2-C1）")
    ap.add_argument("--samples", type=int, default=2, help="1テンプレートあたりの問題数")
    ap.add_argument("--root", default="data/templates")
    args = ap.parse_args()

    paths = sorted(Path(args.root).rglob("T-*.yaml"))
    shown = 0
    for path in paths:
        tpl = yaml.safe_load(path.read_text())
        if args.filter and args.filter not in tpl["id"] and args.filter not in tpl["item"]:
            continue
        shown += 1
        print(f"\n===== {tpl['id']}  {tpl['title']}"
              f"  [{tpl['item']} {tpl['item_kind'][:1].upper()}{tpl['item_index']}"
              f" / 難易度{tpl['difficulty']} / {tpl['status']}] =====")
        rng = random.Random(tpl["id"])
        for i in range(args.samples):
            env = instantiate(tpl, rng.randrange(10**6))
            if tpl.get("case_var"):
                case = env[tpl["case_var"]]
                body = render(tpl["body_by_case"][case], env, tpl["id"])
                ans = tpl["correct_by_case"][case]
                others = "／".join(str(d) for d in tpl["distractors_by_case"][case])
                print(f"\n[問{i + 1}] {body.strip()}")
                print(f"  正解: {ans}")
                print(f"  誤答: {others}")
            elif tpl["format"] == "numeric":
                body = render(tpl["body"], env, tpl["id"])
                ans = ", ".join(f"{k}={fmt(safe_eval(v, env))}"
                                for k, v in tpl["answers"].items())
                print(f"\n[問{i + 1}] {body.strip()}")
                print(f"  正解: {ans}")
            else:
                body = render(tpl["body"], env, tpl["id"])
                print(f"\n[問{i + 1}] {body.strip()}")
                print(f"  正解: {tpl['correct']}")
            print("  解説: " + render(tpl["explanation"], env, tpl["id"]).strip()
                  .replace("\n", "\n        "))
    print(f"\n--- {shown}本のテンプレートを表示しました ---")
    return 0


if __name__ == "__main__":
    sys.exit(main())
