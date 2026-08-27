#!/usr/bin/env python3
"""問題テンプレートの機械検証（検品フロー②）。

使い方:
    python3 tools/validate_templates.py data/templates/

各テンプレートについて:
  - スキーマ（必須フィールド・形式）を検査する
  - サンプルを N 回実生成し、制約の充足・式の評価・プレースホルダの解決を確認する
  - choice 形式は選択肢の重複・正解との衝突を検査する
終了コード 0 = 全テンプレート合格。
"""

import ast
import random
import re
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

SAMPLES = 100
MAX_TRIES = 1000

# ast.Num は Python 3.12 で削除された。3.8以降は数値も ast.Constant として
# パースされるため、ast.Constant だけで足りる。
ALLOWED_NODES = (
    ast.Expression, ast.BinOp, ast.UnaryOp, ast.Compare, ast.BoolOp,
    ast.Constant, ast.Name, ast.Load,
    ast.Add, ast.Sub, ast.Mult, ast.Div, ast.FloorDiv, ast.Mod, ast.Pow,
    ast.USub, ast.UAdd,
    ast.Eq, ast.NotEq, ast.Lt, ast.LtE, ast.Gt, ast.GtE,
    ast.And, ast.Or, ast.Not,
)


def safe_eval(expr, env):
    """四則演算・比較・変数参照のみを許可して式を評価する。"""
    tree = ast.parse(str(expr), mode="eval")
    for node in ast.walk(tree):
        if not isinstance(node, ALLOWED_NODES):
            raise ValueError(f"式に使用できない構文です: {expr!r} ({type(node).__name__})")
        if isinstance(node, ast.Name) and node.id not in env:
            raise ValueError(f"未定義の変数 {node.id!r} が式に含まれています: {expr!r}")
    return eval(compile(tree, "<expr>", "eval"), {"__builtins__": {}}, env)


def draw_variables(spec, rng):
    env = {}
    for name, s in spec.items():
        if s.get("type") != "int":
            raise ValueError(f"変数 {name}: type は int のみ対応（{s.get('type')!r}）")
        lo, hi = s["min"], s["max"]
        exclude = set(s.get("exclude", []))
        candidates = [v for v in range(lo, hi + 1) if v not in exclude]
        if not candidates:
            raise ValueError(f"変数 {name}: 取り得る値がありません")
        env[name] = rng.choice(candidates)
    return env


def instantiate(tpl, seed):
    rng = random.Random(seed)
    for _ in range(MAX_TRIES):
        env = draw_variables(tpl.get("variables", {}), rng)
        if all(safe_eval(c, env) for c in tpl.get("constraints", [])):
            break
    else:
        raise ValueError("制約を満たす変数の組を生成できません（制約が厳しすぎる可能性）")

    for name, expr in (tpl.get("derived") or {}).items():
        env[name] = safe_eval(expr, env)
    return env


def fmt(v):
    """整数値は小数点なしで表示する（Postgres側の _fmt_num と表示を揃える）。"""
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def render(text, env, tpl_id):
    placeholders = re.findall(r"\{(\w+)\}", text)
    for p in placeholders:
        if p not in env:
            raise ValueError(f"本文/解説のプレースホルダ {{{p}}} が未定義です")
    return text.format(**{k: fmt(env[k]) for k in placeholders})


def check_template(path):
    errors = []
    tpl = yaml.safe_load(path.read_text())

    for field in ("id", "item", "item_kind", "item_index", "format",
                  "difficulty", "title", "variables", "explanation", "status"):
        if field not in tpl:
            errors.append(f"必須フィールドがありません: {field}")
    if errors:
        return errors

    tfmt = tpl["format"]
    case_var = tpl.get("case_var")
    if tfmt == "numeric":
        if "answers" not in tpl or "body" not in tpl:
            errors.append("numeric には body と answers が必要です")
    elif tfmt == "choice":
        if case_var:
            for field in ("body_by_case", "correct_by_case", "distractors_by_case"):
                if field not in tpl:
                    errors.append(f"ケース分岐型 choice には {field} が必要です")
        else:
            for field in ("body", "correct", "distractors"):
                if field not in tpl:
                    errors.append(f"choice には {field} が必要です")
    else:
        errors.append(f"不明な format: {tfmt}")
    if errors:
        return errors

    seen_answers = set()
    for seed in range(SAMPLES):
        try:
            env = instantiate(tpl, seed)

            # 全ての値が整数であることを要求する。
            # Postgres の整数どうしの除算は切り捨てになるため、割り切れない式があると
            # Python 側の評価結果と食い違う。整数に限れば両者は必ず一致する。
            for k, v in env.items():
                if isinstance(v, float) and not v.is_integer():
                    errors.append(f"seed={seed}: 変数/derived {k} が整数になりません: {v}")

            if tfmt == "numeric":
                body = render(tpl["body"], env, tpl["id"])
                for field, expr in tpl["answers"].items():
                    val = safe_eval(expr, env)
                    if isinstance(val, float) and not val.is_integer():
                        errors.append(f"seed={seed}: 解答 {field} が整数になりません: {val}")
                    seen_answers.add((field, val))
            else:
                if case_var:
                    case = env[case_var]
                    body = render(tpl["body_by_case"][case], env, tpl["id"])
                    correct = str(tpl["correct_by_case"][case])
                    distractors = [str(d) for d in tpl["distractors_by_case"][case]]
                else:
                    body = render(tpl["body"], env, tpl["id"])
                    correct = str(safe_eval_or_str(tpl["correct"], env))
                    distractors = [str(safe_eval_or_str(d, env)) for d in tpl["distractors"]]
                options = [correct] + distractors
                if len(set(options)) != len(options):
                    errors.append(f"seed={seed}: 選択肢に重複があります: {options}")
                seen_answers.add(correct)

            render(tpl["explanation"], env, tpl["id"])
        except Exception as e:  # noqa: BLE001 - 検証結果として全て報告する
            errors.append(f"seed={seed}: {e}")
            break

    if len(seen_answers) <= 1 and tfmt == "numeric":
        errors.append("全サンプルで解答が同一です（変数が実質固定になっていないか確認）")
    return errors


def safe_eval_or_str(value, env):
    """式として評価できれば評価し、できなければ文字列として扱う。"""
    try:
        return safe_eval(value, env)
    except (ValueError, SyntaxError):
        return value


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "data/templates")
    paths = sorted(root.rglob("T-*.yaml"))
    if not paths:
        print(f"テンプレートが見つかりません: {root}")
        return 1

    failed = 0
    for path in paths:
        errors = check_template(path)
        if errors:
            failed += 1
            print(f"NG {path}")
            for e in errors[:10]:
                print(f"   - {e}")
        else:
            print(f"OK {path}")

    print(f"\n{len(paths)}本中 {len(paths) - failed}本 合格 / {failed}本 不合格")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
